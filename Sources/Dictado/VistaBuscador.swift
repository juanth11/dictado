import AppKit
import SwiftUI

/// Buscador de ventanas (Hyper + Espacio) en vidrio claro, como el portapapeles: arriba la búsqueda, en medio
/// las ventanas (ícono, título y app) y abajo las teclas.
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
            BotonCirculo(simbolo: "xmark", lado: 34, ayuda: "Cerrar (Esc)") { control?.cerrar() }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Diseno.tintaSuave)
                if simulado {  // ImageRenderer no dibuja campos de AppKit
                    if estado.busqueda.isEmpty {
                        Text("Buscar una ventana por título o app").font(.system(size: 15)).foregroundStyle(Diseno.tintaTenue)
                    } else {
                        HStack(spacing: 1) {
                            Text(estado.busqueda).font(.system(size: 15)).foregroundStyle(Diseno.tinta)
                            Rectangle().fill(Diseno.tintaSuave).frame(width: 1.5, height: 18)  // cursor
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
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(Color.white.opacity(0.5)))
            .overlay(Capsule().strokeBorder(Diseno.borde, lineWidth: 0.8))
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
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(secciones, id: \.titulo) { seccion in
                if !seccion.titulo.isEmpty {
                    EtiquetaSeccion(titulo: seccion.titulo)
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }
                ForEach(seccion.ventanas) { v in
                    FilaVentana(ventana: v, cursor: v.id == estado.seleccion)
                        .id(v.id)
                        .onTapGesture { control?.elegir(v) }
                }
            }
            if lista.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: estado.cargando ? "hourglass" : "macwindow")
                        .font(.system(size: 24)).foregroundStyle(Diseno.tintaTenue)
                    Text(vacio).font(.system(size: 13)).foregroundStyle(Diseno.tintaSuave)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 90)
            }
        }
        .padding(.bottom, 4)
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
        HStack(spacing: 14) {
            Tecla(texto: "↑↓", accion: "elegir")
            Tecla(texto: "↩", accion: "ir a la ventana")
            Tecla(texto: "esc", accion: "cerrar")
            Spacer()
            Text("Solo este Escritorio y las minimizadas")
                .font(.system(size: 10))
                .foregroundStyle(Diseno.tintaTenue)
        }
        .padding(.horizontal, 6)
    }

    private struct Tecla: View {
        let texto: String
        let accion: String

        var body: some View {
            HStack(spacing: 5) {
                Text(texto)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Diseno.tintaSuave)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.55)))
                Text(accion).font(.system(size: 11)).foregroundStyle(Diseno.tintaSuave)
            }
        }
    }
}

private struct FilaVentana: View {
    let ventana: VentanaEncontrada
    let cursor: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 12) {
            Group {
                if let icono = ventana.icono {
                    Image(nsImage: icono).resizable()
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 18))
                        .foregroundStyle(Diseno.tintaTenue)
                }
            }
            .frame(width: 30, height: 30)
            .opacity(ventana.guardada ? 0.7 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(ventana.tituloVisible)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Diseno.tinta)
                    .lineLimit(1)
                Text(detalle)
                    .font(.system(size: 11))
                    .foregroundStyle(Diseno.tintaSuave)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if cursor {
                Text("↩").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Diseno.tintaTenue)
            } else if ventana.minimizada {
                Image(systemName: "minus.circle").font(.system(size: 11)).foregroundStyle(Diseno.tintaTenue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if cursor { forma.fill(Color.white).shadow(color: Diseno.sombra, radius: 8, y: 3) }
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
