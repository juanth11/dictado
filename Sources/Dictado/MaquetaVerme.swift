import AppKit
import SwiftUI

/// Maqueta (solo render, no está en la app): botón «Verme» junto a Unirse en el aviso de reunión y el espejo
/// de cámara que bajaría desde el notch. `Dictado --vista-verme salida.png`
@MainActor
func hojaVerme(_ destino: URL) -> Bool {
    let fondo = fondoDeMuestra()
    let azul = Color(red: 0.35, green: 0.6, blue: 1.0)
    let verde = Color(red: 0.20, green: 0.84, blue: 0.35)
    let notch = CGSize(width: 186, height: 32)
    let ancho = notch.width + 2 * FormaIsla.hombro + 2 * 175

    let isla = ZStack(alignment: .top) {
        FormaIsla(radio: 24).fill(.black).shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            HStack(spacing: 10) {
                Capsule().fill(azul).frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("VIDEOLLAMADA").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(azul)
                    Text("Revisión de contrato").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("1:58").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(azul)
                Label("Verme", systemImage: "person.crop.square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(.white))
                Image(systemName: "video.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(Circle().fill(verde))
            }
            .padding(.horizontal, 26)
            .frame(maxHeight: .infinity)
        }
    }
    .frame(width: ancho, height: notch.height + 52)

    // El "espejo": aquí iría la cámara en vivo (en la maqueta, una silueta sobre el fondo).
    let espejo = VStack(spacing: 8) {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: fondo).resizable().scaledToFill()
                .frame(width: 300, height: 188).clipped()
                .blur(radius: 6)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                        .offset(y: 34)
                )
            HStack(spacing: 5) {
                Circle().fill(verde).frame(width: 7, height: 7)
                Text("Cámara").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.45)))
            .padding(10)
        }
        .frame(width: 300, height: 188)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        HStack {
            Text("Así te ven").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            Text("se apaga al unirte o en 60 s").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
        }
        .frame(width: 300)
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.black).shadow(color: .black.opacity(0.35), radius: 18, y: 8))

    let hoja = ZStack(alignment: .top) {
        Image(nsImage: fondo).resizable().scaledToFill().frame(width: 760, height: 380, alignment: .top).clipped()
        Rectangle().fill(.white.opacity(0.18)).frame(height: notch.height)
        VStack(spacing: 10) {
            isla
            espejo
        }
    }
    .frame(width: 760, height: 380)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}
