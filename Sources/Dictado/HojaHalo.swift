import AppKit
import SwiftUI

/// Hoja del sistema Halo (solo render): tonos, letra y todas las piezas base con su nombre en el código.
/// `Dictado --vista-halo salida.png`
@MainActor
func hojaHalo(_ destino: URL) -> Bool {
    func seccion<C: View>(_ titulo: String, _ nota: String, @ViewBuilder _ c: () -> C) -> some View {
        let contenido = c()
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Rotulo(titulo, color: Halo.texto2)
                Text(nota).font(Halo.detalle).foregroundStyle(Halo.texto3)
            }
            contenido
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjetaHalo(radio: 22)
    }
    func nombre(_ texto: String) -> some View {
        Text(texto).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Halo.texto3)
    }
    let tonos: [(String, Tono, String)] = [
        ("claude", .claude, "Claude"), ("verde", .verde, "Bien · Unirse"), ("ambar", .ambar, "Atento · alerta"),
        ("rojo", .rojo, "Mal · sin conexión"), ("azul", .azul, "Reuniones · enlaces"), ("violeta", .violeta, "Texto"),
        ("volumen", .volumen, "Volumen"), ("brillo", .brillo, "Brillo"), ("neutro", .neutro, "Sin tono"),
    ]

    let hoja = VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Halo").font(.system(size: 44, weight: .thin)).foregroundStyle(Halo.texto)
                Text("El lenguaje visual de Dictado: diales de marcas finas y luz de color que nace del borde, sobre negro.")
                    .font(.system(size: 13)).foregroundStyle(Halo.texto2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("1 · Negro de fondo   2 · Un tono por momento   3 · Cifras finas").font(Halo.detalle).foregroundStyle(Halo.texto3)
                Text("4 · Marcas con brillo   5 · Nada se mueve en reposo").font(Halo.detalle).foregroundStyle(Halo.texto3)
            }
        }
        seccion("Tonos", "Cada momento tiene uno; aparece en la luz del borde, el dato principal y el botón de acción. Lo demás es blanco.") {
            HStack(spacing: 12) {
                ForEach(tonos, id: \.0) { clave, tono, uso in
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.04))
                            LuzBorde(tono: tono, fuerza: 0.7, alto: 1, centro: 0.5, ancho: 1)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Capsule().fill(LinearGradient(colors: tono.gradiente, startPoint: .leading, endPoint: .trailing))
                                .frame(width: 56, height: 8).shadow(color: tono.base, radius: 6)
                        }
                        .frame(width: 104, height: 78)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                        Text("Tono.\(clave)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Halo.texto)
                        nombre(uso)
                    }
                }
            }
        }
        HStack(alignment: .top, spacing: 18) {
            seccion("Letra", "Texto del sistema. Cifras finas para el dato principal; rótulos en mayúsculas con espaciado.") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Cifra(numero: "62", unidad: "%", tamano: 54)
                        Cifra(numero: "7,9", unidad: "GB", tamano: 34)
                        Cifra(numero: "768", unidad: "k", tamano: 14, peso: .semibold, color: Tono.ambar.claro)
                    }
                    nombre("Cifra · .thin 54 / 34 · .semibold 14 para datos secundarios")
                    Rotulo("Necesita tu permiso", color: Tono.claude.claro)
                    Text("Rediseño del sitio web").font(Halo.titulo).foregroundStyle(Halo.texto)
                    Text("Terminal · swift build -c release").font(Halo.cuerpo).foregroundStyle(Halo.texto2)
                    Text("hace 4 min · próxima 3:00 a. m.").font(Halo.detalle).foregroundStyle(Halo.texto3)
                    nombre("Rotulo 9 semibold · Halo.titulo 13,5 · cuerpo 11,5 · detalle 10,5 · texto / texto2 / texto3")
                    NumeroPuntos(texto: "4:12", punto: 3.2, paso: 4.4, color: Tono.azul.claro)
                    nombre("NumeroPuntos · solo para cuentas regresivas")
                }
            }
            .frame(width: 430)
            seccion("Medidores", "Las mismas marcas finas en círculo (Dial) y en línea (Regla); la última encendida es más clara.") {
                HStack(alignment: .top, spacing: 26) {
                    VStack(spacing: 8) {
                        Dial(lado: 92, valor: 0.62, colores: Tono.volumen.gradiente, marcas: 40, brillo: 0.85) {
                            Image(systemName: "speaker.wave.3.fill").font(.system(size: 20)).foregroundStyle(.white)
                        }
                        nombre("Dial · ícono")
                    }
                    VStack(spacing: 8) {
                        Dial(lado: 92, valor: 0.81, colores: Tono.ambar.gradiente, marcas: 36, anillo: 5, brillo: 0.7) {
                            Cifra(numero: "13", unidad: "/16", tamano: 24, peso: .light)
                        }
                        nombre("Dial · cifra")
                    }
                    VStack(spacing: 8) {
                        Dial(lado: 92, valor: 1, colores: Tono.rojo.gradiente, marcas: 30, arco: 360, anillo: 4, brillo: 0.7, destello: false) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundStyle(Tono.rojo.claro)
                        }
                        nombre("Dial · aviso (360°)")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Regla(valor: 0.62, tono: .volumen, cuantas: 32).frame(width: 220)
                        Regla(valor: 0.81, tono: .brillo, cuantas: 32).frame(width: 220)
                        Regla(valor: 0.62, tono: .volumen, cuantas: 32, apagada: true).frame(width: 220)
                        nombre("Regla · encendida, brillo y apagada (silencio)")
                    }
                }
            }
        }
        HStack(alignment: .top, spacing: 18) {
            seccion("Luz y líquido", "La luz nace del borde de abajo y no se mueve; el líquido es para procesos que avanzan.") {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black)
                        LuzBorde(tono: .claude, fuerza: 0.5, alto: 0.95).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        HStack(spacing: 10) {
                            Insignia(icono: .estrella, tono: .claude, lado: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Rotulo("Luz del borde", color: Tono.claude.claro)
                                Text("LuzBorde(tono: .claude)").font(Halo.cuerpo).foregroundStyle(Halo.texto)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                    }
                    .frame(width: 400, height: 76)
                    Liquido(valor: 0.83, tono: .verde, alto: 24, icono: "checkmark", texto: "5 de 6 hoy").frame(width: 400)
                    Liquido(valor: 0.35, tono: .ambar, alto: 12).frame(width: 400)
                    Liquido(valor: 0.6, tono: .verde, alto: 5).frame(width: 400)
                    nombre("Liquido · 24 con ícono y texto · 12 · 5 (en una fila)")
                }
            }
            .frame(width: 450)
            seccion("Botones, pestañas e íconos", "Principal blanco (el de Apple); con tono si la acción tiene significado; vidrio para lo secundario.") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        BotonHalo(titulo: "Ver")
                        BotonHalo(titulo: "Responder", tono: .claude)
                        BotonHalo(titulo: "Unirse", icono: "video.fill", tono: .verde)
                        BotonHalo(titulo: "Abrir Spotify", secundario: true)
                        BotonHalo(titulo: "Pegar en Mail", teclas: "↩", alto: 36)
                    }
                    nombre("BotonHalo · blanco · tono · secundario · con teclas")
                    HStack(spacing: 4) {
                        PildoraHalo(titulo: "Agentes", cuenta: 4, punto: Tono.claude.base, activa: true)
                        PildoraHalo(titulo: "Agenda", cuenta: 2, activa: false)
                        PildoraHalo(titulo: "Mac", punto: Tono.rojo.base, activa: false)
                    }
                    nombre("PildoraHalo · la activa en vidrio blanco; punto si pide atención")
                    HStack(spacing: 14) {
                        Insignia(icono: .estrella, tono: .claude)
                        Insignia(icono: .simbolo("server.rack"), tono: .verde)
                        Insignia(icono: .simbolo("cpu"), tono: .ambar)
                        Insignia(icono: .simbolo("video.fill"), tono: .azul)
                        PuntoBrillante(color: Tono.verde.base, lado: 8)
                        PuntoBrillante(color: Tono.ambar.base, lado: 8)
                        PuntoBrillante(color: Tono.rojo.base, lado: 8)
                    }
                    nombre("Insignia · PuntoBrillante")
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Tarjeta").font(Halo.titulo).foregroundStyle(Halo.texto)
                            Text("tarjetaHalo()").font(Halo.detalle).foregroundStyle(Halo.texto3)
                        }
                        .padding(14).frame(width: 150, alignment: .leading).tarjetaHalo()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Elegida").font(Halo.titulo).foregroundStyle(Halo.texto)
                            Text("activa, tono: .violeta").font(Halo.detalle).foregroundStyle(Halo.texto3)
                        }
                        .padding(14).frame(width: 170, alignment: .leading).tarjetaHalo(activa: true, tono: .violeta)
                    }
                }
            }
        }
        seccion("Movimiento", "Todo es resorte o fundido y acompaña un cambio. En reposo no se anima nada (0 % de procesador).") {
            HStack(alignment: .top, spacing: 28) {
                ForEach([("Halo.morfosis", "0,44 s · 0,82", "La isla se abre, se cierra o cambia de tamaño", 0.44, 0.82),
                         ("Halo.entrada", "0,38 s · 0,74", "Un aviso entra: escala 0,88 → 1 y desenfoque 10 → 0", 0.38, 0.74),
                         ("Halo.cambio", "0,30 s · 0,88", "Un valor cambia: marcas, cifras que ruedan, pestañas", 0.30, 0.88)],
                        id: \.0) { nombreR, valores, uso, r, a in
                    VStack(alignment: .leading, spacing: 6) {
                        Canvas { ctx, tam in  // la curva del resorte
                            var p = Path()
                            for i in 0...60 {
                                let t = Double(i) / 60 * 1.0
                                let y = resorte(t, respuesta: r, amortiguacion: a)
                                let punto = CGPoint(x: tam.width * CGFloat(i) / 60, y: tam.height * (1 - CGFloat(y) * 0.8) - 4)
                                if i == 0 { p.move(to: punto) } else { p.addLine(to: punto) }
                            }
                            ctx.stroke(p, with: .linearGradient(Gradient(colors: Tono.azul.gradiente), startPoint: .zero,
                                                                 endPoint: CGPoint(x: tam.width, y: 0)), lineWidth: 2)
                        }
                        .frame(width: 200, height: 56)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.03)))
                        Text(nombreR).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Halo.texto)
                        nombre(valores + " · " + uso)
                    }
                    .frame(width: 220, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Halo.fundido").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Halo.texto)
                    nombre("0,5 s · la luz cambia de tono")
                    Text("Símbolos").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Halo.texto).padding(.top, 6)
                    nombre("Rebote una vez al entrar un aviso; reemplazo al cambiar (▶︎ ⇄ ❙❙)")
                    Text("Lo único que se mueve solo").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Halo.texto).padding(.top, 6)
                    nombre("La onda del dictado mientras escuchas y el ecualizador mientras suena música, solo a la vista")
                }
            }
        }
    }
    .padding(30)
    .frame(width: 1400)
    .background(Color.black)
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}
