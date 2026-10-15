import AVFoundation
import CoreAudio
import Foundation

// Grabación de una reunión en dos pistas: tu micrófono ("Tú") y lo que suena en el Mac, que en una llamada es la voz
// de los demás ("Otros"). Cada pista va a un archivo AAC (unos 30 MB por hora entre las dos) que luego se transcribe
// en el Mac y se borra. Nada sale a la red.

/// Tu voz: el micrófono por omisión, con su propio motor de audio (no toca el del dictado).
final class GrabadorMicrofono: @unchecked Sendable {
    private let motor = AVAudioEngine()
    private var archivo: AVAudioFile?

    func empezar(en url: URL) throws {
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.channelCount > 0, formato.sampleRate > 0 else { throw DictadoError.sinMicrofono }
        archivo = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                             AVSampleRateKey: formato.sampleRate,
                                                             AVNumberOfChannelsKey: formato.channelCount,
                                                             AVEncoderBitRateKey: 48_000],
                                  commonFormat: .pcmFormatFloat32, interleaved: false)
        entrada.installTap(onBus: 0, bufferSize: 4096, format: formato) { [weak self] buffer, _ in
            try? self?.archivo?.write(from: buffer)
        }
        try motor.start()
    }

    func detener() {
        motor.inputNode.removeTap(onBus: 0)
        motor.stop()
        archivo = nil   // cierra el archivo
    }
}

/// Lo que suena en el Mac, con un "tap" de Core Audio (macOS 14.2+) sobre toda la salida menos Dictado. La primera vez,
/// macOS pide permiso para "grabar el audio del sistema".
final class GrabadorSistema: @unchecked Sendable {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var agregado = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var archivo: AVAudioFile?
    private let cola = DispatchQueue(label: "app.dictado.reunion.sistema")

    enum Fallo: LocalizedError {
        case coreAudio(String, OSStatus)
        var errorDescription: String? {
            if case .coreAudio(let paso, let s) = self { return "No se pudo grabar el audio del sistema (\(paso): \(s))." }
            return nil
        }
    }

    func empezar(en url: URL) throws {
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

        archivo = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                             AVSampleRateKey: formato.sampleRate,
                                                             AVNumberOfChannelsKey: formato.channelCount,
                                                             AVEncoderBitRateKey: 64_000],
                                  commonFormat: .pcmFormatFloat32, interleaved: formato.isInterleaved)
        estado = AudioDeviceCreateIOProcIDWithBlock(&proc, agregado, cola) { [weak self] _, entrada, _, _, _ in
            guard let self, let archivo = self.archivo,
                  let buffer = AVAudioPCMBuffer(pcmFormat: formato, bufferListNoCopy: entrada, deallocator: nil) else { return }
            try? archivo.write(from: buffer)
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
        cola.sync { archivo = nil }   // espera a la última escritura y cierra el archivo
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
