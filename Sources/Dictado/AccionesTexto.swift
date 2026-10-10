import AppKit
import ApplicationServices
import Carbon.HIToolbox
import NaturalLanguage
import Observation
import SwiftUI
import Translation
import os

private let log = Logger(subsystem: "app.dictado", category: "acciones")

/// Lo que se puede hacer con el texto seleccionado. El número es su tecla en el panel.
enum AccionTexto: Int, CaseIterable, Identifiable {
    case traducir = 1, corregir, resumir, formal, claude, idea

    var id: Int { rawValue }

    var titulo: String {
        switch self {
        case .traducir: return "Traducir"
        case .corregir: return "Corregir"
        case .resumir: return "Resumir"
        case .formal: return "Más formal"
        case .claude: return "A Claude"
        case .idea: return "Guardar idea"
        }
    }

    var simbolo: String {
        switch self {
        case .traducir: return "character.bubble"
        case .corregir: return "checkmark.seal"
        case .resumir: return "text.line.first.and.arrowtriangle.forward"
        case .formal: return "briefcase"
        case .claude: return "sparkle"
        case .idea: return "tray.and.arrow.down"
        }
    }

    var ayuda: String {
        switch self {
        case .traducir: return "Español ↔ inglés, con la traducción de Apple en el Mac"
        case .corregir: return "Ortografía y gramática, sin cambiar el estilo"
        case .resumir: return "En pocas frases"
        case .formal: return "El mismo contenido con tono profesional"
        case .claude: return "Abre un chat nuevo en Claude con este texto"
        case .idea: return "Lo guarda como nota en tu carpeta de ideas"
        }
    }

    /// Instrucción para el modelo del Mac (solo las acciones que lo usan).
    var instrucciones: String? {
        switch self {
        case .corregir:
            return "Corrige la ortografía, la gramática, las tildes y la puntuación del texto. No cambies el estilo, el tono, el idioma, el registro ni el vocabulario, y no reescribas lo que ya está bien."
        case .resumir:
            return "Resume el texto en su mismo idioma, en pocas frases claras (como mucho un tercio del largo original). No agregues nada que no esté en el texto."
        case .formal:
            return "Reescribe el texto con un tono más formal y profesional, en su mismo idioma. Conserva todo el contenido y el sentido; no agregues información. Quien escribe sigue siendo el mismo y pide o cuenta lo mismo: si dice «mándame», sigue pidiendo que se lo manden (por ejemplo, «¿Podría enviarme…?»)."
        default:
            return nil
        }
    }

    /// Lo que se pide justo antes del texto. El resumen lleva un número de palabras: sin él, el modelo lo copia casi entero.
    func tarea(palabras: Int) -> String {
        switch self {
        case .corregir: return "Corrige este texto:"
        case .resumir: return "Resume este texto en máximo \(max(12, palabras / 4)) palabras:"
        case .formal: return "Reescribe este texto con tono formal, sin cambiar quién habla:"
        default: return ""
        }
    }

    /// Etiqueta sobre el resultado.
    var etiqueta: String {
        switch self {
        case .corregir: return "Corregido"
        case .resumir: return "Resumen"
        case .formal: return "Más formal"
        default: return titulo
        }
    }
}

@MainActor @Observable
final class EstadoAcciones {
    var texto = ""
    var app = ""
    @ObservationIgnored var icono: NSImage?
    var accion: AccionTexto?
    var cargando = false
    var resultado: String?
    /// Encima del resultado: "Traducción · Español → Inglés", "Resumen"…
    var detalle = ""
    /// Error o algo que falta (idiomas sin descargar, Apple Intelligence apagado).
    var aviso: String?
    var faltanIdiomas = false
    /// Al ponerla, la vista corre `.translationTask`, que sabe pedir a macOS que descargue los idiomas.
    var traduccion: TranslationSession.Configuration?
}

/// Acciones sobre texto seleccionado (Funcion.acciones, Hyper+T): lee la selección de la app al frente y abre un
/// panel pequeño para traducir, corregir, resumir, volver formal, mandar a Claude o guardar como idea.
/// El resultado se puede pegar encima de la selección ("Reemplazar") o copiar.
@MainActor
final class AccionesTexto {
    static let idAtajo: UInt32 = 50

    let estado = EstadoAcciones()
    private let contexto: ContextoModulos
    private var panel: PanelClave?
    private var hosting: NSHostingView<VistaAcciones>?
    private var monitor: Any?
    private var observador: NSObjectProtocol?
    private var leyendo = false
    private var trabajo: Task<Void, Never>?
    private var idiomas: (origen: Locale.Language, destino: Locale.Language)?

    init(_ contexto: ContextoModulos) {
        self.contexto = contexto
        if Funcion.acciones.activa { registrarAtajo(avisarSiFalla: false) }
        observador = NotificationCenter.default.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] aviso in
            let id = aviso.userInfo?["funcion"] as? String
            MainActor.assumeIsolated {
                guard let self, id == Funcion.acciones.rawValue else { return }
                if Funcion.acciones.activa {
                    self.registrarAtajo(avisarSiFalla: true)
                } else {
                    Atajos.shared.quitar(id: Self.idAtajo)
                    self.cerrar()
                }
            }
        }
    }

    /// Hyper+T = ⌃⌥⌘⇧T: con la tecla hyper es Bloq Mayús + T.
    private func registrarAtajo(avisarSiFalla: Bool) {
        let ok = Atajos.shared.registrar(id: Self.idAtajo, tecla: kVK_ANSI_T,
                                         modificadores: cmdKey | optionKey | controlKey | shiftKey,
                                         alPresionar: { [weak self] in self?.alternar() })
        if !ok {
            log.error("Hyper+T ocupado por otra app")
            if avisarSiFalla { contexto.avisar("Hyper+T lo usa otra app", "keyboard", nil) }
        }
    }

    var abierto: Bool { panel?.isVisible == true }

    func alternar() {
        if abierto { cerrar() } else { abrir() }
    }

    // MARK: Leer la selección

    func abrir() {
        guard !leyendo else { return }
        guard AXIsProcessTrusted() else {
            contexto.avisar("Activa Accesibilidad para leer la selección", "hand.raised", nil)
            return
        }
        guard !Salida.focoEsContrasena() else {
            contexto.avisar("No leo campos de contraseña", "lock", nil)
            return
        }
        let app = NSWorkspace.shared.frontmostApplication
        leyendo = true
        Task {
            defer { leyendo = false }
            var marco: CGRect?
            let texto: String
            if let s = Self.seleccionPorAccesibilidad() {
                texto = s.texto
                marco = s.marco
            } else if let copiado = await seleccionCopiando() {
                texto = copiado
            } else {
                contexto.avisar("Selecciona un texto primero", "text.cursor", nil)
                return
            }
            mostrar(texto, app: app, cerca: marco)
        }
    }

    /// Lo seleccionado según Accesibilidad y, si la app lo sabe, dónde está en pantalla (para abrir ahí el panel).
    static func seleccionPorAccesibilidad() -> (texto: String, marco: CGRect?)? {
        let sistema = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sistema, 0.3)
        var foco: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sistema, kAXFocusedUIElementAttribute as CFString, &foco) == .success,
              let foco, CFGetTypeID(foco) == AXUIElementGetTypeID() else { return nil }
        let elemento = foco as! AXUIElement
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, kAXSelectedTextAttribute as CFString, &valor) == .success,
              let texto = valor as? String, !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var rango: CFTypeRef?
        var limites: CFTypeRef?
        var marco = CGRect.zero
        guard AXUIElementCopyAttributeValue(elemento, kAXSelectedTextRangeAttribute as CFString, &rango) == .success, let rango,
              AXUIElementCopyParameterizedAttributeValue(elemento, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         rango, &limites) == .success,
              let limites, CFGetTypeID(limites) == AXValueGetTypeID(),
              AXValueGetValue(limites as! AXValue, .cgRect, &marco),
              marco.height > 0, marco.height < 400 else { return (texto, nil) }  // una selección enorme: mejor junto al puntero
        return (texto, marco)
    }

    /// Chrome y las apps Electron no le cuentan la selección a Accesibilidad: se copia con ⌘C y el portapapeles
    /// vuelve a quedar como estaba. El historial se pausa para que esa copia de paso no quede guardada.
    private func seleccionCopiando() async -> String? {
        let pb = NSPasteboard.general
        let foto = FotoPortapapeles(pb)
        let antes = pb.changeCount
        contexto.pausarHistorial(true)
        await Self.simularCopiar()
        var texto: String?
        for _ in 0..<20 where pb.changeCount == antes {  // hasta 0,5 s
            try? await Task.sleep(for: .milliseconds(25))
        }
        if pb.changeCount != antes {
            texto = pb.string(forType: .string)
            foto.restaurar(en: pb)
        }
        contexto.pausarHistorial(false)
        guard let texto, !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return texto
    }

    /// ⌘C en la app con el foco. Espera a que sueltes Hyper (⌃⌥⌘⇧): si siguen presionadas llegaría como ⌃⌥⌘⇧C.
    private static func simularCopiar() async {
        var espera = 0
        while !NSEvent.modifierFlags.intersection([.option, .shift, .control, .command]).isEmpty, espera < 30 {
            try? await Task.sleep(for: .milliseconds(50))
            espera += 1
        }
        let fuente = CGEventSource(stateID: .combinedSessionState)
        for abajo in [true, false] {
            let evento = CGEvent(keyboardEventSource: fuente, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: abajo)
            evento?.flags = .maskCommand
            evento?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Panel

    private func mostrar(_ texto: String, app: NSRunningApplication?, cerca marco: CGRect?) {
        trabajo?.cancel()
        estado.texto = texto
        estado.app = app?.localizedName ?? ""
        estado.icono = app?.icon.map { Privacidad.mapaDeBits($0) }  // el multirresolución de macOS pesa más y vela los renders
        estado.accion = nil
        estado.resultado = nil
        estado.aviso = nil
        estado.cargando = false
        estado.faltanIdiomas = false
        estado.traduccion = nil
        let panel = self.panel ?? crearPanel()
        let tam = hosting?.fittingSize ?? NSSize(width: VistaAcciones.ancho, height: 200)
        panel.setFrame(Self.marcoInicial(tamano: tam, cerca: marco), display: true)
        panel.makeKeyAndOrderFront(nil)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
                nonisolated(unsafe) let e = evento  // el monitor local siempre corre en el hilo principal
                return MainActor.assumeIsolated { self?.tecla(e) ?? e }
            }
        }
    }

    private func crearPanel() -> PanelClave {
        let panel = PanelClave(contentRect: NSRect(x: 0, y: 0, width: VistaAcciones.ancho, height: 200),
                               styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let hosting = NSHostingView(rootView: VistaAcciones(estado: estado, control: self))
        hosting.sizingOptions = []  // el tamaño lo pone `ajustarAlto`, para que crezca hacia abajo y no hacia arriba
        panel.contentView = hosting
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.estado.traduccion == nil else { return }  // el aviso de descarga de idiomas toma el foco
                self.cerrar()
            }
        }
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    /// Debajo de la selección si se conoce; si no, junto al puntero. Siempre dentro de la pantalla.
    static func marcoInicial(tamano: NSSize, cerca marco: CGRect?) -> NSRect {
        let altoPrincipal = NSScreen.screens.first?.frame.maxY ?? 0
        let raton = NSEvent.mouseLocation
        // Accesibilidad mide desde arriba a la izquierda de la pantalla principal; AppKit, desde abajo.
        let debajo = marco.map { NSPoint(x: $0.minX, y: altoPrincipal - $0.maxY - 8) } ?? NSPoint(x: raton.x - 24, y: raton.y - 20)
        let encima = marco.map { altoPrincipal - $0.minY + 8 } ?? raton.y + 20
        let pantalla = NSScreen.screens.first { NSMouseInRect(debajo, $0.frame, false) } ?? NSScreen.main
        let z = pantalla?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(debajo.x, z.minX + 8), z.maxX - tamano.width - 8)
        var arriba = debajo.y
        if arriba - tamano.height < z.minY + 8 { arriba = encima + tamano.height }
        arriba = min(arriba, z.maxY - 8)
        return NSRect(x: x, y: arriba - tamano.height, width: tamano.width, height: tamano.height)
    }

    /// La vista avisa su alto real cada vez que cambia (al llegar un resultado): el borde de arriba no se mueve.
    func ajustarAlto(_ alto: CGFloat) {
        guard let panel, alto > 0, abs(panel.frame.height - alto) > 0.5 else { return }
        var f = panel.frame
        f.origin.y = f.maxY - alto
        f.size = NSSize(width: VistaAcciones.ancho, height: alto)
        if let z = panel.screen?.visibleFrame, f.minY < z.minY + 8 { f.origin.y = z.minY + 8 }
        panel.setFrame(f, display: true)
    }

    func cerrar() {
        trabajo?.cancel()
        trabajo = nil
        estado.traduccion = nil
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func tecla(_ evento: NSEvent) -> NSEvent? {
        guard panel?.isKeyWindow == true else { return evento }
        let cmd = evento.modifierFlags.contains(.command)
        switch Int(evento.keyCode) {
        case kVK_Escape:
            cerrar()
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if estado.resultado != nil { reemplazar() }
            return nil
        default:
            break
        }
        guard let letra = evento.charactersIgnoringModifiers?.lowercased() else { return evento }
        if cmd, letra == "c", estado.resultado != nil {
            copiar()
            return nil
        }
        if !cmd, let n = Int(letra), let accion = AccionTexto(rawValue: n) {
            ejecutar(accion)
            return nil
        }
        return evento
    }

    // MARK: Acciones

    func ejecutar(_ accion: AccionTexto) {
        let texto = estado.texto
        switch accion {
        case .claude:
            cerrar()
            mandarAClaude(texto)
        case .idea:
            cerrar()
            contexto.guardarIdea(texto)
        case .traducir, .corregir, .resumir, .formal:
            trabajo?.cancel()
            estado.accion = accion
            estado.resultado = nil
            estado.aviso = nil
            estado.faltanIdiomas = false
            estado.cargando = true
            trabajo = Task {
                let salida: Result<(String, String), Error>
                do {
                    salida = .success(accion == .traducir ? try await Self.traducir(texto) : try await Self.transformar(texto, accion))
                } catch {
                    salida = .failure(error)
                }
                guard !Task.isCancelled else { return }
                estado.cargando = false
                switch salida {
                case .success(let (resultado, detalle)):
                    estado.resultado = resultado
                    estado.detalle = detalle
                case .failure(let error):
                    estado.aviso = Self.mensaje(error)
                    if let falta = error as? FaltanIdiomas {
                        idiomas = (falta.origen, falta.destino)
                        estado.faltanIdiomas = true
                    }
                }
            }
        }
    }

    /// Corregir, resumir y más formal, con el modelo del Mac. Aquí sí se muestra el error: estás esperando.
    static func transformar(_ texto: String, _ accion: AccionTexto) async throws -> (String, String) {
        guard let instrucciones = accion.instrucciones else { return (texto, "") }
        guard texto.count <= 9_000 else { throw IALocal.Fallo.muyLargo }
        let r = try await IALocal.generar(instrucciones, texto, tarea: accion.tarea(palabras: PulidoIA.contar(texto)), limite: 30)
        guard !r.isEmpty else { throw IALocal.Fallo.otro("respuesta vacía") }
        return (r, accion.etiqueta)
    }

    nonisolated static func mensaje(_ error: Error) -> String {
        if let fallo = error as? IALocal.Fallo { return fallo.mensaje }
        if let falta = error as? FaltanIdiomas { return falta.mensaje }
        return error.localizedDescription
    }

    // MARK: Traducir

    /// Español → inglés; cualquier otro idioma → español.
    nonisolated static func idiomas(de texto: String) -> (origen: Locale.Language, destino: Locale.Language) {
        let r = NLLanguageRecognizer()
        r.languageHints = [.spanish: 0.4, .english: 0.4]  // los textos cortos se confunden fácil (es/pt, en/nl)
        r.processString(texto)
        let detectado = r.dominantLanguage ?? .spanish
        let es = Locale.Language(identifier: "es"), en = Locale.Language(identifier: "en")
        if detectado == .spanish { return (es, en) }
        return (Locale.Language(identifier: detectado.rawValue), es)
    }

    nonisolated static func nombre(_ idioma: Locale.Language) -> String {
        let codigo = idioma.languageCode?.identifier ?? idioma.maximalIdentifier
        return (Locale(identifier: "es").localizedString(forLanguageCode: codigo) ?? codigo).capitalized(with: Locale(identifier: "es"))
    }

    struct FaltanIdiomas: Error {
        let origen: Locale.Language
        let destino: Locale.Language
        var mensaje: String {
            "Para traducir en el Mac falta descargar \(AccionesTexto.nombre(origen)) y \(AccionesTexto.nombre(destino)). "
                + "Toca Descargar (macOS pide confirmación) o hazlo en Ajustes del Sistema → General → Idioma y región → Idiomas de traducción."
        }
    }

    /// Con la traducción de Apple en el Mac. Si los idiomas ya están descargados basta `TranslationSession`;
    /// si no, se avisa y el botón Descargar pasa por `.translationTask` en la vista (la única vía que puede pedirlos).
    static func traducir(_ texto: String) async throws -> (String, String) {
        let (origen, destino) = idiomas(de: texto)
        let detalle = "Traducción · \(nombre(origen)) → \(nombre(destino))"
        switch await LanguageAvailability().status(from: origen, to: destino) {
        case .installed:
            let sesion = TranslationSession(installedSource: origen, target: destino)
            return (try await sesion.translate(texto).targetText, detalle)
        case .supported:
            throw FaltanIdiomas(origen: origen, destino: destino)
        case .unsupported:
            throw IALocal.Fallo.otro("el Mac no traduce de \(nombre(origen)) a \(nombre(destino))")
        @unknown default:
            throw IALocal.Fallo.otro("traducción no disponible")
        }
    }

    /// Botón Descargar: la vista corre `.translationTask` y macOS muestra su aviso para bajar los idiomas.
    func descargarIdiomas() {
        guard let idiomas else { return }
        var config = TranslationSession.Configuration(source: idiomas.origen, target: idiomas.destino)
        if config == estado.traduccion { config.invalidate() }
        estado.aviso = nil
        estado.faltanIdiomas = false
        estado.cargando = true
        estado.traduccion = config
    }

    /// Lo llama `.translationTask` desde la vista, con la sesión que sí puede descargar idiomas.
    func traducir(con sesion: TranslationSession) async {
        let texto = estado.texto
        do {
            try await sesion.prepareTranslation()
            let r = try await sesion.translate(texto)
            estado.resultado = r.targetText
            estado.detalle = "Traducción · \(Self.nombre(r.sourceLanguage)) → \(Self.nombre(r.targetLanguage))"
        } catch {
            estado.aviso = "No se pudo traducir: \(error.localizedDescription)"
        }
        estado.cargando = false
        estado.traduccion = nil
    }

    func abrirAjustesIdiomas() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Resultado

    /// Pega el resultado encima de la selección y devuelve el portapapeles como estaba.
    func reemplazar() {
        guard let resultado = estado.resultado else { return }
        cerrar()
        let pb = NSPasteboard.general
        guard AXIsProcessTrusted() else {
            copiarAlPortapapeles(resultado)
            contexto.avisar(resultado, "doc.on.clipboard", "Copiado · activa Accesibilidad para reemplazar")
            return
        }
        Task {
            let foto = FotoPortapapeles(pb)
            contexto.pausarHistorial(true)
            pb.clearContents()
            pb.setString(resultado, forType: .string)
            try? await Task.sleep(for: .milliseconds(90))  // que la app de destino recupere el foco
            await Salida.simularPegar()
            try? await Task.sleep(for: .milliseconds(450))  // que la app lea el portapapeles antes de devolverlo
            foto.restaurar(en: pb)
            contexto.pausarHistorial(false)
        }
    }

    func copiar() {
        guard let resultado = estado.resultado else { return }
        cerrar()
        copiarAlPortapapeles(resultado)
        contexto.avisar(resultado, "doc.on.doc", "Copiado")
    }

    private func copiarAlPortapapeles(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }

    // MARK: Claude

    /// Claude para Mac acepta `claude://claude.ai/new?q=<texto>` (lo usa su propio servicio "Ask Claude") y deja
    /// el texto en un chat nuevo. Corta en 14.336 caracteres y rechaza un `q` que empiece por "/".
    nonisolated static func enlaceClaude(_ texto: String) -> URL? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 14_000, !t.hasPrefix("/") else { return nil }
        let permitidos = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let q = t.addingPercentEncoding(withAllowedCharacters: permitidos) else { return nil }
        return URL(string: "claude://claude.ai/new?q=\(q)&surface=chat")
    }

    private func mandarAClaude(_ texto: String) {
        let hayApp = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "claude://")!) != nil
        if hayApp, let url = Self.enlaceClaude(texto) {
            NSWorkspace.shared.open(url)
            return
        }
        // Texto muy largo, que empieza por "/" o sin la app: va copiado y se abre un chat nuevo para pegarlo.
        copiarAlPortapapeles(texto)
        NSWorkspace.shared.open(URL(string: hayApp ? "claude://claude.ai/new" : "https://claude.ai/new")!)
        contexto.avisar("Copiado: pégalo en Claude con ⌘V", "doc.on.clipboard", nil)
    }
}

/// Foto del portapapeles (todos los elementos con todos sus tipos) para devolverlo como estaba.
struct FotoPortapapeles {
    let elementos: [[(NSPasteboard.PasteboardType, Data)]]

    init(_ pb: NSPasteboard) {
        elementos = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { tipo in item.data(forType: tipo).map { (tipo, $0) } }
        }
    }

    func restaurar(en pb: NSPasteboard) {
        pb.clearContents()
        guard !elementos.isEmpty else { return }
        pb.writeObjects(elementos.map { tipos in
            let item = NSPasteboardItem()
            for (tipo, datos) in tipos { item.setData(datos, forType: tipo) }
            return item
        })
    }
}
