import AppKit
import SwiftUI

/// Lenguaje visual de los paneles: vidrio claro tipo visionOS,
/// pestañas en píldora con la activa en blanco sólido, botones circulares de vidrio, esquinas amplias,
/// etiquetas en mayúsculas monoespaciadas, sin líneas de color.
enum Diseno {
    static let tinta = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let tintaSuave = Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.55)
    static let tintaTenue = Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.35)
    static let vidrio = Color.white.opacity(0.42)
    static let borde = Color.white.opacity(0.72)
    static let sombra = Color.black.opacity(0.12)
}

/// Panel flotante de vidrio claro: Liquid Glass real en la app; en los renders, una simulación
/// (el render pone el fondo desenfocado detrás con `lienzoConVidrio`).
struct PanelVidrio: ViewModifier {
    let radio: CGFloat
    let simulado: Bool

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        Group {
            if simulado {
                content.background(forma.fill(Color.white.opacity(0.40)))
            } else {
                content.glassEffect(.regular.tint(Color.white.opacity(0.22)), in: forma)
            }
        }
        .overlay(forma.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.25)], startPoint: .top, endPoint: .bottom),
            lineWidth: 1))
        .environment(\.colorScheme, .light)
    }
}

/// Pestañas en píldora: la activa en blanco sólido con sombra suave.
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
                        if activa { Capsule().fill(.white).shadow(color: Diseno.sombra, radius: 6, y: 2) }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.spring(duration: 0.3)) { valor = opcion.valor } }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.32)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8))
    }
}

/// Botón circular de vidrio; el activo, blanco sólido.
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
                .foregroundStyle(activo ? Diseno.tinta : Diseno.tinta.opacity(0.72))
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

/// Botón en píldora: el primario blanco sólido; los demás, vidrio.
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
                    Text(teclas).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Diseno.tintaTenue)
                }
            }
            .foregroundStyle(Diseno.tinta)
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
        .background(Capsule().fill(Color.white.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.65), lineWidth: 0.6))
    }
}

/// Encabezado de sección en mayúsculas monoespaciadas.
struct EtiquetaSeccion: View {
    let titulo: String

    var body: some View {
        Text(titulo.uppercased())
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.4)
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
            .blur(radius: 26)
            .brightness(0.06)
            .mask(RoundedRectangle(cornerRadius: radio, style: .continuous).frame(width: panel.width, height: panel.height))
        contenido().shadow(color: .black.opacity(0.20), radius: 34, y: 16)
    }
    .frame(width: lienzo.width, height: lienzo.height)
}
