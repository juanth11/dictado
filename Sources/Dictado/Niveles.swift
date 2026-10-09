import AppKit
import AudioToolbox
import CoreAudio

// Volumen y brillo con las teclas del teclado (F1/F2, F10–F12), mostrados como una barra en la isla en vez del
// cuadro de macOS. Solo se interceptan esas teclas; si el cambio no se puede aplicar (salida HDMI sin volumen,
// tapa cerrada sin pantalla integrada, isla oculta), la tecla sigue su camino y macOS hace lo de siempre.

@MainActor
final class Niveles {
    enum Tipo { case volumen, brillo }

    var alCambiar: ((Tipo, Double, Bool) -> Void)?  // tipo, valor 0–1, silenciado
    /// La isla está a la vista; si no, las teclas pasan a macOS para no quedarte sin respuesta visual.
    var puedeMostrar: () -> Bool = { true }

    private var tap: CFMachPort?
    private var reintento: Timer?
    private var propias = Set<Int>()  // teclas cuyo "presionar" manejamos: su "soltar" tampoco pasa

    // Teclas multimedia (NX_KEYTYPE_* de IOKit).
    private static let subeVolumen = 0, bajaVolumen = 1, subeBrillo = 2, bajaBrillo = 3, silencio = 7

    init(vivo: Bool = true) {
        guard vivo else { return }
        conectar()
        // Sin Accesibilidad no hay intercepción; se reintenta hasta que la concedas.
        reintento = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.conectar() }
        }
    }

    var conectado: Bool { tap != nil }

    func apagar() {
        reintento?.invalidate()
        reintento = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
    }

    private func conectar() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let nuevo = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << 14,  // NX_SYSDEFINED: teclas multimedia
            callback: { _, tipo, evento, refcon in
                guard let refcon else { return Unmanaged.passUnretained(evento) }
                let yo = Unmanaged<Niveles>.fromOpaque(refcon).takeUnretainedValue()
                let consumida = MainActor.assumeIsolated { yo.manejar(tipo, evento) }
                return consumida ? nil : Unmanaged.passUnretained(evento)
            },
            userInfo: refcon)
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, nuevo, 0), .commonModes)
        CGEvent.tapEnable(tap: nuevo, enable: true)
        tap = nuevo
    }

    /// true = la tecla la manejó Dictado y macOS no la ve (así no sale su cuadro).
    private func manejar(_ tipo: CGEventType, _ evento: CGEvent) -> Bool {
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard tipo.rawValue == 14, let e = NSEvent(cgEvent: evento), e.subtype.rawValue == 8 else { return false }
        let tecla = (e.data1 & 0xFFFF0000) >> 16
        let presionada = (e.data1 & 0xFF00) >> 8 == 0xA
        guard [Self.subeVolumen, Self.bajaVolumen, Self.subeBrillo, Self.bajaBrillo, Self.silencio].contains(tecla) else {
            return false
        }
        guard presionada else { return propias.remove(tecla) != nil }
        guard puedeMostrar() else { return false }
        let fino = e.modifierFlags.contains([.shift, .option])  // ⇧⌥ + tecla: pasos de un cuarto, como macOS
        let hecho: Bool
        switch tecla {
        case Self.subeVolumen, Self.bajaVolumen: hecho = volumen(sube: tecla == Self.subeVolumen, fino: fino)
        case Self.silencio: hecho = alternarSilencio()
        default: hecho = brillo(sube: tecla == Self.subeBrillo, fino: fino)
        }
        if hecho { propias.insert(tecla) }
        return hecho
    }

    private static func paso(_ actual: Double, sube: Bool, fino: Bool) -> Double {
        let paso = fino ? 1.0 / 64 : 1.0 / 16
        return min(1, max(0, ((actual / paso).rounded() + (sube ? 1 : -1)) * paso))
    }

    private func volumen(sube: Bool, fino: Bool) -> Bool {
        guard let salida = Audio.salida(), let actual = Audio.volumen(salida) else { return false }
        var silenciado = Audio.silenciado(salida) ?? false
        if silenciado && sube, Audio.silenciar(salida, false) { silenciado = false }  // subir quita el silencio
        let nuevo = Self.paso(actual, sube: sube, fino: fino)
        guard Audio.ponerVolumen(salida, nuevo) else { return false }
        alCambiar?(.volumen, nuevo, silenciado || nuevo == 0)
        return true
    }

    private func alternarSilencio() -> Bool {
        guard let salida = Audio.salida(), let silenciado = Audio.silenciado(salida),
              Audio.silenciar(salida, !silenciado) else { return false }
        let valor = Audio.volumen(salida) ?? 0
        alCambiar?(.volumen, valor, !silenciado || valor == 0)
        return true
    }

    private func brillo(sube: Bool, fino: Bool) -> Bool {
        guard let pantalla = Brillo.pantallaIntegrada(), let actual = Brillo.leer(pantalla) else { return false }
        let nuevo = Self.paso(actual, sube: sube, fino: fino)
        guard Brillo.poner(pantalla, nuevo) else { return false }
        alCambiar?(.brillo, nuevo, false)
        return true
    }
}

// MARK: - CoreAudio

/// Lectura y escritura de propiedades de CoreAudio (volumen, silencio, quién usa el micrófono).
enum Audio {
    static let sistema = AudioObjectID(kAudioObjectSystemObject)

    static func direccion(_ selector: AudioObjectPropertySelector,
                          _ alcance: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: alcance, mElement: kAudioObjectPropertyElementMain)
    }

    static func leer<T: BitwiseCopyable>(_ objeto: AudioObjectID, _ selector: AudioObjectPropertySelector, _ inicial: T,
                        _ alcance: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var d = direccion(selector, alcance)
        var valor = inicial
        var tam = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(objeto, &d, 0, nil, &tam, &valor) == noErr ? valor : nil
    }

    static func escribir<T: BitwiseCopyable>(_ objeto: AudioObjectID, _ selector: AudioObjectPropertySelector, _ valor: T,
                            _ alcance: AudioObjectPropertyScope) -> Bool {
        var d = direccion(selector, alcance)
        var modificable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(objeto, &d, &modificable) == noErr, modificable.boolValue else { return false }
        var v = valor
        return AudioObjectSetPropertyData(objeto, &d, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
    }

    static func lista(_ objeto: AudioObjectID, _ selector: AudioObjectPropertySelector,
                      _ alcance: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var d = direccion(selector, alcance)
        var tam: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objeto, &d, 0, nil, &tam) == noErr, tam > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(tam) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(objeto, &d, 0, nil, &tam, &ids) == noErr else { return [] }
        return ids
    }

    static func salida() -> AudioDeviceID? {
        leer(sistema, kAudioHardwarePropertyDefaultOutputDevice, AudioDeviceID(0)).flatMap { $0 == 0 ? nil : $0 }
    }

    static func volumen(_ id: AudioDeviceID) -> Double? {
        leer(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0), kAudioDevicePropertyScopeOutput).map(Double.init)
    }

    static func ponerVolumen(_ id: AudioDeviceID, _ valor: Double) -> Bool {
        escribir(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(valor), kAudioDevicePropertyScopeOutput)
    }

    static func silenciado(_ id: AudioDeviceID) -> Bool? {
        leer(id, kAudioDevicePropertyMute, UInt32(0), kAudioDevicePropertyScopeOutput).map { $0 != 0 }
    }

    static func silenciar(_ id: AudioDeviceID, _ si: Bool) -> Bool {
        escribir(id, kAudioDevicePropertyMute, UInt32(si ? 1 : 0), kAudioDevicePropertyScopeOutput)
    }

    /// Dispositivos con micrófono.
    static func entradas() -> [AudioDeviceID] {
        lista(sistema, kAudioHardwarePropertyDevices).filter { !lista($0, kAudioDevicePropertyStreams, kAudioDevicePropertyScopeInput).isEmpty }
    }

    static func corriendo(_ id: AudioDeviceID) -> Bool {
        (leer(id, kAudioDevicePropertyDeviceIsRunningSomewhere, UInt32(0)) ?? 0) != 0
    }

    /// Procesos que están grabando del micrófono (macOS 14.2+).
    static func procesosEscuchando() -> [(pid: pid_t, bundle: String)] {
        lista(sistema, kAudioHardwarePropertyProcessObjectList).compactMap { proceso in
            guard (leer(proceso, kAudioProcessPropertyIsRunningInput, UInt32(0)) ?? 0) != 0,
                  let pid = leer(proceso, kAudioProcessPropertyPID, pid_t(0)) else { return nil }
            var d = direccion(kAudioProcessPropertyBundleID)
            var texto: Unmanaged<CFString>?
            var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let bundle = AudioObjectGetPropertyData(proceso, &d, 0, nil, &tam, &texto) == noErr
                ? (texto?.takeRetainedValue() as String? ?? "") : ""
            return (pid, bundle)
        }
    }
}

// MARK: - Brillo (DisplayServices, el mismo que usa macOS para la pantalla integrada)

enum Brillo {
    private typealias Leer = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Poner = @convention(c) (UInt32, Float) -> Int32

    private static let marco = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let leerFn: Leer? = dlsym(marco, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: Leer.self) }
    private static let ponerFn: Poner? = dlsym(marco, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: Poner.self) }

    /// La pantalla del Mac (nil con la tapa cerrada).
    static func pantallaIntegrada() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        guard CGGetActiveDisplayList(8, &ids, &n) == .success else { return nil }
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func leer(_ pantalla: CGDirectDisplayID) -> Double? {
        var valor: Float = 0
        guard let leerFn, leerFn(pantalla, &valor) == 0 else { return nil }
        return Double(valor)
    }

    static func poner(_ pantalla: CGDirectDisplayID, _ valor: Double) -> Bool {
        guard let ponerFn else { return false }
        return ponerFn(pantalla, Float(valor)) == 0
    }
}
