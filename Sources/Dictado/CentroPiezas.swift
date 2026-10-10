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
                Rotulo(rotulo, color: tono?.claro ?? Halo.texto3)
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
        .tarjetaHalo(radio: Halo.radioTarjeta + 4)
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
