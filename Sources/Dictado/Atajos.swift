import Carbon.HIToolbox

/// Atajos globales con la API de Carbon: entrega "presionado" y "soltado" (necesario para push-to-talk)
/// y no requiere permiso de Accesibilidad.
@MainActor
final class Atajos {
    static let shared = Atajos()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var acciones: [UInt32: (presionar: () -> Void, soltar: () -> Void)] = [:]

    private init() {
        var tipos = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, evento, _ in
            var id = EventHotKeyID()
            GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let presionado = GetEventKind(evento) == UInt32(kEventHotKeyPressed)
            let clave = id.id
            Task { @MainActor in Atajos.shared.disparar(clave, presionado: presionado) }
            return noErr
        }, tipos.count, &tipos, nil, nil)
    }

    @discardableResult
    func registrar(id: UInt32, tecla: Int, modificadores: Int,
                   alPresionar: @escaping () -> Void, alSoltar: @escaping () -> Void = {}) -> Bool {
        quitar(id: id)
        var ref: EventHotKeyRef?
        let firma = EventHotKeyID(signature: OSType(0x4449_4354), id: id)  // 'DICT'
        let estado = RegisterEventHotKey(UInt32(tecla), UInt32(modificadores), firma, GetApplicationEventTarget(), 0, &ref)
        guard estado == noErr, let ref else { return false }
        refs[id] = ref
        acciones[id] = (alPresionar, alSoltar)
        return true
    }

    func quitar(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        acciones[id] = nil
    }

    private func disparar(_ id: UInt32, presionado: Bool) {
        guard let a = acciones[id] else { return }
        presionado ? a.presionar() : a.soltar()
    }
}
