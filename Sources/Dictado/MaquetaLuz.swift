import AppKit
import SwiftUI

/// Maqueta (solo render, no está en la app): variante «Luz» de la isla. La isla sigue siendo la de Apple (negra,
/// pegada al notch, tipografía del sistema, controles de iOS) y se mejora con luz: un resplandor del color de lo
/// que muestra sube desde el borde de abajo, barras de LED encendidas, cápsulas de progreso líquidas que brillan,
/// un arco de medidor para el Mac y datos con la unidad en versalitas. `Dictado --vista-luz salida.png`
@MainActor
func hojaLuz(_ destino: URL) -> Bool {
    maqueta = .ejemplo()
    let fondo = fondoDeMuestra()
    let notch = CGSize(width: 186, height: 32)

    func escena<C: View>(alto: CGFloat, isla: CGSize, radio: CGFloat, @ViewBuilder _ contenido: () -> C) -> some View {
        ZStack(alignment: .top) {
            Image(nsImage: fondo).resizable().scaledToFill().frame(width: 760, height: alto, alignment: .top).clipped()
            Rectangle().fill(.white.opacity(0.18)).frame(height: 32)
            IslaLuz(tamano: isla, radio: radio) { contenido() }
        }
        .frame(width: 760, height: alto)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    let t = TamanosLuz(notch: notch)

    let hoja = VStack(spacing: 14) {
        HStack(spacing: 14) {
            escena(alto: 150, isla: t.nivel, radio: 26) { LNivel(tipo: .volumen) }
            escena(alto: 150, isla: t.nivel, radio: 26) { LNivel(tipo: .brillo) }
        }
        HStack(spacing: 14) {
            escena(alto: 150, isla: t.nivel, radio: 26) { LNivel(tipo: .silencio) }
            escena(alto: 150, isla: t.carga, radio: 10) { LCarga() }
        }
        HStack(spacing: 14) {
            escena(alto: 150, isla: t.reunion, radio: 26) { LReunion() }
            escena(alto: 150, isla: t.cancion, radio: 26) { LCancion() }
        }
        HStack(spacing: 14) {
            escena(alto: 150, isla: t.aviso, radio: 26) {
                LAviso(color: L.naranja, icono: .estrella, rotulo: "Necesita tu permiso", titulo: "Rediseño del sitio web",
                       detalle: "Terminal · swift build -c release", boton: "Responder")
            }
            escena(alto: 150, isla: t.aviso, radio: 26) {
                LAviso(color: L.ambar, icono: .simbolo("server.rack"), rotulo: "Alerta · Hermes", titulo: "resumen-finanzas falló",
                       detalle: "el banco no respondió", boton: "Ver")
            }
        }
        escena(alto: 300, isla: t.abierta, radio: 34) { LAbierta(pestana: .agentes) }
        escena(alto: 300, isla: t.abierta, radio: 34) { LAbierta(pestana: .agente) }
        escena(alto: 300, isla: t.abierta, radio: 34) { LAbierta(pestana: .agenda) }
        escena(alto: 300, isla: t.abierta, radio: 34) { LAbierta(pestana: .mac) }
    }
    .padding(14)
    .background(Color(white: 0.08))
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Tamaños de la isla en la variante Luz según el notch.
struct TamanosLuz {
    let notch: CGSize
    private var w: CGFloat { notch.width + 2 * FormaIsla.hombro }
    private func aviso(_ ala: CGFloat, _ alto: CGFloat) -> CGSize { CGSize(width: w + 2 * ala, height: notch.height + alto) }
    var nivel: CGSize { aviso(150, 50) }
    var carga: CGSize { aviso(70, 0) }
    var reunion: CGSize { aviso(165, 60) }
    var cancion: CGSize { aviso(135, 60) }
    var aviso: CGSize { aviso(155, 60) }
    var abierta: CGSize { CGSize(width: 680, height: 250) }
}

/// La isla negra con su contenido recortado a la forma y la sombra.
private struct IslaLuz<C: View>: View {
    let tamano: CGSize
    let radio: CGFloat
    let contenido: C

    init(tamano: CGSize, radio: CGFloat, @ViewBuilder contenido: () -> C) {
        self.tamano = tamano
        self.radio = radio
        self.contenido = contenido()
    }

    var body: some View {
        ZStack(alignment: .top) {
            FormaIsla(radio: radio).fill(.black)
            contenido.clipShape(FormaIsla(radio: radio))
        }
        .frame(width: tamano.width, height: tamano.height)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

/// Escenas de la comparación con el setup real: volumen, aviso de Claude, abierta en Agentes, Agenda y Mac.
@MainActor
func escenasLuz(_ real: SetupReal) -> [AnyView] {
    let t = TamanosLuz(notch: real.notch)
    var escenas: [AnyView] = [
        AnyView(escenaReal(real, alto: 150) { IslaLuz(tamano: t.nivel, radio: 26) { LNivel(tipo: maqueta.silencio ? .silencio : .volumen) } }),
    ]
    if let s = maqueta.sesionAviso {
        let espera = s.estado == .esperando
        escenas.append(AnyView(escenaReal(real, alto: 150) {
            IslaLuz(tamano: t.aviso, radio: 26) {
                LAviso(color: L.naranja, icono: .estrella, rotulo: espera ? "Necesita tu permiso" : "Terminó · 4:12",
                       titulo: s.nombre, detalle: espera ? s.espera : (s.resumen.isEmpty ? "Lista" : s.resumen),
                       boton: espera ? "Responder" : "Ver")
            }
        }))
    }
    for p in [LAbierta.Pestana.agentes, .agenda, .mac] {
        escenas.append(AnyView(escenaReal(real, alto: 300) { IslaLuz(tamano: t.abierta, radio: 34) { LAbierta(pestana: p) } }))
    }
    return escenas
}

// MARK: Lenguaje

private enum L {
    static let azul = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let verde = Color(red: 0.24, green: 0.86, blue: 0.46)
    static let naranja = Color(red: 1.0, green: 0.52, blue: 0.30)
    static let ambar = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let rojo = Color(red: 1.0, green: 0.34, blue: 0.32)
    static let violeta = Color(red: 0.62, green: 0.45, blue: 1.0)
    static let rosa = Color(red: 1.0, green: 0.40, blue: 0.62)
    @MainActor static var album: [Color] { maqueta.colores }
    @MainActor static var acento: Color { maqueta.colores.count > 1 ? maqueta.colores[1] : maqueta.colores[0] }

    /// "8:53 – 9:38 p. m."
    static func franja(_ inicio: Date, _ fin: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "h:mm"
        let a = f.string(from: inicio)
        f.dateFormat = "h:mm a"
        return a + " – " + f.string(from: fin)
    }

    static func servicio(_ enlace: URL?) -> String {
        let h = enlace?.host ?? ""
        return h.contains("zoom") ? "Zoom" : h.contains("teams") ? "Teams" : h.contains("meet") ? "Meet" : "Reunión"
    }

    static func color(_ colores: [Color], _ t: Double) -> Color {
        guard colores.count > 1 else { return colores.first ?? .white }
        let x = min(1, max(0, t)) * Double(colores.count - 1)
        let i = min(colores.count - 2, Int(x))
        return colores[i].mix(with: colores[i + 1], by: x - Double(i))
    }
}

/// La luz que sube desde el borde de abajo, del color de lo que muestra la isla (como el reproductor de iOS
/// que se tiñe con la carátula). Con varios colores, cada uno ocupa una parte del borde.
private struct LLuz: View {
    let colores: [Color]
    var alto: CGFloat = 0.85      // hasta dónde sube (fracción del alto)
    var fuerza: Double = 0.8
    var centro: Double = 0.5      // dónde nace en el ancho (0–1)
    var ancho: Double = 1

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                ForEach(colores.indices, id: \.self) { i in
                    let n = Double(colores.count)
                    let x = centro + ancho * (n == 1 ? 0 : -0.32 + 0.64 * Double(i) / (n - 1))
                    Ellipse()
                        .fill(colores[i])
                        .frame(width: w * ancho * (n == 1 ? 0.9 : 0.62), height: h * alto)
                        .position(x: w * x, y: h * 1.04)
                        .blur(radius: min(h * 0.32, 44))
                }
            }
            .opacity(fuerza)
        }
        .allowsHitTesting(false)
    }
}

/// Barra de LED: rayitas que se encienden con brillo en su color; la última más clara.
private struct LBarraLED: View {
    let valor: Double
    let colores: [Color]
    var cuantos = 30
    var alto: CGFloat = 14
    var grosor: CGFloat = 3.2
    var hueco: CGFloat = 2.6
    var apagada = false

    var body: some View {
        let encendidas = Int((valor * Double(cuantos)).rounded())
        HStack(spacing: hueco) {
            ForEach(0..<cuantos, id: \.self) { i in
                let c = L.color(colores, Double(i) / Double(max(1, cuantos - 1)))
                let encendida = i < encendidas && !apagada
                let punta = i == encendidas - 1
                RoundedRectangle(cornerRadius: grosor / 2, style: .continuous)
                    .fill(encendida ? (punta ? c.mix(with: .white, by: 0.55) : c) : Color.white.opacity(i < encendidas ? 0.24 : 0.08))
                    .frame(width: grosor, height: alto)
                    .shadow(color: encendida ? c.opacity(0.9) : .clear, radius: punta ? 5 : 3)
            }
        }
    }
}

/// Cápsula de progreso líquida: el relleno brilla, tiene un reflejo arriba y un ícono en la punta.
private struct LLiquido: View {
    let valor: Double
    let colores: [Color]
    var alto: CGFloat = 24
    var icono: String?
    var texto: String?

    var body: some View {
        GeometryReader { g in
            let lleno = max(alto, g.size.width * valor)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 1))
                if let texto {
                    Text(texto).font(.system(size: alto * 0.42, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, alto * 0.5)
                }
                Capsule()
                    .fill(LinearGradient(colors: colores, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)],
                                                           startPoint: .top, endPoint: .center)).padding(alto * 0.08))
                    .overlay(alignment: .trailing) {
                        if let icono {
                            Image(systemName: icono).font(.system(size: alto * 0.44, weight: .bold)).foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.25), radius: 2).padding(.trailing, alto * 0.34)
                        }
                    }
                    .frame(width: lleno)
                    .shadow(color: (colores.last ?? .white).opacity(0.75), radius: alto * 0.45)
            }
        }
        .frame(height: alto)
    }
}

/// Medio arco de medidor, de izquierda a derecha por arriba.
private struct LArcoForma: Shape {
    var hasta: Double

    func path(in r: CGRect) -> Path {
        let radio = min(r.width / 2, r.height)
        var p = Path()
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + radio), radius: radio, startAngle: .degrees(180),
                 endAngle: .degrees(180 + 180 * hasta), clockwise: false)
        return p
    }
}

private struct LArco: View {
    let valor: Double
    let colores: [Color]
    var grosor: CGFloat = 7

    var body: some View {
        ZStack {
            LArcoForma(hasta: 1).stroke(.white.opacity(0.1), style: StrokeStyle(lineWidth: grosor, lineCap: .round))
            LArcoForma(hasta: valor)
                .stroke(LinearGradient(colors: colores, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                .shadow(color: (colores.last ?? .white).opacity(0.7), radius: 6)
        }
        .padding(grosor / 2)
    }
}

/// Dato con su unidad en versalitas al lado ("4:12 MIN", "62 %").
private struct LDato: View {
    let numero: String
    var unidad = ""
    var color: Color = .white
    var tamano: CGFloat = 22
    var peso: Font.Weight = .medium

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: tamano * 0.1) {
            Text(numero).font(.system(size: tamano, weight: peso)).monospacedDigit().kerning(-tamano * 0.02)
            if !unidad.isEmpty {
                Text(unidad.uppercased()).font(.system(size: max(8, tamano * 0.38), weight: .semibold)).opacity(0.7)
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Ícono dentro de un círculo de vidrio teñido.
private struct LInsignia: View {
    enum Icono { case simbolo(String), estrella }
    let icono: Icono
    let color: Color
    var lado: CGFloat = 32

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.42), color.opacity(0.14)], center: .top, startRadius: 0, endRadius: lado))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [color.opacity(0.7), color.opacity(0.15)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay {
                switch icono {
                case .estrella: EstrellaClaude().fill(color.mix(with: .white, by: 0.25)).frame(width: lado * 0.5, height: lado * 0.5)
                case .simbolo(let s):
                    Image(systemName: s).font(.system(size: lado * 0.4, weight: .semibold)).foregroundStyle(color.mix(with: .white, by: 0.25))
                }
            }
            .frame(width: lado, height: lado)
            .shadow(color: color.opacity(0.45), radius: 8)
    }
}

/// Botón en cápsula del color, con brillo (Unirse, Responder, Ver).
private struct LBoton: View {
    let texto: String
    let color: Color
    var icono: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icono { Image(systemName: icono).font(.system(size: 11, weight: .bold)) }
            Text(texto).font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background {
            Capsule().fill(LinearGradient(colors: [color.mix(with: .white, by: 0.25), color], startPoint: .top, endPoint: .bottom))
                .shadow(color: color.opacity(0.65), radius: 9)
        }
        .fixedSize()
    }
}

private struct LRotulo: View {
    let texto: String
    var color: Color = .white.opacity(0.5)

    var body: some View {
        Text(texto.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.9).foregroundStyle(color).lineLimit(1)
    }
}

/// Debajo del notch, como los avisos de la isla.
private struct LFila<C: View>: View {
    @ViewBuilder let contenido: () -> C

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 32)
            HStack(spacing: 12) { contenido() }
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: Avisos

private struct LNivel: View {
    enum Tipo { case volumen, brillo, silencio }
    let tipo: Tipo

    var body: some View {
        let colores: [Color] = tipo == .brillo ? Paleta.brillo : tipo == .volumen ? Paleta.volumen : [L.rojo]
        let valor = tipo == .brillo ? maqueta.brillo : maqueta.volumen
        ZStack {
            if tipo != .silencio { LLuz(colores: colores, alto: 0.7, fuerza: 0.55) }
            LFila {
                if tipo == .silencio {
                    Image(systemName: "speaker.slash.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 24).background(Capsule().fill(L.rojo))
                } else {
                    Image(systemName: tipo == .volumen ? "speaker.wave.3.fill" : "sun.max.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 40)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: tipo == .brillo ? "display" : maqueta.salidaSimbolo).font(.system(size: 9.5, weight: .semibold))
                        Text(tipo == .brillo ? "Pantalla integrada" : maqueta.salida).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.55))
                    LBarraLED(valor: valor, colores: colores, apagada: tipo == .silencio)
                }
                Spacer(minLength: 4)
                if tipo == .silencio {
                    Text("Silencio").font(.system(size: 15, weight: .semibold)).foregroundStyle(L.rojo)
                } else {
                    LDato(numero: "\(Int((valor * 100).rounded()))", unidad: "%", tamano: 30, peso: .light)
                }
            }
        }
    }
}

private struct LCarga: View {
    var body: some View {
        HStack {
            Image(systemName: "bolt.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(L.verde)
                .shadow(color: L.verde.opacity(0.8), radius: 5)
            Spacer()
            Text("87 %").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(L.verde)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.35), lineWidth: 1.2).frame(width: 28, height: 14)
                RoundedRectangle(cornerRadius: 2.5).fill(L.verde).frame(width: 22 * 0.87, height: 9).padding(.leading, 2.5)
                    .shadow(color: L.verde.opacity(0.8), radius: 4)
            }
        }
        .padding(.horizontal, 26)
        .frame(maxHeight: .infinity)
    }
}

private struct LReunion: View {
    var body: some View {
        if let e = maqueta.reunion {
            ZStack {
                LLuz(colores: [L.azul], alto: 0.75, fuerza: 0.5)
                LFila {
                    NumeroPuntos(texto: Tiempo.cuentaRegresiva(hasta: e.inicio, desde: Date()), punto: 3.0, paso: 4.0,
                                 color: L.azul.mix(with: .white, by: 0.35))
                    VStack(alignment: .leading, spacing: 2) {
                        LRotulo(texto: "Empieza en · " + L.servicio(e.enlace), color: L.azul)
                        Text(e.titulo).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(L.franja(e.inicio, e.fin)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer(minLength: 6)
                    LBoton(texto: "Unirse", color: L.verde, icono: "video.fill")
                }
            }
        }
    }
}

private struct LCancion: View {
    var body: some View {
        ZStack {
            LLuz(colores: L.album, alto: 0.8, fuerza: 0.6)
            LFila {
                Image(nsImage: maqueta.caratula).resizable().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: L.acento.opacity(0.6), radius: 8)
                VStack(alignment: .leading, spacing: 1) {
                    LRotulo(texto: maqueta.sonando ? "Ahora suena" : "En pausa", color: L.acento.mix(with: .white, by: 0.3))
                    Text(maqueta.cancion).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(maqueta.artista).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 6)
                LOnda(colores: L.album)
            }
        }
    }
}

/// Onda de la música: barras del color de la carátula con brillo (planas si está en pausa).
private struct LOnda: View {
    let colores: [Color]
    var alturas: [CGFloat] = [8, 15, 22, 12, 18, 9, 14]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(alturas.indices, id: \.self) { i in
                let c = L.color(colores, Double(i) / Double(alturas.count - 1))
                Capsule().fill(c).frame(width: 3, height: maqueta.sonando ? alturas[i] : 4)
                    .shadow(color: c.opacity(0.8), radius: 3)
            }
        }
        .frame(height: 24)
    }
}

private struct LAviso: View {
    let color: Color
    let icono: LInsignia.Icono
    let rotulo: String
    let titulo: String
    let detalle: String
    let boton: String

    var body: some View {
        ZStack {
            LLuz(colores: [color], alto: 0.75, fuerza: 0.5)
            LFila {
                LInsignia(icono: icono, color: color, lado: 36)
                VStack(alignment: .leading, spacing: 2) {
                    LRotulo(texto: rotulo, color: color)
                    Text(titulo).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(detalle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 6)
                LBoton(texto: boton, color: color)
            }
        }
    }
}

// MARK: Isla abierta

private struct LAbierta: View {
    enum Pestana { case agentes, agente, agenda, mac }
    let pestana: Pestana

    var body: some View {
        let d = maqueta
        let alerta = d.agente.map { $0.estado == .alerta || $0.estado == .caido } ?? false
        ZStack {
            // La música tiñe el borde de abajo a la izquierda; la pestaña, a la derecha.
            LLuz(colores: L.album, alto: 0.55, fuerza: 0.55, centro: 0.22, ancho: 0.5)
            LLuz(colores: [luz], alto: 0.5, fuerza: 0.26, centro: 0.76, ancho: 0.5)
            VStack(spacing: 0) {
                Color.clear.frame(height: 32)
                HStack(alignment: .top, spacing: 24) {
                    LReproductor().frame(width: 250)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 4) {
                            LPildora(titulo: "Agentes", cuenta: d.claude.sesiones.count + (d.agente == nil ? 0 : 1),
                                     punto: !d.claude.esperando.isEmpty ? L.naranja : alerta ? L.ambar : nil,
                                     activa: pestana == .agentes || pestana == .agente)
                            LPildora(titulo: "Agenda", cuenta: d.reunion == nil ? 0 : 1, activa: pestana == .agenda)
                            LPildora(titulo: "Mac", punto: color(d.salud.diagnostico.gravedad), activa: pestana == .mac)
                            Spacer()
                        }
                        switch pestana {
                        case .agentes: LAgentes()
                        case .agente: LHermes()
                        case .agenda: LAgenda()
                        case .mac: LMac()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 30)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
        }
    }

    private var luz: Color {
        switch pestana {
        case .agentes: return maqueta.claude.esperando.isEmpty ? L.naranja.opacity(0.7) : L.naranja
        case .agente: return L.verde
        case .agenda: return L.azul
        case .mac: return color(maqueta.salud.diagnostico.gravedad)
        }
    }
}

private func color(_ g: Gravedad) -> Color {
    switch g {
    case .bien: return L.verde
    case .atento: return L.ambar
    case .mal: return L.rojo
    }
}

private struct LPildora: View {
    let titulo: String
    var cuenta = 0
    var punto: Color?
    let activa: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let punto { Circle().fill(punto).frame(width: 6, height: 6).shadow(color: punto, radius: 3) }
            Text(titulo).font(.system(size: 11.5, weight: .semibold))
            if cuenta > 0 { Text("\(cuenta)").font(.system(size: 10.5, weight: .semibold)).opacity(0.45) }
        }
        .foregroundStyle(.white.opacity(activa ? 1 : 0.5))
        .padding(.horizontal, 11)
        .frame(height: 24)
        .background(Capsule().fill(.white.opacity(activa ? 0.14 : 0)))
    }
}

/// Reproductor de iOS: carátula, título, onda; progreso del color del álbum con su punta; controles del sistema.
private struct LReproductor: View {
    var body: some View {
        let d = maqueta
        let avance = d.duracion > 0 ? min(1, d.posicion / d.duracion) : 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: d.caratula).resizable().frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: L.acento.opacity(0.55), radius: 12, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.cancion).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(d.artista).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 4)
                LOnda(colores: L.album, alturas: [7, 13, 19, 10, 15])
            }
            VStack(spacing: 5) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                        Capsule().fill(LinearGradient(colors: L.album, startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * avance, height: 4)
                            .shadow(color: L.acento.opacity(0.8), radius: 4)
                        Circle().fill(.white).frame(width: 10, height: 10).shadow(color: L.acento, radius: 5)
                            .offset(x: g.size.width * avance - 5)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 10)
                HStack {
                    Text(Tiempo.reloj(d.posicion)); Spacer(); Text("-" + Tiempo.reloj(d.duracion - d.posicion))
                }
                .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
            }
            HStack {
                Spacer()
                Image(systemName: "backward.fill").font(.system(size: 19))
                Spacer()
                Image(systemName: d.sonando ? "pause.fill" : "play.fill").font(.system(size: 28))
                Spacer()
                Image(systemName: "forward.fill").font(.system(size: 19))
                Spacer()
            }
            .foregroundStyle(.white)
        }
    }
}

/// Cuánto corrió hoy un agente: corridas de hoy, las que faltan hoy y la próxima.
private struct DiaAgente {
    let corridas: [AgentesRemotos.Tarea]
    let faltan: Int
    let proxima: AgentesRemotos.Tarea?

    init(_ a: AgentesRemotos.Agente) {
        let cal = Calendar.current
        let activas = a.tareas.filter(\.activa)
        corridas = activas.filter { $0.ultima.map(cal.isDateInToday) ?? false }.sorted { $0.ultima! > $1.ultima! }
        faltan = activas.filter { t in t.proxima.map { cal.isDateInToday($0) && $0 > Date() } ?? false }.count
        proxima = activas.filter { ($0.proxima ?? .distantPast) > Date() }.min { $0.proxima! < $1.proxima! }
    }

    var total: Int { corridas.count + faltan }
    var avance: Double { total == 0 ? 0 : Double(corridas.count) / Double(total) }
}

/// Pestaña Agentes: la sesión que te espera en una tarjeta encendida; las demás en filas; Hermes con su día
/// en una cápsula líquida.
private struct LAgentes: View {
    var body: some View {
        let sesiones = maqueta.claude.sesiones
        let espera = sesiones.first { $0.estado == .esperando }
        let resto = sesiones.filter { $0.id != espera?.id }
        VStack(alignment: .leading, spacing: 8) {
            if let s = espera { tarjeta(s) }
            ForEach(Array(resto.prefix(espera == nil ? 3 : 2))) { fila($0) }
            if let a = maqueta.agente { hermes(a) }
        }
    }

    private func tarjeta(_ s: SesionesClaude.Sesion) -> some View {
        HStack(spacing: 10) {
            LInsignia(icono: .estrella, color: L.naranja, lado: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.nombre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(Tiempo.sesion(s)).font(.system(size: 10.5)).foregroundStyle(L.naranja).lineLimit(1)
            }
            Spacer(minLength: 4)
            LBoton(texto: "Responder", color: L.naranja).scaleEffect(0.86)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [L.naranja.opacity(0.24), L.naranja.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(L.naranja.opacity(0.3), lineWidth: 1))
        }
    }

    private func fila(_ s: SesionesClaude.Sesion) -> some View {
        HStack(spacing: 10) {
            Group {
                switch s.estado {
                case .trabajando: EstrellaClaude().fill(L.naranja).frame(width: 14, height: 14)
                case .esperando: Circle().fill(L.naranja).frame(width: 8, height: 8).shadow(color: L.naranja, radius: 4)
                case .lista: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.nombre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(Tiempo.sesion(s)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
            Spacer(minLength: 4)
            if s.contexto > 0 {
                LDato(numero: "\(s.contexto / 1000)", unidad: "k", color: s.contexto > 600_000 ? L.ambar : .white.opacity(0.35),
                      tamano: 13, peso: .semibold)
            }
        }
        .padding(.horizontal, 9)
    }

    private func hermes(_ a: AgentesRemotos.Agente) -> some View {
        let dia = DiaAgente(a)
        let mal = !a.alertas.isEmpty || a.estado == .caido
        let c = mal ? (a.estado == .caido ? L.rojo : L.ambar) : L.verde
        let detalle = a.alertas.first ?? a.error ?? ("\(dia.corridas.count) de \(dia.total) hoy"
            + (dia.proxima?.proxima).map { " · próxima " + Tiempo.hora($0) }.orEmpty)
        return HStack(spacing: 10) {
            LInsignia(icono: .simbolo("server.rack"), color: c, lado: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(a.nombre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    Text(detalle).font(.system(size: 10.5)).foregroundStyle(mal ? c : .white.opacity(0.45)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                LLiquido(valor: max(0.04, dia.avance), colores: [c.mix(with: .white, by: 0.35), c], alto: 8)
            }
        }
        .padding(.horizontal, 9)
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

/// El día de Hermes: estado, cápsula líquida con lo que ya corrió hoy, rayitas de cada corrida y sus tareas.
private struct LHermes: View {
    var body: some View {
        if let a = maqueta.agente {
            let dia = DiaAgente(a)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                    Text(a.nombre).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                    LRotulo(texto: a.estado == .ok ? "En línea" : a.estado == .caido ? "Sin conexión" : "Alerta",
                            color: a.estado == .ok ? L.verde : a.estado == .caido ? L.rojo : L.ambar)
                    Spacer()
                    LDato(numero: "\(a.tareas.filter(\.activa).count)", unidad: "tareas", color: .white.opacity(0.75), tamano: 13, peso: .semibold)
                }
                LLiquido(valor: max(0.08, dia.avance), colores: [L.verde.mix(with: .white, by: 0.4), L.verde], alto: 22,
                         icono: "checkmark", texto: "\(dia.corridas.count) de \(dia.total)")
                LTiras(horas: dia.corridas.compactMap(\.ultima).map(LTiras.hora))
                VStack(spacing: 4) {
                    ForEach(dia.corridas.prefix(2), id: \.nombre) { t in
                        LTarea(nombre: t.nombre, hora: t.ultima.map(Tiempo.hora) ?? "", color: t.color == .white ? .white : L.verde)
                    }
                    if let p = dia.proxima, let cuando = p.proxima {
                        LTarea(nombre: p.nombre, hora: Tiempo.hora(cuando), color: .white.opacity(0.5), proxima: true)
                    }
                }
            }
        }
    }
}

/// Rayitas del día (como los gráficos del reloj): una por corrida, con "12 A. M." y "AHORA" en los extremos.
private struct LTiras: View {
    let horas: [Double]

    static func hora(_ d: Date) -> Double {
        d.timeIntervalSince(Calendar.current.startOfDay(for: d)) / 3600
    }

    var body: some View {
        let ahora = Self.hora(Date())
        VStack(spacing: 3) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(0..<48, id: \.self) { i in
                            Rectangle().fill(.white.opacity(Double(i) / 2 < ahora ? 0.16 : 0.06)).frame(width: 1, height: 9)
                            Spacer(minLength: 0)
                        }
                    }
                    ForEach(horas, id: \.self) { h in
                        Capsule().fill(L.verde).frame(width: 2.5, height: 14).shadow(color: L.verde, radius: 3)
                            .offset(x: g.size.width * h / 24)
                    }
                    Capsule().fill(.white).frame(width: 2, height: 16).offset(x: g.size.width * ahora / 24)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            HStack {
                Text("12 A. M."); Spacer(); Text("6 A. M."); Spacer(); Text("12 M."); Spacer(); Text("6 P. M."); Spacer(); Text("12 A. M.")
            }
            .font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
        }
    }
}

private struct LTarea: View {
    let nombre: String
    let hora: String
    let color: Color
    var proxima = false

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if proxima { Circle().strokeBorder(color, lineWidth: 1.2) } else { Circle().fill(color).shadow(color: color, radius: 3) }
            }
            .frame(width: 6, height: 6)
            Text(nombre).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.88))
            Spacer()
            Text(proxima ? "próxima · " + hora : hora).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
        }
    }
}

/// Agenda: la cuenta regresiva en puntos, la reunión y Unirse; abajo las próximas 4 horas con las reuniones como
/// cápsulas de luz.
private struct LAgenda: View {
    var body: some View {
        if let e = maqueta.reunion {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    NumeroPuntos(texto: Tiempo.cuentaRegresiva(hasta: e.inicio, desde: Date()), punto: 2.6, paso: 3.6,
                                 color: L.azul.mix(with: .white, by: 0.35))
                    VStack(alignment: .leading, spacing: 2) {
                        LRotulo(texto: "Empieza en · " + L.servicio(e.enlace), color: L.azul)
                        Text(e.titulo).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(L.franja(e.inicio, e.fin)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer(minLength: 4)
                    LBoton(texto: "Unirse", color: L.verde, icono: "video.fill")
                }
                riel([e])
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                LRotulo(texto: "Hoy", color: L.azul)
                Text("Sin reuniones").font(.system(size: 22, weight: .light)).foregroundStyle(.white)
                riel([])
            }
        }
    }

    private func riel(_ eventos: [Agenda.Evento]) -> some View {
        let cal = Calendar.current
        let desde = cal.dateInterval(of: .hour, for: Date())!.start
        let horas = 4.0
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "h a"
        return VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                let x = { (d: Date) in w * min(1, max(0, d.timeIntervalSince(desde) / (horas * 3600))) }
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07)).frame(height: 18)
                    Capsule().fill(.white.opacity(0.1)).frame(width: x(Date()), height: 18)
                    ForEach(eventos) { e in
                        LBloque(color: e.color, texto: e.titulo).frame(width: max(30, x(e.fin) - x(e.inicio))).offset(x: x(e.inicio))
                    }
                    Capsule().fill(.white).frame(width: 2, height: 24).offset(x: x(Date())).shadow(color: .white, radius: 3)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 24)
            HStack {
                ForEach(0..<5, id: \.self) { i in
                    if i > 0 { Spacer() }
                    Text(f.string(from: desde.addingTimeInterval(Double(i) * 3600)).uppercased())
                }
            }
            .font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
        }
    }
}

private struct LBloque: View {
    let color: Color
    let texto: String

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.3), color], startPoint: .top, endPoint: .bottom))
            .frame(height: 18)
            .shadow(color: color.opacity(0.7), radius: 6)
            .overlay(Text(texto).font(.system(size: 8.5, weight: .bold)).foregroundStyle(.black.opacity(0.75)).lineLimit(1)
                .padding(.horizontal, 6))
    }
}

/// Mac: el arco del dato que más importa y, al lado, las demás medidas con su ícono.
private struct LMac: View {
    var body: some View {
        let s = maqueta.salud
        let d = s.diagnostico
        let memoria = s.memoriaUsada / max(1, s.memoriaTotal)
        // El arco muestra lo peor; si todo está bien, el disco (lo que más cambia con los días).
        let principal: (valor: Double, numero: String, unidad: String, pie: String, g: Gravedad) = {
            if s.gravedadMemoria > s.gravedadDisco && s.gravedadMemoria >= s.gravedadCPU {
                return (memoria, String(format: "%.0f", s.memoriaUsada / 1e9), "GB", String(format: "de %.0f en uso", s.memoriaTotal / 1.073741824e9), s.gravedadMemoria)
            }
            if s.gravedadCPU > s.gravedadDisco { return (s.cpu, "\(Int(s.cpu * 100))", "%", "procesador", s.gravedadCPU) }
            return (1 - s.discoLibre / max(1, s.discoTotal), String(format: s.discoLibre < 10e9 ? "%.1f" : "%.0f", s.discoLibre / 1e9)
                .replacingOccurrences(of: ".", with: ","), "GB", String(format: "libres de %.0f", s.discoTotal / 1e9), s.gravedadDisco)
        }()
        let colores: [Color] = principal.g == .bien ? [L.verde.mix(with: .white, by: 0.4), L.verde]
            : principal.g == .atento ? [L.ambar.mix(with: .white, by: 0.3), L.ambar, L.naranja] : [L.ambar, L.naranja, L.rojo]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                ZStack(alignment: .bottom) {
                    LArco(valor: principal.valor, colores: colores, grosor: 8).frame(width: 128, height: 68)
                    VStack(spacing: 0) {
                        LDato(numero: principal.numero, unidad: principal.unidad, tamano: 26, peso: .light)
                        Text(principal.pie).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 128, height: 74)
                VStack(alignment: .leading, spacing: 7) {
                    LMedida(simbolo: "cpu", color: color(s.gravedadCPU), dato: "\(Int(s.cpu * 100))", unidad: "%", titulo: "Procesador")
                    LMedida(simbolo: "memorychip", color: color(s.gravedadMemoria),
                            dato: String(format: "%.0f/%.0f", s.memoriaUsada / 1e9, s.memoriaTotal / 1.073741824e9), unidad: "GB", titulo: "Memoria")
                    LMedida(simbolo: "square.stack.3d.up", color: color(s.gravedadGPU), dato: "\(Int(s.gpu * 100))", unidad: "%", titulo: "Gráficos")
                }
            }
            HStack(spacing: 6) {
                Circle().fill(color(d.gravedad)).frame(width: 6, height: 6).shadow(color: color(d.gravedad), radius: 3)
                Text(d.titulo + (d.frase.isEmpty ? "" : " · " + d.frase)).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "arrow.up.forward.app").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

private struct LMedida: View {
    let simbolo: String
    let color: Color
    let dato: String
    let unidad: String
    let titulo: String

    var body: some View {
        HStack(spacing: 8) {
            LInsignia(icono: .simbolo(simbolo), color: color, lado: 22)
            LDato(numero: dato, unidad: unidad, tamano: 14, peso: .semibold)
            Text(titulo).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
        }
    }
}
