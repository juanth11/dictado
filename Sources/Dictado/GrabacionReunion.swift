import AVFoundation
import CoreAudio
import Foundation

// Grabación de una reunión en dos pistas: tu micrófono ("Tú") y lo que suena en el Mac, que en una llamada es la voz
// de los demás ("Otros"). Cada pista va en trozos AAC de 2 minutos (unos 30 MB por hora entre las dos) que luego se
// transcriben en el Mac y se borran. Nada sale a la red.

/// Escribe una pista en trozos de 2 minutos (`<base>-<segundo>.m4a`, el segundo desde que empezó la grabación). Si
/// Dictado se cierra a mitad de una reunión, los trozos cerrados se transcriben al volver a abrirla: se pierde como
/// mucho el último. Un trozo nuevo también empieza si cambia el formato (conectaste los AirPods).
final class Trozos: @unchecked Sendable {
    static let segundos: Double = 120

    private let base: String
    private let desde: Date
    private let tasaBits: Int
    private let candado = NSLock()
    private var archivo: AVAudioFile?
    private var cuadros: AVAudioFramePosition = 0
    private var _total: AVAudioFramePosition = 0
    private var _pico: Float = 0

    init(base: String, desde: Date, tasaBits: Int) {
        self.base = base
        self.desde = desde
        self.tasaBits = tasaBits
    }

    /// Cuadros escritos y el pico de la señal: si a los pocos segundos siguen en cero, el micrófono no está entrando.
    var total: AVAudioFramePosition { candado.withLock { _total } }
    var pico: Float { candado.withLock { _pico } }

    func escribir(_ buffer: AVAudioPCMBuffer) {
        candado.lock()
        defer { candado.unlock() }
        let formato = buffer.format
        if let a = archivo, cuadros >= AVAudioFramePosition(formato.sampleRate * Self.segundos) || a.processingFormat != formato {
            archivo = nil
        }
        if archivo == nil {
            let segundo = max(0, Int(Date().timeIntervalSince(desde)))
            let url = URL(fileURLWithPath: base + String(format: "-%06d.m4a", segundo))
            archivo = try? AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                                  AVSampleRateKey: formato.sampleRate,
                                                                  AVNumberOfChannelsKey: formato.channelCount,
                                                                  AVEncoderBitRateKey: tasaBits],
                                       commonFormat: formato.commonFormat, interleaved: formato.isInterleaved)
            cuadros = 0
        }
        guard let archivo, (try? archivo.write(from: buffer)) != nil else { return }
        cuadros += AVAudioFramePosition(buffer.frameLength)
        _total += AVAudioFramePosition(buffer.frameLength)
        if _pico < 0.01, let canal = buffer.floatChannelData?[0] {
            for i in stride(from: 0, to: Int(buffer.frameLength), by: 16) { _pico = max(_pico, abs(canal[i])) }
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
            guard nombre.hasPrefix(prefijo), a.pathExtension == "m4a",
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
        trozos = Trozos(base: base, desde: desde, tasaBits: 48_000)
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

        let t = Trozos(base: base, desde: desde, tasaBits: 64_000)
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
