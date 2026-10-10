import AppKit
import SwiftUI

/// Portapapeles (⌘⌥V) en el lenguaje Halo (ver Halo.swift), en su versión sobria: casi monocromo, blanco con
/// opacidades sobre vidrio oscuro, trazos finos y cifras finas. Arriba: cerrar, búsqueda y pestañas. A la izquierda:
/// un dial con cuántos recortes hay (sus marcas blancas se encienden según la parte del historial a la vista) y la
/// lista o la cuadrícula de imágenes. A la derecha: la vista previa, con sus datos en cifras finas y las acciones.
/// El color de cada tipo (texto violeta, enlace azul, imagen rosa rojizo, archivo ámbar) queda solo en puntos de
/// 5–6 pt en filas y pestañas, y como una luz tenue que sube desde el borde de la vista previa.
/// Medidas en una rejilla de 4/8 pt.
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
        VStack(spacing: 16) {
            cabecera
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
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
                        .foregroundStyle(Halo.texto3)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 320)
                TarjetaPrevia(elegidos: elegidos, historial: historial, estado: estado, control: control, simulado: simulado)
            }
        }
        .padding(16)
        .frame(width: Self.ancho, height: Self.alto)
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
            BotonCirculo(simbolo: "xmark", lado: 36, ayuda: "Cerrar (Esc)") { control?.cerrar() }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Halo.texto3)
                if simulado {  // ImageRenderer no dibuja campos de AppKit
                    Text(estado.busqueda.isEmpty ? "Buscar en el historial" : estado.busqueda)
                        .font(.system(size: 13.5))
                        .foregroundStyle(estado.busqueda.isEmpty ? Halo.texto3 : Halo.texto)
                    Spacer()
                } else {
                    TextField("Buscar en el historial", text: $estado.busqueda)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Halo.texto)
                        .focused($buscando)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.09), lineWidth: 0.5))
            PestanasTipo(valor: $estado.filtro)
        }
    }
}

// MARK: - Tonos

/// El tono de cada tipo de recorte (Halo: base y luz). Solo aparece en los puntos de filas y pestañas y en la luz
/// tenue de la vista previa.
enum TonoRecorte {
    static let texto = Tono.violeta
    static let enlace = Tono.azul
    static let imagen = Tono(base: Color(red: 0.98, green: 0.28, blue: 0.42), claro: Color(red: 1.0, green: 0.64, blue: 0.72))
    static let archivo = Tono.ambar

    static func de(_ tipo: Recorte.Tipo) -> Tono {
        switch tipo {
        case .texto: return texto
        case .enlace: return enlace
        case .imagen: return imagen
        case .archivo: return archivo
        }
    }

    static func de(_ filtro: EstadoPanel.Filtro) -> Tono? {
        switch filtro {
        case .texto: return texto
        case .enlaces: return enlace
        case .imagenes: return imagen
        case .archivos: return archivo
        case .todo, .fijados: return nil
        }
    }

    /// La luz de la vista previa: el color del contenido si lo tiene (una imagen, su color más vivo; un color
    /// copiado, ese color); si no, el de su tipo. Los puntos siempre usan el del tipo.
    @MainActor static func luz(_ r: Recorte, _ h: Historial) -> Tono {
        if r.tipo == .texto, let color = Formato.colorHex(r.texto) { return Tono.de(color) }
        guard r.tipo == .imagen else { return de(r.tipo) }
        guard let vivo = paleta(r, h).first(where: { $0.saturationComponent > 0.12 }) else { return .neutro }
        return Tono.de(Color(nsColor: vivo))
    }

    @MainActor private static var paletas: [UUID: [NSColor]] = [:]

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

/// Punto del color de un tipo, liso y sin brillo: el único lugar fijo del color (filas y pestañas).
private struct PuntoTipo: View {
    let tono: Tono
    var lado: CGFloat = 5

    var body: some View {
        Circle().fill(tono.base).frame(width: lado, height: lado)
    }
}

// MARK: - Cabecera: pestañas y contador

/// Pestañas en píldora (como `Segmentado`, 36 pt de alto) con el punto de cada tipo. La píldora activa se desliza
/// a la pestaña nueva.
private struct PestanasTipo: View {
    @Binding var valor: EstadoPanel.Filtro
    @Namespace private var espacio

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EstadoPanel.Filtro.allCases, id: \.self) { filtro in
                let activa = filtro == valor
                HStack(spacing: 6) {
                    if let tono = TonoRecorte.de(filtro) { PuntoTipo(tono: tono, lado: 6) }
                    Text(filtro.rawValue)
                        .font(.system(size: 12, weight: activa ? .medium : .regular))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(activa ? Halo.texto : Halo.texto2)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background {
                    if activa {
                        Capsule().fill(.white.opacity(0.12))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                            .matchedGeometryEffect(id: "activa", in: espacio)
                    }
                }
                .contentShape(Capsule())
                .onTapGesture { valor = filtro }
            }
        }
        .padding(4)
        .background(Capsule().fill(.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.09), lineWidth: 0.5))
        .animation(Halo.cambio, value: valor)  // también con Tab, que cambia el filtro desde el teclado
    }
}

/// Cuántos recortes hay a la vista: el dial con la cifra fina y, al lado, la cuenta por tipo en texto tenue.
private struct Contador: View {
    let lista: [Recorte]
    let estado: EstadoPanel
    let total: Int

    var body: some View {
        HStack(spacing: 12) {
            DialRecorte(numero: lista.count, parte: Double(lista.count) / Double(max(total, 1)), lado: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(nombre)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Halo.texto)
                detalle
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Halo.texto2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        // Dial de 40 al borde de las tarjetas + 12 = el texto empieza en 52, la misma columna que el de las filas
        // (8 de margen + miniatura de 32 + 12).
        .animation(Halo.cambio, value: lista.map(\.id))
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

    @ViewBuilder private var detalle: some View {
        let consulta = estado.busqueda.trimmingCharacters(in: .whitespaces)
        let partes = Parte.de(lista).map { Formato.cantidad($0.cuenta, $0.tipo) }
        if !consulta.isEmpty {
            Text("con «\(consulta)» · de \(total)")
        } else if estado.filtro == .todo || estado.filtro == .fijados, partes.count > 1 {
            // La cuenta por tipo; si no cabe, los dos primeros y cuántos tipos más.
            ViewThatFits(in: .horizontal) {
                Text(partes.joined(separator: " · "))
                Text((partes.prefix(2) + ["\(partes.count - 2) más"]).joined(separator: " · "))
            }
        } else {
            Text(total == lista.count ? "en el historial" : "de \(total) en el historial")
        }
    }
}

/// Cuántos recortes hay de cada tipo.
private struct Parte: Identifiable {
    let tipo: Recorte.Tipo
    let cuenta: Int
    var id: Recorte.Tipo { tipo }

    static func de(_ rs: [Recorte]) -> [Parte] {
        let conteo = Dictionary(grouping: rs, by: \.tipo).mapValues(\.count)
        return [Recorte.Tipo.imagen, .texto, .enlace, .archivo].compactMap { t in conteo[t].map { Parte(tipo: t, cuenta: $0) } }
    }
}

/// Dial: el disco negro de la isla con la cifra fina y un anillo de marcas blancas de 1 pt. Se encienden según la
/// parte del historial que está a la vista (todo: la vuelta entera; un filtro o una búsqueda: su fracción) y, al
/// cambiar, se encienden o apagan una a una con un resorte.
private struct DialRecorte: View {
    let numero: Int
    let parte: Double
    var lado: CGFloat = 40

    var body: some View {
        let disco = lado - 12
        ZStack {
            MarcasRecorte(desde: parte, hasta: 1)
                .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            MarcasRecorte(desde: 0, hasta: parte)
                .stroke(Color.white.opacity(0.78), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            Disco().frame(width: disco, height: disco)
            Text("\(numero)")
                .font(Halo.cifra(disco * 0.5, .light))  // a 14 pt, el trazo .thin se pierde
                .monospacedDigit()
                .foregroundStyle(Halo.texto)
                .contentTransition(.numericText(value: Double(numero)))
                .minimumScaleFactor(0.6)
                .frame(width: disco - 4)
        }
        .frame(width: lado, height: lado)
    }
}

/// Marcas finas alrededor de un círculo, solo en el tramo [desde, hasta) de la vuelta (empieza arriba, sentido horario).
/// Animable: al moverse los límites, las marcas se encienden o apagan una a una.
private struct MarcasRecorte: Shape {
    var desde: Double
    var hasta: Double
    var total = 48
    var largo: CGFloat = 3.5

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(desde, hasta) }
        set { desde = newValue.first; hasta = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let externo = min(rect.width, rect.height) / 2 - 0.5
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
    @Namespace private var espacio

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
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(secciones, id: \.titulo) { seccion in
                EtiquetaSeccion(titulo: seccion.titulo)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                ForEach(seccion.recortes) { r in
                    Fila(recorte: r, historial: historial, cursor: r.id == estado.seleccion,
                         marcado: varios && estado.marcados.contains(r.id), numero: numeros[r.id], espacio: espacio)
                        .id(r.id)
                        .modifier(Interaccion(id: r.id, control: control, simulado: simulado))
                }
            }
        }
        .padding(.bottom, 8)
        // La tarjeta del cursor se desliza a la fila nueva; las marcas de elegido entran con escala.
        .animation(Halo.cambio, value: estado.seleccion)
        .animation(Halo.cambio, value: estado.marcados)
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

/// Una fila de 48 pt: miniatura de 32, título, el punto de su tipo con la app y la hora, y el número de su atajo
/// (⌘1–9). La del cursor es una tarjeta levantada; las elegidas, una tarjeta tenue con el visto.
private struct Fila: View {
    let recorte: Recorte
    let historial: Historial
    let cursor: Bool
    let marcado: Bool
    let numero: Int?
    let espacio: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            Miniatura(recorte: recorte, historial: historial, lado: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(recorte.titulo)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Halo.texto)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    PuntoTipo(tono: TonoRecorte.de(recorte.tipo), lado: 5)
                    Text([recorte.app, Formato.relativo(recorte.fecha)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(cursor ? Halo.texto2 : Halo.texto3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if recorte.fijado {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Halo.texto3)
            }
            if marcado {
                Marca().transition(.scale(scale: 0.4).combined(with: .opacity))
            } else if let numero {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if cursor { Text("⌘").font(.system(size: 10, weight: .regular)) }
                    Text("\(numero)").font(Halo.cifra(16, .light)).monospacedDigit()
                }
                .foregroundStyle(cursor ? Halo.texto2 : Halo.texto3.opacity(0.7))
                .frame(minWidth: 24, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background {
            if cursor {
                Color.clear.tarjetaHalo(radio: 16, activa: true)
                    .matchedGeometryEffect(id: "cursor", in: espacio)
            } else if marcado {
                Color.clear.tarjetaHalo(radio: 16)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Marca de elegido: círculo blanco sólido con el visto negro (el mismo blanco del botón de pegar).
private struct Marca: View {
    var lado: CGFloat = 16

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: lado * 0.46, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: lado, height: lado)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

/// Miniatura: la imagen, la muestra de un color copiado, el ícono de la app de origen (tal cual: ya trae su forma)
/// o el símbolo del tipo en blanco tenue.
private struct Miniatura: View {
    let recorte: Recorte
    let historial: Historial
    let lado: CGFloat
    @MainActor private static var iconos: [String: NSImage] = [:]

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: lado / 4, style: .continuous)
        if let mini = historial.miniatura(de: recorte) {
            Image(nsImage: mini).resizable().scaledToFill()
                .frame(width: lado, height: lado)
                .clipShape(forma)
                .overlay(forma.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        } else if recorte.tipo == .texto, let color = Formato.colorHex(recorte.texto) {
            // Un color copiado se muestra a sí mismo.
            forma.fill(color)
                .frame(width: lado, height: lado)
                .overlay(forma.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        } else if let icono = Self.icono(recorte.appID) {
            // El dibujo del ícono ocupa ~80 % de su lienzo: se agranda para medir lo mismo que las fotos.
            Image(nsImage: icono).resizable()
                .frame(width: lado * 1.22, height: lado * 1.22)
                .frame(width: lado, height: lado)
        } else {
            Image(systemName: recorte.simbolo)
                .font(.system(size: lado * 0.38, weight: .regular))
                .foregroundStyle(Halo.texto2)
                .frame(width: lado, height: lado)
                .background(forma.fill(.white.opacity(0.06)))
                .overlay(forma.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        }
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
    @Namespace private var espacio

    var body: some View {
        let celdas = LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(lista) { r in
                Celda(recorte: r, historial: historial, cursor: r.id == estado.seleccion,
                      marcado: estado.marcados.count > 1 && estado.marcados.contains(r.id), espacio: espacio)
                    .id(r.id)
                    .modifier(Interaccion(id: r.id, control: control, simulado: simulado))
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .animation(Halo.cambio, value: estado.seleccion)
        .animation(Halo.cambio, value: estado.marcados)
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

    /// Una imagen con su tamaño debajo; la del cursor se levanta en una tarjeta (radio 14 = 10 de la foto + 4).
    private struct Celda: View {
        let recorte: Recorte
        let historial: Historial
        let cursor: Bool
        let marcado: Bool
        let espacio: Namespace.ID

        var body: some View {
            let forma = RoundedRectangle(cornerRadius: 10, style: .continuous)
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let mini = historial.miniatura(de: recorte) {
                            Image(nsImage: mini).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.06).overlay(Image(systemName: "photo").foregroundStyle(Halo.texto3))
                        }
                    }
                    .frame(height: 88)
                    .frame(maxWidth: .infinity)
                    .clipShape(forma)
                    .overlay(forma.strokeBorder(.white.opacity(cursor ? 0.24 : 0.1), lineWidth: 0.5))
                    if marcado { Marca(lado: 18).padding(6).transition(.scale(scale: 0.4).combined(with: .opacity)) }
                }
                HStack(spacing: 6) {
                    Text("\(recorte.ancho ?? 0) × \(recorte.alto ?? 0)")
                        .font(.system(size: 12, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(cursor ? Halo.texto : Halo.texto2)
                    Text(Formato.relativo(recorte.fecha))
                        .font(.system(size: 10))
                        .foregroundStyle(Halo.texto3)
                }
                .lineLimit(1)
                .frame(height: 16)
                .padding(.leading, 2)
            }
            .padding(4)
            .background {
                if cursor {
                    Color.clear.tarjetaHalo(radio: 14, activa: true)
                        .matchedGeometryEffect(id: "cursor", in: espacio)
                }
            }
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Tarjeta de vista previa y acciones

/// La vista previa: tarjeta negra (radio 16, casi concéntrico con el panel: 30 − 16 de margen) con una luz tenue
/// del recorte que sube desde el borde de abajo. Todo va a 20 pt de los bordes. Al cambiar de recorte, el contenido
/// se reemplaza con desenfoque y la luz se funde al tono nuevo.
private struct TarjetaPrevia: View {
    let elegidos: [Recorte]
    let historial: Historial
    let estado: EstadoPanel
    let control: Portapapeles?
    let simulado: Bool

    static let margen: CGFloat = 20

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Halo.radioTarjeta, style: .continuous)
        let primero = elegidos.first
        let tono = primero.map { TonoRecorte.luz($0, historial) }
        // Una imagen o un color no tiñen la tarjeta: su luz es aún más tenue que la de los demás tipos.
        let propia = primero.map { $0.tipo == .imagen || Formato.colorHex($0.texto) != nil } ?? false
        VStack(alignment: .leading, spacing: 0) {
            if elegidos.count > 1 {
                Moodboard(recortes: elegidos, historial: historial, estado: estado)
                    .transition(.blurReplace)
            } else if let r = primero {
                VStack(alignment: .leading, spacing: 0) {
                    cabecera(r)
                    Contenido(recorte: r, historial: historial, simulado: simulado)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 16)
                    Datos(recorte: r, historial: historial)
                        .padding(.top, 16)
                }
                .id(r.id)
                .transition(.blurReplace)
            } else {
                vacia.transition(.blurReplace)
            }
            if !elegidos.isEmpty { pildoras.padding(.top, 16) }
        }
        .padding(Self.margen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if let tono { LuzBorde(tono: tono, fuerza: propia ? 0.12 : 0.16, alto: 0.6).clipShape(forma) }
        }
        .tarjetaHalo(activa: true)
        // Negro debajo: la tarjeta es más oscura que el vidrio del panel.
        .background(forma.fill(.black.opacity(0.55)))
        .animation(Halo.cambio, value: elegidos.map(\.id))
    }

    /// Sin nada elegido: el historial vacío, una búsqueda sin resultados o un filtro sin recortes.
    private var vacia: some View {
        let consulta = estado.busqueda.trimmingCharacters(in: .whitespaces)
        let (simbolo, titulo, detalle): (String, String, String) =
            if !consulta.isEmpty {
                ("magnifyingglass", "Nada con «\(consulta)»", "La búsqueda mira el texto, la app y la página de origen.")
            } else if historial.recortes.isEmpty {
                ("doc.on.clipboard", "Lo que copies aparecerá aquí", "Textos, enlaces, imágenes y archivos, con su app de origen.")
            } else if estado.filtro == .fijados {
                ("pin", "Nada fijado", "Fija un recorte con ⌘P y quedará siempre arriba.")
            } else {
                ("tray", "Nada en \(estado.filtro.rawValue.lowercased())", "Tab cambia de filtro.")
            }
        return VStack(spacing: 8) {
            Image(systemName: simbolo)
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(Halo.texto3)
                .frame(height: 40)
            Text(titulo).font(.system(size: 15, weight: .medium)).foregroundStyle(Halo.texto)
            Text(detalle).font(.system(size: 11.5)).foregroundStyle(Halo.texto3)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Origen (app, hora, tipo, página); a la derecha, las acciones secundarias en círculos de vidrio.
    private func cabecera(_ r: Recorte) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let icono = Miniatura.icono(r.appID) {
                    Image(nsImage: icono).resizable().frame(width: 39, height: 39).frame(width: 32, height: 32)
                } else {
                    Insignia(icono: .simbolo(r.simbolo), tono: .neutro, lado: 32)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(r.app ?? "Copiado").font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto)
                    Text(Formato.relativo(r.fecha)).font(.system(size: 12)).foregroundStyle(Halo.texto3)
                }
                HStack(spacing: 6) {
                    Text(Formato.etiqueta(r))
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Halo.texto2)
                    if let origen = r.origen, let host = URL(string: origen)?.host() {
                        Text("·").foregroundStyle(Halo.texto3)
                        Text(host).font(.system(size: 11)).foregroundStyle(Halo.texto3)
                    }
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            circulos
        }
    }

    /// Acciones secundarias en botones circulares de vidrio; fijar, encendido (blanco) si ya está fijado.
    private var circulos: some View {
        let hayTexto = elegidos.contains { $0.tipo == .texto || $0.tipo == .enlace }
        let abrible = elegidos.contains { $0.tipo == .enlace || $0.tipo == .archivo }
        let fijados = elegidos.allSatisfy(\.fijado)
        return HStack(spacing: 8) {
            BotonCirculo(simbolo: fijados ? "pin.fill" : "pin", activo: fijados, lado: 32, ayuda: "Fijar (⌘P)") { control?.fijar() }
            if hayTexto {
                BotonCirculo(simbolo: "tray.and.arrow.down", lado: 32, ayuda: "Mandar a _inbox (⌘I)") { control?.aInbox() }
            }
            if abrible {
                BotonCirculo(simbolo: "arrow.up.forward", lado: 32, ayuda: "Abrir (⌘O)") { control?.abrirSeleccion() }
            }
            BotonCirculo(simbolo: "trash", lado: 32, ayuda: "Borrar (⌘⌫)") { control?.borrar() }
        }
    }

    /// Pegar es el único botón blanco sólido; Limpio y Copiar, de vidrio (`BotonVidrio`). Todos de 32 pt.
    private var pildoras: some View {
        let n = elegidos.count
        let hayTexto = elegidos.contains { $0.tipo == .texto || $0.tipo == .enlace }
        return HStack(spacing: 8) {
            BotonHalo(titulo: n > 1 ? "Pegar \(n) en \(estado.appDestino)" : "Pegar en \(estado.appDestino)", teclas: "↩", alto: 32) {
                control?.pegar()
            }
            .help("Pegar (↩)")
            .layoutPriority(1)
            if hayTexto {
                BotonVidrio(titulo: "Limpio", teclas: "⌥↩") { control?.pegar(limpio: true) }
                    .help("Pegar sin formato (⌥↩)")
            }
            BotonVidrio(titulo: "Copiar", teclas: "⌘C") { control?.copiar() }
            Spacer(minLength: 0)
            if n > 1 {
                BotonCirculo(simbolo: "trash", lado: 32, ayuda: "Borrar (⌘⌫)") { control?.borrar() }
            }
        }
    }
}

/// Botón secundario en píldora de vidrio, más liviano que `BotonHalo(secundario:)`: letra media, atajo tenue y filo
/// de 0,5 pt. Mide 32 pt y lleva el mismo margen que el principal.
private struct BotonVidrio: View {
    let titulo: String
    let teclas: String
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                Text(titulo).font(.system(size: 13, weight: .medium))
                Text(teclas).font(.system(size: 11.5)).foregroundStyle(Halo.texto3)
            }
            .foregroundStyle(Halo.texto)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Capsule().fill(.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// Un dato: la cifra grande y fina (con su unidad en versalitas si la tiene: "455 KB") y su rótulo debajo.
private struct Dato: View {
    let valor: String
    let nombre: String

    var body: some View {
        let (numero, unidad) = Self.partir(valor)
        VStack(alignment: .leading, spacing: 4) {
            Cifra(numero: numero, unidad: unidad, tamano: 28, color: Halo.texto)
            EtiquetaSeccion(titulo: nombre)
        }
        .fixedSize()
    }

    /// "455 KB" → ("455", "KB"); lo demás ("650 × 400", "13:8", "PDF") va entero.
    private static func partir(_ valor: String) -> (String, String) {
        let partes = valor.split(whereSeparator: \.isWhitespace)
        guard partes.count == 2, partes[0].contains(where: \.isNumber), partes[1].allSatisfy(\.isLetter) else { return (valor, "") }
        return (String(partes[0]), String(partes[1]))
    }
}

/// Los números del recorte: palabras y caracteres de un texto, tamaño y proporción de una imagen
/// (con su paleta), cantidad y peso de los archivos. Si no caben (una foto de 4032 × 3024 con su paleta),
/// se queda con los primeros.
private struct Datos: View {
    let recorte: Recorte
    let historial: Historial

    var body: some View {
        let datos = Formato.datos(recorte)
        let paleta = recorte.tipo == .imagen ? TonoRecorte.paleta(recorte, historial) : []
        if !datos.isEmpty || !paleta.isEmpty {
            ViewThatFits(in: .horizontal) {
                fila(datos, paleta)
                fila(Array(datos.prefix(2)), paleta)
                fila(Array(datos.prefix(2)), [])
            }
        }
    }

    private func fila(_ datos: [(valor: String, nombre: String)], _ paleta: [NSColor]) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(alignment: .bottom, spacing: 24) {
                ForEach(datos, id: \.nombre) { d in Dato(valor: d.valor, nombre: d.nombre) }
            }
            Spacer(minLength: 16)
            if !paleta.isEmpty {
                // La paleta de la imagen: muestras pequeñas, separadas, con filo de 0,5 pt.
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(Array(paleta.enumerated()), id: \.offset) { _, c in
                            Circle().fill(Color(nsColor: c))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                                .help(TonoRecorte.hex(c))
                        }
                    }
                    .frame(height: 16)
                    EtiquetaSeccion(titulo: "Paleta")
                }
                .fixedSize()
            }
        }
    }
}

/// El contenido de un recorte, sin márgenes propios (la tarjeta pone los 20 pt).
private struct Contenido: View {
    let recorte: Recorte
    let historial: Historial
    let simulado: Bool

    var body: some View {
        let r = recorte
        switch r.tipo {
        case .texto:
            let codigo = Formato.pareceCodigo(r.texto)
            let color = Formato.colorHex(r.texto)
            let cuerpo =
                VStack(alignment: .leading, spacing: 16) {
                    if let color {
                        // El color copiado, como una muestra con filo fino.
                        Circle().fill(color)
                            .frame(width: 80, height: 80)
                            .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        Text(r.texto.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                            .font(Halo.cifra(36))
                            .kerning(-0.5)
                            .foregroundStyle(Halo.texto)
                            .modifier(Seleccionable(activo: !simulado))
                    } else if codigo {
                        Text(r.texto)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Halo.texto)
                            .lineSpacing(4)
                            .modifier(Seleccionable(activo: !simulado))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.3)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                    } else {
                        let tamano = Formato.tamanoLectura(r.texto)
                        Text(r.texto)
                            .font(.system(size: tamano, weight: tamano > 20 ? .light : .regular))
                            .foregroundStyle(Halo.texto)
                            .lineSpacing(tamano > 20 ? 4 : 3)
                            .modifier(Seleccionable(activo: !simulado))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            // El pie se desvanece para que un texto largo no termine en seco contra los datos.
            let desvanecido = LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86),
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
            VStack(alignment: .leading, spacing: 8) {
                Text(Formato.dominio(url) ?? r.texto)
                    .font(Halo.cifra(36))
                    .kerning(-0.5)
                    .foregroundStyle(Halo.texto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(r.texto)
                    .font(.system(size: 12))
                    .foregroundStyle(Halo.texto2)
                    .modifier(Seleccionable(activo: !simulado))
                    .lineLimit(4)
                if !partes.ruta.isEmpty || !partes.parametros.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !partes.ruta.isEmpty {
                            HStack(spacing: 8) {
                                EtiquetaSeccion(titulo: "Ruta").frame(width: 88, alignment: .leading)
                                Text(partes.ruta.joined(separator: "  ›  "))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Halo.texto)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(height: 24)
                        }
                        if !partes.parametros.isEmpty {
                            HStack(spacing: 8) {
                                EtiquetaSeccion(titulo: "Parámetros").frame(width: 88, alignment: .leading)
                                HStack(spacing: 4) {
                                    ForEach(partes.parametros.prefix(3), id: \.self) { Chip(texto: $0) }
                                    if partes.parametros.count > 3 { Chip(texto: "+\(partes.parametros.count - 3)") }
                                }
                            }
                            .frame(height: 24)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        case .imagen:
            if let imagen = historial.imagen(de: r) {
                let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
                Image(nsImage: imagen)
                    .resizable()
                    .scaledToFit()
                    .clipShape(forma)
                    .overlay(forma.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .archivo:
            let rutas = r.texto.split(separator: "\n").map(String.init)
            VStack(alignment: .leading, spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: rutas.first ?? ""))
                    .resizable().frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                Text(r.titulo).font(.system(size: 20, weight: .medium)).foregroundStyle(Halo.texto).lineLimit(2)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rutas.prefix(4), id: \.self) { ruta in
                        Text((ruta as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 11.5)).foregroundStyle(Halo.texto3)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
    }
}

private struct Seleccionable: ViewModifier {
    let activo: Bool
    func body(content: Content) -> some View {
        if activo { content.textSelection(.enabled) } else { content }
    }
}

/// Varios elegidos: cuántos en cifra fina (rueda al sumar o quitar), las fotos apiladas como un moodboard y los textos.
private struct Moodboard: View {
    let recortes: [Recorte]
    let historial: Historial
    let estado: EstadoPanel

    var body: some View {
        let imagenes = recortes.filter { $0.tipo == .imagen }
        let otros = recortes.filter { $0.tipo != .imagen }
        let giros: [Double] = [-6, 4, -2, 7]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Cifra(numero: "\(recortes.count)", tamano: 56, color: Halo.texto, valor: Double(recortes.count))
                VStack(alignment: .leading, spacing: 4) {
                    Text("elegidos").font(.system(size: 15, weight: .medium)).foregroundStyle(Halo.texto)
                    Text(Parte.de(recortes).map { Formato.cantidad($0.cuenta, $0.tipo) }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(Halo.texto2)
                        .lineLimit(1)
                }
                Spacer()
                BotonCirculo(simbolo: "xmark", lado: 32, ayuda: "Quitar la selección (Esc)") { estado.marcados = [] }
            }
            if !imagenes.isEmpty {
                ZStack {
                    ForEach(Array(imagenes.prefix(4).enumerated()), id: \.element.id) { i, r in
                        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
                        Group {
                            if let mini = historial.miniatura(de: r) {
                                Image(nsImage: mini).resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.06)
                            }
                        }
                        .frame(width: 200, height: 132)
                        .clipShape(forma)
                        .overlay(forma.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                        .rotationEffect(.degrees(giros[i % giros.count]))
                        .offset(x: Double(i) * 32 - 48, y: Double(i % 2) * 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(otros.prefix(5)) { r in
                    HStack(spacing: 8) {
                        PuntoTipo(tono: TonoRecorte.de(r.tipo), lado: 5)
                        Text(r.titulo).font(.system(size: 13)).foregroundStyle(Halo.texto).lineLimit(1)
                    }
                }
                if otros.count > 5 {
                    Text("y \(otros.count - 5) más").font(.system(size: 12)).foregroundStyle(Halo.texto2).padding(.leading, 13)
                }
            }
            Spacer(minLength: 0)
            Text("Las imágenes se pegan como imágenes separadas y los textos se unen. También puedes arrastrarlos.")
                .font(.system(size: 11))
                .foregroundStyle(Halo.texto3)
        }
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
