import Foundation
import Observation

/// Lo que te toca, de a una cosa. Junta tus pendientes de las reuniones de los últimos 7 días (las líneas
/// `- [ ] Juan · qué · cuándo · si: gatillo` de `_inbox/reunion-*.md` y del cierre del día) y muestra solo
/// "lo siguiente", con su "si… entonces". Hecho y soltado se guardan en el Mac (las preferencias de Dictado), no en el
/// cerebro: el archivo de la reunión no se toca. Lo de más de 7 días se deja de mostrar solo, para que nada se vuelva
/// deuda (regla 1 del cerebro). Solo lee archivos cuando se lo piden (al abrir la pestaña o al llegar notas nuevas).
@MainActor @Observable
final class Pendientes {
    struct Item: Identifiable, Equatable {
        let id: String
        let texto: String
        var cuando: String?
        var gatillo: String?
        let reunion: String
        let fecha: Date
    }

    struct ReunionDia: Identifiable, Equatable {
        var id: String { archivo }
        let archivo: String
        let titulo: String
        let fecha: Date
    }

    private(set) var items: [Item] = []
    /// Las reuniones con notas de hoy (para la pestaña Notas).
    private(set) var hoy: [ReunionDia] = []
    private(set) var hechasHoy = 0
    /// Los que pasaste con "Otra" (vuelven cuando se acaban los demás).
    private var saltados: [String] = []

    @ObservationIgnored private let cerebro: String?
    @ObservationIgnored private let clave = "pendientes.estado"
    static let dias = 7

    init(cerebro: String?) {
        self.cerebro = cerebro
        refrescar()
    }

    /// Lo único que se muestra: el primero que no hayas saltado.
    var siguiente: Item? { items.first { !saltados.contains($0.id) } ?? items.first }
    var abiertos: Int { items.count }

    func refrescar() {
        let estado = Self.leerEstado(clave)
        hechasHoy = estado.values.filter { $0.hasPrefix("hecho|") && $0.hasSuffix(Self.dia(Date())) }.count
        guard let cerebro else { return }
        let carpeta = URL(fileURLWithPath: cerebro).appendingPathComponent("_inbox")
        let archivos = (try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil)) ?? []
        let limite = Date().addingTimeInterval(-Double(Self.dias) * 86400)
        var vistos = Set<String>()
        var lista: [Item] = []
        var reuniones: [ReunionDia] = []
        for a in archivos where a.pathExtension == "md"
            && (a.lastPathComponent.hasPrefix("reunion-") || a.lastPathComponent.hasPrefix("cierre-")) {
            guard let texto = try? String(contentsOf: a, encoding: .utf8) else { continue }
            let (meta, cuerpo) = Self.frontmatter(texto)
            guard let fecha = meta["date"].flatMap(Self.fecha), fecha > limite else { continue }
            let titulo = meta["reunion"] ?? "Cierre del día"
            if a.lastPathComponent.hasPrefix("reunion-"), Calendar.current.isDateInToday(fecha) {
                reuniones.append(ReunionDia(archivo: a.path, titulo: titulo, fecha: fecha))
            }
            for linea in cuerpo.split(separator: "\n").map(String.init) {
                guard let item = Self.item(linea, reunion: titulo, fecha: fecha) else { continue }
                let id = item.id
                guard estado[id] == nil, vistos.insert(id).inserted else { continue }
                lista.append(item)
            }
        }
        // Lo más reciente primero: es lo que tienes fresco en la cabeza.
        items = lista.sorted { $0.fecha > $1.fecha }
        hoy = reuniones.sorted { $0.fecha < $1.fecha }
        saltados.removeAll { id in !items.contains { $0.id == id } }
    }

    /// "Otra": pasa a la siguiente sin perder esta.
    func otra() {
        guard let s = siguiente else { return }
        saltados.append(s.id)
        if saltados.count >= items.count { saltados = [] }
    }

    func hecho(_ item: Item) { marcar(item.id, "hecho|" + Self.dia(Date())) }
    func soltar(_ item: Item) { marcar(item.id, "soltado|" + Self.dia(Date())) }

    /// Terminó un bloque de foco con un pendiente: si quedó hecho, sale de la lista.
    func focoHecho(_ titulo: String) {
        if let i = items.first(where: { $0.texto == titulo }) { hecho(i) }
    }

    /// El cierre del día con "Soltar": lo de hoy deja de mostrarse (si importaba, vuelve a aparecer en una reunión).
    func soltarTodos() {
        var estado = Self.leerEstado(clave)
        for i in items { estado[i.id] = "soltado|" + Self.dia(Date()) }
        guardar(estado)
    }

    private func marcar(_ id: String, _ valor: String) {
        var estado = Self.leerEstado(clave)
        estado[id] = valor
        guardar(estado)
    }

    private func guardar(_ estado: [String: String]) {
        // Se olvida lo de hace más de un mes para que el ajuste no crezca sin fin.
        let viejo = Self.dia(Date().addingTimeInterval(-31 * 86400))
        UserDefaults.dictado.set(estado.filter { ($0.value.split(separator: "|").last.map(String.init) ?? "") >= viejo }, forKey: clave)
        refrescar()
    }

    // MARK: Leer

    /// `- [ ] Juan · revisar las correcciones · miércoles · si: al llegar a la oficina · (Contabilidad)`.
    /// Solo los tuyos (Juan, Tú o sin dueño) y sin marcar.
    nonisolated static func item(_ linea: String, reunion: String, fecha: Date) -> Item? {
        let t = linea.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("- [ ] ") else { return nil }
        var partes = t.dropFirst(6).components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard partes.count >= 2 else { return nil }
        let quien = partes.removeFirst().lowercased()
        guard quien.hasPrefix("juan") || quien == "tú" || quien == "tu" || quien == "¿?" else { return nil }
        var origen = reunion
        if let ultima = partes.last, ultima.hasPrefix("("), ultima.hasSuffix(")") {
            origen = String(ultima.dropFirst().dropLast())
            partes.removeLast()
        }
        let gatillo = partes.first { $0.hasPrefix("si:") }.map { String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        partes.removeAll { $0.hasPrefix("si:") }
        guard let texto = partes.first, !texto.isEmpty else { return nil }
        let cuando = partes.dropFirst().first
        return Item(id: clave(texto), texto: texto, cuando: cuando, gatillo: gatillo, reunion: origen, fecha: fecha)
    }

    /// Mismo pendiente en la nota de la reunión y en el cierre: misma clave (sin tildes, mayúsculas ni signos).
    nonisolated static func clave(_ texto: String) -> String {
        texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func frontmatter(_ texto: String) -> ([String: String], String) {
        guard texto.hasPrefix("---"),
              let fin = texto.range(of: "\n---", range: texto.index(texto.startIndex, offsetBy: 3)..<texto.endIndex) else { return ([:], texto) }
        var meta: [String: String] = [:]
        for linea in texto[texto.index(texto.startIndex, offsetBy: 3)..<fin.lowerBound].split(separator: "\n") {
            guard let dos = linea.firstIndex(of: ":") else { continue }
            meta[String(linea[..<dos]).trimmingCharacters(in: .whitespaces)] =
                String(linea[linea.index(after: dos)...]).trimmingCharacters(in: .whitespaces)
        }
        return (meta, String(texto[fin.upperBound...]))
    }

    nonisolated static func fecha(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return f.date(from: s)
    }

    nonisolated static func dia(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func leerEstado(_ clave: String) -> [String: String] {
        UserDefaults.dictado.dictionary(forKey: clave) as? [String: String] ?? [:]
    }
}
