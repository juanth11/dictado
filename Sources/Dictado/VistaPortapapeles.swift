import AppKit
import SwiftUI

/// Portapapeles (⌘⌥V) en vidrio claro con luz de color. Arriba: cerrar, búsqueda y pestañas con el punto de color
/// de cada tipo. A la izquierda: un dial con cuántos recortes hay (sus marcas se pintan con el color de cada tipo)
/// y la lista o la cuadrícula de imágenes. A la derecha: la vista previa, con sus datos en números finos y las acciones.
/// Cada tipo de recorte tiene su color (texto violeta, enlace azul, archivo durazno; la imagen, el suyo propio)
/// y lo irradia como un resplandor suave detrás del contenido, sin taparlo.
struct VistaPortapapeles: View {
    static let ancho: CGFloat = 880
    static let alto: CGFloat = 540

    let historial: Historial
    @Bindable var estado: EstadoPanel
    let control: Portapapeles?
    var simulado = false
    @FocusState private var buscando: Bool

    private var seleccionado: Recorte? { historial.recortes.first { $0.id == estado.seleccion } }

    var body: some View {
        let lista = Portapapeles.filtrar(historial.recortes, estado)
        let elegidos = Portapapeles.elegidos(lista, estado, seleccionado)
        let tono = elegidos.first.map { Tono.de($0, historial) } ?? Tono.texto
        VStack(spacing: 14) {
            cabecera
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Contador(lista: lista, estado: estado, total: historial.recortes.count)
                    Group {
                        if estado.filtro == .imagenes {
                            RejillaImagenes(lista: lista, estado: estado, historial: historial, control: control, simulado: simulado)
                        } else {
                            ListaRecortes(lista: lista, estado: estado, historial: historial, control: control, simulado: simulado)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    Text("⌘clic elige varios · arrástralos a otra app · Tab cambia de filtro")
                        .font(.system(size: 10))
                        .foregroundStyle(Diseno.tintaTenue)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 320)
                TarjetaPrevia(elegidos: elegidos, tono: tono, historial: historial, estado: estado, control: control, simulado: simulado)
            }
        }
        .padding(16)
        .frame(width: Self.ancho, height: Self.alto)
        .background { LuzPanel(tono: tono) }
        .modifier(PanelVidrio(radio: 30, simulado: simulado))
        .onAppear { buscando = true }
        .onChange(of: estado.busqueda) { reiniciarSeleccion() }
        .onChange(of: estado.filtro) { reiniciarSeleccion() }
    }

    private func reiniciarSeleccion() {
        estado.marcados = []
        estado.seleccion = Portapapeles.filtrar(historial.recortes, estado).first?.id
        estado.ancla = estado.seleccion
    }

    private var cabecera: some View {
        HStack(spacing: 12) {
            BotonCirculo(simbolo: "xmark", lado: 34, ayuda: "Cerrar (Esc)") { control?.cerrar() }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Diseno.tintaSuave)
                if simulado {  // ImageRenderer no dibuja campos de AppKit
                    Text("Buscar en el historial").font(.system(size: 14)).foregroundStyle(Diseno.tintaTenue)
                    Spacer()
                } else {
                    TextField("Buscar en el historial", text: $estado.busqueda)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($buscando)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(Color.white.opacity(0.5)))
            .overlay(Capsule().strokeBorder(Diseno.borde, lineWidth: 0.8))
            PestanasTipo(valor: $estado.filtro)
        }
    }
}

// MARK: - Color y luz

/// Color de cada tipo de recorte (como las luces de un dial): se usa en los puntos, las marcas y los resplandores.
enum Tono {
    static let texto = Color(red: 0.50, green: 0.37, blue: 1.00)    // violeta
    static let enlace = Color(red: 0.14, green: 0.52, blue: 1.00)   // azul
    static let imagen = Color(red: 0.98, green: 0.28, blue: 0.42)   // rosa rojizo
    static let archivo = Color(red: 1.00, green: 0.66, blue: 0.24)  // durazno ámbar

    static func de(_ tipo: Recorte.Tipo) -> Color {
        switch tipo {
        case .texto: return texto
        case .enlace: return enlace
        case .imagen: return imagen
        case .archivo: return archivo
        }
    }

    /// Segundo color del resplandor, para que la luz no sea plana (como los diales: violeta con durazno, azul con violeta).
    static func par(_ tipo: Recorte.Tipo) -> Color {
        switch tipo {
        case .texto: return archivo
        case .enlace: return texto
        case .imagen: return texto
        case .archivo: return imagen
        }
    }

    static func de(_ filtro: EstadoPanel.Filtro) -> Color? {
        switch filtro {
        case .texto: return texto
        case .enlaces: return enlace
        case .imagenes: return imagen
        case .archivos: return archivo
        case .todo, .fijados: return nil
        }
    }

    @MainActor private static var paletas: [UUID: [NSColor]] = [:]

    /// El color del recorte: el de su tipo; una imagen, su color más vivo (avivado para que brille).
    @MainActor static func de(_ r: Recorte, _ h: Historial) -> Color {
        guard r.tipo == .imagen else { return de(r.tipo) }
        let vivo = paleta(r, h).first { $0.saturationComponent > 0.12 }
        guard let vivo else { return imagen }
        return Color(nsColor: NSColor(hue: vivo.hueComponent, saturation: min(1, max(vivo.saturationComponent * 1.5, 0.5)),
                                      brightness: max(vivo.brightnessComponent, 0.8), alpha: 1))
    }

    /// Hasta cinco colores dominantes de una imagen, calculados una vez sobre una copia de 24 px de la miniatura.
    @MainActor static func paleta(_ r: Recorte, _ h: Historial) -> [NSColor] {
        if let p = paletas[r.id] { return p }
        guard r.tipo == .imagen, let mini = h.miniatura(de: r),
              let cg = mini.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let lado = 24
        var px = [UInt8](repeating: 0, count: lado * lado * 4)
        let dibujado = px.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: lado * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: lado, height: lado))
            return true
        }
        guard dibujado else { return [] }
        // Cubetas de 3 bits por canal; el color de cada cubeta es el promedio de sus píxeles.
        var cubetas: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 128 {
            let (cr, cg, cb) = (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
            let k = (cr >> 5) << 6 | (cg >> 5) << 3 | (cb >> 5)
            let c = cubetas[k] ?? (0, 0, 0, 0)
            cubetas[k] = (c.n + 1, c.r + cr, c.g + cg, c.b + cb)
        }
        let ordenados = cubetas.values.sorted { $0.n > $1.n }.map { c in
            NSColor(srgbRed: CGFloat(c.r) / CGFloat(c.n) / 255, green: CGFloat(c.g) / CGFloat(c.n) / 255,
                    blue: CGFloat(c.b) / CGFloat(c.n) / 255, alpha: 1)
        }
        func distancia(_ a: NSColor, _ b: NSColor) -> CGFloat {
            abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
        }
        var elegidos: [NSColor] = []
        for c in ordenados where elegidos.allSatisfy({ distancia($0, c) > 0.22 }) {
            elegidos.append(c)
            if elegidos.count == 5 { break }
        }
        paletas[r.id] = elegidos
        return elegidos
    }

    static func hex(_ c: NSColor) -> String {
        String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Resplandor radial difuso: un círculo de luz que se desvanece hacia los bordes.
private struct Halo: View {
    let color: Color
    var lado: CGFloat
    var intensidad: Double = 0.5

    var body: some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: color.opacity(intensidad), location: 0),
                .init(color: color.opacity(intensidad * 0.82), location: 0.18),
                .init(color: color.opacity(intensidad * 0.52), location: 0.38),
                .init(color: color.opacity(intensidad * 0.24), location: 0.6),
                .init(color: color.opacity(intensidad * 0.07), location: 0.8),
                .init(color: color.opacity(0), location: 1),
            ], center: .center, startRadius: 0, endRadius: lado / 2))
            .frame(width: lado, height: lado)
            .allowsHitTesting(false)
    }
}

/// Luz de fondo del panel: un resplandor grande del color de lo elegido detrás de la vista previa.
private struct LuzPanel: View {
    let tono: Color

    var body: some View {
        Color.clear
            .overlay {
                Halo(color: tono, lado: 560, intensidad: 0.16).offset(x: 120, y: 260)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .animation(.easeOut(duration: 0.35), value: tono)
            .allowsHitTesting(false)
    }
}

/// Punto de color de un tipo.
private struct Punto: View {
    let color: Color
    var lado: CGFloat = 6

    var body: some View {
        Circle().fill(color)
            .frame(width: lado, height: lado)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}

// MARK: - Cabecera: pestañas y contador

/// Pestañas en píldora (como `Segmentado`) con el punto de color de cada tipo: la leyenda de los colores.
private struct PestanasTipo: View {
    @Binding var valor: EstadoPanel.Filtro

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EstadoPanel.Filtro.allCases, id: \.self) { filtro in
                let activa = filtro == valor
                HStack(spacing: 6) {
                    if let color = Tono.de(filtro) { Punto(color: color, lado: 6) }
                    Text(filtro.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(activa ? Diseno.tinta : Diseno.tintaSuave)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                    if activa { Capsule().fill(.white).shadow(color: Diseno.sombra, radius: 6, y: 2) }
                }
                .contentShape(Capsule())
                .onTapGesture { withAnimation(.spring(duration: 0.3)) { valor = filtro } }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.32)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8))
    }
}

/// Cuántos recortes hay a la vista: un dial negro con el número fino y un anillo de marcas pintadas por tipo.
private struct Contador: View {
    let lista: [Recorte]
    let estado: EstadoPanel
    let total: Int

    var body: some View {
        let partes = Parte.de(lista)
        HStack(spacing: 12) {
            Dial(numero: lista.count, partes: partes, lado: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(nombre)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Diseno.tinta)
                detalle(partes)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)  // el dial alineado con las miniaturas de la lista
        .padding(.top, 2)
    }

    private var nombre: String {
        let uno = lista.count == 1
        switch estado.filtro {
        case .todo: return uno ? "recorte" : "recortes"
        case .texto: return uno ? "texto" : "textos"
        case .enlaces: return uno ? "enlace" : "enlaces"
        case .imagenes: return uno ? "imagen" : "imágenes"
        case .archivos: return uno ? "archivo" : "archivos"
        case .fijados: return uno ? "fijado" : "fijados"
        }
    }

    @ViewBuilder private func detalle(_ partes: [Parte]) -> some View {
        let consulta = estado.busqueda.trimmingCharacters(in: .whitespaces)
        if !consulta.isEmpty {
            Text("con «\(consulta)» · de \(total)")
                .font(.system(size: 11))
                .foregroundStyle(Diseno.tintaSuave)
                .lineLimit(1)
        } else if estado.filtro == .todo || estado.filtro == .fijados, !partes.isEmpty {
            ViewThatFits(in: .horizontal) {
                leyenda(partes, conNombre: true)
                leyenda(partes, conNombre: false)
            }
        } else {
            Text(total == lista.count ? "en el historial" : "de \(total) en el historial")
                .font(.system(size: 11))
                .foregroundStyle(Diseno.tintaSuave)
        }
    }

    private func leyenda(_ partes: [Parte], conNombre: Bool) -> some View {
        HStack(spacing: 9) {
            ForEach(partes) { p in
                HStack(spacing: 4) {
                    Punto(color: p.color, lado: 5)
                    Text(conNombre ? Formato.cantidad(p.cuenta, p.tipo) : "\(p.cuenta)")
                        .font(.system(size: 11))
                        .foregroundStyle(Diseno.tintaSuave)
                        .fixedSize()
                }
            }
        }
    }
}

/// Cuántos recortes hay de cada tipo, en el orden de los colores.
private struct Parte: Identifiable {
    let tipo: Recorte.Tipo
    let cuenta: Int
    var id: Recorte.Tipo { tipo }
    var color: Color { Tono.de(tipo) }

    static func de(_ rs: [Recorte]) -> [Parte] {
        let conteo = Dictionary(grouping: rs, by: \.tipo).mapValues(\.count)
        return [Recorte.Tipo.imagen, .texto, .enlace, .archivo].compactMap { t in conteo[t].map { Parte(tipo: t, cuenta: $0) } }
    }
}

/// Dial: círculo negro con el número en trazo fino, un anillo de marcas finas (cada tramo con el color de su tipo)
/// y, detrás, un resplandor de cada color hacia el lado donde están sus marcas.
private struct Dial: View {
    let numero: Int
    let partes: [Parte]
    var lado: CGFloat = 54

    var body: some View {
        let total = Double(max(partes.reduce(0) { $0 + $1.cuenta }, 1))
        let tramos = partes.reduce(into: [(parte: Parte, desde: Double, hasta: Double)]()) { acc, p in
            let desde = acc.last?.hasta ?? 0
            acc.append((p, desde, desde + Double(p.cuenta) / total))
        }
        ZStack {
            Marcas(desde: 0, hasta: 1).stroke(Diseno.tinta.opacity(0.12), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            ForEach(tramos, id: \.parte.id) { t in
                Marcas(desde: t.desde, hasta: t.hasta)
                    .stroke(t.parte.color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
                .frame(width: lado - 18, height: lado - 18)
                .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
            Text("\(numero)")
                .font(.system(size: (lado - 18) * 0.46, weight: .thin))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .frame(width: lado - 24)
        }
        .frame(width: lado, height: lado)
        .background {
            ZStack {
                ForEach(tramos, id: \.parte.id) { t in
                    let medio = CGFloat((t.desde + t.hasta) / 2 * 2 * .pi - .pi / 2)
                    Halo(color: t.parte.color, lado: lado * 1.5, intensidad: 0.42)
                        .offset(x: cos(medio) * lado * 0.22, y: sin(medio) * lado * 0.22)
                }
            }
            .frame(width: lado, height: lado)
        }
    }
}

/// Marcas finas alrededor de un círculo, solo en el tramo [desde, hasta) de la vuelta (empieza arriba, sentido horario).
private struct Marcas: Shape {
    var desde: Double
    var hasta: Double
    var total = 48
    var largo: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let externo = min(rect.width, rect.height) / 2 - 1
        for i in 0..<total {
            let f = (Double(i) + 0.5) / Double(total)
            guard f >= desde, f < hasta else { continue }
            let a = CGFloat(f * 2 * .pi - .pi / 2)
            p.move(to: CGPoint(x: c.x + cos(a) * (externo - largo), y: c.y + sin(a) * (externo - largo)))
            p.addLine(to: CGPoint(x: c.x + cos(a) * externo, y: c.y + sin(a) * externo))
        }
        return p
    }
}

/// Clics y arrastre por AppKit (el render de prueba no puede dibujar vistas de AppKit).
private struct Interaccion: ViewModifier {
    let id: UUID
    let control: Portapapeles?
    let simulado: Bool

    func body(content: Content) -> some View {
        if simulado || control == nil {
            content
        } else {
            content.overlay(ZonaInteractiva(
                alClic: { mods, clics in control?.clic(id, modificadores: mods, clics: clics) },
                alArrastrar: { control?.arrastre(desde: id) ?? ([], nil) }))
        }
    }
}

// MARK: - Lista

private struct ListaRecortes: View {
    let lista: [Recorte]
    let estado: EstadoPanel
    let historial: Historial
    let control: Portapapeles?
    var simulado = false

    var body: some View {
        if simulado {  // ImageRenderer no dibuja ScrollView
            filas.frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView { filas }
                    .scrollIndicators(.never)
                    .onChange(of: estado.seleccion) {
                        if let s = estado.seleccion {
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(s, anchor: .center) }
                        }
                    }
            }
        }
    }

    private var filas: some View {
        let numeros = Dictionary(uniqueKeysWithValues: lista.prefix(9).enumerated().map { ($1.id, $0 + 1) })
        let varios = estado.marcados.count > 1
        return LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(secciones, id: \.titulo) { seccion in
                EtiquetaSeccion(titulo: seccion.titulo)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                ForEach(seccion.recortes) { r in
                    Fila(recorte: r, historial: historial, cursor: r.id == estado.seleccion,
                         marcado: varios && estado.marcados.contains(r.id), numero: numeros[r.id])
                        .id(r.id)
                        .modifier(Interaccion(id: r.id, control: control, simulado: simulado))
                }
            }
            if lista.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 24, weight: .light)).foregroundStyle(Diseno.tintaTenue)
                    Text("Nada por aquí").font(.system(size: 13)).foregroundStyle(Diseno.tintaSuave)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        }
        .padding(.bottom, 6)
    }

    /// Fijados, Hoy, Ayer, Esta semana, Antes.
    private var secciones: [(titulo: String, recortes: [Recorte])] {
        let cal = Calendar.current
        func grupo(_ r: Recorte) -> String {
            if r.fijado { return "Fijados" }
            if cal.isDateInToday(r.fecha) { return "Hoy" }
            if cal.isDateInYesterday(r.fecha) { return "Ayer" }
            if let dias = cal.dateComponents([.day], from: r.fecha, to: Date()).day, dias < 7 { return "Esta semana" }
            return "Antes"
        }
        var resultado: [(titulo: String, recortes: [Recorte])] = []
        for r in simulado ? Array(lista.prefix(7)) : lista {  // el render no tiene scroll
            let g = grupo(r)
            if resultado.last?.titulo == g {
                resultado[resultado.count - 1].recortes.append(r)
            } else {
                resultado.append((g, [r]))
            }
        }
        return resultado
    }
}

private struct Fila: View {
    let recorte: Recorte
    let historial: Historial
    let cursor: Bool
    let marcado: Bool
    let numero: Int?

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let tono = Tono.de(recorte, historial)
        HStack(spacing: 11) {
            Miniatura(recorte: recorte, historial: historial, lado: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(recorte.titulo)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Diseno.tinta)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Punto(color: tono, lado: 5)
                    Text([recorte.app, Formato.relativo(recorte.fecha)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(Diseno.tintaSuave)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if recorte.fijado {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Diseno.tintaTenue)
            }
            if marcado {
                Marca()
            } else if let numero {
                HStack(spacing: 1) {
                    if cursor { Text("⌘").font(.system(size: 10, weight: .medium)) }
                    Text("\(numero)").font(.system(size: 17, weight: .thin)).monospacedDigit()
                }
                .foregroundStyle(cursor ? Diseno.tintaSuave : Diseno.tintaTenue.opacity(0.8))
                .frame(minWidth: 22, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if cursor {
                // Tarjeta blanca con el color del recorte encendido detrás de su miniatura.
                forma.fill(Color.white)
                    .overlay(alignment: .leading) { Halo(color: tono, lado: 150, intensidad: 0.45).offset(x: -50) }
                    .clipShape(forma)
                    .overlay(forma.strokeBorder(.white, lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
                    .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            } else if marcado {
                forma.fill(Color.white.opacity(0.55))
                    .overlay(alignment: .leading) { Halo(color: tono, lado: 120, intensidad: 0.18).offset(x: -40) }
                    .clipShape(forma)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Marca de elegido: círculo negro con el visto blanco (el mismo negro del dial y del botón de pegar).
private struct Marca: View {
    var lado: CGFloat = 18

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: lado * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: lado, height: lado)
            .background(Circle().fill(Diseno.tinta))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// Miniatura de la imagen, ícono de la app de origen sobre una baldosa blanca o el símbolo del tipo.
private struct Miniatura: View {
    let recorte: Recorte
    let historial: Historial
    let lado: CGFloat
    @MainActor private static var iconos: [String: NSImage] = [:]

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: lado * 0.28, style: .continuous)
        Group {
            if let mini = historial.miniatura(de: recorte) {
                Image(nsImage: mini).resizable().scaledToFill()
            } else if let icono = Self.icono(recorte.appID) {
                Image(nsImage: icono).resizable().padding(lado * 0.12)
                    .background(Color.white.opacity(0.8))
            } else {
                Image(systemName: recorte.simbolo)
                    .font(.system(size: lado * 0.38, weight: .medium))
                    .foregroundStyle(Tono.de(recorte.tipo))
                    .frame(width: lado, height: lado)
                    .background(Color.white.opacity(0.75))
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(forma)
        .overlay(forma.strokeBorder(Color.white.opacity(0.9), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    @MainActor static func icono(_ id: String?) -> NSImage? {
        guard let id else { return nil }
        if let i = iconos[id] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        // Copia en mapa de bits de 64 px: más liviana que el ícono multirresolución de macOS.
        let original = NSWorkspace.shared.icon(forFile: url.path)
        let i = NSImage(size: NSSize(width: 64, height: 64))
        i.lockFocus()
        original.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        i.unlockFocus()
        iconos[id] = i
        return i
    }
}

// MARK: - Cuadrícula de imágenes

private struct RejillaImagenes: View {
    let lista: [Recorte]
    let estado: EstadoPanel
    let historial: Historial
    let control: Portapapeles?
    var simulado = false

    var body: some View {
        let celdas = LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(lista) { r in
                Celda(recorte: r, historial: historial, cursor: r.id == estado.seleccion,
                      marcado: estado.marcados.count > 1 && estado.marcados.contains(r.id))
                    .id(r.id)
                    .modifier(Interaccion(id: r.id, control: control, simulado: simulado))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        if simulado {
            celdas.frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView { celdas }
                    .scrollIndicators(.never)
                    .onChange(of: estado.seleccion) {
                        if let s = estado.seleccion { proxy.scrollTo(s, anchor: .center) }
                    }
            }
        }
    }

    private struct Celda: View {
        let recorte: Recorte
        let historial: Historial
        let cursor: Bool
        let marcado: Bool

        var body: some View {
            let forma = RoundedRectangle(cornerRadius: 16, style: .continuous)
            let tono = Tono.de(recorte, historial)
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let mini = historial.miniatura(de: recorte) {
                            Image(nsImage: mini).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.4).overlay(Image(systemName: "photo").foregroundStyle(Diseno.tintaTenue))
                        }
                    }
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .clipShape(forma)
                    if marcado { Marca(lado: 20).padding(7) }
                }
                .overlay(forma.strokeBorder(Color.white, lineWidth: cursor ? 3 : 0.8))
                // Sombra del color de la propia imagen: la foto parece iluminar el vidrio.
                .shadow(color: tono.opacity(cursor ? 0.55 : 0.30), radius: cursor ? 14 : 8, y: cursor ? 8 : 5)
                HStack(spacing: 5) {
                    Text("\(recorte.ancho ?? 0) × \(recorte.alto ?? 0)")
                        .font(.system(size: 12, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Diseno.tinta.opacity(0.75))
                    Text(Formato.relativo(recorte.fecha))
                        .font(.system(size: 10))
                        .foregroundStyle(Diseno.tintaTenue)
                }
                .lineLimit(1)
                .padding(.leading, 4)
            }
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Tarjeta de vista previa y acciones

private struct TarjetaPrevia: View {
    let elegidos: [Recorte]
    let tono: Color
    let historial: Historial
    let estado: EstadoPanel
    let control: Portapapeles?
    let simulado: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if elegidos.count > 1 {
                Moodboard(recortes: elegidos, historial: historial, estado: estado)
            } else if let r = elegidos.first {
                cabecera(r)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                Contenido(recorte: r, tono: tono, historial: historial, simulado: simulado)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Datos(recorte: r, historial: historial)
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 30, weight: .light)).foregroundStyle(Diseno.tintaTenue)
                    Text("Lo que copies aparecerá aquí").font(.system(size: 13)).foregroundStyle(Diseno.tintaSuave)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !elegidos.isEmpty { pildoras.padding(16) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                forma.fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.10), radius: 24, y: 12)
                    .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
                Color.clear
                    .overlay(alignment: .bottomLeading) {
                        ZStack {
                            Halo(color: elegidos.first.map { Tono.par($0.tipo) } ?? Tono.archivo, lado: 400, intensidad: 0.42)
                                .offset(x: 210, y: 50)
                            Halo(color: tono, lado: 440, intensidad: 0.70)
                        }
                        .frame(width: 440, height: 440)
                        .offset(x: -130, y: 180)
                    }
                    .clipShape(forma)
                    .animation(.easeOut(duration: 0.3), value: tono)
            }
        }
        .overlay(forma.strokeBorder(LinearGradient(colors: [.white.opacity(0.98), .white.opacity(0.35)], startPoint: .top, endPoint: .bottom),
                                    lineWidth: 1))
    }

    /// Origen (app, hora, página) y el tipo con su color; a la derecha, las acciones secundarias en círculos.
    private func cabecera(_ r: Recorte) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let icono = Miniatura.icono(r.appID) {
                    Image(nsImage: icono).resizable().frame(width: 30, height: 30)
                } else {
                    Image(systemName: r.simbolo).font(.system(size: 13, weight: .medium)).foregroundStyle(Tono.de(r.tipo))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.white))
                }
            }
            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.app ?? "Copiado").font(.system(size: 13, weight: .semibold)).foregroundStyle(Diseno.tinta)
                    Text(Formato.relativo(r.fecha)).font(.system(size: 12)).foregroundStyle(Diseno.tintaSuave)
                }
                .lineLimit(1)
                HStack(spacing: 6) {
                    Punto(color: Tono.de(r.tipo), lado: 6)
                    Text(Formato.etiqueta(r))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Diseno.tintaSuave)
                    if let origen = r.origen, let host = URL(string: origen)?.host() {
                        Text("·  \(host)").font(.system(size: 11)).foregroundStyle(Diseno.tintaSuave)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            circulos
        }
    }

    /// Acciones secundarias en botones circulares, arriba a la derecha (como el menú de Notas de visionOS).
    private var circulos: some View {
        let hayTexto = elegidos.contains { $0.tipo == .texto || $0.tipo == .enlace }
        let abrible = elegidos.contains { $0.tipo == .enlace || $0.tipo == .archivo }
        let fijados = elegidos.allSatisfy(\.fijado)
        return HStack(spacing: 6) {
            Redondo(simbolo: fijados ? "pin.fill" : "pin", activo: fijados, ayuda: "Fijar (⌘P)") { control?.fijar() }
            if hayTexto {
                Redondo(simbolo: "tray.and.arrow.down", ayuda: "Mandar a _inbox (⌘I)") { control?.aInbox() }
            }
            if abrible {
                Redondo(simbolo: "arrow.up.forward", ayuda: "Abrir (⌘O)") { control?.abrirSeleccion() }
            }
            Redondo(simbolo: "trash", ayuda: "Borrar (⌘⌫)") { control?.borrar() }
        }
    }

    private var pildoras: some View {
        let n = elegidos.count
        let hayTexto = elegidos.contains { $0.tipo == .texto || $0.tipo == .enlace }
        return HStack(spacing: 8) {
            BotonPegar(titulo: n > 1 ? "Pegar \(n) en \(estado.appDestino)" : "Pegar en \(estado.appDestino)") { control?.pegar() }
                .fixedSize()
                .layoutPriority(1)
            if hayTexto {
                PildoraClara(titulo: "Limpio", teclas: "⌥↩") { control?.pegar(limpio: true) }.fixedSize()
            }
            PildoraClara(titulo: "Copiar", teclas: "⌘C") { control?.copiar() }.fixedSize()
            Spacer(minLength: 0)
            if n > 1 {
                Redondo(simbolo: "trash", ayuda: "Borrar (⌘⌫)") { control?.borrar() }
            }
        }
    }
}

/// Acción principal: píldora negra con la tecla ↩ en un círculo blanco al final.
private struct BotonPegar: View {
    let titulo: String
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 10) {
                Text(titulo).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("↩")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Diseno.tinta)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom)))
            }
            .foregroundStyle(.white)
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .frame(height: 38)
            .background(Capsule().fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
                                            lineWidth: 0.8))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Pegar (↩)")
    }
}

/// Botón redondo para la tarjeta clara: blanco en relieve; el activo (fijado), negro como el dial.
private struct Redondo: View {
    let simbolo: String
    var activo = false
    var lado: CGFloat = 32
    var ayuda = ""
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: lado * 0.38, weight: .medium))
                .foregroundStyle(activo ? Color.white : Diseno.tinta.opacity(0.72))
                .frame(width: lado, height: lado)
                .background(Circle().fill(LinearGradient(colors: activo ? [Color(white: 0.22), Color(white: 0.05)] : [.white, Color(white: 0.94)],
                                                         startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(activo ? Color.white.opacity(0.2) : Color.white, lineWidth: 0.8))
                .shadow(color: .black.opacity(activo ? 0.22 : 0.10), radius: 5, y: 2.5)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
    }
}

/// Píldora secundaria para la tarjeta clara: blanca en relieve, con su atajo en gris.
private struct PildoraClara: View {
    let titulo: String
    let teclas: String
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                Text(titulo).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(teclas).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Diseno.tintaTenue)
            }
            .foregroundStyle(Diseno.tinta)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.75)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(.white, lineWidth: 0.8))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Un dato con el número grande en trazo fino y su nombre debajo.
private struct Dato: View {
    let valor: String
    let nombre: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(valor)
                .font(.system(size: 26, weight: .thin))
                .monospacedDigit()
                .foregroundStyle(Diseno.tinta)
                .lineLimit(1)
            Text(nombre)
                .font(.system(size: 10.5))
                .foregroundStyle(Diseno.tintaSuave)
        }
    }
}

/// Los números del recorte: palabras y caracteres de un texto, tamaño y proporción de una imagen
/// (con su paleta), cantidad y peso de los archivos.
private struct Datos: View {
    let recorte: Recorte
    let historial: Historial

    var body: some View {
        let datos = Formato.datos(recorte)
        let paleta = recorte.tipo == .imagen ? Tono.paleta(recorte, historial) : []
        if !datos.isEmpty || !paleta.isEmpty {
            HStack(alignment: .bottom, spacing: 26) {
                ForEach(datos, id: \.nombre) { d in Dato(valor: d.valor, nombre: d.nombre) }
                Spacer(minLength: 0)
                if !paleta.isEmpty {
                    VStack(alignment: .trailing, spacing: 5) {
                        HStack(spacing: -5) {
                            ForEach(Array(paleta.enumerated()), id: \.offset) { _, c in
                                Circle().fill(Color(nsColor: c))
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                    .shadow(color: Color(nsColor: c).opacity(0.5), radius: 4, y: 2)
                                    .help(Tono.hex(c))
                            }
                        }
                        Text("paleta").font(.system(size: 10.5)).foregroundStyle(Diseno.tintaSuave)
                    }
                }
            }
        }
    }
}

private struct Contenido: View {
    let recorte: Recorte
    let tono: Color
    let historial: Historial
    let simulado: Bool

    var body: some View {
        let r = recorte
        switch r.tipo {
        case .texto:
            let codigo = Formato.pareceCodigo(r.texto)
            let cuerpo =
                VStack(alignment: .leading, spacing: 14) {
                    if let color = Formato.colorHex(r.texto) {
                        ZStack {
                            Halo(color: color, lado: 190, intensidad: 0.55)
                            Circle().fill(color).frame(width: 84, height: 84)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                                .shadow(color: color.opacity(0.5), radius: 12, y: 6)
                        }
                        .frame(width: 110, height: 110)
                    }
                    if codigo {
                        Text(r.texto)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Diseno.tinta)
                            .lineSpacing(3)
                            .modifier(Seleccionable(activo: !simulado))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Diseno.tinta.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Diseno.tinta.opacity(0.06), lineWidth: 0.6))
                    } else {
                        Text(r.texto)
                            .font(.system(size: Formato.tamanoLectura(r.texto)))
                            .foregroundStyle(Diseno.tinta)
                            .lineSpacing(4)
                            .modifier(Seleccionable(activo: !simulado))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            // El pie se desvanece para que un texto largo no termine en seco contra los datos.
            let desvanecido = LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                                     .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
            Group {
                if simulado {
                    cuerpo.frame(maxHeight: .infinity, alignment: .top).clipped()
                } else {
                    ScrollView { cuerpo }.scrollIndicators(.never)
                }
            }
            .mask(desvanecido)
        case .enlace:
            let url = URL(string: r.texto.trimmingCharacters(in: .whitespacesAndNewlines))
            let partes = Formato.partesURL(url)
            VStack(alignment: .leading, spacing: 12) {
                Text(Formato.dominio(url) ?? r.texto)
                    .font(.system(size: 34, weight: .thin))
                    .foregroundStyle(Diseno.tinta)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(r.texto)
                    .font(.system(size: 13))
                    .foregroundStyle(Diseno.tintaSuave)
                    .modifier(Seleccionable(activo: !simulado))
                    .lineLimit(4)
                if !partes.ruta.isEmpty || !partes.parametros.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !partes.ruta.isEmpty {
                            HStack(spacing: 8) {
                                EtiquetaSeccion(titulo: "Ruta").frame(width: 78, alignment: .leading)
                                Text(partes.ruta.joined(separator: "  ›  "))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Diseno.tinta.opacity(0.8))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        if !partes.parametros.isEmpty {
                            HStack(spacing: 8) {
                                EtiquetaSeccion(titulo: "Parámetros").frame(width: 78, alignment: .leading)
                                HStack(spacing: 6) {
                                    ForEach(partes.parametros.prefix(3), id: \.self) { Ficha(texto: $0) }
                                    if partes.parametros.count > 3 { Ficha(texto: "+\(partes.parametros.count - 3)") }
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        case .imagen:
            if let imagen = historial.imagen(de: r) {
                // El resplandor va de fondo para no ocupar espacio: la imagen manda en el tamaño.
                Image(nsImage: imagen)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white, lineWidth: 2))
                    .shadow(color: tono.opacity(0.45), radius: 18, y: 10)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                    .background { Halo(color: tono, lado: 420, intensidad: 0.42) }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .archivo:
            let rutas = r.texto.split(separator: "\n").map(String.init)
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Halo(color: tono, lado: 200, intensidad: 0.45)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: rutas.first ?? ""))
                        .resizable().frame(width: 76, height: 76)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 4)
                }
                .frame(width: 96, height: 96)
                Text(r.titulo).font(.system(size: 20, weight: .semibold)).foregroundStyle(Diseno.tinta).lineLimit(2)
                ForEach(rutas.prefix(4), id: \.self) { ruta in
                    Text((ruta as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Diseno.tintaSuave)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }
}

/// Dato corto en píldora gris, para la tarjeta clara (los `Chip` de vidrio se pierden sobre el blanco).
private struct Ficha: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Diseno.tinta.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Diseno.tinta.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Diseno.tinta.opacity(0.06), lineWidth: 0.6))
    }
}

private struct Seleccionable: ViewModifier {
    let activo: Bool
    func body(content: Content) -> some View {
        if activo { content.textSelection(.enabled) } else { content }
    }
}

/// Varios elegidos: cuántos en número fino, las fotos apiladas como un moodboard (cada una con su luz) y los textos.
private struct Moodboard: View {
    let recortes: [Recorte]
    let historial: Historial
    let estado: EstadoPanel

    var body: some View {
        let imagenes = recortes.filter { $0.tipo == .imagen }
        let otros = recortes.filter { $0.tipo != .imagen }
        let giros: [Double] = [-7, 5, -2, 8]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(recortes.count)")
                    .font(.system(size: 56, weight: .thin))
                    .monospacedDigit()
                    .foregroundStyle(Diseno.tinta)
                VStack(alignment: .leading, spacing: 4) {
                    Text("elegidos").font(.system(size: 15, weight: .medium)).foregroundStyle(Diseno.tinta)
                    HStack(spacing: 9) {
                        ForEach(Parte.de(recortes)) { p in
                            HStack(spacing: 4) {
                                Punto(color: p.color, lado: 5)
                                Text(Formato.cantidad(p.cuenta, p.tipo)).font(.system(size: 11)).foregroundStyle(Diseno.tintaSuave)
                            }
                        }
                    }
                }
                Spacer()
                Redondo(simbolo: "xmark", ayuda: "Quitar la selección (Esc)") { estado.marcados = [] }
            }
            if !imagenes.isEmpty {
                ZStack {
                    ForEach(Array(imagenes.prefix(4).enumerated()), id: \.offset) { i, r in
                        Halo(color: Tono.de(r, historial), lado: 260, intensidad: 0.30)
                            .offset(x: Double(i) * 34 - 50, y: Double(i % 2) * 10 + 10)
                    }
                    ForEach(Array(imagenes.prefix(4).enumerated()), id: \.offset) { i, r in
                        Group {
                            if let mini = historial.miniatura(de: r) {
                                Image(nsImage: mini).resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.5)
                            }
                        }
                        .frame(width: 210, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white, lineWidth: 3))
                        .shadow(color: Tono.de(r, historial).opacity(0.35), radius: 14, y: 8)
                        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                        .rotationEffect(.degrees(giros[i % giros.count]))
                        .offset(x: Double(i) * 34 - 50, y: Double(i % 2) * 10)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(otros.prefix(5)) { r in
                    HStack(spacing: 8) {
                        Punto(color: Tono.de(r.tipo), lado: 6)
                        Text(r.titulo).font(.system(size: 13)).foregroundStyle(Diseno.tinta).lineLimit(1)
                    }
                }
                if otros.count > 5 {
                    Text("y \(otros.count - 5) más").font(.system(size: 12)).foregroundStyle(Diseno.tintaSuave).padding(.leading, 14)
                }
            }
            Spacer(minLength: 0)
            Text("Las imágenes se pegan como imágenes separadas y los textos se unen. También puedes arrastrarlos.")
                .font(.system(size: 11))
                .foregroundStyle(Diseno.tintaSuave)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum Formato {
    @MainActor private static let relativoES: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es")
        f.unitsStyle = .short
        return f
    }()

    @MainActor static func relativo(_ fecha: Date) -> String {
        Date().timeIntervalSince(fecha) < 60 ? "ahora" : relativoES.localizedString(for: fecha, relativeTo: Date())
    }

    static func fecha(_ fecha: Date) -> String {
        fecha.formatted(.dateTime.locale(Locale(identifier: "es")).day().month(.abbreviated).hour().minute())
    }

    static func cantidad(_ n: Int, _ tipo: Recorte.Tipo) -> String {
        let (uno, varios): (String, String) = switch tipo {
        case .imagen: ("imagen", "imágenes")
        case .texto: ("texto", "textos")
        case .enlace: ("enlace", "enlaces")
        case .archivo: ("archivo", "archivos")
        }
        return "\(n) \(n == 1 ? uno : varios)"
    }

    /// Tipo del recorte en mayúsculas para la cabecera de la vista previa.
    static func etiqueta(_ r: Recorte) -> String {
        var partes: [String]
        switch r.tipo {
        case .texto: partes = [colorHex(r.texto) != nil ? "COLOR" : pareceCodigo(r.texto) ? "CÓDIGO" : "TEXTO"]
        case .enlace: partes = ["ENLACE"]
        case .imagen: partes = ["IMAGEN"]
        case .archivo: partes = [r.texto.split(separator: "\n").count == 1 ? "ARCHIVO" : "ARCHIVOS"]
        }
        if r.conFormato { partes.append("CON FORMATO") }
        if r.fijado { partes.append("FIJADO") }
        return partes.joined(separator: " · ")
    }

    private static let numeroES: Locale = Locale(identifier: "es")

    /// Los números que acompañan la vista previa (valor en grande, nombre debajo).
    static func datos(_ r: Recorte) -> [(valor: String, nombre: String)] {
        switch r.tipo {
        case .texto:
            if let v = valorHex(r.texto) {
                return [("\((v >> 16) & 0xFF)", "rojo"), ("\((v >> 8) & 0xFF)", "verde"), ("\(v & 0xFF)", "azul")]
            }
            let palabras = r.texto.split { $0.isWhitespace || $0.isNewline }.count
            let lineas = r.texto.split(whereSeparator: \.isNewline).count
            if pareceCodigo(r.texto) {
                return [(miles(lineas), lineas == 1 ? "línea" : "líneas"), (miles(r.texto.count), "caracteres")]
            }
            var d = [(miles(palabras), palabras == 1 ? "palabra" : "palabras"), (miles(r.texto.count), "caracteres")]
            if lineas > 1 { d.append((miles(lineas), "líneas")) }
            return d
        case .enlace:
            return []
        case .imagen:
            let (w, h) = (r.ancho ?? 0, r.alto ?? 0)
            guard w > 0, h > 0 else { return [] }
            let mp = Double(w * h) / 1_000_000
            return [("\(w) × \(h)", "píxeles"), (proporcion(w, h), "proporción"),
                    (mp.formatted(.number.precision(.fractionLength(mp < 10 ? 1 : 0)).locale(numeroES)), "megapíxeles")]
        case .archivo:
            let rutas = r.texto.split(separator: "\n").map(String.init)
            var d = [("\(rutas.count)", rutas.count == 1 ? "archivo" : "archivos")]
            let bytes = rutas.compactMap { (try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.fileSizeKey]))?.fileSize }
            if !bytes.isEmpty {
                d.append((ByteCountFormatter.string(fromByteCount: Int64(bytes.reduce(0, +)), countStyle: .file), "en total"))
            }
            let extensiones = Set(rutas.map { URL(fileURLWithPath: $0).pathExtension.uppercased() })
            if extensiones.count == 1, let ext = extensiones.first, !ext.isEmpty { d.append((ext, "tipo")) }
            return d
        }
    }

    private static func miles(_ n: Int) -> String { n.formatted(.number.locale(numeroES)) }

    /// 650 × 400 → 13:8; si los términos quedan grandes, en decimal (1,78:1).
    static func proporcion(_ w: Int, _ h: Int) -> String {
        func mcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : mcd(b, a % b) }
        let d = mcd(w, h)
        let (a, b) = (w / d, h / d)
        if a <= 21, b <= 21 { return "\(a):\(b)" }
        return (Double(w) / Double(h)).formatted(.number.precision(.fractionLength(2)).locale(numeroES)) + ":1"
    }

    /// Dominio sin "www." para mostrarlo en grande.
    static func dominio(_ url: URL?) -> String? {
        guard let host = url?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Ruta en pedazos y parámetros "clave = valor" de un enlace.
    static func partesURL(_ url: URL?) -> (ruta: [String], parametros: [String]) {
        guard let url, let comp = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return ([], []) }
        let ruta = comp.path.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        let parametros = (comp.queryItems ?? []).map { item in item.value.map { "\(item.name) = \($0)" } ?? item.name }
        return (ruta, parametros)
    }

    /// Texto corto en grande, como una cita; largo, en tamaño de lectura.
    static func tamanoLectura(_ texto: String) -> CGFloat {
        switch texto.count {
        case ..<140: return 22
        case ..<500: return 17
        default: return 14.5
        }
    }

    static func colorHex(_ texto: String) -> Color? {
        guard let v = valorHex(texto) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    private static func valorHex(_ texto: String) -> UInt32? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return v
    }

    static func pareceCodigo(_ texto: String) -> Bool {
        let señales = ["{", "}", ";", "=>", "func ", "def ", "const ", "</", "$ "]
        return señales.filter { texto.contains($0) }.count >= 2
    }
}
