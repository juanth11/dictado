import AppKit
import CoreAudio
import CoreMediaIO
import Observation

/// Cámara y micrófono en uso: el punto verde (cámara) o naranja (micrófono) del iPhone, en el ala de la isla.
/// Todo llega por avisos del sistema, sin consultar en bucle: CoreAudio avisa cuando un micrófono arranca o
/// para y CoreMediaIO cuando una cámara. No cuenta el dictado de la propia app (ya se ve en la isla) ni la
/// escucha permanente de "Oye Siri" (CoreSpeech).
@MainActor @Observable
final class Privacidad {
    var camara = false
    var microfono = false
    var icono: NSImage?   // app que escucha, si se sabe
    var nombre = ""
    var desde: Date?      // desde cuándo (para el cronómetro de llamada)
    @ObservationIgnored var pid: pid_t = 0

    var activo: Bool { camara || microfono }

    /// Vuelve a la app de la llamada.
    func irALaApp() {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    @ObservationIgnored private var entradas = Set<AudioObjectID>()
    @ObservationIgnored private var camaras = Set<CMIOObjectID>()
    @ObservationIgnored private var pendiente = false

    init(vivo: Bool = true) {
        guard vivo else { return }
        escucharAudio(Audio.sistema, kAudioHardwarePropertyDevices) { [weak self] in self?.vigilarEntradas() }
        escucharAudio(Audio.sistema, kAudioHardwarePropertyProcessObjectList) { [weak self] in self?.programarRevision() }
        escucharCamara(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)) { [weak self] in
            self?.vigilarCamaras()
        }
        vigilarEntradas()
        vigilarCamaras()
    }

    // MARK: Avisos del sistema

    private func escucharAudio(_ objeto: AudioObjectID, _ selector: AudioObjectPropertySelector, _ accion: @escaping @MainActor () -> Void) {
        var d = Audio.direccion(selector)
        AudioObjectAddPropertyListenerBlock(objeto, &d, .main) { _, _ in MainActor.assumeIsolated { accion() } }
    }

    private func escucharCamara(_ objeto: CMIOObjectID, _ selector: CMIOObjectPropertySelector, _ accion: @escaping @MainActor () -> Void) {
        var d = CMIOObjectPropertyAddress(mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                          mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        CMIOObjectAddPropertyListenerBlock(objeto, &d, .main) { _, _ in MainActor.assumeIsolated { accion() } }
    }

    private func vigilarEntradas() {
        for id in Audio.entradas() where !entradas.contains(id) {
            entradas.insert(id)
            escucharAudio(id, kAudioDevicePropertyDeviceIsRunningSomewhere) { [weak self] in self?.programarRevision() }
        }
        programarRevision()
    }

    private func vigilarCamaras() {
        for id in Self.listaCamaras() where !camaras.contains(id) {
            camaras.insert(id)
            escucharCamara(id, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)) { [weak self] in
                self?.programarRevision()
            }
        }
        programarRevision()
    }

    /// Varios avisos llegan juntos (dispositivo + lista de procesos): se revisa una vez.
    private func programarRevision() {
        guard !pendiente else { return }
        pendiente = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                self?.pendiente = false
                self?.revisar()
            }
        }
    }

    func revisar() {
        let camaraAhora = Self.listaCamaras().contains(where: Self.camaraCorriendo)
        var app: NSRunningApplication?
        var microAhora = false
        if Audio.entradas().contains(where: Audio.corriendo) {
            let propio = getpid()
            let otros = Audio.procesosEscuchando().filter { $0.pid != propio && !$0.bundle.hasPrefix("com.apple.CoreSpeech") }
            microAhora = !otros.isEmpty
            app = otros.lazy.compactMap { Self.appResponsable(de: $0.pid) }.first
        }
        if camara != camaraAhora { camara = camaraAhora }
        if microfono != microAhora { microfono = microAhora }
        if activo && desde == nil { desde = Date() }
        if !activo { desde = nil }
        pid = app?.processIdentifier ?? 0
        let nuevoNombre = app?.localizedName ?? ""
        if nombre != nuevoNombre {
            nombre = nuevoNombre
            icono = app?.icon.map { Self.mapaDeBits($0) }
        }
    }

    /// Copia de 36 px del ícono de la app: más liviana que el ícono multirresolución de macOS.
    static func mapaDeBits(_ original: NSImage, lado: CGFloat = 36) -> NSImage {
        let i = NSImage(size: NSSize(width: lado, height: lado))
        i.lockFocus()
        original.draw(in: NSRect(x: 0, y: 0, width: lado, height: lado))
        i.unlockFocus()
        return i
    }

    // MARK: Consultas

    private static func listaCamaras() -> [CMIOObjectID] {
        var d = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                          mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                          mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let sistema = CMIOObjectID(kCMIOObjectSystemObject)
        var tam: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(sistema, &d, 0, nil, &tam) == noErr, tam > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(tam) / MemoryLayout<CMIOObjectID>.size)
        var usado: UInt32 = 0
        guard CMIOObjectGetPropertyData(sistema, &d, 0, nil, tam, &usado, &ids) == noErr else { return [] }
        return ids
    }

    private static func camaraCorriendo(_ id: CMIOObjectID) -> Bool {
        var d = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                          mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                          mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var valor: UInt32 = 0
        var usado: UInt32 = 0
        return CMIOObjectGetPropertyData(id, &d, 0, nil, UInt32(MemoryLayout<UInt32>.size), &usado, &valor) == noErr && valor != 0
    }

    /// La app "dueña" del proceso: el micrófono de Meet lo abre un ayudante de Chrome, no Chrome.
    private typealias Responsable = @convention(c) (pid_t) -> pid_t
    private static let responsable: Responsable? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Responsable.self) }

    private static func appResponsable(de pid: pid_t) -> NSRunningApplication? {
        let dueno = responsable?(pid) ?? pid
        for candidato in [dueno, pid] {
            if let app = NSRunningApplication(processIdentifier: candidato), app.activationPolicy == .regular { return app }
        }
        return nil
    }
}
