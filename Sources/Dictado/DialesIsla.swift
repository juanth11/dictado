import SwiftUI

// Piezas del lenguaje visual de la isla: diales con anillo de marcas finas, resplandores radiales de color,
// números grandes y finos, números de puntos y destellos. Todo es estático: nada se anima solo (en reposo la
// isla queda en 0 % de procesador); solo se mueve cuando cambia un valor.

/// Paletas de los resplandores (de un extremo al otro del anillo).
enum Paleta {
    static let volumen = [Color(red: 0.26, green: 0.48, blue: 1.0), Color(red: 0.52, green: 0.38, blue: 1.0),
                          Color(red: 0.86, green: 0.42, blue: 0.96)]
    static let brillo = [Color(red: 1.0, green: 0.48, blue: 0.12), Color(red: 1.0, green: 0.72, blue: 0.28),
                         Color(red: 1.0, green: 0.90, blue: 0.62)]
    static let silencio = [Color(white: 0.42), Color(white: 0.30), Color(white: 0.36)]
    static let claude = [Color(red: 0.95, green: 0.42, blue: 0.24), Color.claude, Color(red: 1.0, green: 0.66, blue: 0.42)]
    static let ahora = Color(red: 1.0, green: 0.36, blue: 0.34)

    static func gravedad(_ g: Gravedad) -> [Color] {
        switch g {
        case .bien: return [Color(red: 0.16, green: 0.62, blue: 0.86), Color(red: 0.18, green: 0.84, blue: 0.58),
                            Color(red: 0.55, green: 0.95, blue: 0.62)]
        case .atento: return [Color(red: 1.0, green: 0.50, blue: 0.10), Color(red: 1.0, green: 0.70, blue: 0.16),
                              Color(red: 1.0, green: 0.84, blue: 0.40)]
        case .mal: return [Color(red: 0.92, green: 0.22, blue: 0.48), Color(red: 1.0, green: 0.30, blue: 0.26),
                           Color(red: 1.0, green: 0.52, blue: 0.30)]
        }
    }

    static func agente(_ e: AgentesRemotos.Estado) -> [Color] {
        switch e {
        case .ok: return gravedad(.bien)
        case .alerta: return gravedad(.atento)
        case .caido: return gravedad(.mal)
        case .desconocido: return [Color(white: 0.5), Color(white: 0.38), Color(white: 0.45)]
        }
    }
}

/// Anillo de rayitas finas repartidas en un arco con el hueco abajo (como la perilla de un equipo de sonido).
/// `desde`/`hasta` (0–1) eligen qué rayitas se dibujan; así un mismo anillo se pinta encendido y apagado.
struct Marcas: Shape {
    var cuenta = 44
    var arco = 300.0
    var desde = 0.0
    var hasta = 1.0
    var largo: CGFloat = 6

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(desde, hasta) }
        set { desde = newValue.first; hasta = newValue.second }
    }

    /// Ángulo (grados, 0 = derecha, sentido horario) donde empieza el arco.
    static func inicio(_ arco: Double) -> Double { arco >= 360 ? -90 : 90 + (360 - arco) / 2 }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let radio = min(r.width, r.height) / 2
        let c = CGPoint(x: r.midX, y: r.midY)
        let completo = arco >= 360
        for i in 0..<cuenta {
            let medio = Double(i) + 0.5
            guard medio > desde * Double(cuenta), medio <= hasta * Double(cuenta) + 1e-9 else { continue }
            let f = completo ? Double(i) / Double(cuenta) : Double(i) / Double(max(1, cuenta - 1))
            let a = CGFloat((Self.inicio(arco) + f * arco) * .pi / 180)
            let fuera = CGPoint(x: c.x + radio * cos(a), y: c.y + radio * sin(a))
            let dentro = CGPoint(x: c.x + (radio - largo) * cos(a), y: c.y + (radio - largo) * sin(a))
            p.move(to: dentro)
            p.addLine(to: fuera)
        }
        return p
    }
}

/// Resplandor radial de color: un aro difuso que cambia de tono alrededor (como las píldoras de referencia).
struct Resplandor: View {
    let colores: [Color]
    var difuso: CGFloat = 12
    var giro = -30.0

    var body: some View {
        Circle()
            .fill(AngularGradient(colors: colores + [colores.first ?? .white], center: .center, angle: .degrees(giro)))
            .mask(EllipticalGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.9), location: 0.42),
                                             .init(color: .black.opacity(0.35), location: 0.72), .init(color: .clear, location: 1)],
                                     center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
            .blur(radius: difuso)
            .allowsHitTesting(false)
    }
}

/// Disco negro con volumen: brillo arriba, borde fino y sombra (la "perilla" de los diales).
struct Disco: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.15), Color(white: 0.04), .black], center: UnitPoint(x: 0.5, y: 0.18),
                                 startRadius: 0, endRadius: 60))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.05), .white.opacity(0.10)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.7), radius: 5, y: 2)
    }
}

/// Destello de cuatro puntas: marca el valor en el anillo.
struct Destello: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let largo = min(r.width, r.height) / 2
        let corto = largo * 0.16
        var p = Path()
        for i in 0..<8 {
            let a = CGFloat(Double(i) * .pi / 4 - .pi / 2)
            let rr = i.isMultiple(of: 2) ? largo : corto
            let punto = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
            if i == 0 { p.move(to: punto) } else { p.addLine(to: punto) }
        }
        p.closeSubpath()
        return p
    }
}

/// Dial: resplandor de color detrás, anillo de marcas que se enciende hasta `valor`, disco negro y, en el centro,
/// lo que pongas (un número fino o un ícono). `fantasma` dibuja tenues las marcas hasta ese valor (el volumen
/// guardado mientras está en silencio).
struct Dial<Centro: View>: View {
    let lado: CGFloat
    var valor: Double
    var colores: [Color]
    var marcas = 44
    var arco = 300.0
    var anillo: CGFloat = 6
    var brillo = 1.0
    var fantasma: Double?
    var destello = true
    /// Tamaño del resplandor respecto al dial.
    var halo: CGFloat = 1.7
    @ViewBuilder var centro: () -> Centro

    private var disco: CGFloat { lado - 2 * (anillo + 3.5) }

    var body: some View {
        let v = max(0, min(1, valor))
        let inicio = Marcas.inicio(arco)
        ZStack {
            Marcas(cuenta: marcas, arco: arco, desde: fantasma ?? v, hasta: 1, largo: anillo)
                .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .frame(width: lado, height: lado)
            if let fantasma {
                Marcas(cuenta: marcas, arco: arco, desde: 0, hasta: fantasma, largo: anillo)
                    .stroke(Color.white.opacity(0.36), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .frame(width: lado, height: lado)
            } else {
                Marcas(cuenta: marcas, arco: arco, desde: 0, hasta: v, largo: anillo)
                    .stroke(AngularGradient(colors: colores, center: .center, startAngle: .degrees(inicio),
                                            endAngle: .degrees(inicio + arco)),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: lado, height: lado)
                    .shadow(color: (colores.last ?? .white).opacity(0.85), radius: 2.5)
                // núcleo claro de cada rayita encendida: se ve "prendida", no solo pintada
                Marcas(cuenta: marcas, arco: arco, desde: 0, hasta: v, largo: anillo * 0.55)
                    .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
                    .frame(width: lado - anillo * 0.24, height: lado - anillo * 0.24)
            }
            Disco().frame(width: disco, height: disco)
            centro().frame(width: disco, height: disco)
            if destello && fantasma == nil && v > 0.001 {
                let a = CGFloat((inicio + v * arco) * .pi / 180)
                let r = lado / 2 + 1
                Destello().fill(.white)
                    .frame(width: 9, height: 9)
                    .shadow(color: .white, radius: 2)
                    .shadow(color: colores.last ?? .white, radius: 4)
                    .offset(x: r * cos(a), y: r * sin(a))
            }
        }
        .frame(width: lado, height: lado)
        .background {
            Resplandor(colores: colores, difuso: lado * 0.16)
                .frame(width: lado * halo, height: lado * halo)
                .opacity(brillo)
        }
    }
}

/// Punto de estado con resplandor (verde, ámbar, rojo).
struct PuntoBrillante: View {
    let color: Color
    var lado: CGFloat = 7

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.9), color], center: UnitPoint(x: 0.4, y: 0.35),
                                 startRadius: 0, endRadius: lado * 0.45))
            .frame(width: lado, height: lado)
            .shadow(color: color.opacity(0.9), radius: lado * 0.55)
            .shadow(color: color.opacity(0.5), radius: lado * 1.2)
    }
}

/// Número grande y fino con su unidad pequeña al lado ("62 %", "7,9 GB").
struct NumeroFino: View {
    let texto: String
    var unidad = ""
    var tamano: CGFloat = 34
    var peso: Font.Weight = .thin
    var color: Color = .white
    var valor: Double?  // para la transición de dígitos

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: tamano * 0.06) {
            Text(texto)
                .font(.system(size: tamano, weight: peso))
                .monospacedDigit()
                .kerning(-tamano * 0.03)
                .contentTransition(valor.map { .numericText(value: $0) } ?? .identity)
            if !unidad.isEmpty {
                Text(unidad)
                    .font(.system(size: max(8, tamano * 0.3), weight: .regular))
                    .foregroundStyle(color.opacity(0.5))
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Números de puntos (matriz de 5×7), con las celdas apagadas apenas visibles, como un panel de LED.
struct NumeroPuntos: View {
    let texto: String
    var punto: CGFloat = 2.6
    var paso: CGFloat = 3.6
    var color: Color = .white

    private static let glifos: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "0", "1", "0", "1", "0", "0"],
        ".": ["0", "0", "0", "0", "0", "0", "1"],
        " ": ["0", "0", "0", "0", "0", "0", "0"],
    ]

    private var ancho: CGFloat {
        let columnas = texto.reduce(0) { $0 + (Self.glifos[$1]?[0].count ?? 0) + 1 }
        return CGFloat(max(0, columnas - 1)) * paso + punto
    }

    var body: some View {
        Canvas { ctx, _ in
            var x: CGFloat = 0
            for ch in texto {
                guard let g = Self.glifos[ch] else { continue }
                for (fila, linea) in g.enumerated() {
                    for (col, c) in linea.enumerated() {
                        let rect = CGRect(x: x + CGFloat(col) * paso, y: CGFloat(fila) * paso, width: punto, height: punto)
                        ctx.fill(Path(ellipseIn: rect), with: .color(c == "1" ? color : color.opacity(0.07)))
                    }
                }
                x += CGFloat(g[0].count + 1) * paso
            }
        }
        .frame(width: ancho, height: 6 * paso + punto)
        .shadow(color: color.opacity(0.55), radius: 3)
    }
}

/// Etiqueta pequeña en mayúsculas y monoespaciada ("VOLUMEN", "EMPIEZA EN").
struct Rotulo: View {
    let texto: String
    var color: Color = .white.opacity(0.45)

    init(_ texto: String, color: Color = .white.opacity(0.45)) {
        self.texto = texto
        self.color = color
    }

    var body: some View {
        Text(texto.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
