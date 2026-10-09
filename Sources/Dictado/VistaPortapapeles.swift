import AppKit
import SwiftUI

/// Portapapeles (⌘⌥V) en vidrio claro: arriba cerrar + búsqueda + pestañas; a la izquierda la lista
/// (o cuadrícula de imágenes); a la derecha una tarjeta con la vista previa y los botones de acción.
struct VistaPortapapeles: View {
    static let ancho: CGFloat = 880
    static let alto: CGFloat = 540

    let historial: Historial
    @Bindable var estado: EstadoPanel
    let control: Portapapeles?
    var simulado = false
    @FocusState private var buscando: Bool

    private var lista: [Recorte] { Portapapeles.filtrar(historial.recortes, estado) }
    private var seleccionado: Recorte? { historial.recortes.first { $0.id == estado.seleccion } }
    private var elegidos: [Recorte] { Portapapeles.elegidos(lista, estado, seleccionado) }

    var body: some View {
        VStack(spacing: 14) {
            cabecera
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
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
        estado.seleccion = lista.first?.id
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
                    Text("Buscar en \(historial.recortes.count) recortes").font(.system(size: 14)).foregroundStyle(Diseno.tintaTenue)
                    Spacer()
                } else {
                    TextField("Buscar en \(historial.recortes.count) recortes", text: $estado.busqueda)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($buscando)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(Color.white.opacity(0.5)))
            .overlay(Capsule().strokeBorder(Diseno.borde, lineWidth: 0.8))
            if estado.marcados.count > 1 {
                Button { estado.marcados = [] } label: {
                    Chip(texto: "\(estado.marcados.count) elegidos  ✕", simbolo: "checkmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            Segmentado(opciones: EstadoPanel.Filtro.allCases.map { ($0, $0.rawValue) }, valor: $estado.filtro)
        }
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
                    .padding(.top, 12)
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
                    Image(systemName: "tray").font(.system(size: 24)).foregroundStyle(Diseno.tintaTenue)
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
        HStack(spacing: 11) {
            Miniatura(recorte: recorte, historial: historial, lado: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(recorte.titulo)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Diseno.tinta)
                    .lineLimit(1)
                Text([recorte.app, Formato.relativo(recorte.fecha)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Diseno.tintaSuave)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if recorte.fijado {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Diseno.tintaTenue)
            }
            if marcado {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white, Color(red: 0.36, green: 0.34, blue: 0.95))
            } else if let numero, cursor {
                Text("⌘\(numero)").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Diseno.tintaTenue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if cursor {
                forma.fill(Color.white).shadow(color: Diseno.sombra, radius: 8, y: 3)
            } else if marcado {
                forma.fill(Color.white.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
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
                    .background(Color.white.opacity(0.7))
            } else {
                Image(systemName: recorte.simbolo)
                    .font(.system(size: lado * 0.38, weight: .medium))
                    .foregroundStyle(Diseno.tintaSuave)
                    .frame(width: lado, height: lado)
                    .background(Color.white.opacity(0.6))
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(forma)
        .overlay(forma.strokeBorder(Color.white.opacity(0.8), lineWidth: 0.6))
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
        let celdas = LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
            ForEach(lista) { r in
                Celda(recorte: r, historial: historial, cursor: r.id == estado.seleccion,
                      marcado: estado.marcados.count > 1 && estado.marcados.contains(r.id))
                    .id(r.id)
                    .modifier(Interaccion(id: r.id, control: control, simulado: simulado))
            }
        }
        .padding(4)
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
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let mini = historial.miniatura(de: recorte) {
                            Image(nsImage: mini).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.4).overlay(Image(systemName: "photo").foregroundStyle(Diseno.tintaTenue))
                        }
                    }
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .clipShape(forma)
                    if marcado {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Color(red: 0.36, green: 0.34, blue: 0.95))
                            .shadow(color: .black.opacity(0.2), radius: 3)
                            .padding(7)
                    }
                }
                .overlay(forma.strokeBorder(Color.white, lineWidth: cursor ? 3 : 0.6))
                .shadow(color: cursor ? Diseno.sombra : .clear, radius: 10, y: 4)
                Text("\(recorte.ancho ?? 0) × \(recorte.alto ?? 0) · \(Formato.relativo(recorte.fecha))")
                    .font(.system(size: 10))
                    .foregroundStyle(Diseno.tintaSuave)
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
    let historial: Historial
    let estado: EstadoPanel
    let control: Portapapeles?
    let simulado: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if elegidos.count > 1 {
                Moodboard(recortes: elegidos, historial: historial)
            } else if let r = elegidos.first {
                HStack(alignment: .top, spacing: 8) {
                    chips(r)
                    Spacer(minLength: 8)
                    circulos
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                Contenido(recorte: r, historial: historial, simulado: simulado)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 28)).foregroundStyle(Diseno.tintaTenue)
                    Text("Lo que copies aparecerá aquí").font(.system(size: 13)).foregroundStyle(Diseno.tintaSuave)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !elegidos.isEmpty { pildoras.padding(16) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(forma.fill(Color.white.opacity(0.34)))
        .overlay(forma.strokeBorder(Color.white.opacity(0.65), lineWidth: 0.8))
    }

    /// Datos del recorte en píldoras (como máximo tres, para que respiren).
    private func chips(_ r: Recorte) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let app = r.app { Chip(texto: app, icono: Miniatura.icono(r.appID)) }
                Chip(texto: Formato.relativo(r.fecha), simbolo: "clock")
            }
            HStack(spacing: 6) {
                if let origen = r.origen, let host = URL(string: origen)?.host() { Chip(texto: host, simbolo: "globe") }
                Chip(texto: Formato.contenido(r))
            }
        }
    }

    /// Acciones secundarias en botones circulares, arriba a la derecha (como el menú de Notas de visionOS).
    private var circulos: some View {
        let hayTexto = elegidos.contains { $0.tipo == .texto || $0.tipo == .enlace }
        let abrible = elegidos.contains { $0.tipo == .enlace || $0.tipo == .archivo }
        let fijados = elegidos.allSatisfy(\.fijado)
        return HStack(spacing: 6) {
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

    private var pildoras: some View {
        let n = elegidos.count
        let hayTexto = elegidos.contains { $0.tipo == .texto || $0.tipo == .enlace }
        return HStack(spacing: 8) {
            BotonPildora(titulo: n > 1 ? "Pegar \(n) en \(estado.appDestino)" : "Pegar en \(estado.appDestino)",
                         teclas: "↩", primario: true) { control?.pegar() }
                .fixedSize()
                .layoutPriority(1)
            if hayTexto {
                BotonPildora(titulo: "Limpio", teclas: "⌥↩") { control?.pegar(limpio: true) }.fixedSize()
            }
            BotonPildora(titulo: "Copiar", teclas: "⌘C") { control?.copiar() }.fixedSize()
            Spacer(minLength: 0)
            if n > 1 {
                BotonCirculo(simbolo: "trash", lado: 32, ayuda: "Borrar (⌘⌫)") { control?.borrar() }
            }
        }
    }
}

private struct Contenido: View {
    let recorte: Recorte
    let historial: Historial
    let simulado: Bool

    var body: some View {
        let r = recorte
        switch r.tipo {
        case .texto:
            let cuerpo =
                VStack(alignment: .leading, spacing: 14) {
                    if let color = Formato.colorHex(r.texto) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color).frame(width: 72, height: 72)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white, lineWidth: 2))
                            .shadow(color: Diseno.sombra, radius: 8, y: 3)
                    }
                    Text(r.texto)
                        .font(Formato.pareceCodigo(r.texto) ? .system(size: 12.5, design: .monospaced) : .system(size: 15))
                        .foregroundStyle(Diseno.tinta)
                        .lineSpacing(4)
                        .modifier(Seleccionable(activo: !simulado))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            if simulado { cuerpo } else { ScrollView { cuerpo }.scrollIndicators(.never) }
        case .enlace:
            let url = URL(string: r.texto.trimmingCharacters(in: .whitespacesAndNewlines))
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Diseno.tinta)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.white).shadow(color: Diseno.sombra, radius: 8, y: 3))
                Text(url?.host() ?? r.texto).font(.system(size: 24, weight: .semibold)).foregroundStyle(Diseno.tinta).lineLimit(1)
                Text(r.texto).font(.system(size: 13)).foregroundStyle(Diseno.tintaSuave).modifier(Seleccionable(activo: !simulado)).lineLimit(5)
            }
            .padding(22)
        case .imagen:
            if let imagen = historial.imagen(de: r) {
                Image(nsImage: imagen)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white, lineWidth: 2))
                    .shadow(color: Diseno.sombra, radius: 14, y: 6)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .archivo:
            let rutas = r.texto.split(separator: "\n").map(String.init)
            VStack(alignment: .leading, spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: rutas.first ?? ""))
                    .resizable().frame(width: 72, height: 72)
                Text(r.titulo).font(.system(size: 20, weight: .semibold)).foregroundStyle(Diseno.tinta).lineLimit(2)
                ForEach(rutas.prefix(5), id: \.self) { ruta in
                    Text(ruta).font(.system(size: 11, design: .monospaced)).foregroundStyle(Diseno.tintaSuave)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(22)
        }
    }
}

private struct Seleccionable: ViewModifier {
    let activo: Bool
    func body(content: Content) -> some View {
        if activo { content.textSelection(.enabled) } else { content }
    }
}

/// Varios elegidos: fotos apiladas como un moodboard y el resumen por tipo.
private struct Moodboard: View {
    let recortes: [Recorte]
    let historial: Historial

    var body: some View {
        let imagenes = recortes.filter { $0.tipo == .imagen }
        let otros = recortes.filter { $0.tipo != .imagen }
        let giros: [Double] = [-7, 5, -2, 8]
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                EtiquetaSeccion(titulo: "Selección")
                Spacer()
                Chip(texto: Formato.resumen(recortes), simbolo: "square.stack")
            }
            if !imagenes.isEmpty {
                ZStack {
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
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                        .rotationEffect(.degrees(giros[i % giros.count]))
                        .offset(x: Double(i) * 34 - 50, y: Double(i % 2) * 10)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(otros.prefix(5)) { r in
                    HStack(spacing: 8) {
                        Image(systemName: r.simbolo).font(.system(size: 11)).foregroundStyle(Diseno.tintaSuave)
                        Text(r.titulo).font(.system(size: 13)).foregroundStyle(Diseno.tinta).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Las imágenes se pegan como imágenes separadas y los textos se unen. También puedes arrastrarlos.")
                .font(.system(size: 11))
                .foregroundStyle(Diseno.tintaSuave)
        }
        .padding(20)
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

    static func contenido(_ r: Recorte) -> String {
        switch r.tipo {
        case .texto, .enlace:
            let palabras = r.texto.split { $0.isWhitespace || $0.isNewline }.count
            return "\(palabras) palabras" + (r.conFormato ? " · con formato" : "")
        case .imagen:
            return "\(r.ancho ?? 0) × \(r.alto ?? 0) px"
        case .archivo:
            let n = r.texto.split(separator: "\n").count
            return n == 1 ? "1 archivo" : "\(n) archivos"
        }
    }

    static func resumen(_ rs: [Recorte]) -> String {
        let conteo = Dictionary(grouping: rs, by: \.tipo).mapValues(\.count)
        let nombres: [(Recorte.Tipo, String, String)] = [
            (.imagen, "imagen", "imágenes"), (.texto, "texto", "textos"), (.enlace, "enlace", "enlaces"), (.archivo, "archivo", "archivos"),
        ]
        return nombres.compactMap { tipo, uno, varios in conteo[tipo].map { "\($0) \($0 == 1 ? uno : varios)" } }
            .joined(separator: " · ")
    }

    static func colorHex(_ texto: String) -> Color? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func pareceCodigo(_ texto: String) -> Bool {
        let señales = ["{", "}", ";", "=>", "func ", "def ", "const ", "</", "$ "]
        return señales.filter { texto.contains($0) }.count >= 2
    }
}
