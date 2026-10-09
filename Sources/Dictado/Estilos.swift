import SwiftUI

/// Estilos visuales del HUD. Se eligen en el menú de Dictado (se guarda en `defaults … estilo`).
enum Estilo: String, CaseIterable, Identifiable {
    case auroraOrbe, eco, aurora, orbe, constelacion, topografia, prisma, cometa
    case prismaContorno, prismaLineas, prismaOrbe, topografiaNocturna, topografiaOrbe, relievePrisma

    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .auroraOrbe: return "Aurora + Orbe"
        case .topografia: return "Topografía"
        case .prisma: return "Prisma"
        case .cometa: return "Cometa"
        case .prismaContorno: return "Prisma Contorno"
        case .prismaLineas: return "Prisma de Líneas"
        case .prismaOrbe: return "Prisma + Orbe"
        case .topografiaNocturna: return "Topografía Nocturna"
        case .topografiaOrbe: return "Topografía + Orbe"
        case .relievePrisma: return "Relieve Prisma"
        case .eco: return "Eco"
        case .aurora: return "Aurora"
        case .orbe: return "Orbe"
        case .constelacion: return "Constelación"
        }
    }
}

/// Rampa de color común: naranja → rosa → violeta → azul → cian.
enum Rampa {
    static let paradas: [(Double, (Double, Double, Double))] = [
        (0.00, (1.00, 0.62, 0.36)),
        (0.28, (0.99, 0.38, 0.62)),
        (0.55, (0.70, 0.38, 1.00)),
        (0.80, (0.36, 0.55, 1.00)),
        (1.00, (0.40, 0.86, 0.95)),
    ]

    static func color(_ p: Double) -> Color {
        let p = min(max(p, 0), 1)
        for (a, b) in zip(paradas, paradas.dropFirst()) where p <= b.0 {
            let f = (p - a.0) / (b.0 - a.0)
            return Color(red: a.1.0 + (b.1.0 - a.1.0) * f, green: a.1.1 + (b.1.1 - a.1.1) * f,
                         blue: a.1.2 + (b.1.2 - a.1.2) * f)
        }
        return Color(red: 0.40, green: 0.86, blue: 0.95)
    }

    static var gradiente: Gradient {
        Gradient(stops: paradas.map { .init(color: Color(red: $0.1.0, green: $0.1.1, blue: $0.1.2), location: $0.0) })
    }
}

extension EstadoHUD {
    /// Energía que mueve la animación: la voz al escuchar, un pulso al transcribir, calma al terminar.
    func energia(_ t: Double) -> Double {
        switch fase {
        case .escuchando: return nivel
        case .transcribiendo: return 0.45 + 0.1 * sin(t * 5)
        case .resultado: return 0.1
        }
    }
}

/// El visual del estilo elegido.
struct Visual: View {
    let estado: EstadoHUD
    let t: Double

    var body: some View {
        switch estado.estilo {
        case .auroraOrbe:
            ZStack {  // la esfera al centro y las cintas saliendo de ella hacia los lados
                Aurora(estado: estado, t: t)
                Esfera(estado: estado, t: t, anillos: false, conHalo: false)
            }
        case .eco: Eco(estado: estado, t: t)
        case .aurora: Aurora(estado: estado, t: t)
        case .orbe: Esfera(estado: estado, t: t)
        case .constelacion: Constelacion(estado: estado, t: t)
        case .topografia: Topografia(estado: estado, t: t)
        case .prisma: Prisma(estado: estado, t: t)
        case .cometa: Cometa(estado: estado, t: t)
        case .prismaContorno: Prisma(estado: estado, t: t, modo: .contorno)
        case .prismaLineas: Prisma(estado: estado, t: t, modo: .lineas)
        case .prismaOrbe:
            ZStack {
                Prisma(estado: estado, t: t)
                Esfera(estado: estado, t: t, anillos: false, conHalo: false, escala: 0.72)
            }
        case .topografiaNocturna: Topografia(estado: estado, t: t, variante: .nocturna)
        case .topografiaOrbe:  // una luna líquida sobre las cordilleras
            ZStack {
                Esfera(estado: estado, t: t, anillos: false, conHalo: false, escala: 0.5, dy: -30)
                Topografia(estado: estado, t: t)
            }
        case .relievePrisma:  // montañas de líneas con los colores de Siri, iluminadas desde atrás por Prisma
            ZStack {
                Prisma(estado: estado, t: t, intensidad: 0.55, eje: false)
                Topografia(estado: estado, t: t, variante: .prisma, conHalo: false)
            }
        }
    }
}

/// Halo violeta difuso detrás del visual: separa del fondo sin dibujar una caja.
private func halo(_ ctx: GraphicsContext, _ tam: CGSize, ancho: Double) {
    ctx.drawLayer { capa in
        capa.addFilter(.blur(radius: 26))
        let w = Double(tam.width), h = Double(tam.height)
        let r = CGRect(x: (w - ancho) / 2, y: h / 2 - 22, width: ancho, height: 44)
        capa.fill(Path(roundedRect: r, cornerRadius: 22), with: .color(Color(red: 0.16, green: 0.08, blue: 0.30).opacity(0.38)))
    }
}

private func circulo(_ c: CGPoint, _ r: Double) -> Path {
    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

// MARK: - Aurora

/// Cuatro cintas de seda iridiscente que ondulan y se cruzan; la voz las abre, al transcribir fluyen planas.
struct Aurora: View {
    let estado: EstadoHUD
    let t: Double

    private struct Cinta {
        let amplitud: Double, frecuencia: Double, fase: Double, grosor: Double, sentido: Double
    }

    private static let cintas = [
        Cinta(amplitud: 1.00, frecuencia: 1.6, fase: 0.0, grosor: 11, sentido: 1.0),
        Cinta(amplitud: 0.78, frecuencia: 2.4, fase: 1.7, grosor: 8, sentido: -1.3),
        Cinta(amplitud: 0.56, frecuencia: 3.3, fase: 3.1, grosor: 6, sentido: 1.6),
        Cinta(amplitud: 0.38, frecuencia: 4.4, fase: 4.4, grosor: 4, sentido: -2.1),
    ]

    var body: some View {
        Canvas { ctx, tam in dibujar(ctx, tam) }
            .hueRotation(.degrees(estado.fase == .transcribiendo ? sin(t * 1.8) * 25 : sin(t * 0.5) * 10))
    }

    private func dibujar(_ ctx: GraphicsContext, _ tam: CGSize) {
        let e: Double = estado.energia(t)
        let medio: Double = tam.height / 2
        let margen: Double = 14
        let ancho: Double = tam.width - 2 * margen
        let rapidez: Double = estado.fase == .transcribiendo ? 2.8 : 1.0 + 1.8 * e
        let altura: Double = estado.fase == .transcribiendo ? 5 : 5 + 36 * e
        halo(ctx, tam, ancho: tam.width - 90)
        let sombreado = GraphicsContext.Shading.linearGradient(
            Rampa.gradiente, startPoint: CGPoint(x: margen, y: medio), endPoint: CGPoint(x: margen + ancho, y: medio))
        for (k, c) in Self.cintas.enumerated() {
            let (cinta, borde) = forma(c, medio: medio, margen: margen, ancho: ancho, altura: altura, rapidez: rapidez, e: e)
            let opacidad: Double = 0.92 - Double(k) * 0.16
            ctx.drawLayer { capa in
                capa.addFilter(.blur(radius: 9))
                capa.opacity = 0.5
                capa.fill(cinta, with: sombreado)
            }
            ctx.drawLayer { capa in
                capa.addFilter(.blur(radius: 1))
                capa.opacity = opacidad
                capa.fill(cinta, with: sombreado)
            }
            ctx.drawLayer { capa in  // filo de luz
                capa.opacity = opacidad * 0.6
                capa.stroke(borde, with: .color(.white.opacity(0.7)), lineWidth: 0.6)
            }
        }
    }

    private func forma(_ c: Cinta, medio: Double, margen: Double, ancho: Double, altura: Double,
                       rapidez: Double, e: Double) -> (Path, Path) {
        var borde = Path()
        var inferior: [CGPoint] = []
        for i in 0...96 {
            let u: Double = Double(i) / 96
            let envolvente: Double = pow(sin(u * .pi), 1.5)
            let x: Double = margen + u * ancho
            let ola: Double = sin(u * c.frecuencia * 2 * .pi + t * rapidez * c.sentido + c.fase)
            let y: Double = medio + altura * c.amplitud * envolvente * ola
            let grosor: Double = c.grosor * envolvente * (0.55 + 0.6 * e) + 0.5
            let superior = CGPoint(x: x, y: y - grosor / 2)
            if i == 0 { borde.move(to: superior) } else { borde.addLine(to: superior) }
            inferior.append(CGPoint(x: x, y: y + grosor / 2))
        }
        var cinta = borde
        for p in inferior.reversed() { cinta.addLine(to: p) }
        cinta.closeSubpath()
        return (cinta, borde)
    }
}

// MARK: - Orbe

/// Esfera de líquido luminoso: manchas de color que giran dentro, volumen, brillo especular y ondas expansivas.
struct Esfera: View {
    let estado: EstadoHUD
    let t: Double
    var anillos = true
    var conHalo = true
    var escala = 1.0   // para combinarla con otros estilos
    var dy = 0.0

    private struct Mancha { let p: Double, vx: Double, vy: Double, fase: Double }
    private static let manchas = [
        Mancha(p: 0.02, vx: 1.0, vy: 1.3, fase: 0.0), Mancha(p: 0.30, vx: -1.2, vy: 0.9, fase: 1.6),
        Mancha(p: 0.58, vx: 0.8, vy: -1.1, fase: 3.1), Mancha(p: 0.92, vx: -0.7, vy: -1.4, fase: 4.4),
    ]

    var body: some View {
        Canvas { ctx, tam in dibujar(ctx, tam) }
    }

    private func dibujar(_ ctx: GraphicsContext, _ tam: CGSize) {
        let e: Double = estado.energia(t)
        let c = CGPoint(x: Double(tam.width) / 2, y: Double(tam.height) / 2 + dy)
        let r: Double = (30 + 10 * e + 1.5 * sin(t * 1.6)) * escala
        if conHalo { halo(ctx, tam, ancho: 200) }
        if anillos { ondas(ctx, c, r, e) }

        let esfera = circulo(c, r)
        ctx.drawLayer { capa in  // resplandor
            capa.addFilter(.blur(radius: 18))
            capa.opacity = 0.45 + 0.45 * e
            capa.fill(esfera, with: .color(Rampa.color(0.35)))
        }
        let giro: Double = estado.fase == .transcribiendo ? 2.6 : 0.6 + 1.8 * e
        ctx.drawLayer { capa in  // líquido interior
            capa.clip(to: esfera)
            capa.fill(esfera, with: .color(Color(red: 0.20, green: 0.08, blue: 0.34)))
            capa.addFilter(.blur(radius: 9))
            for m in Self.manchas {
                let pos = CGPoint(x: c.x + r * 0.5 * sin(t * giro * m.vx + m.fase),
                                  y: c.y + r * 0.5 * cos(t * giro * m.vy + m.fase))
                let rm: Double = r * (0.62 + 0.14 * sin(t * 1.3 + m.fase))
                capa.fill(circulo(pos, rm), with: .color(Rampa.color(m.p)))
            }
        }
        let sombra = Gradient(colors: [.clear, .clear, Color(red: 0.10, green: 0.03, blue: 0.20).opacity(0.55)])
        ctx.fill(esfera, with: .radialGradient(sombra, center: c, startRadius: 0, endRadius: r))  // volumen
        ctx.drawLayer { capa in  // brillo especular
            capa.addFilter(.blur(radius: 3))
            let brillo = CGRect(x: c.x - r * 0.58, y: c.y - r * 0.74, width: r * 0.72, height: r * 0.38)
            capa.fill(Path(ellipseIn: brillo), with: .color(.white.opacity(0.55)))
        }
        let filo = Gradient(colors: [.white.opacity(0.65), .clear, .white.opacity(0.25)])
        ctx.stroke(esfera, with: .linearGradient(filo, startPoint: CGPoint(x: c.x - r, y: c.y - r),
                                                 endPoint: CGPoint(x: c.x + r, y: c.y + r)), lineWidth: 1)
    }

    /// Anillos que salen de la esfera (convergen al transcribir).
    private func ondas(_ ctx: GraphicsContext, _ c: CGPoint, _ r: Double, _ e: Double) {
        for i in 0..<3 {
            var p: Double = (t * (0.4 + 0.7 * e) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            if estado.fase == .transcribiendo { p = 1 - p }
            let rr: Double = r + 4 + p * 70
            let alto: Double = min(rr, 54)
            let anillo = Path(ellipseIn: CGRect(x: c.x - rr * 1.6, y: c.y - alto, width: rr * 3.2, height: alto * 2))
            let alfa: Double = pow(1 - p, 2) * (0.2 + 0.8 * e)
            ctx.drawLayer { capa in
                capa.addFilter(.blur(radius: 1 + 3 * p))
                capa.opacity = alfa
                capa.stroke(anillo, with: .color(Rampa.color(0.45 + 0.5 * p)), lineWidth: 1.6)
            }
        }
    }
}

// MARK: - Constelación

/// Tres hebras de partículas luminosas unidas por líneas finas; la voz las agita, al transcribir un pulso las recorre.
struct Constelacion: View {
    let estado: EstadoHUD
    let t: Double
    private let n = 156

    private struct Particula { let punto: CGPoint, radio: Double, color: Color, brillo: Double }

    var body: some View {
        Canvas { ctx, tam in dibujar(ctx, tam) }
    }

    private func dibujar(_ ctx: GraphicsContext, _ tam: CGSize) {
        let medio: Double = tam.height / 2
        halo(ctx, tam, ancho: tam.width - 90)
        let hebras = (0..<3).map { h in stride(from: h, to: n, by: 3).map { particula($0, hebra: h, tam: tam) } }

        let gradiente = GraphicsContext.Shading.linearGradient(
            Rampa.gradiente, startPoint: CGPoint(x: 0, y: medio), endPoint: CGPoint(x: tam.width, y: medio))
        ctx.drawLayer { capa in  // líneas finas que unen cada hebra
            capa.opacity = 0.35
            for hebra in hebras {
                var linea = Path()
                linea.addLines(hebra.map(\.punto))
                capa.stroke(linea, with: gradiente, lineWidth: 0.6)
            }
        }
        ctx.drawLayer { capa in  // resplandor
            capa.addFilter(.blur(radius: 5))
            for p in hebras.joined() {
                capa.fill(circulo(p.punto, p.radio * 2.6), with: .color(p.color.opacity(0.55 * p.brillo)))
            }
        }
        for p in hebras.joined() {
            ctx.fill(circulo(p.punto, p.radio), with: .color(Eco.mezclar(p.color, .white, 0.35).opacity(p.brillo)))
        }
    }

    private func particula(_ i: Int, hebra: Int, tam: CGSize) -> Particula {
        let e: Double = estado.energia(t)
        let medio: Double = tam.height / 2
        let u: Double = (Double(i) + 0.5) / Double(n)
        let semilla: Double = sin(Double(i) * 12.9898) * 43_758.5453
        let azar: Double = semilla - floor(semilla)
        let envolvente: Double = pow(sin(u * .pi), 1.3)
        let x: Double = 16 + u * (tam.width - 32)
        let h = Double(hebra)
        var y: Double
        var brillo: Double = 0.35 + 0.65 * envolvente
        if estado.fase == .transcribiendo {
            y = medio + sin(u * 14 - t * 6 + h) * 3
            brillo *= 0.35 + 0.65 * pow(max(0, sin(u * 5 * .pi - t * 5)), 4)
        } else {
            let sentido: Double = hebra == 1 ? -1 : 1
            let ola: Double = sin(u * (4.5 + h * 2) * .pi + t * (1.3 + 2.2 * e) * sentido + h * 2)
            let amplitud: Double = (4 + 38 * e) * envolvente * (1 - 0.22 * h)
            y = medio + ola * amplitud + (azar - 0.5) * 7 * e
        }
        let radio: Double = (1.0 + 1.9 * envolvente * (0.4 + 0.6 * e)) * (0.7 + 0.6 * azar)
        return Particula(punto: CGPoint(x: x, y: y), radio: radio, color: Rampa.color(u), brillo: brillo)
    }
}
