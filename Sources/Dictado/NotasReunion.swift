import AppKit
import Observation

/// Notas de reunión. Cuando el micrófono entra en una llamada (hay una reunión en el calendario, es una app de llamadas
/// o están la cámara y el micrófono a la vez), la isla ofrece tomar notas; nunca graba sola, porque es tu decisión y la
/// de avisar a los demás. Graba tu micrófono y el audio del Mac en dos pistas (GrabacionReunion.swift) y, al colgar,
/// transcribe todo en el Mac (sin red), arma la transcripción con "Tú:" y "Otros:", la guarda en la carpeta de Dictado
/// y borra el audio. Luego le pide al cerebro las notas (`accion.sh reunion`): un resumen con decisiones y pendientes
/// que queda en tu inbox, con su commit. La transcripción completa no entra al cerebro.
@MainActor @Observable
final class NotasReunion {
    enum Fase: Equatable { case libre, grabando, procesando }

    private(set) var fase = Fase.libre
    private(set) var desde: Date?
    private(set) var titulo = ""

    /// Para mostrar un aviso en la isla (actividad, segundos).
    @ObservationIgnored var avisar: ((EstadoIsla.Actividad, Double) -> Void)?

    @ObservationIgnored private let agenda: Agenda
    @ObservationIgnored private let privacidad: Privacidad
    @ObservationIgnored private var personas: [String] = []
    @ObservationIgnored private var inicioReunion: Date?
    @ObservationIgnored private var microfono: GrabadorMicrofono?
    @ObservationIgnored private var sistema: GrabadorSistema?
    @ObservationIgnored private var pistas: (tu: URL, otros: URL?)?
    @ObservationIgnored private var ofrecida = false
    @ObservationIgnored private var oferta: DispatchWorkItem?
    @ObservationIgnored private var silencio: DispatchWorkItem?

    static let carpeta = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/app.dictado/reuniones")
    private static let appsDeLlamada = ["zoom", "teams", "meet", "facetime", "slack", "whatsapp", "discord", "webex", "skype"]

    init(agenda: Agenda, privacidad: Privacidad) {
        self.agenda = agenda
        self.privacidad = privacidad
    }

    var grabando: Bool { fase == .grabando }

    /// Lo avisa la isla cuando otra app empieza o deja de usar el micrófono.
    func microfonoCambio(_ enUso: Bool) {
        if enUso {
            silencio?.cancel()
            silencio = nil
            guard fase == .libre, !ofrecida else { return }
            // Unos segundos de margen: una nota de voz o una prueba de micrófono no son una llamada.
            let tarea = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.ofrecer() } }
            oferta = tarea
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: tarea)
        } else {
            oferta?.cancel()
            oferta = nil
            ofrecida = false
            guard fase == .grabando else { return }
            // Colgaste: si en 20 s el micrófono no vuelve, se cierran las notas.
            let tarea = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.terminar() } }
            silencio = tarea
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: tarea)
        }
    }

    private var eventoActual: Agenda.Evento? {
        let ahora = Date()
        return agenda.eventos.first { $0.inicio.timeIntervalSince(ahora) < 600 && $0.fin > ahora }
    }

    private var esLlamada: Bool {
        eventoActual != nil || privacidad.camara
            || Self.appsDeLlamada.contains { privacidad.nombre.localizedCaseInsensitiveContains($0) }
    }

    private func ofrecer() {
        guard fase == .libre, privacidad.microfono, esLlamada else { return }
        ofrecida = true
        titulo = eventoActual?.titulo ?? "Llamada en \(privacidad.nombre.isEmpty ? "el Mac" : privacidad.nombre)"
        avisar?(.notas(titulo: titulo), 25)
    }

    func empezar() {
        guard fase == .libre else { return }
        let e = eventoActual
        if let e { titulo = e.titulo } else if titulo.isEmpty { titulo = "Llamada" }
        personas = e?.personas ?? []
        inicioReunion = e?.inicio ?? Date()
        do {
            try FileManager.default.createDirectory(at: Self.carpeta, withIntermediateDirectories: true)
            let base = Self.carpeta.appendingPathComponent(Self.marca(Date()) + "-" + Self.slug(titulo)).path
            let tu = URL(fileURLWithPath: base + "-tu.m4a")
            let m = GrabadorMicrofono()
            try m.empezar(en: tu)
            microfono = m
            var otros: URL? = URL(fileURLWithPath: base + "-otros.m4a")
            let s = GrabadorSistema()
            do {
                try s.empezar(en: otros!)
                sistema = s
            } catch {
                otros = nil
                avisar?(.aviso(icono: "exclamationmark.triangle", texto: "Solo tu voz: falta el permiso de audio del sistema"), 5)
            }
            pistas = (tu, otros)
            desde = Date()
            fase = .grabando
            if otros != nil { avisar?(.aviso(icono: "record.circle", texto: "Tomando notas · avísales que grabas"), 3) }
        } catch {
            microfono?.detener()
            microfono = nil
            avisar?(.aviso(icono: "exclamationmark.triangle", texto: "No se pudo grabar: \(error.localizedDescription)"), 5)
        }
    }

    func terminar() {
        guard fase == .grabando, let pistas else { return }
        silencio?.cancel()
        silencio = nil
        microfono?.detener()
        sistema?.detener()
        microfono = nil
        sistema = nil
        fase = .procesando
        avisar?(.aviso(icono: "waveform", texto: "Transcribiendo la reunión en el Mac… (unos minutos)"), 900)
        let datos = Datos(titulo: titulo, personas: personas, inicio: inicioReunion ?? Date(),
                          duracion: Date().timeIntervalSince(desde ?? Date()),
                          idioma: UserDefaults.dictado.string(forKey: "idioma") ?? "es-US", vocabulario: Ajustes().vocabulario(),
                          acciones: CentroStore.acciones)
        Task { [weak self] in
            let (texto, bien) = await Self.procesar(pistas, datos)
            guard let self else { return }
            self.fase = .libre
            self.desde = nil
            self.pistas = nil
            self.avisar?(.aviso(icono: bien ? "checkmark.circle" : "exclamationmark.triangle", texto: bien ? texto + " · Centro → Notas" : texto), 12)
        }
    }

    // MARK: Transcribir y mandar al cerebro

    struct Datos: Sendable {
        let titulo: String
        let personas: [String]
        let inicio: Date
        let duracion: TimeInterval
        let idioma: String
        /// Tus palabras del dictado (nombres de clientes, marcas): ayudan a que salgan bien escritas.
        var vocabulario: [String] = []
        let acciones: String?
    }

    /// Transcribe las dos pistas, las mezcla por tiempo y pide las notas al cerebro. Devuelve el aviso y si salió bien.
    /// Si la transcripción falla, el audio se queda en la carpeta para no perder la reunión.
    nonisolated static func procesar(_ pistas: (tu: URL, otros: URL?), _ d: Datos) async -> (String, Bool) {
        let tu: [(inicio: Double, texto: String)]
        do {
            tu = try await Transcripcion.transcribirConTiempos(pistas.tu, idioma: d.idioma, vocabulario: d.vocabulario)
        } catch {
            return ("No se pudo transcribir; el audio quedó guardado en la carpeta de Dictado", false)
        }
        var otros: [(inicio: Double, texto: String)] = []
        if let o = pistas.otros {
            otros = (try? await Transcripcion.transcribirConTiempos(o, idioma: d.idioma, vocabulario: d.vocabulario)) ?? []
        }
        let lineas = mezclar(tu, otros)
        try? FileManager.default.removeItem(at: pistas.tu)
        if let o = pistas.otros { try? FileManager.default.removeItem(at: o) }
        guard !lineas.isEmpty else { return ("La grabación quedó en silencio: no hay notas", false) }

        let ruta = URL(fileURLWithPath: pistas.tu.path.replacingOccurrences(of: "-tu.m4a", with: ".md"))
        do {
            try markdown(lineas, d).write(to: ruta, atomically: true, encoding: .utf8)
        } catch {
            return ("No se pudo guardar la transcripción", false)
        }
        guard let acciones = d.acciones else { return ("Transcripción guardada en el Mac (sin script de acciones para el resumen)", true) }
        var argumentos = ["reunion", "--titulo", d.titulo, "--inicio", ISO8601DateFormatter().string(from: d.inicio),
                          "--transcripcion", ruta.path]
        for p in d.personas { argumentos += ["--persona", p] }
        let (salida, fallo) = CentroStore.correr(URL(fileURLWithPath: acciones), argumentos, limite: 180)
        struct Respuesta: Decodable { var ok: Bool; var captura: String?; var error: String? }
        guard let r = try? JSONDecoder().decode(Respuesta.self, from: salida) else {
            return ("Transcripción guardada; el cerebro no respondió (\(fallo ?? "sin respuesta"))", false)
        }
        return r.ok ? ("Notas listas en tu inbox", true) : ("Transcripción guardada; el resumen falló: \(r.error ?? "")", false)
    }

    /// Las dos pistas en orden de tiempo; los tramos seguidos de la misma persona se juntan.
    nonisolated static func mezclar(_ tu: [(inicio: Double, texto: String)], _ otros: [(inicio: Double, texto: String)])
        -> [(inicio: Double, quien: String, texto: String)] {
        let todas = (tu.map { ($0.inicio, "Tú", $0.texto) } + otros.map { ($0.inicio, "Otros", $0.texto) }).sorted { $0.0 < $1.0 }
        var salida: [(inicio: Double, quien: String, texto: String)] = []
        for (inicio, quien, texto) in todas {
            if let ultima = salida.last, ultima.quien == quien {
                salida[salida.count - 1].texto += " " + texto
            } else {
                salida.append((inicio, quien, texto))
            }
        }
        return salida
    }

    nonisolated static func markdown(_ lineas: [(inicio: Double, quien: String, texto: String)], _ d: Datos) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var t = ["# \(d.titulo)", "", "- Inicio: \(f.string(from: d.inicio)) · duración: \(Int((d.duracion / 60).rounded())) min"]
        if !d.personas.isEmpty { t.append("- Personas: \(d.personas.joined(separator: ", "))") }
        t += ["- Transcripción automática en el Mac. \"Tú\" es tu micrófono; \"Otros\", el audio del Mac (la llamada).", ""]
        for l in lineas {
            let s = Int(l.inicio)
            t.append(String(format: "[%02d:%02d] ", s / 60, s % 60) + "\(l.quien): \(l.texto)")
            t.append("")
        }
        return t.joined(separator: "\n")
    }

    private static func marca(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        return f.string(from: d)
    }

    private static func slug(_ t: String) -> String {
        let plano = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let s = plano.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(s.prefix(40)).isEmpty ? "reunion" : String(s.prefix(40))
    }
}
