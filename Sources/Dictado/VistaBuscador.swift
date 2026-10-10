import AppKit
import SwiftUI

/// Buscador de ventanas (Hyper + Espacio) en Halo: arriba la búsqueda en una cápsula de vidrio, en medio las
/// ventanas (ícono, título y app; la elegida levantada con el tono azul y su ↩ en blanco) y abajo las teclas.
struct VistaBuscador: View {
    static let ancho: CGFloat = 640
    static let alto: CGFloat = 512

    @Bindable var estado: EstadoBuscador
    let control: BuscadorVentanas?
    var simulado = false
    @FocusState private var buscando: Bool

    private var lista: [VentanaEncontrada] { BuscadorVentanas.filtrar(estado.ventanas, estado.busqueda) }

    var body: some View {
        VStack(spacing: 12) {
            cabecera
            contenido.frame(maxHeight: .infinity)
            pie
        }
        .padding(16)
        .frame(width: Self.ancho, height: Self.alto)
        .modifier(PanelVidrio(radio: 28, simulado: simulado))
        .onAppear { buscando = true }
        .onChange(of: estado.busqueda) { estado.seleccion = lista.first?.id }
    }

    private var cabecera: some View {
        HStack(spacing: 12) {
            BotonCirculo(simbolo: "xmark", lado: 40, ayuda: "Cerrar (Esc)") { control?.cerrar() }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(estado.busqueda.isEmpty ? Halo.texto3 : Halo.texto2)
                if simulado {  // ImageRenderer no dibuja campos de AppKit
                    if estado.busqueda.isEmpty {
                        Text("Buscar una ventana por título o app").font(.system(size: 15)).foregroundStyle(Halo.texto3)
                    } else {
                        HStack(spacing: 1) {
                            Text(estado.busqueda).font(.system(size: 15)).foregroundStyle(Halo.texto)
                            Rectangle().fill(Tono.azul.claro).frame(width: 1.5, height: 18)  // cursor
                        }
                    }
                    Spacer()
                } else {
                    TextField("Buscar una ventana por título o app", text: $estado.busqueda)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($buscando)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule().fill(.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.05)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1))
            if !estado.cargando {
                Chip(texto: lista.count == 1 ? "1 ventana" : "\(lista.count) ventanas", simbolo: "macwindow.on.rectangle")
            }
        }
    }

    @ViewBuilder private var contenido: some View {
        if simulado {  // ImageRenderer no dibuja ScrollView
            filas.frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView { filas }
                    .scrollIndicators(.never)
                    .onChange(of: estado.seleccion) {
                        if let s = estado.seleccion { proxy.scrollTo(s, anchor: .center) }
                    }
            }
        }
    }

    private var filas: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(secciones, id: \.titulo) { seccion in
                if !seccion.titulo.isEmpty {
                    EtiquetaSeccion(titulo: seccion.titulo)
                        .padding(.horizontal, 12)
                        .padding(.top, seccion.titulo == secciones.first?.titulo ? 4 : 12)
                        .padding(.bottom, 4)
                }
                ForEach(seccion.ventanas) { v in
                    FilaVentana(ventana: v, cursor: v.id == estado.seleccion)
                        .id(v.id)
                        .onTapGesture { control?.elegir(v) }
                }
            }
            if lista.isEmpty {
                VStack(spacing: 12) {
                    Insignia(icono: .simbolo(estado.cargando ? "hourglass" : "macwindow"), tono: .neutro, lado: 44)
                    Text(vacio).font(.system(size: 13)).foregroundStyle(Halo.texto2)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 88)
            }
        }
    }

    private var vacio: String {
        if estado.cargando { return "Buscando ventanas…" }
        return estado.ventanas.isEmpty ? "No hay ventanas abiertas" : "Ninguna ventana coincide"
    }

    /// Sin búsqueda: las que están en pantalla y, aparte, las minimizadas u ocultas. Con búsqueda: una sola lista.
    private var secciones: [(titulo: String, ventanas: [VentanaEncontrada])] {
        let todas = simulado ? Array(lista.prefix(8)) : lista  // el render no tiene scroll
        guard estado.busqueda.trimmingCharacters(in: .whitespaces).isEmpty else { return [("", todas)] }
        let enPantalla = todas.filter { !$0.guardada }
        let guardadas = todas.filter(\.guardada)
        return [("En pantalla", enPantalla), ("Minimizadas y ocultas", guardadas)].filter { !$0.1.isEmpty }
    }

    private var pie: some View {
        HStack(spacing: 16) {
            Tecla(texto: "↑↓", accion: "elegir")
            Tecla(texto: "↩", accion: "ir a la ventana")
            Tecla(texto: "esc", accion: "cerrar")
            Spacer()
            Text("Solo este Escritorio y las minimizadas")
                .font(.system(size: 10.5))
                .foregroundStyle(Halo.texto3)
        }
        .padding(.horizontal, 12)
    }

    private struct Tecla: View {
        let texto: String
        let accion: String

        var body: some View {
            HStack(spacing: 6) {
                Text(texto)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Halo.texto2)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                Text(accion).font(.system(size: 11)).foregroundStyle(Halo.texto2)
            }
        }
    }
}

/// Una ventana: ícono, título y app. La elegida se levanta en una tarjeta con el tono azul que nace de la esquina
/// y muestra ↩ en una tecla blanca (la acción principal); al moverte, la tarjeta cambia con un resorte corto.
private struct FilaVentana: View {
    let ventana: VentanaEncontrada
    let cursor: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icono = ventana.icono {
                    Image(nsImage: icono).resizable()
                } else {
                    Insignia(icono: .simbolo("app.dashed"), tono: .neutro, lado: 30)
                }
            }
            .frame(width: 30, height: 30)
            .opacity(ventana.guardada ? 0.6 : 1)
            .saturation(ventana.guardada ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(ventana.tituloVisible)
                    .font(.system(size: 13, weight: cursor ? .semibold : .medium))
                    .foregroundStyle(ventana.guardada && !cursor ? Halo.texto2 : Halo.texto)
                    .lineLimit(1)
                Text(detalle)
                    .font(.system(size: 11))
                    .foregroundStyle(cursor ? Halo.texto2 : Halo.texto3)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if cursor {
                Text("↩")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 20)
                    .background(Capsule().fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: .white.opacity(0.18), radius: 6)
            } else if ventana.minimizada {
                Image(systemName: "minus.circle").font(.system(size: 11)).foregroundStyle(Halo.texto3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if cursor {
                Color.clear.tarjetaHalo(radio: Halo.radioFila, activa: true, tono: .azul)
            }
        }
        .contentShape(Rectangle())
    }

    private var detalle: String {
        var partes = [ventana.app]
        if ventana.minimizada { partes.append("Minimizada") }
        if ventana.appOculta { partes.append("App oculta") }
        return partes.joined(separator: " · ")
    }
}
