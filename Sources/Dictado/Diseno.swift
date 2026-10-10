import AppKit
import SwiftUI

/// Piezas comunes de los paneles en el lenguaje Halo (ver Halo.swift): vidrio oscuro, pestañas en píldora con la
/// activa en vidrio blanco translúcido, botones circulares de vidrio, el botón principal blanco sólido, rótulos en
/// mayúsculas pequeñas con espaciado.
enum Diseno {
    static let tinta = Halo.texto
    static let tintaSuave = Halo.texto2
    static let tintaTenue = Halo.texto3
    static let vidrio = Color.white.opacity(0.08)
    static let borde = Color.white.opacity(0.12)
    static let sombra = Color.black.opacity(0.4)
}

/// Panel flotante: el vidrio oscuro de Halo (ver PanelHalo).
struct PanelVidrio: ViewModifier {
    let radio: CGFloat
    let simulado: Bool

    func body(content: Content) -> some View {
        content.modifier(PanelHalo(radio: radio, simulado: simulado))
    }
}

/// Pestañas en píldora: la activa en vidrio blanco translúcido.
struct Segmentado<Valor: Hashable>: View {
    let opciones: [(valor: Valor, titulo: String)]
    @Binding var valor: Valor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(opciones, id: \.valor) { opcion in
                let activa = opcion.valor == valor
                Text(opcion.titulo)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(activa ? Diseno.tinta : Diseno.tintaSuave)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if activa {
                            Capsule().fill(.white.opacity(0.14)).overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.spring(duration: 0.3)) { valor = opcion.valor } }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Botón circular de vidrio; el activo, blanco sólido con el ícono negro.
struct BotonCirculo: View {
    let simbolo: String
    var activo = false
    var lado: CGFloat = 36
    var ayuda = ""
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: lado * 0.38, weight: .medium))
                .foregroundStyle(activo ? Color.black : Diseno.tinta.opacity(0.8))
                .frame(width: lado, height: lado)
                .background(Circle().fill(activo ? Color.white : Diseno.vidrio))
                .overlay(Circle().strokeBorder(Diseno.borde, lineWidth: 0.8))
                .shadow(color: activo ? Diseno.sombra : .clear, radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
    }
}

/// Botón en píldora: el primario blanco sólido con letra negra (el de Apple); los demás, vidrio.
struct BotonPildora: View {
    let titulo: String
    var teclas: String?
    var simbolo: String?
    var primario = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                if let simbolo { Image(systemName: simbolo).font(.system(size: 12, weight: .semibold)) }
                Text(titulo).font(.system(size: 13, weight: primario ? .semibold : .medium)).lineLimit(1)
                if let teclas {
                    Text(teclas).font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.45)
                }
            }
            .foregroundStyle(primario ? Color.black : Diseno.tinta)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(primario ? Color.white : Diseno.vidrio))
            .overlay(Capsule().strokeBorder(Diseno.borde, lineWidth: 0.8))
            .shadow(color: primario ? Diseno.sombra : .clear, radius: 10, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Dato pequeño en píldora (app, página, hora…).
struct Chip: View {
    let texto: String
    var simbolo: String?
    var icono: NSImage?

    var body: some View {
        HStack(spacing: 5) {
            if let icono {
                Image(nsImage: icono).resizable().frame(width: 14, height: 14)
            } else if let simbolo {
                Image(systemName: simbolo).font(.system(size: 10, weight: .semibold))
            }
            Text(texto).lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Diseno.tintaSuave)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6))
    }
}

/// Encabezado de sección en mayúsculas pequeñas con espaciado.
struct EtiquetaSeccion: View {
    let titulo: String

    var body: some View {
        Text(titulo.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Diseno.tintaTenue)
    }
}

/// Para renders: el fondo de pantalla y, detrás del panel, el mismo fondo desenfocado (vidrio esmerilado).
@MainActor
func lienzoConVidrio<Contenido: View>(_ fondo: NSImage, lienzo: CGSize, panel: CGSize, radio: CGFloat,
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
