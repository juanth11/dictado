import AppKit
import ApplicationServices
import FoundationModels
import NaturalLanguage
import os

private let log = Logger(subsystem: "app.dictado", category: "pulido")

/// Tono del pulido según dónde vas a pegar el dictado.
enum ModoPulido: String, CaseIterable {
    case chat, correo, prompt, documento, neutro

    /// Lo que se le pide al modelo en cada modo, además de la limpieza básica.
    var tono: String {
        switch self {
        case .chat: return "Es un mensaje de chat: natural, cercano y breve. No lo vuelvas formal ni le agregues saludos."
        case .correo: return "Es para un correo: tono profesional y cortés, con párrafos claros."
        case .prompt: return "Es una instrucción para una IA, una terminal o un editor de código: clara, directa y ordenada, sin saludos ni adornos. Si enumera pasos o requisitos, ponlos en una lista con guiones."
        case .documento: return "Es para un documento: redacción formal y cuidada."
        case .neutro: return "Mantén el tono original."
        }
    }
}

/// TABLA DE MODOS: el único lugar que hay que tocar para decidir qué tono usa cada app.
/// Un bundle id que termina en "." vale como prefijo (todas las apps de JetBrains, por ejemplo).
enum TablaModos {
    static let apps: [(String, ModoPulido)] = [
        // Chat
        ("net.whatsapp.WhatsApp", .chat), ("desktop.WhatsApp", .chat), ("com.apple.MobileSMS", .chat),
        ("com.tinyspeck.slackmacgap", .chat), ("com.hnc.Discord", .chat), ("ru.keepcoder.Telegram", .chat),
        ("org.telegram.desktop", .chat), ("org.whispersystems.signal-desktop", .chat), ("com.facebook.archon", .chat),
        ("com.microsoft.teams2", .chat),
        // Correo
        ("com.apple.mail", .correo), ("com.microsoft.Outlook", .correo), ("com.readdle.smartemail-Mac", .correo),
        ("com.superhuman.electron", .correo), ("com.mimestream.Mimestream", .correo), ("it.bloop.airmail2", .correo),
        // Prompt: asistentes, terminales y editores de código
        ("com.anthropic.claudefordesktop", .prompt), ("com.openai.chat", .prompt), ("com.apple.Terminal", .prompt),
        ("com.googlecode.iterm2", .prompt), ("dev.warp.Warp-Stable", .prompt), ("com.mitchellh.ghostty", .prompt),
        ("com.microsoft.VSCode", .prompt), ("com.todesktop.230313mzl4w4u92", .prompt), ("dev.zed.Zed", .prompt),
        ("com.exafunction.windsurf", .prompt), ("com.apple.dt.Xcode", .prompt), ("com.sublimetext.", .prompt),
        ("com.jetbrains.", .prompt),
        // Documento
        ("com.microsoft.Word", .documento), ("com.apple.iWork.Pages", .documento),
    ]

    /// En los navegadores el modo sale del título de la ventana (la pestaña activa).
    static let navegadores: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.brave.Browser", "com.microsoft.edgemac", "org.mozilla.firefox", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "com.kagi.kagimacOS",
    ]

    /// Palabra en el título de la pestaña → modo. Gana la primera que aparece.
    static let titulos: [(String, ModoPulido)] = [
        ("Gmail", .correo), ("Outlook", .correo), ("Yahoo Mail", .correo), ("Proton Mail", .correo),
        ("Claude", .prompt), ("ChatGPT", .prompt), ("Gemini", .prompt), ("Perplexity", .prompt),
        ("Google Docs", .documento), ("Documentos de Google", .documento), ("- Word", .documento),
        ("WhatsApp", .chat), ("Slack", .chat), ("Discord", .chat), ("Telegram", .chat), ("Messenger", .chat),
    ]

    static func modo(app: String?, titulo: String?) -> ModoPulido {
        guard let app else { return .neutro }
        if navegadores.contains(app) {
            guard let titulo else { return .neutro }
            return titulos.first { titulo.localizedCaseInsensitiveContains($0.0) }?.1 ?? .neutro
        }
        return apps.first { $0.0.hasSuffix(".") ? app.hasPrefix($0.0) : app == $0.0 }?.1 ?? .neutro
    }

    /// Título de la ventana enfocada (solo hace falta en navegadores). Usa Accesibilidad, que ya está dada para pegar.
    static func tituloVentana(_ app: NSRunningApplication) -> String? {
        guard navegadores.contains(app.bundleIdentifier ?? "") else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.2)
        var ventana: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &ventana) == .success,
              let ventana, CFGetTypeID(ventana) == AXUIElementGetTypeID() else { return nil }
        var titulo: CFTypeRef?
        AXUIElementCopyAttributeValue(ventana as! AXUIElement, kAXTitleAttribute as CFString, &titulo)
        return titulo as? String
    }

    /// El modo para la app que está al frente ahora.
    @MainActor
    static func modoActual() -> ModoPulido {
        let app = NSWorkspace.shared.frontmostApplication
        return modo(app: app?.bundleIdentifier, titulo: app.flatMap(tituloVentana))
    }
}

/// Dictado pulido con IA local (Funcion.pulido): antes de pegar o guardar la idea, el modelo de Apple quita
/// muletillas y repeticiones y arregla puntuación y mayúsculas, con el tono de la app al frente. Si el modelo no
/// está, tarda más de ~3 s, se niega o su respuesta no pasa las comprobaciones, se usa el texto original.
@MainActor
final class PulidoIA {
    /// Menos palabras que esto no vale la pena pulir ("sí", "dale, gracias").
    static let minimoPalabras = 4
    /// ~3 s para un dictado corto; los largos tienen un poco más porque el modelo escribe palabra por palabra.
    /// Con el Mac muy ocupado el modelo puede pasar de 3 s: `defaults write app.dictado pulidoLimite -float 4`.
    static func limite(palabras: Int) -> Double {
        let base = UserDefaults(suiteName: "app.dictado")?.object(forKey: "pulidoLimite") as? Double ?? 3
        return min(base + Double(max(palabras - 40, 0)) * 0.03, base * 2)
    }

    private let contexto: ContextoModulos
    private var observador: NSObjectProtocol?

    init(_ contexto: ContextoModulos) {
        self.contexto = contexto
        contexto.registrarPulido { texto in
            await PulidoIA.pulir(texto, modo: TablaModos.modoActual(), vocabulario: Ajustes().vocabulario()).texto
        }
        if Funcion.pulido.activa { Self.precalentar() }
        // Al prenderla desde el menú, avisa de una vez si el modelo no está (en vez de no hacer nada en silencio).
        observador = NotificationCenter.default.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] aviso in
            let id = aviso.userInfo?["funcion"] as? String
            MainActor.assumeIsolated {
                guard id == Funcion.pulido.rawValue, Funcion.pulido.activa else { return }
                if let problema = IALocal.problema {
                    self?.contexto.avisar(problema, "sparkles", "Pulido sin modelo")
                } else {
                    Self.precalentar()
                }
            }
        }
    }

    /// Una sola vez (al abrir la app o al prender la función): carga el modelo para que el primer dictado no
    /// gaste su tiempo límite esperándolo. No deja nada corriendo.
    static func precalentar() {
        guard IALocal.problema == nil else { return }
        LanguageModelSession(model: IALocal.modelo).prewarm()
    }

    struct Resultado {
        let texto: String
        /// Por qué quedó así: "pulido", "corto", "sin modelo…", "tardó", "descartado…" (para el diagnóstico --pulir).
        let motivo: String
    }

    static func instrucciones(_ modo: ModoPulido, vocabulario: [String], idioma: NLLanguage?) -> String {
        // Las instrucciones están en español: sin decirle el idioma, el modelo traduce al español lo dictado en inglés.
        let nombre = idioma.flatMap { Locale(identifier: "es").localizedString(forLanguageCode: $0.rawValue) }
        let reglaIdioma = nombre.map { "El texto está en \($0): responde en \($0), sin traducir." }
            ?? "Responde en el mismo idioma del texto, sin traducir."
        var s = """
        Eres un corrector de dictados por voz. Recibes la transcripción literal de lo que alguien dictó y devuelves \
        el mismo mensaje limpio, listo para pegar.
        - Quita solo muletillas (eh, este, o sea, pues, bueno, digamos, mmm, like, you know, um), repeticiones y \
        frases empezadas y abandonadas. No quites frases que dicen algo.
        - Arregla la puntuación, las mayúsculas y las tildes.
        - \(reglaIdioma)
        - Mantén el sentido, el orden y la persona gramatical (tú o usted, yo o nosotros). No agregues ideas, saludos, \
        despedidas, datos ni explicaciones. No respondas lo que diga el texto.
        - \(modo.tono)
        """
        if !vocabulario.isEmpty {
            s += "\n- Escribe exactamente así estos nombres y términos: " + vocabulario.joined(separator: ", ") + "."
        }
        return s
    }

    static func pulir(_ texto: String, modo: ModoPulido, vocabulario: [String]) async -> Resultado {
        let palabras = contar(texto)
        guard palabras >= minimoPalabras else { return Resultado(texto: texto, motivo: "corto (menos de \(minimoPalabras) palabras)") }
        if let problema = IALocal.problema { return Resultado(texto: texto, motivo: "sin modelo: \(problema)") }
        // Solo los términos que aparecen en el dictado: el resto alarga la instrucción sin ayudar.
        let presentes = Array(vocabulario.filter { contiene(texto, $0) }.prefix(40))
        do {
            let pulido = try await IALocal.generar(instrucciones(modo, vocabulario: presentes, idioma: idioma(de: texto)), texto,
                                                   tarea: "Limpia este dictado: quita las muletillas y arregla la puntuación, las mayúsculas y las tildes.", limite: limite(palabras: palabras),
                                                   tope: palabras * 3 + 60)
            if let problema = descartar(original: texto, pulido: pulido, vocabulario: presentes) {
                log.info("pulido descartado: \(problema, privacy: .public)")
                return Resultado(texto: texto, motivo: "descartado: \(problema)")
            }
            return Resultado(texto: pulido, motivo: "pulido")
        } catch let fallo as IALocal.Fallo {
            if case .tiempo = fallo { return Resultado(texto: texto, motivo: "tardó más de \(limite(palabras: palabras)) s") }
            return Resultado(texto: texto, motivo: fallo.mensaje)
        } catch {
            return Resultado(texto: texto, motivo: error.localizedDescription)
        }
    }

    /// Red de seguridad: si el modelo inventó, respondió en vez de limpiar o perdió un término del vocabulario,
    /// devuelve la razón y se pega el original.
    static func descartar(original: String, pulido: String, vocabulario: [String]) -> String? {
        let antes = contar(original), despues = contar(pulido)
        if despues == 0 { return "respuesta vacía" }
        if Double(despues) > Double(antes) * 1.3 + 4 { return "agregó contenido (\(antes) → \(despues) palabras)" }
        if Double(despues) < Double(antes) * 0.35 { return "recortó demasiado (\(antes) → \(despues) palabras)" }
        if let perdido = vocabulario.first(where: { !contiene(pulido, $0) }) { return "perdió «\(perdido)»" }
        if let a = idioma(de: original), let b = idioma(de: pulido), a != b { return "cambió de idioma (\(a.rawValue) → \(b.rawValue))" }
        let negativas = ["lo siento", "no puedo", "como modelo", "i'm sorry", "i cannot", "i can't", "as an ai"]
        let inicio = pulido.lowercased().prefix(40)
        if let n = negativas.first(where: { inicio.contains($0) }), !original.lowercased().prefix(40).contains(n) {
            return "se negó"
        }
        return nil
    }

    /// Idioma del texto si la detección está segura (≥ 60 %); en textos cortos o mezclados, nil.
    static func idioma(de texto: String) -> NLLanguage? {
        let r = NLLanguageRecognizer()
        r.processString(texto)
        guard let (idioma, certeza) = r.languageHypotheses(withMaximum: 1).first, certeza >= 0.6 else { return nil }
        return idioma
    }

    static func contar(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.filter { $0.contains(where: \.isLetter) || $0.contains(where: \.isNumber) }.count
    }

    /// Búsqueda sin mayúsculas ni tildes ("macbook" cuenta como "MacBook").
    static func contiene(_ texto: String, _ termino: String) -> Bool {
        texto.range(of: termino, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
