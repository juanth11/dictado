import AVFoundation
import Foundation
import Speech

/// Los dos motores de SpeechAnalyzer (macOS 26+). Ambos corren en el Mac, sin red.
enum Motor: String, CaseIterable {
    case speech     // SpeechTranscriber: modelo nuevo, pensado para frases largas
    case dictation  // DictationTranscriber: modelo de dictado, puntuación explícita
}

struct Segmento: Sendable {
    let texto: String
    let esFinal: Bool
}

enum DictadoError: LocalizedError {
    case idiomaNoSoportado(String)
    case modeloNoDisponible
    case sinFormato
    case sinMicrofono

    var errorDescription: String? {
        switch self {
        case .idiomaNoSoportado(let id): return "El idioma \(id) no está disponible en este Mac"
        case .modeloNoDisponible: return "El modelo de voz no está disponible"
        case .sinFormato: return "No hay formato de audio compatible con el motor"
        case .sinMicrofono: return "No hay micrófono disponible"
        }
    }
}

/// Un módulo de SpeechAnalyzer con sus resultados normalizados a texto.
struct Modulo {
    let modulo: any SpeechModule
    let resultados: AsyncThrowingStream<Segmento, Error>
}

enum Transcripcion {
    static func localeSoportado(_ motor: Motor, para id: String) async -> Locale? {
        let pedido = Locale(identifier: id)
        switch motor {
        case .speech: return await SpeechTranscriber.supportedLocale(equivalentTo: pedido)
        case .dictation: return await DictationTranscriber.supportedLocale(equivalentTo: pedido)
        }
    }

    /// `parciales`: además de los resultados finales, entrega texto provisional mientras hablas (para la vista previa).
    static func crearModulo(_ motor: Motor, locale: Locale, parciales: Bool = false) -> Modulo {
        switch motor {
        case .speech:
            let t = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                      reportingOptions: parciales ? [.volatileResults] : [], attributeOptions: [])
            return Modulo(modulo: t, resultados: normalizar(t.results) { (String($0.text.characters), $0.isFinal) })
        case .dictation:
            let t = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                                         reportingOptions: parciales ? [.volatileResults] : [], attributeOptions: [])
            return Modulo(modulo: t, resultados: normalizar(t.results) { (String($0.text.characters), $0.isFinal) })
        }
    }

    /// Descarga el modelo del idioma si el sistema aún no lo tiene (lo gestiona macOS, se comparte entre apps).
    static func asegurarModelo(_ modulo: any SpeechModule) async throws {
        switch await AssetInventory.status(forModules: [modulo]) {
        case .installed: return
        case .unsupported: throw DictadoError.modeloNoDisponible
        default:
            if let pedido = try await AssetInventory.assetInstallationRequest(supporting: [modulo]) {
                try await pedido.downloadAndInstall()
            }
        }
    }

    static func contexto(_ vocabulario: [String]) -> AnalysisContext {
        let c = AnalysisContext()
        if !vocabulario.isEmpty { c.contextualStrings[.general] = vocabulario }
        return c
    }

    static func recolectar(_ flujo: AsyncThrowingStream<Segmento, Error>) async throws -> String {
        var partes: [String] = []
        for try await s in flujo where s.esFinal { partes.append(s.texto) }
        return unir(partes)
    }

    /// Aplica las correcciones del usuario como palabras completas, sin distinguir mayúsculas.
    static func corregir(_ texto: String, con correcciones: [(String, String)]) -> String {
        correcciones.reduce(texto) { resultado, par in
            let patron = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: par.0) + #"(?![\p{L}\p{N}])"#
            guard let regex = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { return resultado }
            return regex.stringByReplacingMatches(in: resultado, range: NSRange(resultado.startIndex..., in: resultado),
                                                  withTemplate: NSRegularExpression.escapedTemplate(for: par.1))
        }
    }

    static func unir(_ partes: [String]) -> String {
        partes.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" ([,.;:!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Transcribe un archivo completo (modo de prueba por línea de comandos).
    static func transcribirArchivo(_ url: URL, motor: Motor, idioma: String, vocabulario: [String]) async throws -> String {
        guard let locale = await localeSoportado(motor, para: idioma) else { throw DictadoError.idiomaNoSoportado(idioma) }
        let m = crearModulo(motor, locale: locale)
        try await asegurarModelo(m.modulo)
        let archivo = try AVAudioFile(forReading: url)
        let analizador = SpeechAnalyzer(modules: [m.modulo])
        try await analizador.setContext(contexto(vocabulario))
        let recolector = Task { try await recolectar(m.resultados) }
        if let fin = try await analizador.analyzeSequence(from: archivo) {
            try await analizador.finalizeAndFinish(through: fin)
        } else {
            await analizador.cancelAndFinishNow()
        }
        return try await recolector.value
    }

    private static func normalizar<S: AsyncSequence>(
        _ secuencia: S, _ convertir: @escaping (S.Element) -> (String, Bool)
    ) -> AsyncThrowingStream<Segmento, Error> {
        AsyncThrowingStream { cont in
            let tarea = Task {
                do {
                    for try await r in secuencia {
                        let (texto, esFinal) = convertir(r)
                        cont.yield(Segmento(texto: texto, esFinal: esFinal))
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in tarea.cancel() }
        }
    }
}

/// Motor listo para dictar: idioma resuelto, modelo instalado y formato de audio conocido.
final class Reconocedor {
    let motor: Motor
    let locale: Locale
    let formato: AVAudioFormat
    var vocabulario: [String]

    private init(motor: Motor, locale: Locale, formato: AVAudioFormat, vocabulario: [String]) {
        self.motor = motor
        self.locale = locale
        self.formato = formato
        self.vocabulario = vocabulario
    }

    static func preparar(motor: Motor, idioma: String, vocabulario: [String]) async throws -> Reconocedor {
        guard let locale = await Transcripcion.localeSoportado(motor, para: idioma) else {
            throw DictadoError.idiomaNoSoportado(idioma)
        }
        let m = Transcripcion.crearModulo(motor, locale: locale)
        try await Transcripcion.asegurarModelo(m.modulo)
        guard let formato = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [m.modulo]) else {
            throw DictadoError.sinFormato
        }
        // Precalienta el modelo para que el primer dictado no espere la carga.
        let previo = SpeechAnalyzer(modules: [m.modulo], options: .init(priority: .utility, modelRetention: .lingering))
        try? await previo.prepareToAnalyze(in: formato)
        await previo.cancelAndFinishNow()
        return Reconocedor(motor: motor, locale: locale, formato: formato, vocabulario: vocabulario)
    }
}

/// Una pulsación de push-to-talk: micrófono → conversión de formato → SpeechAnalyzer en streaming.
final class SesionEnVivo {
    private let reconocedor: Reconocedor
    private let audio = AVAudioEngine()
    private var entrada: AsyncStream<AnalyzerInput>.Continuation?
    private var convertidor: AVAudioConverter?
    private var analisis: Task<String, Error>?

    /// Volumen del micrófono 0…1 (hilo de audio) y texto provisional (hilo de fondo).
    var alNivel: ((Double) -> Void)?
    var alParcial: ((String) -> Void)?

    init(_ reconocedor: Reconocedor) {
        self.reconocedor = reconocedor
    }

    /// Arranca análisis y micrófono; el audio se acumula en el flujo mientras el analizador se inicia.
    func iniciar() throws {
        iniciarAnalisis()
        let nodo = audio.inputNode
        let formatoMic = nodo.outputFormat(forBus: 0)
        guard formatoMic.channelCount > 0 else {
            cancelar()
            throw DictadoError.sinMicrofono
        }
        nodo.installTap(onBus: 0, bufferSize: 2048, format: formatoMic) { [weak self] buffer, _ in
            self?.medir(buffer)
            self?.alimentar(buffer)
        }
        audio.prepare()
        do {
            try audio.start()
        } catch {
            cancelar()
            throw error
        }
    }

    /// Entrada de audio en cualquier formato (micrófono o archivo en el modo de prueba).
    func alimentar(_ buffer: AVAudioPCMBuffer) {
        guard let salida = convertir(buffer) else { return }
        entrada?.yield(AnalyzerInput(buffer: salida))
    }

    func iniciarAnalisis() {
        let (flujo, entrada) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
        self.entrada = entrada
        let m = Transcripcion.crearModulo(reconocedor.motor, locale: reconocedor.locale, parciales: true)
        let contexto = Transcripcion.contexto(reconocedor.vocabulario)
        let parcial = alParcial
        analisis = Task {
            let analizador = SpeechAnalyzer(inputSequence: flujo, modules: [m.modulo],
                                            options: .init(priority: .userInitiated, modelRetention: .lingering),
                                            analysisContext: contexto)
            let recolector = Task {
                var finales: [String] = []
                for try await s in m.resultados {
                    if s.esFinal { finales.append(s.texto) }
                    parcial?(Transcripcion.unir(s.esFinal ? finales : finales + [s.texto]))
                }
                return Transcripcion.unir(finales)
            }
            try await analizador.finalizeAndFinishThroughEndOfInput()
            return try await recolector.value
        }
    }

    func terminar() async throws -> String {
        detenerAudio()
        return try await analisis?.value ?? ""
    }

    func cancelar() {
        detenerAudio()
        analisis?.cancel()
    }

    private func medir(_ buffer: AVAudioPCMBuffer) {
        guard let alNivel, let canal = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let n = Int(buffer.frameLength)
        var suma: Float = 0
        for i in 0..<n { suma += canal[i] * canal[i] }
        let db = 20 * log10(max(sqrt(suma / Float(n)), 1e-7))
        alNivel(Double(min(max((db + 55) / 40, 0), 1)))  // -55 dB → 0, -15 dB → 1
    }

    private func detenerAudio() {
        if audio.isRunning {
            audio.inputNode.removeTap(onBus: 0)
            audio.stop()
        }
        entrada?.finish()
    }

    private func convertir(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let destino = reconocedor.formato
        if buffer.format == destino { return buffer }
        if convertidor?.inputFormat != buffer.format {
            convertidor = AVAudioConverter(from: buffer.format, to: destino)
        }
        guard let convertidor else { return nil }
        let capacidad = AVAudioFrameCount(Double(buffer.frameLength) * destino.sampleRate / buffer.format.sampleRate) + 1024
        guard let salida = AVAudioPCMBuffer(pcmFormat: destino, frameCapacity: capacidad) else { return nil }
        var entregado = false
        var error: NSError?
        convertidor.convert(to: salida, error: &error) { _, estado in
            if entregado {
                estado.pointee = .noDataNow
                return nil
            }
            entregado = true
            estado.pointee = .haveData
            return buffer
        }
        return error == nil && salida.frameLength > 0 ? salida : nil
    }
}
