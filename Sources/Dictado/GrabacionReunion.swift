import AVFoundation
import CoreAudio
import Foundation

// Grabación de una reunión en dos pistas: tu micrófono ("Tú") y lo que suena en el Mac, que en una llamada es la voz
// de los demás ("Otros"). Cada pista va en trozos de 2 minutos (ver Trozos) que luego se transcriben en el Mac y se
// borran. Nada sale a la red.

/// Escribe una pista en trozos de 2 minutos (`<base>-<segundo>.caf`, el segundo desde que empezó la grabación), en PCM
/// de 16 kHz mono: lo que usa el reconocedor y lo único que se puede leer si Dictado se cierra a la fuerza (un AAC sin
/// cerrar queda ilegible; un CAF con PCM se lee hasta el último cuadro escrito, probado con un cierre a la fuerza). Son
/// unos 115 MB por hora por pista mientras se graba; se borran al transcribir. Al volver a abrir Dictado se transcribe
/// lo que quedó. Un trozo nuevo también empieza si cambia la entrada (conectaste los AirPods).
final class Trozos: @unchecked Sendable {
    static let segundos: Double = 120
    static let formato = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private static let ajustes: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000.0,
                                                 AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                                 AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]

    private let base: String
    private let desde: Date
    private let candado = NSLock()
    private var archivo: AVAudioFile?
    private var conversor: AVAudioConverter?
    private var cuadros: AVAudioFramePosition = 0
    private var _total: AVAudioFramePosition = 0
    private var _pico: Float = 0

    init(base: String, desde: Date) {
        self.base = base
        self.desde = desde
    }

    /// Cuadros escritos y el pico de la señal: si a los pocos segundos siguen en cero, el micrófono no está entrando.
    var total: AVAudioFramePosition { candado.withLock { _total } }
    var pico: Float { candado.withLock { _pico } }

    func escribir(_ buffer: AVAudioPCMBuffer) {
        candado.lock()
        defer { candado.unlock() }
        if conversor?.inputFormat != buffer.format {
            conversor = AVAudioConverter(from: buffer.format, to: Self.formato)
            conversor?.downmix = true
            archivo = nil
        }
        guard let conversor, buffer.frameLength > 0 else { return }
        let capacidad = AVAudioFrameCount(Double(buffer.frameLength) * Self.formato.sampleRate / buffer.format.sampleRate) + 64
        guard let salida = AVAudioPCMBuffer(pcmFormat: Self.formato, frameCapacity: capacidad) else { return }
        var entregado = false
        var error: NSError?
        conversor.convert(to: salida, error: &error) { _, estado in
            if entregado {
                estado.pointee = .noDataNow
                return nil
            }
            entregado = true
            estado.pointee = .haveData
            return buffer
        }
        guard error == nil, salida.frameLength > 0 else { return }
        if cuadros >= AVAudioFramePosition(Self.formato.sampleRate * Self.segundos) { archivo = nil }
        if archivo == nil {
            let segundo = max(0, Int(Date().timeIntervalSince(desde)))
            let url = URL(fileURLWithPath: base + String(format: "-%06d.caf", segundo))
            archivo = try? AVAudioFile(forWriting: url, settings: Self.ajustes, commonFormat: .pcmFormatFloat32, interleaved: false)
            cuadros = 0
        }
        guard let archivo, (try? archivo.write(from: salida)) != nil else { return }
        cuadros += AVAudioFramePosition(salida.frameLength)
        _total += AVAudioFramePosition(salida.frameLength)
        if _pico < 0.01, let canal = salida.floatChannelData?[0] {
            for i in stride(from: 0, to: Int(salida.frameLength), by: 8) { _pico = max(_pico, abs(canal[i])) }
        }
    }

    /// Cierra el trozo abierto (el siguiente buffer abre otro).
    func cortar() { candado.withLock { archivo = nil } }

    /// Los trozos de una pista, en orden, con el segundo en que empieza cada uno.
    static func de(_ base: String) -> [(url: URL, desde: Double)] {
        let url = URL(fileURLWithPath: base)
        let prefijo = url.lastPathComponent + "-"
        let archivos = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        return archivos.compactMap { a -> (url: URL, desde: Double)? in
            let nombre = a.lastPathComponent
            guard nombre.hasPrefix(prefijo), ["caf", "m4a"].contains(a.pathExtension),
                  let s = Double(nombre.dropFirst(prefijo.count).dropLast(4)) else { return nil }
            return (a, s)
        }
        .sorted { $0.desde < $1.desde }
    }
}

/// Tu voz: el micrófono por omisión, con su propio motor de audio (no toca el del dictado). Si cambia la entrada
/// (conectas o quitas unos audífonos), macOS detiene el motor: se arma uno nuevo y la grabación sigue.
final class GrabadorMicrofono: @unchecked Sendable {
    private var motor = AVAudioEngine()
    private var trozos: Trozos?
    private var observador: NSObjectProtocol?

    var cuadros: AVAudioFramePosition { trozos?.total ?? 0 }
    var pico: Float { trozos?.pico ?? 0 }

    func empezar(base: String, desde: Date) throws {
        trozos = Trozos(base: base, desde: desde)
        try arrancar()
        observador = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil,
                                                            queue: .main) { [weak self] nota in
            guard let self, (nota.object as AnyObject?) === self.motor else { return }
            self.reiniciar()
        }
    }

    private func arrancar() throws {
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.channelCount > 0, formato.sampleRate > 0 else { throw DictadoError.sinMicrofono }
        let t = trozos
        entrada.installTap(onBus: 0, bufferSize: 4096, format: formato) { buffer, _ in t?.escribir(buffer) }
        motor.prepare()
        try motor.start()
    }

    private func reiniciar() {
        motor.inputNode.removeTap(onBus: 0)
        motor.stop()
        trozos?.cortar()
        motor = AVAudioEngine()
        try? arrancar()
    }

    func detener() {
        if let observador { NotificationCenter.default.removeObserver(observador) }
        observador = nil
        motor.inputNode.removeTap(onBus: 0)
        motor.stop()
        trozos?.cortar()   // cierra el último trozo
    }
}

/// Lo que suena en el Mac, con un "tap" de Core Audio (macOS 14.2+) sobre toda la salida menos Dictado. La primera vez,
/// macOS pide permiso para "grabar el audio del sistema".
final class GrabadorSistema: @unchecked Sendable {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var agregado = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var trozos: Trozos?
    private let cola = DispatchQueue(label: "app.dictado.reunion.sistema")

    enum Fallo: LocalizedError {
        case coreAudio(String, OSStatus)
        var errorDescription: String? {
            if case .coreAudio(let paso, let s) = self { return "No se pudo grabar el audio del sistema (\(paso): \(s))." }
            return nil
        }
    }

    func empezar(base: String, desde: Date) throws {
        let descripcion = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.procesoPropio().map { [$0] } ?? [])
        descripcion.uuid = UUID()
        descripcion.name = "Dictado · notas de reunión"
        descripcion.isPrivate = true
        descripcion.muteBehavior = .unmuted
        var estado = AudioHardwareCreateProcessTap(descripcion, &tap)
        guard estado == noErr else { throw Fallo.coreAudio("tap", estado) }

        var asbd = AudioStreamBasicDescription()
        var tam = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var dir = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        estado = AudioObjectGetPropertyData(tap, &dir, 0, nil, &tam, &asbd)
        guard estado == noErr, let formato = AVAudioFormat(streamDescription: &asbd) else {
            detener()
            throw Fallo.coreAudio("formato", estado)
        }

        guard let salida = Audio.salida(), let uidSalida = Self.uid(salida) else {
            detener()
            throw Fallo.coreAudio("salida", -1)
        }
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dictado · notas",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: uidSalida,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uidSalida]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: descripcion.uuid.uuidString]],
        ]
        estado = AudioHardwareCreateAggregateDevice(config as CFDictionary, &agregado)
        guard estado == noErr else {
            detener()
            throw Fallo.coreAudio("agregado", estado)
        }

        let t = Trozos(base: base, desde: desde)
        trozos = t
        estado = AudioDeviceCreateIOProcIDWithBlock(&proc, agregado, cola) { _, entrada, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: formato, bufferListNoCopy: entrada, deallocator: nil) else { return }
            t.escribir(buffer)
        }
        guard estado == noErr else {
            detener()
            throw Fallo.coreAudio("lectura", estado)
        }
        estado = AudioDeviceStart(agregado, proc)
        guard estado == noErr else {
            detener()
            throw Fallo.coreAudio("inicio", estado)
        }
    }

    func detener() {
        if agregado != kAudioObjectUnknown, let proc {
            AudioDeviceStop(agregado, proc)
            AudioDeviceDestroyIOProcID(agregado, proc)
        }
        proc = nil
        cola.sync { trozos?.cortar() }   // espera a la última escritura y cierra el trozo
        if agregado != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(agregado) }
        agregado = AudioObjectID(kAudioObjectUnknown)
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    /// El objeto de audio de este proceso (para que Dictado no se grabe a sí mismo).
    private static func procesoPropio() -> AudioObjectID? {
        var pid = getpid()
        var objeto = AudioObjectID(kAudioObjectUnknown)
        var tam = UInt32(MemoryLayout<AudioObjectID>.size)
        var dir = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let estado = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &dir,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &tam, &objeto)
        return estado == noErr && objeto != kAudioObjectUnknown ? objeto : nil
    }

    private static func uid(_ dispositivo: AudioDeviceID) -> String? {
        var uid: Unmanaged<CFString>?
        var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var dir = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(dispositivo, &dir, 0, nil, &tam, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}
