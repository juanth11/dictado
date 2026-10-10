import AppKit
import SwiftUI

// Halo: el lenguaje visual de Dictado, en la isla y en los paneles. Junta los diales de marcas finas con la luz
// de color que sube desde el borde. Las reglas:
//
// 1. Negro de fondo. La isla es negro puro (se funde con el notch); los paneles, vidrio oscuro.
// 2. Un tono por momento. Cada cosa tiene un tono y aparece en tres lugares como máximo: la luz del borde, el dato
//    principal (marcas, líquido) y el botón de acción. Todo lo demás es blanco con opacidad.
// 3. Cifras grandes y finas; texto del sistema; rótulos en mayúsculas pequeñas con espaciado (no monoespaciados).
// 4. Marcas: el mismo trazo fino sirve para diales (en círculo, Dial) y reglas (en línea, Regla); las encendidas
//    brillan y la última es más clara.
// 5. Nada se mueve en reposo (0 % de procesador). Las animaciones solo acompañan un cambio: la isla se transforma
//    con un resorte, los avisos entran con escala y desenfoque, las marcas se encienden, las cifras ruedan y la luz
//    cambia de tono con un fundido.
//
// Ver docs/DISENO.md para el catálogo completo.

enum Halo {
    // Texto sobre negro o vidrio oscuro
    static let texto = Color.white.opacity(0.96)
    static let texto2 = Color.white.opacity(0.58)
    static let texto3 = Color.white.opacity(0.36)
    static let linea = Color.white.opacity(0.08)
    /// Tarjetas dentro de los paneles.
    static let superficie = Color.white.opacity(0.055)
    static let superficieActiva = Color.white.opacity(0.11)

    // Radios
    static let radioPanel: CGFloat = 28
    static let radioTarjeta: CGFloat = 16
    static let radioFila: CGFloat = 12

    // Movimiento: un resorte para transformarse, otro para entrar, uno corto para los cambios de valor.
    static let morfosis = Animation.spring(response: 0.44, dampingFraction: 0.82)
    static let entrada = Animation.spring(response: 0.38, dampingFraction: 0.74)
    static let cambio = Animation.spring(response: 0.30, dampingFraction: 0.88)
    static let fundido = Animation.easeOut(duration: 0.5)

    // Letra
    static func cifra(_ tamano: CGFloat, _ peso: Font.Weight = .thin) -> Font { .system(size: tamano, weight: peso) }
    static let titulo = Font.system(size: 13.5, weight: .semibold)
    static let cuerpo = Font.system(size: 11.5)
    static let detalle = Font.system(size: 10.5)
}

/// Un tono: el color base y su luz (más clara). Las marcas, el líquido y la luz van del base al claro.
struct Tono: Equatable {
    let base: Color
    let claro: Color

    var gradiente: [Color] { [base, claro] }

    static let azul = Tono(base: Color(red: 0.30, green: 0.54, blue: 1.0), claro: Color(red: 0.64, green: 0.80, blue: 1.0))
    static let violeta = Tono(base: Color(red: 0.48, green: 0.40, blue: 1.0), claro: Color(red: 0.80, green: 0.66, blue: 1.0))
    static let claude = Tono(base: Color(red: 0.95, green: 0.47, blue: 0.29), claro: Color(red: 1.0, green: 0.74, blue: 0.55))
    static let ambar = Tono(base: Color(red: 1.0, green: 0.62, blue: 0.14), claro: Color(red: 1.0, green: 0.86, blue: 0.52))
    static let verde = Tono(base: Color(red: 0.18, green: 0.78, blue: 0.46), claro: Color(red: 0.60, green: 0.97, blue: 0.72))
    static let rojo = Tono(base: Color(red: 1.0, green: 0.29, blue: 0.29), claro: Color(red: 1.0, green: 0.62, blue: 0.52))
    static let neutro = Tono(base: Color(white: 0.5), claro: Color(white: 0.86))

    /// Volumen (azul a violeta) y brillo (ámbar cálido): los únicos tonos de dos colores distintos.
    static let volumen = Tono(base: Color(red: 0.32, green: 0.50, blue: 1.0), claro: Color(red: 0.74, green: 0.58, blue: 1.0))
    static let brillo = Tono(base: Color(red: 1.0, green: 0.56, blue: 0.16), claro: Color(red: 1.0, green: 0.88, blue: 0.60))

    static func gravedad(_ g: Gravedad) -> Tono {
        switch g {
        case .bien: return .verde
        case .atento: return .ambar
        case .mal: return .rojo
        }
    }

    static func agente(_ e: AgentesRemotos.Estado) -> Tono {
        switch e {
        case .ok: return .verde
        case .alerta: return .ambar
        case .caido: return .rojo
        case .desconocido: return .neutro
        }
    }

    /// El tono de una carátula: su color más vivo, aclarado para que brille sobre negro.
    static func de(_ color: Color) -> Tono {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .gray
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Tono(base: Color(hue: h, saturation: min(1, max(0.5, s * 1.2)), brightness: max(0.78, b)),
                    claro: Color(hue: h, saturation: min(1, max(0.25, s * 0.6)), brightness: 1))
    }
}

// MARK: Luz

/// La luz que sube desde el borde de abajo, del tono de lo que se muestra (como el reproductor de iOS que se tiñe
/// con la carátula). Estática: no cuesta procesador. Al cambiar de tono, se funde.
struct LuzBorde: View {
    let tono: Tono
    var fuerza = 0.42
    var alto: CGFloat = 0.8        // hasta dónde sube (fracción del alto)
    var centro: CGFloat = 0.5      // dónde nace (fracción del ancho)
    var ancho: CGFloat = 1

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Ellipse().fill(tono.base)
                    .frame(width: w * ancho * 0.78, height: h * alto)
                    .position(x: w * (centro - ancho * 0.12), y: h * 1.04)
                Ellipse().fill(tono.claro)
                    .frame(width: w * ancho * 0.5, height: h * alto * 0.7)
                    .position(x: w * (centro + ancho * 0.18), y: h * 1.06)
            }
            .blur(radius: min(h * 0.34, 46))
            .opacity(fuerza)
        }
        .allowsHitTesting(false)
        .animation(Halo.fundido, value: tono)
    }
}

// MARK: Marcas en línea

/// Regla de marcas: el mismo trazo fino de los diales, en línea. Las encendidas brillan; la última, más clara.
/// Sirve para niveles (volumen, brillo) y medidas pequeñas.
struct Regla: View {
    let valor: Double
    let tono: Tono
    var cuantas = 32
    var alto: CGFloat = 12
    var grosor: CGFloat = 2
    var apagada = false

    var body: some View {
        let encendidas = Int((max(0, min(1, valor)) * Double(cuantas)).rounded())
        HStack(spacing: 0) {
            ForEach(0..<cuantas, id: \.self) { i in
                let c = tono.base.mix(with: tono.claro, by: Double(i) / Double(max(1, cuantas - 1)))
                let prendida = i < encendidas && !apagada
                let punta = prendida && i == encendidas - 1
                Capsule()
                    .fill(prendida ? (punta ? Color.white : c) : Color.white.opacity(i < encendidas ? 0.3 : 0.12))
                    .frame(width: grosor, height: punta ? alto + 3 : alto)
                    .shadow(color: prendida ? c.opacity(0.95) : .clear, radius: punta ? 4 : 2.2)
                if i < cuantas - 1 { Spacer(minLength: 0) }
            }
        }
        .frame(height: alto + 3)
        .animation(Halo.cambio, value: encendidas)
    }
}

// MARK: Líquido

/// Cápsula de progreso líquida para procesos (el día de un agente, espacio liberado, una cuenta atrás larga):
/// el relleno brilla, tiene un reflejo arriba y, opcional, un ícono en la punta y un texto al final del riel.
struct Liquido: View {
    let valor: Double
    let tono: Tono
    var alto: CGFloat = 22
    var icono: String?
    var texto: String?

    var body: some View {
        GeometryReader { g in
            let lleno = max(alto, g.size.width * max(0, min(1, valor)))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 1))
                if let texto {
                    Text(texto).font(.system(size: max(9, alto * 0.42), weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Halo.texto3)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, alto * 0.55)
                }
                Capsule()
                    .fill(LinearGradient(colors: [tono.base, tono.claro], startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                                           startPoint: .top, endPoint: .center)).padding(max(1, alto * 0.08)))
                    .overlay(alignment: .trailing) {
                        if let icono, alto >= 16 {
                            Image(systemName: icono).font(.system(size: alto * 0.44, weight: .bold)).foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.25), radius: 2).padding(.trailing, alto * 0.32)
                        }
                    }
                    .frame(width: lleno)
                    .shadow(color: tono.base.opacity(0.7), radius: alto * 0.45)
            }
        }
        .frame(height: alto)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: valor)
    }
}

// MARK: Íconos y botones

/// Ícono en un círculo de vidrio teñido de su tono (avisos, filas de agentes, medidas del Mac).
struct Insignia: View {
    enum Icono { case simbolo(String), estrella, imagen(NSImage) }
    let icono: Icono
    let tono: Tono
    var lado: CGFloat = 32

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [tono.base.opacity(0.42), tono.base.opacity(0.12)], center: .top, startRadius: 0, endRadius: lado))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [tono.claro.opacity(0.7), tono.base.opacity(0.12)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay {
                switch icono {
                case .estrella:
                    EstrellaClaude().fill(tono.claro).frame(width: lado * 0.5, height: lado * 0.5)
                case .simbolo(let s):
                    Image(systemName: s).font(.system(size: lado * 0.4, weight: .semibold)).foregroundStyle(tono.claro)
                case .imagen(let img):
                    Image(nsImage: img).resizable().scaledToFit().padding(lado * 0.2)
                }
            }
            .frame(width: lado, height: lado)
            .shadow(color: tono.base.opacity(0.4), radius: lado * 0.25)
    }
}

/// Botón en cápsula. Sin tono: blanco sólido con letra negra (el de Apple). Con tono: del color de la acción
/// (Unirse verde, Responder del tono de Claude), con brillo debajo. `secundario`: vidrio.
struct BotonHalo: View {
    let titulo: String
    var icono: String?
    var tono: Tono?
    var secundario = false
    var teclas: String?
    var alto: CGFloat = 30
    var accion: () -> Void = {}

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                if let icono { Image(systemName: icono).font(.system(size: alto * 0.38, weight: .bold)) }
                Text(titulo).font(.system(size: alto * 0.42, weight: .semibold)).lineLimit(1)
                if let teclas {
                    Text(teclas).font(.system(size: alto * 0.36, weight: .medium)).opacity(0.45)
                }
            }
            .foregroundStyle(secundario ? Halo.texto : .black)
            .padding(.horizontal, alto * 0.5)
            .frame(height: alto)
            .background {
                if secundario {
                    Capsule().fill(.white.opacity(0.1)).overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                } else if let tono {
                    Capsule().fill(LinearGradient(colors: [tono.claro, tono.base], startPoint: .top, endPoint: .bottom))
                        .shadow(color: tono.base.opacity(0.6), radius: 9)
                } else {
                    Capsule().fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .white.opacity(0.18), radius: 8)
                }
            }
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// Pestaña en píldora sobre negro: la activa con un vidrio blanco translúcido; un punto de color si pide atención.
struct PildoraHalo: View {
    let titulo: String
    var cuenta = 0
    var punto: Color?
    let activa: Bool
    var accion: () -> Void = {}

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 5) {
                if let punto { PuntoBrillante(color: punto, lado: 6) }
                Text(titulo).font(.system(size: 11.5, weight: .semibold))
                if cuenta > 0 { Text("\(cuenta)").font(.system(size: 10.5, weight: .semibold)).opacity(0.45) }
            }
            .foregroundStyle(.white.opacity(activa ? 1 : 0.5))
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(Capsule().fill(.white.opacity(activa ? 0.13 : 0)))
            .overlay(Capsule().strokeBorder(.white.opacity(activa ? 0.1 : 0), lineWidth: 1))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// Cifra con su unidad en versalitas al lado ("62 %", "7,9 GB"): grande y fina para el dato principal,
/// seminegrita y pequeña para los secundarios.
struct Cifra: View {
    let numero: String
    var unidad = ""
    var tamano: CGFloat = 22
    var peso: Font.Weight = .thin
    var color: Color = .white
    var valor: Double?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: tamano * 0.08) {
            Text(numero).font(.system(size: tamano, weight: peso)).monospacedDigit().kerning(-tamano * 0.025)
                .contentTransition(valor.map { .numericText(value: $0) } ?? .identity)
            if !unidad.isEmpty {
                Text(unidad.uppercased()).font(.system(size: max(8, tamano * 0.34), weight: .semibold)).opacity(0.55)
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: Paneles

/// Panel flotante de vidrio oscuro: Liquid Glass real en la app; en los renders, una simulación (el fondo
/// desenfocado y oscurecido detrás, con `lienzoHalo`). Filo de luz arriba.
struct PanelHalo: ViewModifier {
    var radio: CGFloat = Halo.radioPanel
    let simulado: Bool

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        Group {
            if simulado {
                content.background(forma.fill(Color.black.opacity(0.58)))
            } else {
                content.glassEffect(.regular.tint(Color.black.opacity(0.55)), in: forma)
            }
        }
        .overlay(forma.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04), .white.opacity(0.08)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

/// Tarjeta dentro de un panel; `activa` la levanta (fila elegida, vista previa).
struct TarjetaHalo: ViewModifier {
    var radio: CGFloat = Halo.radioTarjeta
    var activa = false
    var tono: Tono?

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        content
            .background {
                ZStack {
                    forma.fill(activa ? Halo.superficieActiva : Halo.superficie)
                    if let tono {
                        forma.fill(LinearGradient(colors: [tono.base.opacity(activa ? 0.22 : 0.12), .clear],
                                                  startPoint: .bottomLeading, endPoint: .topTrailing))
                    }
                }
            }
            .overlay(forma.strokeBorder(LinearGradient(colors: [.white.opacity(activa ? 0.16 : 0.09), .white.opacity(0.03)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

extension View {
    func panelHalo(radio: CGFloat = Halo.radioPanel, simulado: Bool) -> some View { modifier(PanelHalo(radio: radio, simulado: simulado)) }
    func tarjetaHalo(radio: CGFloat = Halo.radioTarjeta, activa: Bool = false, tono: Tono? = nil) -> some View {
        modifier(TarjetaHalo(radio: radio, activa: activa, tono: tono))
    }
}

/// Para renders: el fondo de pantalla y, detrás del panel, el mismo fondo desenfocado y oscurecido (vidrio oscuro).
@MainActor
func lienzoHalo<Contenido: View>(_ fondo: NSImage, lienzo: CGSize, panel: CGSize, radio: CGFloat = Halo.radioPanel,
                                 @ViewBuilder _ contenido: () -> Contenido) -> some View {
    let imagen = Image(nsImage: fondo).resizable().scaledToFill().frame(width: lienzo.width, height: lienzo.height).clipped()
    return ZStack {
        imagen
        imagen
            .blur(radius: 30)
            .saturation(1.3)
            .mask(RoundedRectangle(cornerRadius: radio, style: .continuous).frame(width: panel.width, height: panel.height))
        contenido().shadow(color: .black.opacity(0.4), radius: 40, y: 20)
    }
    .frame(width: lienzo.width, height: lienzo.height)
}
