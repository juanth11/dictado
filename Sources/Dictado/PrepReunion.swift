import AppKit
import Observation
import SwiftUI

/// "Prepárame" para una reunión: pide al cerebro lo que sabe del cliente o del tema (las páginas de la wiki que los
/// nombran, las reuniones anteriores, las decisiones y los pendientes con ellos, resumidos por Claude) y lo muestra en
/// un panel de vidrio debajo de la isla. Corre `accion.sh prep` (el mismo script de acciones del Centro), sin shell.
/// Lo preparado se guarda mientras Dictado vive: abrirlo otra vez no vuelve a pagar el modelo.
@MainActor
final class PrepReunion {
    static let shared = PrepReunion()

    struct Resultado: Decodable {
        struct Fuente: Decodable, Hashable { var ruta: String; var titulo: String }
        var ok: Bool
        var resumen: String?
        var puntos: [String]?
        var pendientes: [String]?
        var preguntas: [String]?
        var reuniones: [String]?
        var fuentes: [Fuente]?
        var modelo: String?
        var error: String?
    }

    @MainActor @Observable
    final class Estado {
        var titulo = ""
        var inicio: Date?
        var cargando = false
        var resultado: Resultado?
        var error: String?
    }

    let estado = Estado()
    private var panel: NSPanel?
    private var hechos: [String: Resultado] = [:]

    func abrir(_ e: Agenda.Evento) {
        estado.titulo = e.titulo
        estado.inicio = e.inicio
        estado.error = nil
        mostrarPanel()
        if let listo = hechos[e.id] {
            estado.resultado = listo
            estado.cargando = false
            return
        }
        estado.resultado = nil
        guard let acciones = CentroStore.acciones else {
            estado.error = "Falta el script de acciones del Centro (defaults write app.dictado centro -dict-add acciones …)."
            return
        }
        estado.cargando = true
        let f = ISO8601DateFormatter()
        var argumentos = ["prep", "--titulo", e.titulo, "--inicio", f.string(from: e.inicio)]
        for p in e.personas { argumentos += ["--persona", p] }
        let id = e.id
        Task.detached(priority: .userInitiated) {
            let (datos, fallo) = CentroStore.correr(URL(fileURLWithPath: acciones), argumentos, limite: 60)
            let r = try? JSONDecoder().decode(Resultado.self, from: datos)
            await MainActor.run {
                let yo = PrepReunion.shared
                guard yo.estado.titulo == e.titulo else { return }   // abriste otra mientras tanto
                yo.estado.cargando = false
                if let r, r.ok {
                    yo.hechos[id] = r
                    yo.estado.resultado = r
                } else {
                    yo.estado.error = r?.error ?? fallo ?? "El cerebro no respondió."
                }
            }
        }
    }

    func cerrar() { panel?.orderOut(nil) }

    private func mostrarPanel() {
        let p = panel ?? crearPanel()
        panel = p
        let pantalla = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let marco = pantalla?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: marco.midX - p.frame.width / 2, y: marco.maxY - p.frame.height - 18))
        }
        p.orderFrontRegardless()
    }

    private func crearPanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let vista = NSHostingView(rootView: VistaPrep(estado: estado, cerrar: { [weak self] in self?.cerrar() }))
        vista.sizingOptions = []
        p.contentView = vista
        return p
    }

    /// Abre una fuente (página de la wiki) en el editor de siempre, desde la carpeta del cerebro.
    static func abrirFuente(_ ruta: String) {
        let raiz = (try? Data(contentsOf: CentroStore.cache)).flatMap(EstadoCentro.decodificar)?.local?.cerebro
        guard let raiz, !ruta.contains("..") else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: raiz).appendingPathComponent(ruta))
    }
}

private struct VistaPrep: View {
    let estado: PrepReunion.Estado
    let cerrar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Rotulo("Prepárame" + (estado.inicio.map { " · " + Tiempo.horaDelDia($0) } ?? ""), color: Tono.azul.claro)
                    Text(estado.titulo).font(.system(size: 17, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(2)
                }
                Spacer()
                Button(action: cerrar) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Halo.texto2)
                        .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Cerrar")
            }
            if estado.cargando {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Buscando en tu cerebro…").font(.system(size: 12.5)).foregroundStyle(Halo.texto2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = estado.error {
                Text(error).font(.system(size: 12.5)).foregroundStyle(Tono.ambar.claro).frame(maxHeight: .infinity, alignment: .top)
            } else if let r = estado.resultado {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let resumen = r.resumen { Text(resumen).font(.system(size: 13)).foregroundStyle(Halo.texto).fixedSize(horizontal: false, vertical: true) }
                        bloque("Para tener presente", r.puntos)
                        bloque("Pendientes con ellos", r.pendientes)
                        bloque("Reuniones anteriores", r.reuniones)
                        bloque("Preguntas útiles", r.preguntas)
                        if let fuentes = r.fuentes, !fuentes.isEmpty {
                            Rotulo("Fuentes", color: Halo.texto3)
                            ForEach(fuentes, id: \.self) { f in
                                Button { PrepReunion.abrirFuente(f.ruta) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "doc.text").font(.system(size: 11))
                                        Text(f.titulo).font(.system(size: 12, weight: .medium))
                                        Text(f.ruta).font(.system(size: 11)).foregroundStyle(Halo.texto3)
                                    }
                                    .foregroundStyle(Halo.texto2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text(r.modelo == nil || r.modelo == "sin modelo" ? "Sin modelo: lo encontrado tal cual" : "Resumido por Claude")
                        .font(.system(size: 11)).foregroundStyle(Halo.texto3)
                    Spacer()
                    BotonHalo(titulo: "Copiar", icono: "doc.on.doc", secundario: true, alto: 26) { copiar(r) }
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 440, alignment: .topLeading)
        .modifier(VidrioCentro(simulado: false, radio: 24))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func bloque(_ titulo: String, _ lineas: [String]?) -> some View {
        if let lineas, !lineas.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Rotulo(titulo, color: Halo.texto3)
                ForEach(Array(lineas.enumerated()), id: \.offset) { _, l in
                    HStack(alignment: .top, spacing: 7) {
                        Circle().fill(.white.opacity(0.4)).frame(width: 3, height: 3).padding(.top, 7)
                        Text(l).font(.system(size: 12.5)).foregroundStyle(Halo.texto2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func copiar(_ r: PrepReunion.Resultado) {
        var t = ["# \(estado.titulo)", r.resumen ?? ""]
        for (titulo, lineas) in [("Para tener presente", r.puntos), ("Pendientes", r.pendientes), ("Preguntas", r.preguntas)] {
            if let lineas, !lineas.isEmpty { t.append("\n## \(titulo)\n" + lineas.map { "- \($0)" }.joined(separator: "\n")) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t.joined(separator: "\n"), forType: .string)
    }
}
