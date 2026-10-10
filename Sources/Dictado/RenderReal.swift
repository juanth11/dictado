import AppKit
import SwiftUI

// La isla con el setup real del Mac (solo render, no está en la app).
//
//   Dictado --foto-real foto.json         mide el Mac (salud, volumen, salida, brillo) y lo agrega a foto.json
//   Dictado --comparar salida.png halo foto.json
//
// foto.json trae lo que la app no puede leer sola desde la línea de comandos:
//   { "musica": { "titulo", "artista", "duracion", "posicion", "sonando", "caratula": ruta },
//     "agente": { "nombre", "estado": ruta a un JSON con el formato de Agentes.swift },
//     "reunion": { "titulo", "minutos", "duracion" } }
// Las sesiones de Claude se leen en vivo de ~/.claude (solo lectura). El fondo es el del escritorio.

// MARK: Foto del setup real

private func leerJSON(_ ruta: URL) -> [String: Any] {
    (try? Data(contentsOf: ruta)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
}

/// Mide el Mac (dos muestras, para el procesador) y agrega salud, volumen, salida y brillo a la foto.
@MainActor
func fotoReal(_ ruta: URL) -> Bool {
    var foto = leerJSON(ruta)
    let medidor = Medidor()
    _ = medidor.medir()
    Thread.sleep(forTimeInterval: 2)
    let m = medidor.medir()
    // Lo que más consume, con los procesos sumados por la app dueña (como el panel de Salud).
    var apps: [String: (nombre: String, bundle: String, cpu: Double, memoria: Double)] = [:]
    for p in m.procesos {
        guard let app = NSRunningApplication(processIdentifier: p.responsable), app.activationPolicy == .regular,
              let bundle = app.bundleIdentifier else { continue }
        var g = apps[bundle] ?? (app.localizedName ?? bundle, bundle, 0, 0)
        g.cpu += p.cpu
        g.memoria += p.memoria
        apps[bundle] = g
    }
    let top = apps.values.sorted { $0.memoria > $1.memoria }.prefix(4)
    foto["salud"] = ["cpu": m.cpu, "gpu": m.gpu, "memoriaUsada": m.memoriaUsada, "swap": m.swap, "presion": m.presion,
                     "memoriaTotal": Double(ProcessInfo.processInfo.physicalMemory),
                     "discoLibre": m.disco.disponible, "discoTotal": m.disco.total,
                     "consumidores": top.map { ["nombre": $0.nombre, "bundle": $0.bundle, "cpu": $0.cpu, "memoria": $0.memoria] }]
    if let id = Audio.salida() {
        foto["volumen"] = Audio.volumen(id) ?? 0.5
        foto["silencio"] = Audio.silenciado(id) ?? false
        foto["salida"] = Audio.nombre(id) ?? "Altavoces"
        foto["integrado"] = Audio.descripcionSalida()?.integrado ?? false
    }
    foto["brillo"] = Brillo.leer(CGMainDisplayID()) ?? 0.7
    guard let datos = try? JSONSerialization.data(withJSONObject: foto, options: [.prettyPrinted, .sortedKeys]) else { return false }
    return (try? datos.write(to: ruta)) != nil
}

/// Lo que la foto describe, como modelos de la app.
@MainActor
struct SetupReal {
    let musica: Musica
    let agenda: Agenda
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    let salud: EstadoSalud
    let volumen: Double
    let silencio: Bool
    let salida: SalidaAudio
    let brillo: Double
    let fondo: NSImage
    let notch: CGSize

    static func cargar(_ ruta: URL) -> SetupReal {
        let foto = leerJSON(ruta)
        let musica = Musica(vivo: false)
        if let m = foto["musica"] as? [String: Any] {
            musica.titulo = m["titulo"] as? String ?? ""
            musica.artista = m["artista"] as? String ?? ""
            musica.duracion = m["duracion"] as? Double ?? 0
            musica.posicion = m["posicion"] as? Double ?? 0
            musica.sonando = m["sonando"] as? Bool ?? false
            if let r = m["caratula"] as? String, let img = NSImage(contentsOfFile: r) {
                musica.caratula = img
                musica.acento = Musica.colorMedio(img)
            }
        }
        let agenda = Agenda(vivo: false)
        agenda.permitido = true
        if let r = foto["reunion"] as? [String: Any] {
            let inicio = Date().addingTimeInterval((r["minutos"] as? Double ?? 4.2) * 60)
            agenda.eventos = [.init(id: "r", titulo: r["titulo"] as? String ?? "Reunión", inicio: inicio,
                                    fin: inicio.addingTimeInterval((r["duracion"] as? Double ?? 45) * 60),
                                    color: Color(red: 0.36, green: 0.62, blue: 1.0), enlace: URL(string: "https://meet.google.com/abc-defg-hij"))]
        }
        let claude = SesionesClaude(vivo: false)
        claude.leer(avisar: false)
        claude.sesiones = claude.sesiones.map { var s = $0; s.aplicar(Transcripto.leer(s.id)); return s }
        let uso = UsoClaude().calcular(sesiones: claude.sesiones.map(\.id))
        claude.tokensHoy = uso.tokens
        claude.respuestasHoy = uso.respuestas
        claude.porHora = uso.porHora
        claude.sesiones = claude.sesiones.map { var s = $0; s.contexto = uso.contexto[s.id] ?? 0; return s }
        let agentes = AgentesRemotos(vivo: false)
        if let a = foto["agente"] as? [String: Any], let r = a["estado"] as? String {
            agentes.agentes = [AgentesRemotos.consultar(nombre: a["nombre"] as? String ?? "Agente", comando: "cat '\(r)'")]
        }
        let salud = EstadoSalud()
        if let s = foto["salud"] as? [String: Any] {
            salud.cpu = s["cpu"] as? Double ?? 0
            salud.gpu = s["gpu"] as? Double ?? 0
            salud.memoriaUsada = s["memoriaUsada"] as? Double ?? 0
            salud.memoriaTotal = s["memoriaTotal"] as? Double ?? salud.memoriaTotal
            salud.swap = s["swap"] as? Double ?? 0
            salud.presion = s["presion"] as? Int ?? 1
            salud.discoLibre = s["discoLibre"] as? Double ?? 0
            salud.discoTotal = s["discoTotal"] as? Double ?? 1
            salud.consumidores = (s["consumidores"] as? [[String: Any]] ?? []).enumerated().map { i, c in
                let bundle = c["bundle"] as? String ?? ""
                let icono = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                    .map { Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path), lado: 52) }
                return Consumidor(id: bundle, nombre: c["nombre"] as? String ?? "", explicacion: "", icono: icono, simbolo: "app",
                                  cpu: c["cpu"] as? Double ?? 0, memoria: c["memoria"] as? Double ?? 0, pid: pid_t(i + 1), esApp: true)
            }
        }
        let fondo = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }.flatMap { NSImage(contentsOf: $0) } ?? fondoDeMuestra()
        var notch = CGSize(width: 186, height: 32)
        if let p = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            notch = CGSize(width: p.frame.width - (p.auxiliaryTopLeftArea?.width ?? 0) - (p.auxiliaryTopRightArea?.width ?? 0),
                           height: p.safeAreaInsets.top)
        }
        let nombreSalida = foto["salida"] as? String ?? "Altavoces"
        return SetupReal(musica: musica, agenda: agenda, claude: claude, agentes: agentes, salud: salud,
                         volumen: foto["volumen"] as? Double ?? 0.5, silencio: foto["silencio"] as? Bool ?? false,
                         salida: SalidaAudio(nombre: nombreSalida, integrado: foto["integrado"] as? Bool ?? false),
                         brillo: foto["brillo"] as? Double ?? 0.7, fondo: fondo, notch: notch)
    }
}

// MARK: Hoja de comparación

/// Las escenas una debajo de otra (760 pt de ancho): volumen, aviso de Claude, isla abierta en Agentes, en Agenda y
/// en Mac.
@MainActor
func hojaComparar(_ destino: URL, variante: String, foto: URL) -> Bool {
    let real = SetupReal.cargar(foto)
    let escenas = escenasIsla(real)
    let hoja = VStack(spacing: 14) { ForEach(escenas.indices, id: \.self) { escenas[$0] } }
        .padding(14)
        .background(Color(white: 0.08))
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Fondo de pantalla real, barra de menú y el notch físico; encima, la isla del tamaño que pide la escena.
@MainActor
func escenaReal<C: View>(_ real: SetupReal, alto: CGFloat, @ViewBuilder _ isla: () -> C) -> some View {
    ZStack(alignment: .top) {
        Image(nsImage: real.fondo).resizable().scaledToFill().frame(width: 760, height: alto, alignment: .top).clipped()
        Rectangle().fill(.white.opacity(0.18)).frame(height: real.notch.height)
        UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(.black)
            .frame(width: real.notch.width, height: real.notch.height)
        isla()
    }
    .frame(width: 760, height: alto)
    .clipShape(RoundedRectangle(cornerRadius: 12))
}

@MainActor
private func escenasIsla(_ real: SetupReal) -> [AnyView] {
    func isla(_ ajustar: (EstadoIsla) -> Void, alto: CGFloat) -> AnyView {
        let estado = EstadoIsla()
        estado.notch = real.notch
        estado.inicioActividad = Date().addingTimeInterval(-7)
        ajustar(estado)
        let hud = EstadoHUD()
        return AnyView(escenaReal(real, alto: alto) {
            VistaIsla(estado: estado, musica: real.musica, agenda: real.agenda, hud: hud, privacidad: Privacidad(vivo: false),
                      claude: real.claude, agentes: real.agentes, salud: real.salud, control: nil)
                .frame(width: Isla.expandida.width, height: Isla.expandida.height)
                .frame(height: alto, alignment: .top)
        })
    }
    let c = real.claude
    let aviso = c.esperando.first ?? c.sesiones.first { $0.estado == .lista } ?? c.sesiones.first
    return [
        isla({ $0.actividad = .nivel(tipo: .volumen, valor: real.volumen, silencio: real.silencio, salida: real.salida) }, alto: 150),
        isla({ e in
            if let s = aviso { e.actividad = .claude(sesion: s, necesita: s.estado == .esperando, duracion: 252) }
        }, alto: 150),
        isla({ $0.expandida = true; $0.pestana = .agentes }, alto: 300),
        isla({ $0.expandida = true; $0.pestana = .agenda }, alto: 300),
        isla({ $0.expandida = true; $0.pestana = .mac }, alto: 300),
    ]
}
