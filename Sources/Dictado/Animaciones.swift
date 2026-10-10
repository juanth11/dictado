import AppKit
import SwiftUI

// Video de las animaciones de Halo (solo render, no está en la app): `Dictado --animaciones carpeta`.
// ImageRenderer dibuja cuadros quietos, así que cada animación se calcula cuadro por cuadro con los mismos
// resortes que usa la app (Halo.morfosis, Halo.entrada, Halo.cambio, Halo.fundido) y luego ffmpeg arma el video.

/// Posición de un resorte de SwiftUI (respuesta, amortiguación) en el instante t, de 0 a 1 (con rebote).
func resorte(_ t: Double, respuesta: Double, amortiguacion: Double) -> Double {
    guard t > 0 else { return 0 }
    let w0 = 2 * Double.pi / respuesta
    let z = amortiguacion
    if z < 1 {
        let wd = w0 * (1 - z * z).squareRoot()
        return 1 - exp(-z * w0 * t) * (cos(wd * t) + (z * w0 / wd) * sin(wd * t))
    }
    return 1 - exp(-w0 * t) * (1 + w0 * t)
}

private func mezclar(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

/// Los datos de ejemplo de la isla (los mismos de `--vista-isla`).
@MainActor
private struct MuestraIsla {
    let musica = Musica(vivo: false)
    let agenda = Agenda(vivo: false)
    let claude = SesionesClaude(vivo: false)
    let agentes = ejemploAgentes()
    let salud = ejemploSalud()
    let privacidad = Privacidad(vivo: false)
    let hud = EstadoHUD()

    init(fondo: NSImage) {
        let caratula = NSImage(size: NSSize(width: 300, height: 300))
        caratula.lockFocus()
        fondo.draw(in: NSRect(x: 0, y: 0, width: 300, height: 300), from: NSRect(x: 1500, y: 600, width: 900, height: 900),
                   operation: .copy, fraction: 1)
        caratula.unlockFocus()
        musica.titulo = "Weightless"
        musica.artista = "Marconi Union"
        musica.duracion = 480
        musica.posicion = 151
        musica.sonando = true
        musica.caratula = caratula
        musica.acento = Musica.colorMedio(caratula)
        claude.sesiones = [
            .init(id: "a", pid: 1, nombre: "Rediseño del sitio web", carpeta: "", estado: .esperando, espera: "Necesita tu permiso",
                  desde: Date().addingTimeInterval(-40), contexto: 318_000, actividad: "Terminal · swift build -c release"),
            .init(id: "b", pid: 2, nombre: "Informe trimestral", carpeta: "", estado: .trabajando, espera: "",
                  desde: Date().addingTimeInterval(-260), contexto: 768_000, actividad: "Editando HeroSection.tsx"),
        ]
        agenda.permitido = true
        agenda.eventos = [.init(id: "1", titulo: "Revisión de contrato", inicio: Date().addingTimeInterval(252),
                                fin: Date().addingTimeInterval(2952), color: Color(red: 0.35, green: 0.6, blue: 1.0),
                                enlace: URL(string: "https://meet.google.com/abc-defg-hij"))]
        hud.estilo = .prisma
    }

    func isla(_ estado: EstadoIsla) -> VistaIsla {
        VistaIsla(estado: estado, musica: musica, agenda: agenda, hud: hud, privacidad: privacidad, claude: claude,
                  agentes: agentes, salud: salud, control: nil)
    }
}

/// Dibuja los cuadros de cada animación en `carpeta` (cuadro-0001.png…) a 30 cuadros por segundo.
@MainActor
func animaciones(_ carpeta: URL) -> Bool {
    let fondo = fondoDeMuestra()
    let m = MuestraIsla(fondo: fondo)
    let notch = CGSize(width: 186, height: 32)
    let fps = 30.0
    var n = 0
    try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

    func guardar<V: View>(_ vista: V) {
        let renderer = ImageRenderer(content: vista.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        n += 1
        try? png.write(to: carpeta.appendingPathComponent(String(format: "cuadro-%04d.png", n)))
    }

    /// Lienzo: fondo, barra de menú, notch físico, la isla del tamaño dado y el título de la animación.
    func lienzo<C: View>(_ titulo: String, _ detalle: String, tam: CGSize, radio: CGFloat, @ViewBuilder _ contenido: () -> C) -> some View {
        let c = contenido()
        return ZStack(alignment: .top) {
            Image(nsImage: fondo).resizable().scaledToFill().frame(width: 760, height: 290, alignment: .top).clipped()
            Rectangle().fill(.white.opacity(0.18)).frame(height: 32)
            ZStack(alignment: .top) {
                FormaIsla(radio: radio).fill(.black).shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                c.frame(width: tam.width, height: tam.height, alignment: .top).clipShape(FormaIsla(radio: radio))
            }
            .frame(width: tam.width, height: tam.height)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(detalle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.55)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(14)
        }
        .frame(width: 760, height: 290)
    }

    let compacta = CGSize(width: notch.width + 2 * FormaIsla.hombro + 92, height: notch.height)
    let abierta = Isla.expandida

    // 1 · La isla se abre al pasar el mouse: el contorno se transforma con Halo.morfosis y el contenido se enfoca.
    for i in 0..<Int(1.3 * fps) {
        let t = Double(i) / fps
        let p = resorte(t, respuesta: 0.44, amortiguacion: 0.82)
        let tam = CGSize(width: mezclar(compacta.width, abierta.width, p), height: mezclar(compacta.height, abierta.height, p))
        let radio = mezclar(10, 34, min(1, p))
        let enfoque = max(0, min(1, (p - 0.25) / 0.75))
        let cerrado = EstadoIsla(); cerrado.notch = notch
        let abiertoE = EstadoIsla(); abiertoE.notch = notch; abiertoE.expandida = true; abiertoE.pestana = .agentes
        guardar(lienzo("La isla se abre", "Resorte 0,44 s · amortiguación 0,82 · el contenido crece desde el notch y se enfoca",
                       tam: tam, radio: radio) {
            ZStack(alignment: .top) {
                m.isla(cerrado).frame(width: compacta.width, height: compacta.height).opacity(1 - min(1, p * 3))
                m.isla(abiertoE).frame(width: abierta.width, height: abierta.height)
                    .scaleEffect(mezclar(0.88, 1, enfoque), anchor: .top)
                    .blur(radius: mezclar(10, 0, enfoque))
                    .opacity(enfoque)
                    .frame(width: tam.width, height: tam.height, alignment: .top)
            }
        })
    }
    for _ in 0..<Int(0.6 * fps) {  // pausa con la isla abierta
        let e = EstadoIsla(); e.notch = notch; e.expandida = true; e.pestana = .agentes
        guardar(lienzo("La isla se abre", "Resorte 0,44 s · amortiguación 0,82 · el contenido crece desde el notch y se enfoca",
                       tam: abierta, radio: 34) { m.isla(e).frame(width: abierta.width, height: abierta.height) })
    }

    // 2 · La luz cambia de tono al cambiar de pestaña (Agentes → Mac): fundido de 0,5 s.
    for i in 0..<Int(1.0 * fps) {
        let t = min(1, Double(i) / fps / 0.5)
        let suave = 1 - pow(1 - t, 3)
        let a = EstadoIsla(); a.notch = notch; a.expandida = true; a.pestana = .agentes
        let b = EstadoIsla(); b.notch = notch; b.expandida = true; b.pestana = .mac
        guardar(lienzo("La luz cambia de tono", "Fundido de 0,5 s · naranja (Claude te espera) → rojo (disco casi lleno)",
                       tam: abierta, radio: 34) {
            ZStack {
                m.isla(a).frame(width: abierta.width, height: abierta.height).opacity(1 - suave)
                m.isla(b).frame(width: abierta.width, height: abierta.height).opacity(suave)
            }
        })
    }

    // 3 · Un aviso entra: la isla crece desde el notch con Halo.entrada (un rebote leve) y el aviso se enfoca.
    let sesion = m.claude.sesiones[0]
    let conAviso = EstadoIsla(); conAviso.notch = notch; conAviso.actividad = .claude(sesion: sesion, necesita: true, duracion: 0)
    let aviso = conAviso.tamano(alas: false)
    for i in 0..<Int(1.4 * fps) {
        let t = Double(i) / fps
        let p = resorte(t, respuesta: 0.38, amortiguacion: 0.74)
        let tam = CGSize(width: mezclar(compacta.width, aviso.width, p), height: mezclar(compacta.height, aviso.height, p))
        let e = EstadoIsla(); e.notch = notch; e.actividad = .claude(sesion: sesion, necesita: true, duracion: 0)
        guardar(lienzo("Un aviso entra", "Resorte 0,38 s · amortiguación 0,74 (rebote leve) · escala 0,88 → 1 y desenfoque 10 → 0",
                       tam: tam, radio: mezclar(10, 24, min(1, p))) {
            m.isla(e).frame(width: aviso.width, height: aviso.height)
                .scaleEffect(mezclar(0.88, 1, p), anchor: .top)
                .blur(radius: max(0, mezclar(10, 0, p)))
                .opacity(min(1, p * 1.4))
                .frame(width: tam.width, height: tam.height, alignment: .top)
        })
    }

    // 4 · El volumen sube con tres toques de tecla: las marcas se encienden, la cifra rueda y la luz crece.
    let conNivel = EstadoIsla(); conNivel.notch = notch; conNivel.actividad = .nivel(tipo: .volumen, valor: 0.5, silencio: false)
    let nivel = conNivel.tamano(alas: false)
    let pasos: [Double] = [0.38, 0.5, 0.62, 0.74]
    for i in 0..<Int(1.5 * fps) {
        let t = Double(i) / fps
        let k = min(pasos.count - 2, Int(t / 0.35))
        let local = t - Double(k) * 0.35
        let v = pasos[k] + (pasos[k + 1] - pasos[k]) * resorte(local, respuesta: 0.3, amortiguacion: 0.88)
        let e = EstadoIsla(); e.notch = notch
        e.actividad = .nivel(tipo: .volumen, valor: v, silencio: false, salida: SalidaAudio(nombre: "AirPods Pro"))
        guardar(lienzo("El volumen sube", "Resorte 0,30 s por toque · las marcas se encienden una a una y la luz crece con el nivel",
                       tam: nivel, radio: 24) { m.isla(e).frame(width: nivel.width, height: nivel.height) })
    }

    // 5 · Micro-interacciones: el líquido se llena, la regla se enciende y el dial barre hasta su valor.
    for i in 0..<Int(1.6 * fps) {
        let t = Double(i) / fps
        let p = resorte(t, respuesta: 0.6, amortiguacion: 0.85)
        let q = resorte(max(0, t - 0.15), respuesta: 0.45, amortiguacion: 0.9)
        guardar(ZStack {
            Color.black
            LuzBorde(tono: .verde, fuerza: 0.35 * p, alto: 0.7, centro: 0.25, ancho: 0.6)
            HStack(spacing: 46) {
                VStack(alignment: .leading, spacing: 14) {
                    Rotulo("Líquido · el día de Hermes", color: Tono.verde.claro)
                    Liquido(valor: max(0.06, 0.83 * p), tono: .verde, alto: 24, icono: "checkmark", texto: "5 de 6 hoy").frame(width: 260)
                    Rotulo("Regla · un nivel", color: Tono.volumen.claro)
                    Regla(valor: 0.7 * q, tono: .volumen, cuantas: 36).frame(width: 260)
                }
                VStack(spacing: 10) {
                    Dial(lado: 96, valor: 0.72 * q, colores: Tono.ambar.gradiente, marcas: 40, brillo: 0.4 + 0.5 * q) {
                        Cifra(numero: "\(Int(72 * q))", unidad: "%", tamano: 24, peso: .thin)
                    }
                    Rotulo("Dial · memoria", color: Tono.ambar.claro)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Micro-interacciones").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text("Líquido: resorte 0,6 s · Regla y dial: 0,45 s, 0,15 s después · nada se mueve en reposo")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(24)
        }
        .frame(width: 760, height: 290))
    }
    return n > 0
}
