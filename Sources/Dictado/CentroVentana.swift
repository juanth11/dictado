import AppKit
import Observation
import SwiftUI

/// El centro de mando como un espacio (CentroEspacio.swift): una ventana sin marco que cubre la pantalla con tu fondo
/// de pantalla y, encima, las ventanas de vidrio de cada sección: Hoy, Metas, Orquesta e Inbox.
/// Lee el estado con el comando configurado (CentroDatos.swift) al abrirse y cada 5 minutos mientras está abierto.
/// Se crea al abrirlo y se suelta al cerrarlo: cerrado no ocupa memoria ni corre nada. Se cierra con esc, ⌘W, la ×
/// o al irte a otra app (como Launchpad), y entonces vuelve la app que estaba al frente.
/// Atajos: ⌘1 Hoy · ⌘2 Metas · ⌘3 Orquesta · ⌘4 Inbox · ⌘R actualizar · esc o ⌘W cerrar.
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
    /// La app que estaba al frente al abrir: a ella se vuelve al cerrar con esc, ⌘W o la ×.
    private var anterior: NSRunningApplication?
    private var cerrando = false

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
        let nueva = ventana == nil
        if nueva, let frontal = NSWorkspace.shared.frontmostApplication, frontal != NSRunningApplication.current { anterior = frontal }
        let v = ventana ?? crearVentana()
        ventana = v
        NSApp.activate(ignoringOtherApps: true)
        if nueva && !vidrioSimulado {
            v.alphaValue = 0
            v.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.22
                v.animator().alphaValue = 1
            }
        } else {
            v.makeKeyAndOrderFront(nil)
        }
        store.actualizar()
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.actualizar() }
        }
        instalarAtajos()
    }

    /// Cierra el espacio. `devolver`: vuelve a la app que estaba al frente (no al irte tú a otra app).
    func cerrar(devolver: Bool = true) {
        guard let v = ventana, !cerrando else { return }
        cerrando = true
        let app = devolver ? anterior : nil
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = vidrioSimulado ? 0 : 0.14
            v.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                v.close()
                app?.activate()
            }
        })
    }

    /// Una ventana sin marco del tamaño de la pantalla donde está el puntero. La barra de menús y el Dock quedan por
    /// encima (son de otro nivel): lo que tapan se le pasa a la vista como margen.
    private func crearVentana() -> NSWindow {
        let pantalla = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let marco = pantalla.frame, util = pantalla.visibleFrame
        let v = VentanaDelEspacio(contentRect: marco, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        v.setFrame(marco, display: false)
        v.title = "Centro de mando"
        v.backgroundColor = .clear
        v.isOpaque = false
        v.hasShadow = false
        v.level = .normal
        v.appearance = NSAppearance(named: .darkAqua)
        v.isReleasedWhenClosed = false
        v.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        v.delegate = self
        let margenes = EdgeInsets(top: marco.maxY - util.maxY, leading: util.minX - marco.minX,
                                  bottom: util.minY - marco.minY, trailing: marco.maxX - util.maxX)
        let raiz = RaizCentro(store: store, navegacion: navegacion, claude: claudeIsla ?? claudePropio, simulado: vidrioSimulado,
                              fondo: vidrioSimulado ? fondoDeMuestra() : FondoEspacio.deEscritorio(pantalla), margenes: margenes,
                              abrir: { [weak self] destino in self?.abrir(destino: destino) },
                              cerrar: { [weak self] in self?.cerrar() })
        let anfitrion = NSHostingView(rootView: raiz)
        anfitrion.sizingOptions = []   // el tamaño lo decide la ventana (la pantalla), no el ideal de SwiftUI
        v.contentView = anfitrion
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
                guard let self, let v = self.ventana, v.isKeyWindow else { return e }
                if e.keyCode == 53 { self.cerrar(); return nil }   // esc
                guard e.modifierFlags.contains(.command) else { return e }
                switch e.charactersIgnoringModifiers {
                case "1": self.navegacion.seccion = .hoy
                case "2": self.navegacion.seccion = .metas
                case "3": self.navegacion.seccion = .orquesta
                case "4": self.navegacion.seccion = .inbox
                case "r": self.store.actualizar()
                case "w": self.cerrar()
                default: return e
                }
                return nil
            }
        }
    }

    /// Te fuiste a otra app (o abriste un enlace): el espacio se cierra, como Launchpad.
    func windowDidResignKey(_ notification: Notification) {
        cerrar(devolver: false)
    }

    func windowWillClose(_ notification: Notification) {
        reloj?.invalidate()
        reloj = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        claudePropio = nil
        // Se suelta la ventana con toda su jerarquía de vistas (después de que AppKit termine de cerrarla).
        DispatchQueue.main.async { [weak self] in
            self?.ventana = nil
            self?.cerrando = false
        }
    }

    /// Foto de la ventana (para la prueba de humo): sirve para ver que abre y lee el estado. Ni el vidrio ni el giro 3D de
    /// las ventanas laterales salen en ella (cacheDisplay no aplica las transformaciones); el diseño se revisa con los renders.
    func capturar() -> Data? {
        guard let vista = ventana?.contentView, let rep = vista.bitmapImageRepForCachingDisplay(in: vista.bounds) else { return nil }
        vista.cacheDisplay(in: vista.bounds, to: rep)
        // El vidrio lo pone el sistema y no sale en la foto: se compone sobre un fondo oscuro para verla.
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

/// Una ventana sin marco que igual recibe el teclado (esc y los atajos).
private final class VentanaDelEspacio: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct RaizCentro: View {
    let store: CentroStore
    @Bindable var navegacion: Centro.Navegacion
    let claude: SesionesClaude?
    let simulado: Bool
    let fondo: NSImage?
    let margenes: EdgeInsets
    let abrir: (String) -> Void
    let cerrar: () -> Void
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var visto = false

    var body: some View {
        let ctx = ContextoCentro(sesiones: claude?.sesiones ?? [], leido: store.leido, cargando: store.cargando,
                                 error: store.error, configurado: store.configurado, enVentana: true,
                                 actualizar: { store.actualizar() }, abrir: abrir,
                                 abrirSesion: { SesionesClaude.abrir($0) },
                                 aplicando: store.aplicando, fallos: store.fallos, puedeActuar: store.puedeActuar,
                                 aplicarInbox: { store.aplicarInbox($0, accion: $1, destino: $2) },
                                 copiar: { texto in
                                     NSPasteboard.general.clearContents()
                                     NSPasteboard.general.setString(texto, forType: .string)
                                 },
                                 cerrar: cerrar, tokensHoy: claude?.tokensHoy ?? 0, respuestasHoy: claude?.respuestasHoy ?? 0)
        ZStack {
            FondoEspacio(imagen: fondo)
            // Al abrir, las ventanas llegan desde un poco más lejos (sin movimiento si así lo pides).
            VistaCentro(estado: store.estado, ctx: ctx, seccion: $navegacion.seccion)
                .padding(margenes)
                .scaleEffect(visto || sinMovimiento || simulado ? 1 : 0.965)
                .opacity(visto || simulado ? 1 : 0)
        }
        .ignoresSafeArea()
        .environment(\.vidrioSimulado, simulado)
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: sinMovimiento ? 0.2 : 0.5)) { visto = true }
        }
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
