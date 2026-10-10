import AppKit
import SwiftUI

// Piezas comunes del centro de mando (las usan la ventana y las maquetas).

/// Una tarjeta del centro: rótulo arriba (con algo a la derecha si hace falta), contenido y, si tiene tono, la luz del
/// borde.
struct TarjetaCentro<C: View>: View {
    let rotulo: String
    var tono: Tono?
    var luz = 0.0
    var derecha: AnyView?
    @ViewBuilder let contenido: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Rotulo(rotulo, color: tono?.claro ?? TextoCentro.terciario)
                Spacer()
                if let derecha { derecha }
            }
            contenido()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if let tono, luz > 0 {
                LuzBorde(tono: tono, fuerza: luz, alto: 0.7, centro: 0.3, ancho: 0.9)
                    .clipShape(RoundedRectangle(cornerRadius: Halo.radioTarjeta + 4, style: .continuous))
            }
        }
        .superficie(radio: 18)
    }
}

func hace(_ fecha: Date) -> String {
    let s = Int(-fecha.timeIntervalSinceNow)
    if s < 3600 { return "hace \(max(1, s / 60)) min" }
    if s < 86_400 { return "hace \(s / 3600) h" }
    return "hace \(s / 86_400) d"
}

func miles(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "es_CO")
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

/// Sobre el vidrio claro el texto secundario necesita más opacidad que sobre el negro de la isla (contraste AA).
enum TextoCentro {
    static let secundario = Color.white.opacity(0.74)
    static let terciario = Color.white.opacity(0.54)
}

// MARK: - Material espacial (visionOS): vidrio claro y profundidad con propósito

/// El vidrio de la ventana: claro, deja ver el fondo de pantalla, con un brillo arriba y un filo de luz. Con
/// "Reducir transparencia" de macOS se vuelve sólido.
struct VidrioCentro: ViewModifier {
    let simulado: Bool
    var radio: CGFloat = 26
    @Environment(\.accessibilityReduceTransparency) private var sinTransparencia

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        let interior = content.background {
            LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3))
                .clipShape(forma)
        }
        return Group {
            if sinTransparencia {
                interior.background(forma.fill(Color(white: 0.13)))
            } else if simulado {
                interior.background(forma.fill(Color.black.opacity(0.34)))   // el render no compone vidrio real
            } else {
                interior.glassEffect(.regular.tint(Color.black.opacity(0.2)), in: forma)
            }
        }
        .overlay(forma.strokeBorder(LinearGradient(stops: [
            .init(color: .white.opacity(0.4), location: 0), .init(color: .white.opacity(0.09), location: 0.32),
            .init(color: .white.opacity(0.04), location: 0.7), .init(color: .white.opacity(0.13), location: 1),
        ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

/// Lo que pide una decisión se levanta hacia la persona: vidrio más claro, brillo arriba, filo de luz y sombra.
struct LevantadoCentro: ViewModifier {
    var radio: CGFloat = 20
    var tono: Tono?

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        return content
            .background {
                ZStack {
                    forma.fill(Color.white.opacity(0.09))
                    forma.fill(LinearGradient(colors: [.white.opacity(0.09), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
                    if let tono {
                        LuzBorde(tono: tono, fuerza: 0.14, alto: 0.6, centro: 0.2, ancho: 0.85).clipShape(forma)
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
            }
            .overlay(forma.strokeBorder(LinearGradient(stops: [
                .init(color: .white.opacity(0.34), location: 0), .init(color: .white.opacity(0.08), location: 0.4),
                .init(color: .white.opacity(0.12), location: 1),
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
    }
}

/// Lo que se lee sobre el vidrio sin pedir nada: plano, apenas un velo y un filo.
struct SuperficieCentro: ViewModifier {
    var radio: CGFloat = 18

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        return content
            .background(forma.fill(Color.white.opacity(0.035)))
            .overlay(forma.strokeBorder(Color.white.opacity(0.075), lineWidth: 0.75))
    }
}

extension View {
    func vidrioCentro(simulado: Bool) -> some View { modifier(VidrioCentro(simulado: simulado)) }
    func levantado(radio: CGFloat = 20, tono: Tono? = nil) -> some View { modifier(LevantadoCentro(radio: radio, tono: tono)) }
    func superficie(radio: CGFloat = 18) -> some View { modifier(SuperficieCentro(radio: radio)) }
}

/// Línea fina para separar filas sobre el vidrio.
struct FiloCentro: View {
    var body: some View { Rectangle().fill(Halo.linea).frame(height: 0.75) }
}

/// Los botones del centro: un solo vocabulario con todos sus estados (encima, pulsado, desactivado).
/// principal = blanco sólido (la acción de la decisión) · secundario = vidrio · enlace = texto con flecha.
struct BotonCentro: View {
    enum Tipo { case principal, secundario, enlace }
    let titulo: String
    var icono: String?
    var tipo: Tipo = .secundario
    var accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                if let icono, tipo != .enlace { Image(systemName: icono).font(.system(size: 11, weight: .semibold)) }
                Text(titulo).font(.system(size: tipo == .enlace ? 11.5 : 12.5, weight: .semibold)).lineLimit(1)
                if tipo == .enlace { Image(systemName: icono ?? "arrow.up.right").font(.system(size: 9, weight: .bold)) }
            }
        }
        .buttonStyle(EstiloBotonCentro(tipo: tipo))
    }
}

struct EstiloBotonCentro: ButtonStyle {
    let tipo: BotonCentro.Tipo

    func makeBody(configuration: Configuration) -> some View {
        CuerpoBotonCentro(tipo: tipo, pulsado: configuration.isPressed) { configuration.label }
    }
}

private struct CuerpoBotonCentro<L: View>: View {
    let tipo: BotonCentro.Tipo
    let pulsado: Bool
    @ViewBuilder let etiqueta: () -> L
    @Environment(\.isEnabled) private var activo
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var encima = false

    var body: some View {
        etiqueta()
            .foregroundStyle(color)
            .padding(.horizontal, tipo == .enlace ? 0 : 13)
            .frame(height: tipo == .enlace ? 20 : 28)
            .background { if tipo != .enlace { Capsule().fill(fondo) } }
            .overlay { if tipo == .secundario { Capsule().strokeBorder(Color.white.opacity(encima ? 0.24 : 0.13), lineWidth: 0.75) } }
            .contentShape(Capsule())
            .opacity(activo ? (pulsado ? 0.78 : 1) : 0.4)
            .scaleEffect(pulsado && !sinMovimiento ? 0.97 : 1)
            .animation(sinMovimiento ? nil : .easeOut(duration: 0.15), value: encima)
            .animation(sinMovimiento ? nil : .easeOut(duration: 0.12), value: pulsado)
            .onHover { encima = $0 }
    }

    private var color: Color {
        switch tipo {
        case .principal: return Color(white: 0.06)
        case .secundario: return Halo.texto
        case .enlace: return encima ? Halo.texto : TextoCentro.secundario
        }
    }

    private var fondo: Color {
        switch tipo {
        case .principal: return Color(white: encima ? 0.98 : 0.92)
        case .secundario: return Color.white.opacity(encima ? 0.15 : 0.08)
        case .enlace: return .clear
        }
    }
}

/// Fondo de una fila al pasar el puntero (listas del centro).
struct EncimaCentro: ViewModifier {
    var radio: CGFloat = 12
    @State private var encima = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radio, style: .continuous).fill(Color.white.opacity(encima ? 0.05 : 0)))
            .onHover { encima = $0 }
    }
}
