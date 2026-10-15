import AppKit
import SwiftUI

// La sección Notas del centro: los resúmenes de tus reuniones (las que deja "Tomar notas" en `_inbox/reunion-*.md`).
// Solo lee archivos del cerebro: no escribe nada. La transcripción completa vive fuera de git y se abre con un botón.

struct NotaReunion: Identifiable, Equatable {
    var id: String { archivo.lastPathComponent }
    let archivo: URL
    let titulo: String
    let fecha: Date?
    let resumen: String
    let decisiones: [String]
    let pendientes: [String]
    let transcripcion: URL?

    /// Las reuniones guardadas en `<cerebro>/_inbox`, la más reciente primero.
    static func cargar(cerebro: String?) -> [NotaReunion] {
        guard let cerebro else { return [] }
        let carpeta = URL(fileURLWithPath: cerebro).appendingPathComponent("_inbox")
        let archivos = (try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil)) ?? []
        return archivos
            .filter { $0.lastPathComponent.hasPrefix("reunion-") && $0.pathExtension == "md" }
            .compactMap { leer($0) }
            .sorted { ($0.fecha ?? .distantPast) > ($1.fecha ?? .distantPast) }
    }

    static func leer(_ url: URL) -> NotaReunion? {
        guard let texto = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var meta: [String: String] = [:]
        var cuerpo = texto
        if texto.hasPrefix("---"), let fin = texto.range(of: "\n---", range: texto.index(texto.startIndex, offsetBy: 3)..<texto.endIndex) {
            for linea in texto[texto.index(texto.startIndex, offsetBy: 3)..<fin.lowerBound].split(separator: "\n") {
                guard let dos = linea.firstIndex(of: ":") else { continue }
                meta[String(linea[..<dos]).trimmingCharacters(in: .whitespaces)] =
                    String(linea[linea.index(after: dos)...]).trimmingCharacters(in: .whitespaces)
            }
            cuerpo = String(texto[fin.upperBound...])
        }
        var secciones: [String: [String]] = [:]
        var actual = ""
        var titulo = meta["reunion"] ?? url.deletingPathExtension().lastPathComponent
        for linea in cuerpo.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if linea.hasPrefix("## ") { actual = String(linea.dropFirst(3)); continue }
            if linea.hasPrefix("# ") { if meta["reunion"] == nil { titulo = String(linea.dropFirst(2)) }; actual = "resumen"; continue }
            secciones[actual, default: []].append(linea)
        }
        func vinetas(_ clave: String) -> [String] {
            (secciones[clave] ?? []).compactMap { l in
                let t = l.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("- ") else { return nil }
                return String(t.dropFirst(2)).replacingOccurrences(of: "[ ] ", with: "").replacingOccurrences(of: "[x] ", with: "")
            }
        }
        let resumen = (secciones["resumen"] ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        let fecha = meta["date"].flatMap { f.date(from: $0) }
        let trans = meta["transcripcion"].flatMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
        return NotaReunion(archivo: url, titulo: titulo.replacingOccurrences(of: "Notas · ", with: ""), fecha: fecha,
                           resumen: resumen, decisiones: vinetas("Decisiones"), pendientes: vinetas("Pendientes"), transcripcion: trans)
    }
}

/// Notas: la lista de reuniones a la izquierda, el resumen y las decisiones al frente, los pendientes y los archivos a la derecha.
struct EscenaNotasCentro: View {
    let cerebro: String?
    let ctx: ContextoCentro
    @State private var notas: [NotaReunion] = []
    @State private var elegida: String?

    /// En la ventana real el contenido se desplaza; el render de maquetas no dibuja un ScrollView.
    @ViewBuilder private func desplazable<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        if ctx.enVentana { ScrollView { c() } } else { c() }
    }

    private var actual: NotaReunion? { notas.first { $0.id == elegida } ?? notas.first }

    var body: some View {
        EspacioCentro {
            VentanaEspacio(relleno: 0) { lista }
        } centro: {
            VentanaEspacio {
                if let n = actual { resumen(n) } else { vacio }
            }
        } derecha: {
            if let n = actual {
                VentanaEspacio(tono: .claude) { pendientes(n) }
            } else {
                VentanaEspacio { EmptyView() }
            }
        }
        .onAppear { notas = NotaReunion.cargar(cerebro: cerebro) }
    }

    private var vacio: some View {
        VStack(alignment: .leading, spacing: 10) {
            CabeceraVentana(titulo: "Notas", detalle: nil)
            Text("Aún no hay reuniones. Cuando la isla pregunte «¿Tomo notas?» en una llamada y aceptes, el resumen aparece aquí.")
                .font(.system(size: 13.5)).foregroundStyle(TextoCentro.secundario).lineSpacing(3)
            Spacer(minLength: 0)
        }
    }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 10) {
            CabeceraVentana(titulo: "Reuniones", detalle: notas.isEmpty ? nil : "\(notas.count) con notas")
                .padding(.horizontal, 24).padding(.top, 24)
            desplazable {
                VStack(spacing: 2) {
                    ForEach(notas) { n in
                        let activa = n.id == actual?.id
                        Button { elegida = n.id } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(n.titulo).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Halo.texto).lineLimit(2)
                                if let f = n.fecha { Text(hace(f)).font(.system(size: 11.5)).foregroundStyle(TextoCentro.terciario) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(activa ? 0.14 : 0)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }

    private func resumen(_ n: NotaReunion) -> some View {
        desplazable {
            VStack(alignment: .leading, spacing: 14) {
                CabeceraVentana(titulo: n.titulo, detalle: n.fecha.map { Self.formato.string(from: $0) })
                Text(n.resumen).font(.system(size: 14)).foregroundStyle(Halo.texto).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                if !n.decisiones.isEmpty {
                    Text("Decisiones").font(.system(size: 12, weight: .semibold)).foregroundStyle(TextoCentro.secundario).padding(.top, 4)
                    ForEach(Array(n.decisiones.enumerated()), id: \.offset) { _, d in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "checkmark.seal").font(.system(size: 12)).foregroundStyle(TextoCentro.secundario)
                            Text(d).font(.system(size: 13.5)).foregroundStyle(Halo.texto).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func pendientes(_ n: NotaReunion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CabeceraVentana(titulo: "Pendientes", detalle: n.pendientes.isEmpty ? nil : "\(n.pendientes.count)")
            desplazable {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(n.pendientes.enumerated()), id: \.offset) { _, p in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
                            Text(p).font(.system(size: 13)).foregroundStyle(Halo.texto).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Text("Siguen en tu inbox hasta que decidas su destino: nada se mueve sin tu sí.")
                .font(.system(size: 11.5)).foregroundStyle(TextoCentro.terciario).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                BotonCentro(titulo: "Abrir nota", icono: "doc.text") { NSWorkspace.shared.open(n.archivo) }
                if let t = n.transcripcion {
                    BotonCentro(titulo: "Transcripción", icono: "text.alignleft") { NSWorkspace.shared.open(t) }
                }
            }
        }
    }

    private static let formato: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "EEEE d 'de' MMMM, h:mm a"
        return f
    }()
}
