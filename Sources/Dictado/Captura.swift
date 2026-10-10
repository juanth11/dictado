import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI
import Vision

/// Opciones del panel de captura (⌘↩). Usan los atajos de captura de macOS; grabar abre la barra nativa.
enum OpcionCaptura: Int, CaseIterable, Identifiable {
    case area, ventana, pantalla, texto, grabar, retraso

    var id: Int { rawValue }

    var titulo: String {
        switch self {
        case .area: return "Área"
        case .ventana: return "Ventana"
        case .pantalla: return "Pantalla completa"
        case .texto: return "Texto de un área"
        case .grabar: return "Grabar pantalla"
        case .retraso: return "Pantalla en 5 s"
        }
    }

    var detalle: String {
        switch self {
        case .area: return "Selecciona con el cursor"
        case .ventana: return "Clic en la ventana"
        case .pantalla: return "Pantalla principal"
        case .texto: return "Copia el texto (OCR)"
        case .grabar: return "Área o pantalla, audio, clics"
        case .retraso: return "Para abrir menús antes"
        }
    }

    var simbolo: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .ventana: return "macwindow"
        case .pantalla: return "display"
        case .texto: return "text.viewfinder"
        case .grabar: return "record.circle"
        case .retraso: return "timer"
        }
    }
}

enum DestinoCaptura: String, CaseIterable {
    case portapapeles, escritorio, descargas, carpeta
}

@MainActor @Observable
final class EstadoCaptura {
    private static let ajustes = UserDefaults(suiteName: "app.dictado")

    var seleccion = 0
    var destino = DestinoCaptura(rawValue: ajustes?.string(forKey: "capturaDestino") ?? "") ?? .portapapeles {
        didSet { Self.ajustes?.set(destino.rawValue, forKey: "capturaDestino") }
    }
    var carpeta = ajustes?.string(forKey: "capturaCarpeta") {
        didSet { Self.ajustes?.set(carpeta, forKey: "capturaCarpeta") }
    }

    /// nil = al portapapeles.
    var carpetaDestino: URL? {
        let fm = FileManager.default
        switch destino {
        case .portapapeles: return nil
        case .escritorio: return fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        case .descargas: return fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .carpeta: return carpeta.map { URL(fileURLWithPath: $0) } ?? fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
    }

    func titulo(_ d: DestinoCaptura) -> String {
        switch d {
        case .portapapeles: return "Portapapeles"
        case .escritorio: return "Escritorio"
        case .descargas: return "Descargas"
        case .carpeta: return carpeta.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Carpeta…"
        }
    }
}

/// ⌘↩: panel de captura. Al elegir, se cierra y lanza la captura; el resultado se avisa en el HUD.
@MainActor
final class Captura {
    let estado = EstadoCaptura()
    /// texto (vacío si es imagen), icono SF Symbol, nota corta.
    var alTerminar: ((String, String, String) -> Void)?
    private let panel: PanelClave
    private var monitor: Any?

    init() {
        panel = PanelClave(contentRect: NSRect(x: 0, y: 0, width: VistaCaptura.ancho, height: VistaCaptura.alto),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: VistaCaptura(estado: estado, control: self))
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cerrar() }
        }
    }

    var abierto: Bool { panel.isVisible }

    func alternar() { abierto ? cerrar() : abrir() }

    func abrir() {
        if let pantalla = NSScreen.main {
            let z = pantalla.visibleFrame
            panel.setFrameOrigin(NSPoint(x: z.midX - VistaCaptura.ancho / 2, y: z.midY - VistaCaptura.alto / 2 + z.height * 0.08))
        }
        panel.makeKeyAndOrderFront(nil)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
                nonisolated(unsafe) let e = evento
                return MainActor.assumeIsolated { self?.tecla(e) ?? e }
            }
        }
    }

    func cerrar() {
        guard abierto else { return }
        panel.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Elige la carpeta para las capturas (el panel se cierra mientras el selector está abierto).
    func elegirCarpeta() {
        cerrar()
        NSApp.activate(ignoringOtherApps: true)
        let selector = NSOpenPanel()
        selector.canChooseDirectories = true
        selector.canChooseFiles = false
        selector.allowsMultipleSelection = false
        selector.canCreateDirectories = true
        selector.prompt = "Usar esta carpeta"
        selector.message = "¿Dónde guardo las capturas?"
        if let actual = estado.carpeta { selector.directoryURL = URL(fileURLWithPath: actual) }
        if selector.runModal() == .OK, let url = selector.url {
            estado.carpeta = url.path
            estado.destino = .carpeta
        } else if estado.carpeta == nil {
            estado.destino = .escritorio
        }
        abrir()
    }

    func ejecutar(_ opcion: OpcionCaptura) {
        estado.seleccion = opcion.rawValue
        cerrar()
        Task {
            try? await Task.sleep(for: .milliseconds(180))  // que el panel no salga en la captura
            await correr(opcion)
        }
    }

    private func tecla(_ evento: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return evento }
        let total = OpcionCaptura.allCases.count
        switch Int(evento.keyCode) {
        case kVK_Escape: cerrar(); return nil
        case kVK_LeftArrow: estado.seleccion = (estado.seleccion + total - 1) % total; return nil
        case kVK_RightArrow: estado.seleccion = (estado.seleccion + 1) % total; return nil
        case kVK_UpArrow: estado.seleccion = (estado.seleccion + total - 3) % total; return nil
        case kVK_DownArrow: estado.seleccion = (estado.seleccion + 3) % total; return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            ejecutar(OpcionCaptura(rawValue: estado.seleccion) ?? .area)
            return nil
        default: break
        }
        let letra = evento.charactersIgnoringModifiers?.lowercased() ?? ""
        if evento.modifierFlags.contains(.command), letra == "d" {  // recorre los destinos
            let todos = DestinoCaptura.allCases.filter { $0 != .carpeta || estado.carpeta != nil }
            let i = todos.firstIndex(of: estado.destino) ?? 0
            estado.destino = todos[(i + 1) % todos.count]
            return nil
        }
        if let n = Int(letra), (1...total).contains(n), let opcion = OpcionCaptura(rawValue: n - 1) {
            ejecutar(opcion)
            return nil
        }
        return evento
    }

    // MARK: Ejecución

    /// Las capturas las hace macOS con sus propios atajos (⌃⌘⇧4 área, ⌃⌘⇧3 pantalla, ambos al portapapeles).
    /// Así Dictado no necesita el permiso de Grabación de pantalla: solo Accesibilidad para pulsarlos.
    private func correr(_ opcion: OpcionCaptura) async {
        if opcion == .grabar {
            let barra = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
            _ = try? await NSWorkspace.shared.openApplication(at: barra, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        guard AXIsProcessTrusted() else {
            alTerminar?("", "exclamationmark.triangle", "Activa Accesibilidad para capturar")
            return
        }
        if opcion == .retraso { try? await Task.sleep(for: .seconds(5)) }
        let antes = NSPasteboard.general.changeCount
        switch opcion {
        case .pantalla, .retraso:
            Self.tecla(kVK_ANSI_3, [.maskCommand, .maskShift, .maskControl])
        case .ventana:
            Self.tecla(kVK_ANSI_4, [.maskCommand, .maskShift, .maskControl])
            try? await Task.sleep(for: .milliseconds(300))
            Self.tecla(kVK_Space, [])  // pasa al modo ventana
        default:
            Self.tecla(kVK_ANSI_4, [.maskCommand, .maskShift, .maskControl])
        }
        guard let imagen = await Self.esperarImagen(desde: antes) else { return }  // cancelaste con Esc

        if opcion == .texto {
            let temporal = FileManager.default.temporaryDirectory.appendingPathComponent("dictado-ocr-\(UUID().uuidString).png")
            guard let png = Self.png(imagen), (try? png.write(to: temporal)) != nil else { return }
            let texto = (try? await Self.reconocerTexto(temporal)) ?? ""
            try? FileManager.default.removeItem(at: temporal)
            guard !texto.isEmpty else {
                alTerminar?("", "text.viewfinder", "No encontré texto en esa área")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(texto, forType: .string)
            alTerminar?(texto, "text.viewfinder", "Texto copiado")
            return
        }
        if let carpeta = estado.carpetaDestino {
            let archivo = Self.nombre(en: carpeta)
            guard let png = Self.png(imagen), (try? png.write(to: archivo)) != nil else {
                alTerminar?("", "exclamationmark.triangle", "No pude guardar en \(estado.titulo(estado.destino))")
                return
            }
            alTerminar?("", "camera.viewfinder", "Guardada en \(estado.titulo(estado.destino))")
        } else {
            alTerminar?("", "camera.viewfinder", "Captura copiada · también en ⌘⌥V")
        }
    }

    private static func tecla(_ codigo: Int, _ flags: CGEventFlags) {
        let fuente = CGEventSource(stateID: .hidSystemState)
        for abajo in [true, false] {
            let evento = CGEvent(keyboardEventSource: fuente, virtualKey: CGKeyCode(codigo), keyDown: abajo)
            evento?.flags = flags
            evento?.post(tap: .cghidEventTap)
        }
    }

    /// Espera la imagen en el portapapeles. Si cierras la selección de macOS sin capturar, devuelve nil.
    private static func esperarImagen(desde conteo: Int) async -> NSImage? {
        var seAbrio = false
        for _ in 0..<1200 {  // hasta 2 minutos eligiendo el área
            try? await Task.sleep(for: .milliseconds(100))
            let pb = NSPasteboard.general
            if pb.changeCount != conteo { return NSImage(pasteboard: pb) }
            let abierta = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screencaptureui").isEmpty
            if abierta { seAbrio = true } else if seAbrio {
                try? await Task.sleep(for: .milliseconds(400))
                return pb.changeCount != conteo ? NSImage(pasteboard: pb) : nil
            }
        }
        return nil
    }

    private static func png(_ imagen: NSImage) -> Data? {
        imagen.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.representation(using: .png, properties: [:])
    }

    static func nombre(en carpeta: URL) -> URL {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es")
        formato.dateFormat = "yyyy-MM-dd 'a las' HH.mm.ss"
        return carpeta.appendingPathComponent("Captura \(formato.string(from: Date())).png")
    }

    /// OCR en el Mac con Vision (español e inglés), sin red.
    nonisolated static func reconocerTexto(_ url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let pedido = VNRecognizeTextRequest()
            pedido.recognitionLevel = .accurate
            pedido.recognitionLanguages = ["es-ES", "en-US"]
            pedido.usesLanguageCorrection = true
            try VNImageRequestHandler(url: url).perform([pedido])
            return (pedido.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

// MARK: - Vista

let gradientePrisma = Gradient(colors: [
    Color(red: 0.20, green: 0.45, blue: 1.00), Color(red: 0.66, green: 0.28, blue: 1.00),
    Color(red: 0.15, green: 0.85, blue: 0.95), Color(red: 1.00, green: 0.45, blue: 0.16),
])

extension OpcionCaptura {
    var corto: String {
        switch self {
        case .area: return "Área"
        case .ventana: return "Ventana"
        case .pantalla: return "Pantalla"
        case .texto: return "Texto"
        case .grabar: return "Grabar"
        case .retraso: return "En 5 s"
        }
    }
}

extension OpcionCaptura {
    /// Capturar es neutro (blanco); solo grabar lleva tono, el rojo de grabación.
    var tono: Tono { self == .grabar ? .rojo : .neutro }
}

/// Panel de captura en Halo: fila de botones circulares (el elegido en blanco sólido), destino en píldora y, abajo,
/// la opción elegida con su insignia. Una luz blanca tenue sube del borde justo debajo de la opción elegida y la
/// sigue al cambiar (flechas, número o puntero); en Grabar se funde al rojo.
struct VistaCaptura: View {
    static let ancho: CGFloat = 660
    static let alto: CGFloat = 250

    @Bindable var estado: EstadoCaptura
    let control: Captura?
    var simulado = false

    private let margen: CGFloat = 24

    var body: some View {
        let actual = OpcionCaptura(rawValue: estado.seleccion) ?? .area
        let total = CGFloat(OpcionCaptura.allCases.count)
        // Centro de la columna elegida, en fracción del ancho del panel.
        let centro = (margen + (Self.ancho - 2 * margen) * (CGFloat(actual.rawValue) + 0.5) / total) / Self.ancho
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                BotonCirculo(simbolo: "xmark", lado: 32, ayuda: "Cerrar (Esc)") { control?.cerrar() }
                Text("Captura").font(.system(size: 15, weight: .semibold)).foregroundStyle(Halo.texto)
                Spacer()
                Segmentado(opciones: DestinoCaptura.allCases.map { ($0, estado.titulo($0)) }, valor: $estado.destino)
                    .onChange(of: estado.destino) { _, nuevo in
                        if nuevo == .carpeta && estado.carpeta == nil { control?.elegirCarpeta() }
                    }
                if estado.destino == .carpeta {
                    BotonCirculo(simbolo: "folder.badge.gearshape", lado: 30, ayuda: "Cambiar carpeta") { control?.elegirCarpeta() }
                }
            }
            HStack(spacing: 0) {
                ForEach(OpcionCaptura.allCases) { opcion in
                    let elegida = opcion == actual
                    VStack(spacing: 8) {
                        BotonCirculo(simbolo: opcion.simbolo, activo: elegida, lado: 56, ayuda: "\(opcion.titulo) (\(opcion.rawValue + 1))") {
                            control?.ejecutar(opcion)
                        }
                        Text(opcion.corto)
                            .font(.system(size: 12, weight: elegida ? .semibold : .medium))
                            .foregroundStyle(elegida ? Halo.texto : Halo.texto2)
                    }
                    .frame(maxWidth: .infinity)
                    .onHover { if $0 { estado.seleccion = opcion.rawValue } }
                }
            }
            HStack(spacing: 12) {
                Insignia(icono: .simbolo(actual.simbolo), tono: actual.tono, lado: 28)
                Text(actual.titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto)
                Text(actual.detalle).font(.system(size: 12.5)).foregroundStyle(Halo.texto2)
                Spacer(minLength: 8)
                Rotulo("↩ · 1–6 · ⌘D destino · esc", color: Halo.texto3)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .frame(height: 44)
            .tarjetaHalo(radio: 22)
        }
        .padding(margen)
        .frame(width: Self.ancho, height: Self.alto)
        .background(LuzBorde(tono: actual.tono, fuerza: actual == .grabar ? 0.25 : 0.16, alto: 1.05, centro: centro - 0.012, ancho: 0.3))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .modifier(PanelVidrio(radio: 30, simulado: simulado))
        .animation(Halo.cambio, value: estado.seleccion)
    }
}
