import AppKit
import Observation
import SwiftUI

/// La ventana del centro de mando: Hoy (el brief del día), Metas (semana, mes y trimestre) y Orquesta (tus agentes).
/// Lee el estado con el comando configurado (CentroDatos.swift) al abrirse y cada 5 minutos mientras está abierta.
/// Se crea al abrirla y se suelta al cerrarla: cerrada no ocupa memoria ni corre nada.
/// Atajos con la ventana al frente: ⌘1 Hoy · ⌘2 Metas · ⌘3 Orquesta · ⌘R actualizar · ⌘W cerrar.
@MainActor
final class Centro: NSObject, NSWindowDelegate {
    @MainActor @Observable
    final class Navegacion {
        var seccion = SeccionCentro.hoy
    }

    private let store = CentroStore()
    private let navegacion = Navegacion()
    /// Las sesiones de Claude Code: las de la isla si está encendida; si no, unas propias mientras la ventana vive.
    private let claudeIsla: SesionesClaude?
    private var claudePropio: SesionesClaude?
    private var ventana: NSWindow?
    private var reloj: Timer?
    private var monitor: Any?

    /// Solo para la prueba de humo: vidrio simulado, porque el real lo compone el sistema y no sale en una foto.
    private let vidrioSimulado: Bool

    init(claude: SesionesClaude?, vidrioSimulado: Bool = false) {
        claudeIsla = claude
        self.vidrioSimulado = vidrioSimulado
    }

    var abierta: Bool { ventana?.isVisible == true }
    var cargando: Bool { store.cargando }

    func abrir(_ seccion: SeccionCentro? = nil) {
        if let seccion { navegacion.seccion = seccion }
        if claudeIsla == nil && claudePropio == nil { claudePropio = SesionesClaude() }
        let v = ventana ?? crearVentana()
        ventana = v
        NSApp.activate(ignoringOtherApps: true)
        v.makeKeyAndOrderFront(nil)
        store.actualizar()
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.actualizar() }
        }
        instalarAtajos()
    }

    func cerrar() { ventana?.performClose(nil) }

    private func crearVentana() -> NSWindow {
        let v = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        v.title = "Centro de mando"
        v.titlebarAppearsTransparent = true
        v.titleVisibility = .hidden
        v.isMovableByWindowBackground = true
        v.backgroundColor = .clear
        v.isOpaque = false
        v.hasShadow = true
        v.appearance = NSAppearance(named: .darkAqua)
        v.minSize = NSSize(width: 1120, height: 780)
        v.isReleasedWhenClosed = false
        v.collectionBehavior = [.fullScreenPrimary]
        v.delegate = self
        let raiz = RaizCentro(store: store, navegacion: navegacion, claude: claudeIsla ?? claudePropio, simulado: vidrioSimulado,
                              abrir: { [weak self] destino in self?.abrir(destino: destino) })
        let anfitrion = NSHostingView(rootView: raiz)
        anfitrion.sizingOptions = []   // el tamaño lo decide la ventana (redimensionable), no el ideal de SwiftUI
        v.contentView = anfitrion
        v.center()
        v.setFrameAutosaveName("CentroDeMando")
        // Un tamaño guardado que ya no cabe (otra pantalla, otra resolución) vuelve al de siempre.
        if let pantalla = (v.screen ?? NSScreen.main)?.visibleFrame,
           v.frame.height > pantalla.height || v.frame.width > pantalla.width {
            v.setContentSize(NSSize(width: min(1260, pantalla.width), height: min(820, pantalla.height)))
            v.center()
        }
        return v
    }

    /// Ruta relativa al cerebro (el tablero de finanzas, el archivo de metas…) o un enlace web (una noticia).
    /// Solo http(s): los enlaces de las noticias son de terceros y no deben poder abrir otros esquemas.
    private func abrir(destino: String) {
        if destino.contains("://") {
            if let u = URL(string: destino), ["http", "https"].contains(u.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(u) }
            return
        }
        guard let raiz = store.estado?.local?.cerebro, !destino.contains("..") else { return }
        let url = URL(fileURLWithPath: raiz).appendingPathComponent(destino)
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }

    private func instalarAtajos() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
            nonisolated(unsafe) let e = evento
            return MainActor.assumeIsolated {
                guard let self, let v = self.ventana, v.isKeyWindow, e.modifierFlags.contains(.command) else { return e }
                switch e.charactersIgnoringModifiers {
                case "1": self.navegacion.seccion = .hoy
                case "2": self.navegacion.seccion = .metas
                case "3": self.navegacion.seccion = .orquesta
                case "r": self.store.actualizar()
                case "w": v.performClose(nil)
                default: return e
                }
                return nil
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        reloj?.invalidate()
        reloj = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        claudePropio = nil
        // Se suelta la ventana con toda su jerarquía de vistas (después de que AppKit termine de cerrarla).
        DispatchQueue.main.async { [weak self] in self?.ventana = nil }
    }

    /// Foto de la ventana tal cual está (para la prueba de humo). El vidrio lo compone el sistema y no sale en la foto.
    func capturar() -> Data? {
        guard let vista = ventana?.contentView, let rep = vista.bitmapImageRepForCachingDisplay(in: vista.bounds) else { return nil }
        vista.cacheDisplay(in: vista.bounds, to: rep)
        // El fondo de la ventana es transparente (el vidrio lo pone el sistema): se compone sobre negro para verla.
        let imagen = NSImage(size: vista.bounds.size)
        imagen.lockFocus()
        NSColor(white: 0.08, alpha: 1).setFill()
        NSRect(origin: .zero, size: vista.bounds.size).fill()
        rep.draw(in: NSRect(origin: .zero, size: vista.bounds.size), from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: nil)
        imagen.unlockFocus()
        guard let tiff = imagen.tiffRepresentation, let salida = NSBitmapImageRep(data: tiff) else { return nil }
        return salida.representation(using: .png, properties: [:])
    }
}

private struct RaizCentro: View {
    let store: CentroStore
    @Bindable var navegacion: Centro.Navegacion
    let claude: SesionesClaude?
    let simulado: Bool
    let abrir: (String) -> Void

    var body: some View {
        let ctx = ContextoCentro(sesiones: claude?.sesiones ?? [], leido: store.leido, cargando: store.cargando,
                                 error: store.error, configurado: store.configurado, enVentana: true,
                                 actualizar: { store.actualizar() }, abrir: abrir,
                                 abrirSesion: { SesionesClaude.abrir($0) })
        VistaCentro(estado: store.estado, ctx: ctx, seccion: $navegacion.seccion)
            .panelHalo(simulado: simulado)
            .ignoresSafeArea()
    }
}

/// Otra instancia (o un atajo del sistema) le pide a Dictado abierto que muestre el centro: `Dictado --abrir-centro`.
extension Notification.Name {
    static let abrirCentro = Notification.Name("app.dictado.abrirCentro")
}

func pedirAbrirCentro() {
    DistributedNotificationCenter.default().postNotificationName(.abrirCentro, object: nil, userInfo: nil, deliverImmediately: true)
}

/// Prueba de humo de la ventana real: la abre, espera el estado del comando configurado y guarda una foto.
/// `Dictado --probar-ventana-centro salida.png [hoy|metas|orquesta]`
@MainActor
func probarVentanaCentro(_ destino: URL, escena: String?) -> Bool {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let centro = Centro(claude: nil, vidrioSimulado: true)
    centro.abrir(SeccionCentro(rawValue: escena ?? "hoy"))
    let limite = Date().addingTimeInterval(45)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    while centro.cargando && Date() < limite { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    guard let png = centro.capturar() else { return false }
    centro.cerrar()
    return (try? png.write(to: destino)) != nil
}
