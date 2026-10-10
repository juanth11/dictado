import AppKit
import Carbon.HIToolbox
import IOKit
import IOKit.hid
import os

private let log = Logger(subsystem: "app.dictado", category: "hyper")

// Tecla hyper: Bloq Mayús mantenida con otra tecla = ⌃⌥⌘⇧; pulsada sola = Bloq Mayús de siempre.
//
// Dos piezas:
// 1. Mapeo HID (`UserKeyMapping`, lo mismo que hace `hidutil`): Bloq Mayús llega al sistema como F18. Así macOS
//    nunca prende el bloqueo de mayúsculas y la tecla queda libre para usarla como modificador.
// 2. Event tap de teclado: F18 abajo activa hyper (y se consume); mientras está activa, cada tecla lleva los cuatro
//    modificadores; F18 arriba sin otra tecla en medio alterna el bloqueo de mayúsculas, como siempre.
//
// Dónde se intercepta: en el punto HID (`.cghidEventTap`), donde los eventos entran al WindowServer. Es el primer
// punto de la cadena, así que todo lo que viene después ve la combinación ya armada: los atajos de Carbon
// (`RegisterEventHotKey`, los de Dictado y los de otras apps como Raycast), los event taps de sesión de otras
// apps y la app al frente (menús y atajos propios). En el punto de sesión, en cambio, los taps HID de otras
// apps verían la tecla sin modificadores. Si macOS no deja crear el tap HID, se usa el de sesión como respaldo.
//
// El tap corre en un hilo propio con su run loop: si el hilo principal de Dictado se ocupa (transcribir, dibujar,
// esperar a una app por Accesibilidad), el teclado de todo el Mac no se traba ni macOS apaga el tap por demora.
//
// Riesgo: si Dictado se cierra mal (se cuelga o se fuerza la salida), el mapeo queda puesto y Bloq Mayús no hace
// nada hasta reiniciar el Mac o volver a abrir Dictado. Salir con el menú, con `pkill` o al cerrar sesión lo
// quita; para recuperarla a mano: `Dictado --quitar-hyper`.

/// Interruptor del módulo: aplica o quita el mapeo, el tap y los atajos según `Funcion.hyper`.
@MainActor
final class TeclaHyper {
    /// Ids de Carbon reservados para este módulo: 20-29.
    private enum Atajo: UInt32 { case portapapeles = 20, captura = 21, salud = 22, reunion = 23 }

    private let contexto: ContextoModulos
    private let tap = TapHyper()
    private var vigia: VigiaTeclados?
    private var reintento: Timer?
    private var revision: Timer?
    private var senales: [DispatchSourceSignal] = []
    private var pendiente: DispatchWorkItem?
    private var encendida = false

    init(_ contexto: ContextoModulos) {
        self.contexto = contexto
        let centro = NotificationCenter.default
        centro.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] nota in
            guard (nota.userInfo?["funcion"] as? String) == Funcion.hyper.rawValue else { return }
            MainActor.assumeIsolated { self?.sincronizar() }
        }
        centro.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.alSalir() }
        }
        // Al despertar, macOS vuelve a enumerar los teclados y puede perder el mapeo; un soltar perdido en pleno
        // reposo también dejaría hyper pegada.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tap.reiniciarEstado()
                self?.reaplicar(en: 2)
            }
        }
        if Funcion.hyper.activa {
            encender()
        } else {
            // Si la sesión anterior terminó mal, el mapeo pudo quedar puesto.
            MapeoHyper.cola.async { MapeoHyper.quitar() }
        }
    }

    private func sincronizar() {
        Funcion.hyper.activa ? encender() : apagar()
    }

    private func encender() {
        guard !encendida else { return }
        encendida = true
        registrarAtajos()
        vigia = VigiaTeclados { [weak self] in self?.reaplicar(en: 1.5) }
        conectar()
        if !tap.activo {
            // Sin Accesibilidad no hay tap; se reintenta hasta que la concedas. Mientras tanto Bloq Mayús sigue
            // siendo Bloq Mayús: el mapeo solo se pone con el tap vivo (y se quita el que dejara un cierre brusco).
            MapeoHyper.cola.async { MapeoHyper.quitar() }
            reintento = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.conectar() }
            }
        }
    }

    private func apagar() {
        guard encendida else { return }
        encendida = false
        for a in [Atajo.portapapeles, .captura, .salud, .reunion] { Atajos.shared.quitar(id: a.rawValue) }
        reintento?.invalidate()
        reintento = nil
        desconectar()
        vigia?.detener()
        vigia = nil
    }

    /// Tap primero y mapeo después: si el tap no arranca, Bloq Mayús no se queda sin función.
    private func conectar() {
        guard encendida, !tap.activo, AXIsProcessTrusted() else { return }
        guard tap.iniciar() else { return }
        log.info("tap hyper en \(self.tap.ubicacion == .cghidEventTap ? "HID" : "sesión", privacy: .public)")
        if IsSecureEventInputEnabled() { log.info("Entrada Segura activa: hyper no verá el teclado hasta que se apague") }
        reintento?.invalidate()
        reintento = nil
        MapeoHyper.cola.async { MapeoHyper.aplicar() }
        instalarSenales()
        // Si quitas el permiso con el tap vivo, macOS puede dejar el teclado trabado: se revisa cada 15 s.
        revision = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.revisarPermiso() }
        }
        revision?.tolerance = 5
    }

    private func desconectar() {
        revision?.invalidate()
        revision = nil
        pendiente?.cancel()
        pendiente = nil
        tap.detener()
        quitarSenales()
        MapeoHyper.cola.async { MapeoHyper.quitar() }
    }

    private func revisarPermiso() {
        guard tap.activo, !TapHyper.permitido() else { return }
        log.error("se perdió el permiso de Accesibilidad: se quita hyper")
        desconectar()
        if encendida, reintento == nil {
            reintento = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.conectar() }
            }
        }
    }

    /// Vuelve a poner el mapeo tras despertar o conectar un teclado (varias señales seguidas se juntan en una).
    private func reaplicar(en segundos: Double) {
        guard encendida, tap.activo else { return }
        pendiente?.cancel()
        let tarea = DispatchWorkItem { MapeoHyper.cola.async { MapeoHyper.aplicar() } }
        pendiente = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos, execute: tarea)
    }

    private func alSalir() {
        tap.detener()
        MapeoHyper.cola.sync { MapeoHyper.quitar() }  // síncrono: la app termina justo después
    }

    /// `pkill`, Ctrl+C en la terminal o el cierre de sesión mandan una señal que, sin esto, mataría la app sin
    /// pasar por willTerminate y dejaría Bloq Mayús sin función.
    private func instalarSenales() {
        guard senales.isEmpty else { return }
        for s in [SIGTERM, SIGINT, SIGHUP] {
            signal(s, SIG_IGN)
            let fuente = DispatchSource.makeSignalSource(signal: s, queue: .main)
            fuente.setEventHandler {
                MapeoHyper.cola.sync { MapeoHyper.quitar() }
                NSApplication.shared.terminate(nil)
            }
            fuente.resume()
            senales.append(fuente)
        }
    }

    private func quitarSenales() {
        senales.forEach { $0.cancel() }
        senales = []
        for s in [SIGTERM, SIGINT, SIGHUP] { signal(s, SIG_DFL) }
    }

    /// Atajos del módulo con los cuatro modificadores: funcionan con hyper y también pulsando ⌃⌥⌘⇧ a mano
    /// (incluso en campos de contraseña, donde el tap no ve el teclado).
    private func registrarAtajos() {
        let hyper = cmdKey | optionKey | controlKey | shiftKey
        let lista: [(Atajo, Int, String, () -> Void)] = [
            (.portapapeles, kVK_ANSI_V, "V", { [weak self] in self?.contexto.abrirPortapapeles() }),
            (.captura, kVK_ANSI_C, "C", { [weak self] in self?.contexto.abrirCaptura() }),
            (.salud, kVK_ANSI_M, "M", { [weak self] in self?.contexto.abrirSalud() }),
            (.reunion, kVK_ANSI_U, "U", { [weak self] in self?.contexto.unirseAProxima() }),
        ]
        var ocupados: [String] = []
        for (id, tecla, nombre, accion) in lista {
            if !Atajos.shared.registrar(id: id.rawValue, tecla: tecla, modificadores: hyper, alPresionar: accion) {
                ocupados.append(nombre)
            }
        }
        if !ocupados.isEmpty {
            contexto.avisar("Hyper + \(ocupados.joined(separator: ", ")) lo usa otra app", "keyboard.badge.exclamationmark", nil)
        }
    }
}

// MARK: - Máquina de estados (pura: se prueba con --probar-hyper sin publicar eventos)

/// Decide qué hacer con cada evento de teclado. No toca el sistema: recibe el evento descrito y devuelve el
/// resultado; así se prueba con secuencias construidas a mano.
struct MaquinaHyper {
    static let teclaF18: Int64 = 79  // kVK_F18
    static let modificadores: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
    /// Mantenida más de esto sin tocar otra tecla, no alterna las mayúsculas al soltar: cambiaste de idea.
    static let esperaSola: TimeInterval = 1.0
    /// Hyper tiene que llevar al menos esto abajo para dar por perdido su soltar.
    static let esperaSoltarPerdido: TimeInterval = 0.5

    enum Resultado: Equatable {
        case pasar
        case pasarCon(CGEventFlags)
        case consumir
        case consumirYAlternarMayusculas
    }

    private(set) var activa = false
    private var usada = false
    private var desde: TimeInterval = 0
    /// Si al bajar F18 el estado HID ya la mostraba abajo, ese dato es fiable y sirve para detectar un soltar
    /// perdido (Entrada Segura, tap apagado por demora). Si no, no se usa: mejor sin guarda que sin hyper.
    private var guardaFiable = false
    /// Teclas que bajaron con hyper: su soltar también lleva los modificadores aunque F18 ya se haya soltado.
    private var conHyper: Set<Int64> = []

    /// - Parameter f18Abajo: estado físico de F18 según el sistema; solo se consulta si hace falta.
    mutating func procesar(tipo: CGEventType, tecla: Int64, flags: CGEventFlags, repeticion: Bool,
                           momento: TimeInterval, f18Abajo: () -> Bool) -> Resultado {
        switch tipo {
        case .keyDown where tecla == Self.teclaF18:
            // La repetición automática de la tecla mantenida no reinicia nada.
            if !repeticion || !activa {
                activa = true
                usada = repeticion  // si se perdió el primer evento, que no alterne las mayúsculas
                desde = momento
                guardaFiable = f18Abajo()
            }
            return .consumir
        case .keyUp where tecla == Self.teclaF18:
            guard activa else { return .consumir }
            let sola = !usada && momento - desde <= Self.esperaSola
            activa = false
            usada = false
            return sola ? .consumirYAlternarMayusculas : .consumir
        case .keyDown:
            // F18 ya no está abajo: se perdió su soltar. Solo se cree si hyper lleva más de medio segundo: el estado
            // HID puede ir por delante de la cola del tap y, en un Hyper+↩ soltado muy rápido, el ↩ llegaría solo
            // a la app (y mandaría el mensaje o el formulario).
            if activa, guardaFiable, momento - desde > Self.esperaSoltarPerdido, !f18Abajo() {
                reiniciar()
            }
            guard activa else { return .pasar }
            usada = true
            conHyper.insert(tecla)
            return .pasarCon(flags.union(Self.modificadores))
        case .keyUp:
            return conHyper.remove(tecla) != nil ? .pasarCon(flags.union(Self.modificadores)) : .pasar
        case .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if activa { usada = true }  // hyper + ⇧ o + clic: había intención de combinar, no de mayúsculas
            return .pasar
        default:
            return .pasar
        }
    }

    mutating func reiniciar() {
        activa = false
        usada = false
        guardaFiable = false
        conHyper = []
    }
}

// MARK: - Event tap en hilo propio

/// Dueño del event tap. Lo crea y lo atiende en su propio hilo; desde el hilo principal solo se arranca, se
/// detiene y se reinicia la máquina (con bloques que corren en el hilo del tap).
final class TapHyper: @unchecked Sendable {
    /// Lo que vive en el hilo del tap: el puerto y la máquina. Hay una por arranque, así un apagar y prender
    /// rápidos no mezclan el tap viejo con el nuevo. `@unchecked Sendable`: `bucle` y `lugar` se escriben antes
    /// de avisar al hilo principal; `tap` y `maquina` solo se tocan en el hilo del tap.
    private final class Sesion: @unchecked Sendable {
        var tap: CFMachPort?
        var lugar: CGEventTapLocation?
        var bucle: CFRunLoop?
        var maquina = MaquinaHyper()

        /// Corre en el hilo del tap: tiene que ser rápido, cada tecla del Mac pasa por aquí.
        func manejar(_ proxy: CGEventTapProxy, _ tipo: CGEventType, _ evento: CGEvent) -> Unmanaged<CGEvent>? {
            if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
                maquina.reiniciar()  // pudo perderse el soltar de F18 mientras estaba apagado
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(evento)
            }
            let (sigue, mayusculas) = TapHyper.transformar(
                evento, tipo: tipo, maquina: &maquina, momento: ProcessInfo.processInfo.systemUptime,
                f18Abajo: { CGEventSource.keyState(.hidSystemState, key: CGKeyCode(MaquinaHyper.teclaF18)) })
            // Pulsada sola: Bloq Mayús de siempre (prende o apaga el bloqueo de mayúsculas y su luz).
            if mayusculas { MapeoHyper.alternarBloqMayus() }
            return sigue ? Unmanaged.passUnretained(evento) : nil
        }
    }

    /// Solo en el hilo principal.
    private(set) var activo = false
    private(set) var ubicacion: CGEventTapLocation?
    private var sesion: Sesion?

    private static let mascara: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        .reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }

    /// Arranca el hilo y crea el tap allí. false si macOS no lo permite (falta Accesibilidad).
    @MainActor
    func iniciar() -> Bool {
        guard !activo else { return true }
        let s = Sesion()
        let listo = DispatchSemaphore(value: 0)
        let hilo = Thread {
            if let creado = TapHyper.crear(s) {
                s.tap = creado.tap
                s.lugar = creado.lugar
                s.bucle = CFRunLoopGetCurrent()
                CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, creado.tap, 0), .commonModes)
                CGEvent.tapEnable(tap: creado.tap, enable: true)
            }
            let vivo = s.bucle != nil
            listo.signal()
            if vivo { CFRunLoopRun() }  // duerme hasta que llegue un evento: 0 % de CPU en reposo
        }
        hilo.name = "app.dictado.hyper"
        hilo.qualityOfService = .userInteractive
        hilo.start()
        listo.wait()
        guard s.bucle != nil else { return false }
        sesion = s
        ubicacion = s.lugar
        activo = true
        return true
    }

    @MainActor
    func detener() {
        guard activo, let s = sesion, let bucle = s.bucle else { return }
        activo = false
        sesion = nil
        CFRunLoopPerformBlock(bucle, CFRunLoopMode.commonModes.rawValue) {
            if let tap = s.tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            s.tap = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(bucle)
    }

    @MainActor
    func reiniciarEstado() {
        guard activo, let s = sesion, let bucle = s.bucle else { return }
        CFRunLoopPerformBlock(bucle, CFRunLoopMode.commonModes.rawValue) { s.maquina.reiniciar() }
        CFRunLoopWakeUp(bucle)
    }

    /// ¿Se puede filtrar el teclado ahora? Crear un tap de prueba es más fiable que AXIsProcessTrusted, que a
    /// veces sigue diciendo que sí tras quitar el permiso.
    static func permitido() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let prueba = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                             eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
                                             callback: { _, _, e, _ in Unmanaged.passUnretained(e) }, userInfo: nil)
        else { return false }
        CFMachPortInvalidate(prueba)
        return true
    }

    /// Primero en el punto HID; si macOS no lo deja, en el de sesión.
    private static func crear(_ s: Sesion) -> (tap: CFMachPort, lugar: CGEventTapLocation)? {
        let refcon = Unmanaged.passUnretained(s).toOpaque()  // la sesión vive mientras viva su hilo
        for lugar in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            if let nuevo = CGEvent.tapCreate(
                tap: lugar, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mascara,
                callback: { proxy, tipo, evento, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(evento) }
                    return Unmanaged<Sesion>.fromOpaque(refcon).takeUnretainedValue().manejar(proxy, tipo, evento)
                },
                userInfo: refcon) {
                return (nuevo, lugar)
            }
        }
        return nil
    }

    /// Aplica la máquina a un evento (le suma los modificadores si toca) sin publicarlo. Devuelve si el evento
    /// sigue su camino y si hay que alternar el bloqueo de mayúsculas. `--probar-hyper` la usa con eventos
    /// construidos a mano.
    static func transformar(_ evento: CGEvent, tipo: CGEventType, maquina: inout MaquinaHyper, momento: TimeInterval,
                            f18Abajo: () -> Bool) -> (sigue: Bool, mayusculas: Bool) {
        let resultado = maquina.procesar(
            tipo: tipo, tecla: evento.getIntegerValueField(.keyboardEventKeycode), flags: evento.flags,
            repeticion: evento.getIntegerValueField(.keyboardEventAutorepeat) != 0, momento: momento, f18Abajo: f18Abajo)
        switch resultado {
        case .pasar: return (true, false)
        case .pasarCon(let flags):
            evento.flags = flags
            return (true, false)
        case .consumir: return (false, false)
        case .consumirYAlternarMayusculas: return (false, true)
        }
    }
}

// MARK: - Mapeo HID (UserKeyMapping)

/// Bloq Mayús → F18 en el sistema HID, mezclado con los mapeos que ya tengas. Lee con IOKit y escribe con
/// `/usr/bin/hidutil` (lo que Apple documenta para esto; no pide sudo). Todo pasa por `cola` para que dos
/// lecturas-escrituras no se pisen.
enum MapeoHyper {
    static let bloqMayus: Int64 = 0x7_0000_0039
    static let f18: Int64 = 0x7_0000_006D
    static let cola = DispatchQueue(label: "app.dictado.hyper.mapeo")

    struct Par: Equatable {
        var origen: Int64
        var destino: Int64
    }

    static let propio = Par(origen: bloqMayus, destino: f18)

    // MARK: Lógica pura

    /// El mapeo con hyper y qué guardar para restaurar. Si Bloq Mayús ya tenía un mapeo tuyo (por ejemplo a
    /// Control), se guarda para devolverlo al quitar hyper. Si el mapeo ya era nuestro, se conserva lo guardado.
    static func conHyper(_ actual: [Par], guardado: Par?, yaAplicado: Bool) -> (mapeo: [Par], previo: Par?) {
        let previo = yaAplicado ? guardado : actual.first { $0.origen == bloqMayus }
        return (actual.filter { $0.origen != bloqMayus } + [propio], previo)
    }

    /// El mapeo sin hyper: lo demás intacto y, si lo había, el mapeo previo de Bloq Mayús de vuelta.
    static func sinHyper(_ actual: [Par], previo: Par?) -> [Par] {
        actual.filter { $0.origen != bloqMayus } + (previo.map { [$0] } ?? [])
    }

    /// JSON para `hidutil property --set` (números en decimal).
    static func json(_ mapeo: [Par]) -> String {
        let pares = mapeo.map { "{\"HIDKeyboardModifierMappingSrc\":\($0.origen),\"HIDKeyboardModifierMappingDst\":\($0.destino)}" }
        return "{\"UserKeyMapping\":[\(pares.joined(separator: ","))]}"
    }

    static func pares(_ valor: Any?) -> [Par] {
        ((valor as? [[String: Any]]) ?? []).compactMap { d in
            guard let o = (d[kIOHIDKeyboardModifierMappingSrcKey] as? NSNumber)?.int64Value,
                  let de = (d[kIOHIDKeyboardModifierMappingDstKey] as? NSNumber)?.int64Value else { return nil }
            return Par(origen: o, destino: de)
        }
    }

    // MARK: Sistema

    private static var ajustes: UserDefaults? { UserDefaults(suiteName: "app.dictado") }

    /// true mientras Dictado tenga el mapeo puesto (sobrevive a un cierre brusco: al abrir se limpia).
    static var aplicado: Bool { ajustes?.bool(forKey: "hyper.aplicado") ?? false }

    private static var guardado: Par? {
        guard let v = ajustes?.array(forKey: "hyper.previo") as? [NSNumber], v.count == 2 else { return nil }
        return Par(origen: v[0].int64Value, destino: v[1].int64Value)
    }

    /// El mapeo global del sistema HID (vacío si no hay).
    static func leer() -> [Par] {
        let cliente = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let global = IOHIDEventSystemClientCopyProperty(cliente, kIOHIDUserKeyUsageMapKey as CFString) else { return [] }
        return pares(global)
    }

    /// ¿Hay teclados con su propio mapeo (hecho con `hidutil --matching`) y ninguno global? Entonces hyper no
    /// escribe nada: un mapeo global copiaría el de un teclado a todos y, al quitarlo, quedaría en todos.
    static func hayMapeosPorTeclado() -> Bool {
        let cliente = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        if IOHIDEventSystemClientCopyProperty(cliente, kIOHIDUserKeyUsageMapKey as CFString) != nil { return false }
        let servicios = (IOHIDEventSystemClientCopyServices(cliente) as? [IOHIDServiceClient]) ?? []
        return servicios.contains { s in
            IOHIDServiceClientConformsTo(s, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0
                && !pares(IOHIDServiceClientCopyProperty(s, kIOHIDUserKeyUsageMapKey as CFString) ?? [] as CFArray).isEmpty
        }
    }

    @discardableResult
    static func escribir(_ mapeo: [Par]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--set", json(mapeo)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Pone Bloq Mayús → F18. Se llama de nuevo al despertar o al conectar un teclado (es idempotente).
    @discardableResult
    static func aplicar() -> Bool {
        if hayMapeosPorTeclado() {
            log.error("hay mapeos de teclado propios por dispositivo: la tecla hyper no se aplica para no pisarlos")
            return false
        }
        let actual = leer()
        // Tras un cierre brusco y un reinicio, `aplicado` puede seguir en true sin que el mapeo exista: solo cuenta
        // como aplicado si de verdad está.
        let (mapeo, previo) = conHyper(actual, guardado: guardado, yaAplicado: aplicado && actual.contains(propio))
        guard escribir(mapeo) else {
            log.error("hidutil no pudo aplicar el mapeo de Bloq Mayús")
            return false
        }
        ajustes?.set(true, forKey: "hyper.aplicado")
        if let previo {
            ajustes?.set([NSNumber(value: previo.origen), NSNumber(value: previo.destino)], forKey: "hyper.previo")
        } else {
            ajustes?.removeObject(forKey: "hyper.previo")
        }
        apagarBloqMayus()
        return true
    }

    /// Quita el mapeo si lo puso Dictado (o siempre, con `forzar`, para recuperar Bloq Mayús a mano).
    static func quitar(forzar: Bool = false) {
        let actual = leer()
        guard aplicado || (forzar && actual.contains(propio)) else { return }
        if escribir(sinHyper(actual, previo: guardado)) {
            ajustes?.set(false, forKey: "hyper.aplicado")
            ajustes?.removeObject(forKey: "hyper.previo")
        } else {
            log.error("hidutil no pudo quitar el mapeo de Bloq Mayús")
        }
    }

    /// Si el bloqueo de mayúsculas estaba prendido al poner el mapeo, quedaría así para siempre (la tecla ya no
    /// llega como Bloq Mayús). Se apaga una vez.
    private static func apagarBloqMayus() {
        guard CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift) else { return }
        conBloqueo { conexion in IOHIDSetModifierLockState(conexion, Int32(kIOHIDCapsLockState), false) }
    }

    /// Bloq Mayús pulsada sola: prende o apaga el bloqueo de mayúsculas (y su luz), como sin hyper.
    static func alternarBloqMayus() {
        conBloqueo { conexion in
            var prendido = false
            IOHIDGetModifierLockState(conexion, Int32(kIOHIDCapsLockState), &prendido)
            IOHIDSetModifierLockState(conexion, Int32(kIOHIDCapsLockState), !prendido)
        }
    }

    private static func conBloqueo(_ hacer: (io_connect_t) -> Void) {
        let servicio = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard servicio != 0 else { return }
        defer { IOObjectRelease(servicio) }
        var conexion: io_connect_t = 0
        guard IOServiceOpen(servicio, mach_task_self_, UInt32(kIOHIDParamConnectType), &conexion) == KERN_SUCCESS else { return }
        defer { IOServiceClose(conexion) }
        hacer(conexion)
    }
}

// MARK: - Teclados nuevos

/// Avisa cuando se conecta un teclado (USB o Bluetooth) con una notificación de IOKit: nada en bucle y sin
/// pedir Monitoreo de entrada (no abre el dispositivo, solo mira el registro).
@MainActor
final class VigiaTeclados {
    private var puerto: IONotificationPortRef?
    private var iterador: io_iterator_t = 0
    private let alConectar: () -> Void

    init(alConectar: @escaping () -> Void) {
        self.alConectar = alConectar
        guard let puerto = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.puerto = puerto
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(puerto).takeUnretainedValue(), .commonModes)
        let filtro = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        filtro[kIOHIDDeviceUsagePageKey] = kHIDPage_GenericDesktop
        filtro[kIOHIDDeviceUsageKey] = kHIDUsage_GD_Keyboard
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(puerto, kIOFirstMatchNotification, filtro, { refcon, iterador in
            VigiaTeclados.vaciar(iterador)
            guard let refcon else { return }
            let yo = Unmanaged<VigiaTeclados>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { yo.alConectar() }
        }, refcon, &iterador)
        Self.vaciar(iterador)  // los teclados que ya estaban; recorrer el iterador arma la notificación
    }

    func detener() {
        if iterador != 0 { IOObjectRelease(iterador) }
        iterador = 0
        if let puerto { IONotificationPortDestroy(puerto) }
        puerto = nil
    }

    nonisolated private static func vaciar(_ iterador: io_iterator_t) {
        while case let s = IOIteratorNext(iterador), s != 0 { IOObjectRelease(s) }
    }
}
