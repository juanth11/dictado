import SwiftUI

// Estilos de luz: Topografía (líneas de contorno),
// Prisma (onda clásica de Siri) y Cometa (forma líquida que se afina hasta una gota de luz).

private func mezcla(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ f: Double) -> Color {
    Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
}

private func suave(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

private func halo(_ ctx: GraphicsContext, _ tam: CGSize, ancho: Double, intensidad: Double = 0.38) {
    ctx.drawLayer { capa in
        capa.addFilter(.blur(radius: 26))
        let w = Double(tam.width), h = Double(tam.height)
        let r = CGRect(x: (w - ancho) / 2, y: h / 2 - 24, width: ancho, height: 48)
        capa.fill(Path(roundedRect: r, cornerRadius: 24),
                  with: .color(Color(red: 0.10, green: 0.05, blue: 0.20).opacity(intensidad)))
    }
}

// MARK: - Topografía

/// Tres cordilleras de líneas finas; la cresta de cada una brilla (amarillo → naranja → magenta → violeta).
struct Topografia: View {
    let estado: EstadoHUD
    let t: Double
    var variante = Variante.clasica
    var conHalo = true

    enum Variante { case clasica, nocturna, prisma }

    private struct Pico { let centro: Double, ancho: Double, alto: Double, deriva: Double }
    private struct Cordillera { let base: Double, picos: [Pico], desde: Double, hasta: Double, lineas: Int }

    private static let fuego: [(Double, Double, Double)] = [
        (1.00, 0.86, 0.28), (1.00, 0.56, 0.20), (0.96, 0.26, 0.58), (0.56, 0.26, 0.96),
    ]
    private static let noche: [(Double, Double, Double)] = [
        (0.45, 0.92, 1.00), (0.28, 0.55, 1.00), (0.56, 0.32, 1.00), (0.92, 0.32, 0.80),
    ]
    private static let siri: [(Double, Double, Double)] = [
        (1.00, 0.86, 0.42), (1.00, 0.42, 0.16), (0.66, 0.30, 1.00), (0.20, 0.46, 1.00), (0.20, 0.85, 0.95),
    ]

    /// Una sola cordillera densa al frente y otra tenue detrás.
    private static let nocturnas = [
        Cordillera(base: -14, picos: [Pico(centro: 0.28, ancho: 0.08, alto: 0.7, deriva: 0.6),
                                      Pico(centro: 0.74, ancho: 0.07, alto: 0.9, deriva: -0.5)],
                   desde: 0.6, hasta: 1.0, lineas: 6),
        Cordillera(base: 6, picos: [Pico(centro: 0.18, ancho: 0.10, alto: 0.8, deriva: -0.5),
                                    Pico(centro: 0.42, ancho: 0.08, alto: 1.3, deriva: 0.7),
                                    Pico(centro: 0.60, ancho: 0.07, alto: 1.1, deriva: -0.8),
                                    Pico(centro: 0.82, ancho: 0.09, alto: 0.9, deriva: 0.5)],
                   desde: 0.0, hasta: 0.7, lineas: 24),
    ]

    private var paleta: [(Double, Double, Double)] {
        switch variante {
        case .clasica: return Self.fuego
        case .nocturna: return Self.noche
        case .prisma: return Self.siri
        }
    }

    private static let cordilleras = [
        Cordillera(base: -10, picos: [Pico(centro: 0.30, ancho: 0.09, alto: 0.9, deriva: 0.7),
                                      Pico(centro: 0.66, ancho: 0.07, alto: 1.2, deriva: -0.6),
                                      Pico(centro: 0.86, ancho: 0.06, alto: 0.8, deriva: 0.5)],
                   desde: 0.55, hasta: 1.0, lineas: 9),
        Cordillera(base: 2, picos: [Pico(centro: 0.22, ancho: 0.11, alto: 0.9, deriva: -0.5),
                                    Pico(centro: 0.52, ancho: 0.09, alto: 1.45, deriva: 0.8),
                                    Pico(centro: 0.78, ancho: 0.08, alto: 1.0, deriva: -0.7)],
                   desde: 0.0, hasta: 0.45, lineas: 14),
        Cordillera(base: 16, picos: [Pico(centro: 0.36, ancho: 0.14, alto: 0.75, deriva: 0.6),
                                     Pico(centro: 0.70, ancho: 0.12, alto: 0.85, deriva: -0.5)],
                   desde: 0.3, hasta: 0.75, lineas: 10),
    ]

    var body: some View {
        Canvas { ctx, tam in dibujar(ctx, tam) }
    }

    private func color(_ p: Double) -> Color {
        let paleta = self.paleta
        let p = min(max(p, 0), 0.999) * Double(paleta.count - 1)
        let i = Int(p)
        return mezcla(paleta[i], paleta[i + 1], p - Double(i))
    }

    private func dibujar(_ ctx: GraphicsContext, _ tam: CGSize) {
        let e: Double = estado.energia(t)
        let ancho = Double(tam.width), medio = Double(tam.height) / 2 + 8
        let escala: Double = estado.fase == .transcribiendo ? 9 : 8 + 40 * e
        if conHalo { halo(ctx, tam, ancho: ancho - 70) }
        for c in variante == .nocturna ? Self.nocturnas : Self.cordilleras {
            let sombreado = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [color(c.desde), color((c.desde + c.hasta) / 2), color(c.hasta)]),
                startPoint: CGPoint(x: 0, y: medio), endPoint: CGPoint(x: ancho, y: medio))
            for i in 0..<c.lineas {
                let linea = trazo(c, i: i, ancho: ancho, medio: medio, escala: escala)
                let caida: Double = 1 - Double(i) / Double(c.lineas)
                if i == 0 {
                    ctx.drawLayer { capa in  // la cresta brilla
                        capa.addFilter(.blur(radius: 3.5))
                        capa.opacity = 0.9
                        capa.stroke(linea, with: sombreado, lineWidth: 3.2)
                    }
                }
                ctx.drawLayer { capa in
                    capa.opacity = i == 0 ? 1 : 0.6 * caida
                    capa.stroke(linea, with: sombreado, lineWidth: i == 0 ? 1.3 : 0.6)
                }
            }
        }
    }

    private func trazo(_ c: Cordillera, i: Int, ancho: Double, medio: Double, escala: Double) -> Path {
        var p = Path()
        let rapidez: Double = estado.fase == .transcribiendo ? 2.4 : 0.6
        for k in 0...110 {
            let u: Double = Double(k) / 110
            var altura: Double = 0
            for pico in c.picos {
                let centro: Double = pico.centro + 0.05 * sin(t * rapidez * pico.deriva + pico.centro * 9)
                let d: Double = (u - centro) / pico.ancho
                altura += pico.alto * exp(-d * d)
            }
            let borde: Double = suave(0, 0.08, u) * suave(1, 0.92, u)
            let ola: Double = 0.12 * sin(u * 18 + t * 2)
            let y: Double = medio + c.base + Double(i) * 1.7 - (altura + ola) * escala * (1 - Double(i) * 0.065) * borde
            let punto = CGPoint(x: 14 + u * (ancho - 28), y: y)
            if k == 0 { p.move(to: punto) } else { p.addLine(to: punto) }
        }
        return p
    }
}

// MARK: - Prisma

/// Ondas de color translúcidas que se cruzan; donde se superponen la luz se suma hasta el blanco.
struct Prisma: View {
    let estado: EstadoHUD
    let t: Double
    var modo = Modo.relleno
    var conHalo = true
    var intensidad = 1.0
    var eje = true

    /// relleno: luz sólida; contorno: solo el borde de luz; lineas: cada onda hecha de líneas finas anidadas.
    enum Modo { case relleno, contorno, lineas }

    private struct Onda {
        let color: Color, amplitud: Double, frecuencia: Double, fase: Double, sentido: Double
        let centro: Double, ancho: Double, subida: Double, bajada: Double  // dónde y hacia qué lado se abre
    }
    private static let ondas = [
        Onda(color: Color(red: 0.20, green: 0.45, blue: 1.00), amplitud: 1.00, frecuencia: 1.1, fase: 0.0, sentido: 1.0,
             centro: 0.50, ancho: 0.30, subida: 1.25, bajada: 0.15),  // azul, arriba
        Onda(color: Color(red: 0.66, green: 0.28, blue: 1.00), amplitud: 0.75, frecuencia: 1.5, fase: 1.3, sentido: -1.3,
             centro: 0.36, ancho: 0.20, subida: 0.95, bajada: 0.25),  // violeta, izquierda
        Onda(color: Color(red: 0.15, green: 0.85, blue: 0.95), amplitud: 0.70, frecuencia: 1.8, fase: 2.4, sentido: 1.6,
             centro: 0.60, ancho: 0.20, subida: 0.75, bajada: 0.35),  // cian, derecha
        Onda(color: Color(red: 1.00, green: 0.38, blue: 0.12), amplitud: 0.80, frecuencia: 1.3, fase: 3.6, sentido: -1.1,
             centro: 0.64, ancho: 0.20, subida: 0.10, bajada: 0.95),  // naranja, abajo a la derecha
        Onda(color: Color(red: 1.00, green: 0.88, blue: 0.45), amplitud: 0.65, frecuencia: 2.1, fase: 4.7, sentido: 1.4,
             centro: 0.42, ancho: 0.22, subida: 0.10, bajada: 0.90),  // amarillo, abajo
    ]

    var body: some View {
        Canvas { ctx, tam in dibujar(ctx, tam) }
    }

    private func dibujar(_ ctx: GraphicsContext, _ tam: CGSize) {
        let e: Double = estado.energia(t)
        let ancho = Double(tam.width), medio = Double(tam.height) / 2
        if conHalo { halo(ctx, tam, ancho: ancho - 110, intensidad: 0.5) }
        var aditivo = ctx
        aditivo.blendMode = .plusLighter
        for onda in Self.ondas {
            let lente = forma(onda, ancho: ancho, medio: medio, e: e)
            // Los trazos se apagan fuera de la zona de su onda; si no, los bordes colapsados sobre el eje
            // se suman en una barra blanca.
            let x = { (u: Double) in CGPoint(x: 24 + u * (ancho - 48), y: medio) }
            let trazo = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [.init(color: onda.color.opacity(0), location: 0),
                                 .init(color: onda.color, location: 0.32),
                                 .init(color: onda.color, location: 0.68),
                                 .init(color: onda.color.opacity(0), location: 1)]),
                startPoint: x(onda.centro - 1.6 * onda.ancho), endPoint: x(onda.centro + 1.6 * onda.ancho))
            switch modo {
            case .relleno:
                aditivo.drawLayer { capa in
                    capa.addFilter(.blur(radius: 8))
                    capa.opacity = 0.42 * intensidad
                    capa.fill(lente, with: .color(onda.color))
                }
                aditivo.drawLayer { capa in
                    capa.addFilter(.blur(radius: 1.2))
                    capa.opacity = 0.26 * intensidad
                    capa.fill(lente, with: .color(onda.color))
                }
            case .contorno:
                aditivo.drawLayer { capa in
                    capa.addFilter(.blur(radius: 9))
                    capa.opacity = 0.14 * intensidad
                    capa.fill(lente, with: .color(onda.color))
                }
                aditivo.drawLayer { capa in
                    capa.addFilter(.blur(radius: 4))
                    capa.opacity = 0.55 * intensidad
                    capa.stroke(lente, with: trazo, lineWidth: 3)
                }
                aditivo.drawLayer { capa in
                    capa.addFilter(.blur(radius: 0.5))
                    capa.opacity = 0.95 * intensidad
                    capa.stroke(lente, with: trazo, lineWidth: 1.1)
                }
            case .lineas:
                aditivo.drawLayer { capa in
                    capa.addFilter(.blur(radius: 9))
                    capa.opacity = 0.16 * intensidad
                    capa.fill(lente, with: .color(onda.color))
                }
                for j in 0..<8 {
                    let anidada = forma(onda, ancho: ancho, medio: medio, e: e, escala: 1 - Double(j) * 0.12)
                    aditivo.drawLayer { capa in
                        if j == 0 { capa.addFilter(.blur(radius: 1.5)) }
                        capa.opacity = (0.9 - Double(j) * 0.09) * intensidad
                        capa.stroke(anidada, with: trazo, lineWidth: j == 0 ? 1.4 : 0.6)
                    }
                }
            }
        }
        guard eje else { return }
        aditivo.drawLayer { capa in  // hilo de luz en el eje
            capa.addFilter(.blur(radius: 2))
            var eje = Path()
            eje.move(to: CGPoint(x: 30, y: medio))
            eje.addLine(to: CGPoint(x: ancho - 30, y: medio))
            capa.opacity = 0.5
            capa.stroke(eje, with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.7), .clear]),
                startPoint: CGPoint(x: 30, y: medio), endPoint: CGPoint(x: ancho - 30, y: medio)), lineWidth: 1)
        }
    }

    /// Lente: arriba sube con la onda, abajo baja menos (asimetría como en la onda de Siri).
    private func forma(_ o: Onda, ancho: Double, medio: Double, e: Double, escala: Double = 1) -> Path {
        let rapidez: Double = estado.fase == .transcribiendo ? 3.2 : 1.1 + 2.2 * e
        let alto: Double = estado.fase == .transcribiendo ? 12 : 5 + 36 * e
        var arriba: [CGPoint] = []
        var abajo: [CGPoint] = []
        for k in 0...100 {
            let u: Double = Double(k) / 100
            let d: Double = (u - o.centro) / o.ancho
            let envolvente: Double = exp(-d * d) * pow(sin(u * .pi), 0.6)
            let ola: Double = 0.6 + 0.4 * sin(u * o.frecuencia * 2 * .pi + o.fase + t * rapidez * o.sentido)
            let g: Double = alto * o.amplitud * envolvente * ola * escala
            let x: Double = 24 + u * (ancho - 48)
            arriba.append(CGPoint(x: x, y: medio - g * o.subida - 0.6))
            abajo.append(CGPoint(x: x, y: medio + g * o.bajada + 0.6))
        }
        var p = Path()
        p.addLines(arriba)
        for punto in abajo.reversed() { p.addLine(to: punto) }
        p.closeSubpath()
        return p
    }
}

// MARK: - Cometa

/// Forma líquida iridiscente que se afina hasta una gota de luz; las ondas de los bordes viajan hacia la gota.
struct Cometa: View {
    let estado: EstadoHUD
    let t: Double

    var body: some View {
        Canvas { ctx, tam in dibujar(ctx, tam) }
    }

    private func dibujar(_ ctx: GraphicsContext, _ tam: CGSize) {
        let e: Double = estado.energia(t)
        let ancho = Double(tam.width), medio = Double(tam.height) / 2
        let inicio: Double = 24, cuello: Double = ancho * 0.78, gota: Double = ancho * 0.88
        halo(ctx, tam, ancho: ancho - 80, intensidad: 0.45)
        let (cuerpo, filoInferior, filoSuperior) = forma(inicio: inicio, cuello: cuello, medio: medio, e: e)

        ctx.drawLayer { capa in  // cuerpo: degradado + manchas de color que se mueven dentro
            capa.clip(to: cuerpo)
            capa.fill(cuerpo, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.95, green: 0.25, blue: 0.62), location: 0.0),
                    .init(color: Color(red: 0.20, green: 0.78, blue: 0.86), location: 0.35),
                    .init(color: Color(red: 0.16, green: 0.62, blue: 0.80), location: 0.62),
                    .init(color: Color(red: 0.22, green: 0.30, blue: 0.95), location: 0.88),
                    .init(color: Color(red: 0.55, green: 0.15, blue: 0.70), location: 1.0),
                ]),
                startPoint: CGPoint(x: inicio, y: medio), endPoint: CGPoint(x: cuello, y: medio)))
            capa.addFilter(.blur(radius: 12))
            let manchas: [(Double, Double, Color)] = [
                (0.12, -0.3, Color(red: 1.0, green: 0.30, blue: 0.70)),
                (0.38, 0.4, Color(red: 0.30, green: 0.95, blue: 0.55)),
                (0.55, -0.4, Color(red: 0.30, green: 0.45, blue: 1.00)),
            ]
            for (u, dy, color) in manchas {
                let x: Double = inicio + (u + 0.04 * sin(t * 0.9 + u * 7)) * (cuello - inicio)
                let y: Double = medio + dy * (14 + 16 * e) + 4 * sin(t * 1.3 + u * 5)
                let r: Double = 16 + 8 * e
                capa.fill(Path(ellipseIn: CGRect(x: x - r * 1.4, y: y - r, width: r * 2.8, height: r * 2)), with: .color(color))
            }
        }
        ctx.drawLayer { capa in  // luz en el filo inferior y reflejo tenue arriba
            capa.addFilter(.blur(radius: 0.6))
            capa.stroke(filoInferior, with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.9), Color(red: 0.6, green: 0.9, blue: 1.0)]),
                startPoint: CGPoint(x: inicio, y: medio), endPoint: CGPoint(x: cuello, y: medio)), lineWidth: 1.2)
            capa.stroke(filoSuperior, with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.35), .clear]),
                startPoint: CGPoint(x: inicio, y: medio), endPoint: CGPoint(x: cuello, y: medio)), lineWidth: 0.8)
        }
        // Cola: hilo con separación cromática (rojo arriba, azul abajo) hasta la gota.
        for (dy, color) in [(-0.7, Color(red: 1.0, green: 0.2, blue: 0.25)), (0.7, Color(red: 0.25, green: 0.4, blue: 1.0))] {
            var hilo = Path()
            hilo.move(to: CGPoint(x: cuello - 12, y: medio + dy))
            hilo.addLine(to: CGPoint(x: gota, y: medio + dy * 0.3))
            ctx.stroke(hilo, with: .color(color.opacity(0.85)), lineWidth: 0.9)
        }
        perla(ctx, CGPoint(x: gota, y: medio), e: e)
    }

    private func forma(inicio: Double, cuello: Double, medio: Double, e: Double) -> (Path, Path, Path) {
        let rapidez: Double = estado.fase == .transcribiendo ? 6 : 2 + 4 * e
        let rizo: Double = estado.fase == .transcribiendo ? 2.5 : 1.5 + 8 * e
        var superior: [CGPoint] = []
        var inferior: [CGPoint] = []
        for k in 0...90 {
            let u: Double = Double(k) / 90
            let perfil: Double = pow(1 - suave(0.0, 1.0, u), 1.35) * sqrt(suave(0.0, 0.16, u))
            let grosor: Double = (12 + 22 * e) * perfil + 0.6
            let ola1: Double = sin(u * 3.2 * .pi - t * rapidez) * rizo * perfil
            let ola2: Double = sin(u * 2.5 * .pi - t * rapidez * 0.8 + 1.2) * rizo * 0.8 * perfil
            let x: Double = inicio + u * (cuello - inicio)
            superior.append(CGPoint(x: x, y: medio - grosor * 1.1 + ola1))
            inferior.append(CGPoint(x: x, y: medio + grosor * 0.8 + ola2))
        }
        var cuerpo = Path()
        cuerpo.addLines(superior)
        for p in inferior.reversed() { cuerpo.addLine(to: p) }
        cuerpo.closeSubpath()
        var filoInferior = Path()
        filoInferior.addLines(inferior)
        var filoSuperior = Path()
        filoSuperior.addLines(superior)
        return (cuerpo, filoInferior, filoSuperior)
    }

    /// Gota de luz: halo, cuerpo iridiscente, brillo especular y destellos finos.
    private func perla(_ ctx: GraphicsContext, _ c: CGPoint, e: Double) {
        let pulso: Double = estado.fase == .transcribiendo ? 0.5 + 0.5 * sin(t * 7) : e
        let r: Double = 6 + 3 * pulso
        let gota = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.drawLayer { capa in
            capa.addFilter(.blur(radius: 10))
            capa.opacity = 0.5 + 0.5 * pulso
            capa.fill(Path(ellipseIn: CGRect(x: c.x - r * 2, y: c.y - r * 2, width: r * 4, height: r * 4)),
                      with: .color(Color(red: 0.75, green: 0.9, blue: 1.0)))
        }
        for angulo in stride(from: 0.0, to: 180.0, by: 45.0) {  // destellos
            let a = angulo * .pi / 180
            let largo: Double = r * (2.2 + 1.8 * pulso)
            var rayo = Path()
            rayo.move(to: CGPoint(x: c.x - cos(a) * largo, y: c.y - sin(a) * largo))
            rayo.addLine(to: CGPoint(x: c.x + cos(a) * largo, y: c.y + sin(a) * largo))
            ctx.drawLayer { capa in
                capa.addFilter(.blur(radius: 0.8))
                capa.opacity = 0.35 + 0.3 * pulso
                capa.stroke(rayo, with: .color(.white), lineWidth: 0.6)
            }
        }
        ctx.fill(gota, with: .radialGradient(
            Gradient(colors: [.white, Color(red: 0.6, green: 0.85, blue: 1.0), Color(red: 0.85, green: 0.35, blue: 0.9)]),
            center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.2))
        ctx.stroke(gota, with: .conicGradient(
            Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
            center: c, angle: Angle.degrees(t * 40)), lineWidth: 1.2)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.6, width: r * 0.5, height: r * 0.35)),
                 with: .color(.white.opacity(0.9)))
    }
}
