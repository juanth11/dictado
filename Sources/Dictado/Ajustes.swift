import Foundation

/// Ajustes en UserDefaults (dominio app.dictado). Se cambian con `defaults write`:
///   defaults write app.dictado idioma es-MX                  (es-US por defecto)
///   defaults write app.dictado motor speech|dictation
///   defaults write app.dictado estilo prisma|aurora|orbe|…   (también desde el menú)
///   defaults write app.dictado inbox "/ruta/a/tus/ideas"      (adónde van las ideas de ⌥⇧Espacio)
///   defaults write app.dictado protegidas -array "/ruta/1" "/ruta/2"   (carpetas que la limpieza jamás toca)
struct Ajustes {
    private let d = UserDefaults(suiteName: "app.dictado") ?? .standard

    // No hay modelo es-CO: es-CO cae en es_ES. es-US (español latinoamericano) se acerca más al acento colombiano.
    var idioma: String { d.string(forKey: "idioma") ?? "es-US" }
    var motor: Motor { Motor(rawValue: d.string(forKey: "motor") ?? "") ?? .speech }
    var estilo: Estilo { Estilo(rawValue: d.string(forKey: "estilo") ?? "") ?? .prisma }
    func guardar(estilo: Estilo) { d.set(estilo.rawValue, forKey: "estilo") }
    var isla: Bool { d.object(forKey: "isla") as? Bool ?? true }
    func guardar(isla: Bool) { d.set(isla, forKey: "isla") }
    /// Volumen y brillo en la isla en vez del cuadro de macOS.
    var niveles: Bool { d.object(forKey: "niveles") as? Bool ?? true }
    func guardar(niveles: Bool) { d.set(niveles, forKey: "niveles") }
    /// Carpeta de las ideas dictadas con ⌥⇧Espacio (una nota markdown por idea).
    var carpetaInbox: URL {
        URL(fileURLWithPath: d.string(forKey: "inbox") ?? NSHomeDirectory() + "/Documents/Ideas")
    }

    /// Carpetas que la limpieza nunca propone tocar (además de iCloud y los contenedores de apps).
    static var carpetasProtegidas: [String] {
        UserDefaults(suiteName: "app.dictado")?.stringArray(forKey: "protegidas") ?? []
    }

    static var archivoVocabulario: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dictado/vocabulario.txt")
    }

    static var carpetaPortapapeles: URL {
        archivoVocabulario.deletingLastPathComponent().appendingPathComponent("Portapapeles")
    }

    static var archivoCorrecciones: URL {
        archivoVocabulario.deletingLastPathComponent().appendingPathComponent("correcciones.txt")
    }

    /// Términos que el modelo debe preferir (nombres propios, jerga de tu oficio). Una línea por término.
    /// Solo el motor `dictation` los aprovecha; `speech` los ignora (de ahí las correcciones).
    func vocabulario() -> [String] {
        Self.lineas(Self.archivoVocabulario, inicial: Self.vocabularioInicial)
    }

    /// Reemplazos aplicados al texto final: "lo que transcribe = lo correcto".
    func correcciones() -> [(String, String)] {
        Self.lineas(Self.archivoCorrecciones, inicial: Self.correccionesIniciales).compactMap { linea in
            let partes = linea.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard partes.count == 2, !partes[0].isEmpty else { return nil }
            return (partes[0], partes[1])
        }
    }

    private static func lineas(_ url: URL, inicial: String) -> [String] {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? inicial.write(to: url, atomically: true, encoding: .utf8)
        }
        let texto = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return texto.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static let correccionesIniciales = """
    # Correcciones de Dictado: "lo que transcribe = lo correcto", una por línea.
    # No distingue mayúsculas y solo reemplaza palabras completas. Se aplica en el siguiente dictado.
    # Ejemplos (borra el # para activarlos):
    # Mac Book = MacBook
    # chat GPT = ChatGPT
    """

    private static let vocabularioInicial = """
    # Vocabulario de Dictado: una palabra o frase por línea. Las líneas con # se ignoran.
    # Pon aquí nombres propios, empresas, clientes y términos de tu oficio.
    # Se aplica desde el siguiente dictado tras reiniciar la app.
    Claude
    MacBook
    WhatsApp
    Google Meet
    """
}
