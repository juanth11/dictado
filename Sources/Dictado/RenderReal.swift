import AppKit
import SwiftUI

// Comparación de las variantes de la isla con el setup real del Mac (solo render, no está en la app).
//
//   Dictado --foto-real foto.json            mide el Mac (salud, volumen, salida, brillo) y lo agrega a foto.json
//   Dictado --comparar salida.png diales|mosaicos|luz foto.json
//
// foto.json trae lo que la app no puede leer sola desde la línea de comandos:
//   { "musica": { "titulo", "artista", "duracion", "posicion", "sonando", "caratula": ruta },
//     "hermes": ruta a un JSON con el formato de Agentes.swift, "reunion": { "titulo", "minutos", "duracion" } }
// Las sesiones de Claude se leen en vivo de ~/.claude (solo lectura). El fondo es el del escritorio.

/// Datos que pintan las maquetas (Mosaicos, Luz): los de ejemplo o los del setup real.
@MainActor
struct DatosMaqueta {
    var caratula: NSImage
    var colores: [Color]                 // tres colores vivos de la carátula
    var cancion = "Weightless"
    var artista = "Marconi Union"
    var posicion = 151.0
    var duracion = 480.0
    var sonando = true
    var volumen = 0.62
    var silencio = false
    var salida = "AirPods Pro"
    var salidaSimbolo = "airpodspro"
    var brillo = 0.81
    var claude: SesionesClaude
    var agente: AgentesRemotos.Agente?
    var reunion: Agenda.Evento?
    var salud: EstadoSalud

    /// La sesión que te espera o, si ninguna, la última que terminó (para el aviso de Claude).
    var sesionAviso: SesionesClaude.Sesion? {
        claude.esperando.first ?? claude.sesiones.first { $0.estado == .lista } ?? claude.sesiones.first
    }

    static func ejemplo() -> DatosMaqueta {
        let claude = SesionesClaude(vivo: false)
        claude.sesiones = [
            .init(id: "a", pid: 1, nombre: "Rediseño del sitio web", carpeta: "", estado: .esperando, espera: "Necesita tu permiso",
                  desde: Date().addingTimeInterval(-40), contexto: 318_000, actividad: "swift build"),
            .init(id: "b", pid: 2, nombre: "Informe trimestral", carpeta: "", estado: .trabajando, espera: "",
                  desde: Date().addingTimeInterval(-260), contexto: 768_000, actividad: "Editando HeroSection.tsx"),
        ]
        var agente = AgentesRemotos.Agente(nombre: "Hermes", estado: .ok, resumen: "10 tareas activas · todo bien")
        let hoy = Calendar.current.startOfDay(for: Date())
        agente.tareas = [(3.0, "wiki-nightly-lint"), (3.5, "inbox-process"), (7.0, "finanzas-diario"), (7.03, "airbnb-diario"),
                         (8.05, "morning-briefing")].map {
            .init(nombre: $0.1, estado: "ok", ultima: hoy.addingTimeInterval($0.0 * 3600),
                  proxima: hoy.addingTimeInterval(($0.0 + 24) * 3600), detalle: "")
        }
        let ahora = Date()
        return DatosMaqueta(caratula: caratulaVivaDeMuestra(), colores: [Color(red: 1.0, green: 0.56, blue: 0.30),
                            Color(red: 1.0, green: 0.40, blue: 0.62), Color(red: 0.62, green: 0.45, blue: 1.0)],
                            claude: claude, agente: agente,
                            reunion: .init(id: "r", titulo: "Revisión de contrato", inicio: ahora.addingTimeInterval(252),
                                           fin: ahora.addingTimeInterval(2952), color: Color(red: 0.36, green: 0.62, blue: 1.0),
                                           enlace: URL(string: "https://meet.google.com/abc-defg-hij")),
                            salud: ejemploSalud())
    }

    static func caratulaVivaDeMuestra() -> NSImage {
        let img = NSImage(size: NSSize(width: 300, height: 300))
        img.lockFocus()
        NSGradient(colors: [NSColor(red: 1.0, green: 0.62, blue: 0.32, alpha: 1), NSColor(red: 1.0, green: 0.38, blue: 0.58, alpha: 1),
                            NSColor(red: 0.50, green: 0.36, blue: 0.98, alpha: 1)])?
            .draw(in: NSRect(x: 0, y: 0, width: 300, height: 300), angle: -60)
        img.unlockFocus()
        return img
    }

    /// Tres colores vivos de la carátula: la imagen se reduce a 6×6 y se eligen las celdas más saturadas y
    /// distintas entre sí; se aclaran un poco para que brillen sobre negro.
    static func paleta(_ imagen: NSImage) -> [Color] {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 6, pixelsHigh: 6, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 24, bitsPerPixel: 32)
        else { return [.white] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        imagen.draw(in: NSRect(x: 0, y: 0, width: 6, height: 6))
        NSGraphicsContext.restoreGraphicsState()
        var celdas: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        for x in 0..<6 { for y in 0..<6 {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            celdas.append((h, s, b))
        } }
        celdas.sort { $0.s * $0.b > $1.s * $1.b }
        var elegidas: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        for c in celdas where elegidas.count < 3 {
            if elegidas.allSatisfy({ min(abs($0.h - c.h), 1 - abs($0.h - c.h)) > 0.06 }) { elegidas.append(c) }
        }
        while elegidas.count < 3, let primera = elegidas.first ?? celdas.first { elegidas.append(primera) }
        return elegidas.map { Color(hue: $0.h, saturation: min(1, max(0.45, $0.s * 1.15)), brightness: max(0.82, $0.b)) }
    }
}

/// Las maquetas leen de aquí; cada hoja lo pone antes de dibujar.
@MainActor var maqueta: DatosMaqueta = .ejemplo()

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
        if let r = foto["hermes"] as? String {
            agentes.agentes = [AgentesRemotos.consultar(nombre: "Hermes", comando: "cat '\(r)'")]
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

    /// Para las maquetas.
    var datos: DatosMaqueta {
        let caratula = musica.caratula ?? DatosMaqueta.caratulaVivaDeMuestra()
        return DatosMaqueta(caratula: caratula, colores: DatosMaqueta.paleta(caratula), cancion: musica.titulo, artista: musica.artista,
                            posicion: musica.posicion, duracion: musica.duracion, sonando: musica.sonando,
                            volumen: volumen, silencio: silencio, salida: salida.nombre, salidaSimbolo: salida.simbolo, brillo: brillo,
                            claude: claude, agente: agentes.agentes.first, reunion: agenda.eventos.first, salud: salud)
    }
}

// MARK: Hoja de comparación

/// Las mismas escenas para cada variante, una debajo de otra (760 pt de ancho): volumen, aviso de Claude,
/// isla abierta en Agentes, en Agenda y en Mac.
@MainActor
func hojaComparar(_ destino: URL, variante: String, foto: URL) -> Bool {
    let real = SetupReal.cargar(foto)
    maqueta = real.datos
    let escenas: [AnyView]
    switch variante {
    case "mosaicos": escenas = escenasMosaicos(real)
    case "luz": escenas = escenasLuz(real)
    default: escenas = escenasDiales(real)
    }
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
private func escenasDiales(_ real: SetupReal) -> [AnyView] {
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
    let aviso = maqueta.sesionAviso
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
