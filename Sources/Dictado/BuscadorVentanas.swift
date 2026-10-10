import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation
import SwiftUI

// Buscador de ventanas (Hyper + Espacio): un panel de vidrio con las ventanas de todas las apps, incluidas las
// minimizadas. Escribes para filtrar, ↑↓ para moverte, ↩ para saltar, Esc para cerrar.
// Todo se lee por Accesibilidad (título, app, minimizada): sin capturas ni miniaturas, así que no pide Grabación
// de pantalla. Cada app tiene un tiempo de espera corto; la que no responde se salta.

/// Una ventana encontrada. `elemento` es nil en los renders de muestra.
struct VentanaEncontrada: Identifiable, @unchecked Sendable {
    let id: String
    let pid: pid_t
    let app: String
    let bundle: String?
    let titulo: String
    let minimizada: Bool
    let appOculta: Bool
    var elemento: AXUIElement?
    var icono: NSImage?

    /// Hay ventanas sin título (algunas apps Electron): se muestra el nombre de la app.
    var tituloVisible: String { titulo.isEmpty ? app : titulo }
    var guardada: Bool { minimizada || appOculta }
}

@MainActor @Observable
final class EstadoBuscador {
    var ventanas: [VentanaEncontrada] = []
    var busqueda = ""
    var seleccion: String?
    var cargando = false
}

/// Interruptor del módulo, panel y salto a la ventana elegida.
@MainActor
final class BuscadorVentanas {
    /// Id de Carbon reservado para este módulo (rango 40-49).
    private static let idAtajo: UInt32 = 40

    let estado = EstadoBuscador()
    private let contexto: ContextoModulos
    private let panel: PanelClave
    private var monitor: Any?
    private var registrado = false
    /// Cada apertura tiene su número: si cierras y abres rápido, la búsqueda vieja no pisa a la nueva.
    private var generacion = 0
    private var iconos: [String: NSImage] = [:]

    init(_ contexto: ContextoModulos) {
        self.contexto = contexto
        panel = PanelClave(contentRect: NSRect(x: 0, y: 0, width: VistaBuscador.ancho, height: VistaBuscador.alto),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: VistaBuscador(estado: estado, control: self))
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cerrar() }
        }
        NotificationCenter.default.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] nota in
            guard (nota.userInfo?["funcion"] as? String) == Funcion.buscador.rawValue else { return }
            MainActor.assumeIsolated { self?.sincronizar() }
        }
        sincronizar()
    }

    private func sincronizar() {
        if Funcion.buscador.activa {
            guard !registrado else { return }
            registrado = true
            let ok = Atajos.shared.registrar(id: Self.idAtajo, tecla: kVK_Space, modificadores: cmdKey | optionKey | controlKey | shiftKey,
                                             alPresionar: { [weak self] in self?.alternar() })
            if !ok { contexto.avisar("Hyper + Espacio lo usa otra app", "keyboard.badge.exclamationmark", nil) }
        } else {
            guard registrado else { return }
            registrado = false
            Atajos.shared.quitar(id: Self.idAtajo)
            cerrar()
        }
    }

    var abierto: Bool { panel.isVisible }

    func alternar() { abierto ? cerrar() : abrir() }

    func abrir() {
        guard AXIsProcessTrusted() else {
            contexto.avisar("Activa Accesibilidad para buscar ventanas", "lock", nil)
            return
        }
        generacion += 1
        let numero = generacion
        let frente = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = Self.appsVisibles()
        estado.busqueda = ""
        estado.ventanas = []
        estado.seleccion = nil
        estado.cargando = true
        if let pantalla = NSScreen.main {
            let z = pantalla.visibleFrame
            panel.setFrameOrigin(NSPoint(x: z.midX - VistaBuscador.ancho / 2, y: z.midY - VistaBuscador.alto / 2 + z.height * 0.08))
        }
        panel.makeKeyAndOrderFront(nil)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
                nonisolated(unsafe) let e = evento  // el monitor local siempre corre en el hilo principal
                return MainActor.assumeIsolated { self?.tecla(e) ?? e }
            }
        }
        // Las consultas de Accesibilidad van fuera del hilo principal y en paralelo: una app lenta no frena el panel.
        Task { [weak self] in
            let encontradas = await Task.detached(priority: .userInitiated) { BuscadorVentanas.recolectar(apps) }.value
            self?.mostrar(encontradas, frente: frente, generacion: numero)
        }
    }

    func cerrar() {
        guard abierto else { return }
        panel.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func mostrar(_ encontradas: [VentanaEncontrada], frente: pid_t?, generacion numero: Int) {
        guard numero == generacion, abierto else { return }
        var lista = Self.ordenar(encontradas)
        for i in lista.indices { lista[i].icono = icono(lista[i]) }
        estado.ventanas = lista
        estado.cargando = false
        // Si ya empezaste a escribir mientras se leían las ventanas, manda lo escrito.
        estado.seleccion = estado.busqueda.isEmpty ? Self.inicial(lista, frente: frente) : visibles.first?.id
    }

    var visibles: [VentanaEncontrada] { Self.filtrar(estado.ventanas, estado.busqueda) }

    func mover(_ paso: Int) {
        let lista = visibles
        guard !lista.isEmpty else { return }
        let i = lista.firstIndex { $0.id == estado.seleccion } ?? -paso
        estado.seleccion = lista[min(max(i + paso, 0), lista.count - 1)].id
    }

    /// Quita el minimizado, la trae al frente y activa su app.
    func elegir(_ v: VentanaEncontrada) {
        cerrar()
        guard let ventana = v.elemento else { return }
        let app = NSRunningApplication(processIdentifier: v.pid)
        AXUIElementSetMessagingTimeout(ventana, 0.3)
        if v.minimizada { AXUIElementSetAttributeValue(ventana, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        if app?.isHidden == true { app?.unhide() }
        AXUIElementPerformAction(ventana, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(ventana, kAXMainAttribute as CFString, kCFBooleanTrue)
        // Desde un panel que no activa a Dictado, macOS puede ignorar activate(); por Accesibilidad sí obedece.
        let appAX = AXUIElementCreateApplication(v.pid)
        AXUIElementSetMessagingTimeout(appAX, 0.3)
        AXUIElementSetAttributeValue(appAX, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app?.activate()
        AXUIElementPerformAction(ventana, kAXRaiseAction as CFString)
    }

    private func elegirSeleccion() {
        guard let v = visibles.first(where: { $0.id == estado.seleccion }) ?? visibles.first else { return }
        elegir(v)
    }

    private func tecla(_ evento: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return evento }
        switch Int(evento.keyCode) {
        case kVK_Escape: cerrar(); return nil
        case kVK_UpArrow: mover(-1); return nil
        case kVK_DownArrow: mover(1); return nil
        case kVK_Return, kVK_ANSI_KeypadEnter: elegirSeleccion(); return nil
        default: return evento
        }
    }

    /// Ícono de la app en mapa de bits de 64 px (más liviano que el multirresolución de macOS).
    private func icono(_ v: VentanaEncontrada) -> NSImage? {
        let clave = v.bundle ?? "pid-\(v.pid)"
        if let i = iconos[clave] { return i }
        guard let original = NSRunningApplication(processIdentifier: v.pid)?.icon else { return nil }
        let i = Self.mapaDeBits(original)
        iconos[clave] = i
        return i
    }

    static func mapaDeBits(_ original: NSImage) -> NSImage {
        let i = NSImage(size: NSSize(width: 64, height: 64))
        i.lockFocus()
        original.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        i.unlockFocus()
        return i
    }

    // MARK: Recolección

    /// Lo necesario de cada app, copiado en el hilo principal para usarlo en paralelo.
    struct AppVisible: Sendable {
        let pid: pid_t
        let nombre: String
        let bundle: String?
        let oculta: Bool
    }

    /// Apps con interfaz (no las de barra de menús), en el orden en que se ven en pantalla: la del frente primero.
    static func appsVisibles() -> [AppVisible] {
        let orden = ordenEnPantalla()
        let propio = getpid()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != propio && !$0.isTerminated }
            .enumerated()
            .sorted { a, b in
                (orden[a.element.processIdentifier] ?? Int.max, a.offset) < (orden[b.element.processIdentifier] ?? Int.max, b.offset)
            }
            .map { AppVisible(pid: $0.element.processIdentifier, nombre: $0.element.localizedName ?? "App",
                              bundle: $0.element.bundleIdentifier, oculta: $0.element.isHidden) }
    }

    /// Orden de las apps según sus ventanas en pantalla (de adelante hacia atrás). Solo usa el dueño y la capa
    /// de cada ventana, que macOS entrega sin Grabación de pantalla (los títulos no se piden aquí).
    private static func ordenEnPantalla() -> [pid_t: Int] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var orden: [pid_t: Int] = [:]
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, orden[pid] == nil { orden[pid] = orden.count }
        }
        return orden
    }

    /// Lee las ventanas de todas las apps a la vez, con `espera` segundos como máximo por consulta.
    nonisolated static func recolectar(_ apps: [AppVisible], espera: Float = 0.2) -> [VentanaEncontrada] {
        let resultados = Resultados(apps.count)
        DispatchQueue.concurrentPerform(iterations: apps.count) { i in
            resultados.poner(i, ventanas(de: apps[i], espera: espera))
        }
        return resultados.todas
    }

    nonisolated static func ventanas(de app: AppVisible, espera: Float) -> [VentanaEncontrada] {
        let elemento = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(elemento, espera)
        // Si la app no contesta a tiempo, no aparece (mejor eso que trabar el panel).
        guard let lista = AX.valor(elemento, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        let atributos = [kAXTitleAttribute, kAXMinimizedAttribute, kAXSubroleAttribute] as CFArray
        var encontradas: [VentanaEncontrada] = []
        for (i, ventana) in lista.enumerated() {
            AXUIElementSetMessagingTimeout(ventana, espera)
            var valores: CFArray?
            let error = AXUIElementCopyMultipleAttributeValues(ventana, atributos, AXCopyMultipleAttributeOptions(rawValue: 0), &valores)
            if error == .cannotComplete { break }  // dejó de responder a mitad: se salta el resto
            guard error == .success, let v = valores as? [AnyObject], v.count == 3 else { continue }
            let minimizada = (v[1] as? Bool) ?? false
            let subrol = v[2] as? String
            // Ventanas normales y diálogos; fuera paletas flotantes, menús y demás piezas sueltas.
            guard minimizada || subrol == kAXStandardWindowSubrole || subrol == kAXDialogSubrole else { continue }
            let titulo = ((v[0] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            encontradas.append(VentanaEncontrada(id: "\(app.pid)-\(i)", pid: app.pid, app: app.nombre, bundle: app.bundle,
                                                 titulo: titulo, minimizada: minimizada, appOculta: app.oculta, elemento: ventana))
        }
        return encontradas
    }

    private final class Resultados: @unchecked Sendable {
        private var porApp: [[VentanaEncontrada]]
        private let cerrojo = NSLock()
        init(_ cantidad: Int) { porApp = Array(repeating: [], count: cantidad) }
        func poner(_ i: Int, _ v: [VentanaEncontrada]) { cerrojo.withLock { porApp[i] = v } }
        var todas: [VentanaEncontrada] { cerrojo.withLock { porApp.flatMap { $0 } } }
    }

    // MARK: Orden y filtro (puros)

    /// Primero las que están en pantalla (en el orden de las apps), después las minimizadas y las de apps ocultas.
    nonisolated static func ordenar(_ ventanas: [VentanaEncontrada]) -> [VentanaEncontrada] {
        ventanas.filter { !$0.guardada } + ventanas.filter(\.guardada)
    }

    /// La primera suele ser la ventana donde ya estás: se empieza en la segunda para volver a la anterior con
    /// Hyper + Espacio, ↩ (como ⌘Tab).
    nonisolated static func inicial(_ lista: [VentanaEncontrada], frente: pid_t?) -> String? {
        if lista.count > 1, lista[0].pid == frente, !lista[0].guardada { return lista[1].id }
        return lista.first?.id
    }

    nonisolated static func normalizar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es")).lowercased()
    }

    /// Cada palabra escrita tiene que aparecer en el título o en el nombre de la app, sin importar tildes ni
    /// mayúsculas. Arriba, las que tienen una palabra que empieza como lo primero que escribiste.
    nonisolated static func filtrar(_ ventanas: [VentanaEncontrada], _ consulta: String) -> [VentanaEncontrada] {
        let palabras = normalizar(consulta).split(whereSeparator: \.isWhitespace).map(String.init)
        guard let primera = palabras.first else { return ventanas }
        let coinciden = ventanas.compactMap { v -> (VentanaEncontrada, Bool)? in
            let texto = normalizar(v.titulo + " " + v.app)
            guard palabras.allSatisfy({ texto.contains($0) }) else { return nil }
            let empieza = texto.split { !$0.isLetter && !$0.isNumber }.contains { $0.hasPrefix(primera) }
            return (v, empieza)
        }
        return coinciden.filter(\.1).map(\.0) + coinciden.filter { !$0.1 }.map(\.0)
    }
}
