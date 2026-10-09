import AppKit
import SwiftUI

extension Gravedad {
    var color: Color {
        switch self {
        case .bien: return Color(red: 0.20, green: 0.70, blue: 0.42)
        case .atento: return Color(red: 0.95, green: 0.62, blue: 0.10)
        case .mal: return Color(red: 0.92, green: 0.30, blue: 0.26)
        }
    }

    var simbolo: String {
        switch self {
        case .bien: return "checkmark"
        case .atento: return "exclamationmark"
        case .mal: return "exclamationmark.2"
        }
    }
}

/// Salud del Mac (⌃⌘M): semáforo con una frase, cinco anillos, quién consume y limpieza honesta.
struct VistaSalud: View {
    @Bindable var estado: EstadoSalud
    let control: Salud?
    var simulado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BotonCirculo(simbolo: "xmark", lado: 32, ayuda: "Cerrar (Esc)") { control?.cerrar() }
                Text("Salud del Mac").font(.system(size: 15, weight: .semibold)).foregroundStyle(Diseno.tinta)
                Spacer()
                Segmentado(opciones: [(0, "Ahora"), (1, "Limpieza")], valor: $estado.pestana)
            }
            if estado.pestana == 0 {
                PestanaAhora(estado: estado, control: control)
            } else {
                PestanaLimpieza(estado: estado, control: control, simulado: simulado)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: Salud.ancho, height: Salud.alto)
        .modifier(PanelVidrio(radio: 30, simulado: simulado))
    }
}

// MARK: - Ahora

private struct PestanaAhora: View {
    let estado: EstadoSalud
    let control: Salud?

    var body: some View {
        let d = estado.diagnostico
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle().fill(d.gravedad.color.opacity(0.18)).frame(width: 54, height: 54)
                    Circle().fill(d.gravedad.color).frame(width: 38, height: 38)
                        .shadow(color: d.gravedad.color.opacity(0.5), radius: 8, y: 2)
                    Image(systemName: d.gravedad.simbolo).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(d.titulo).font(.system(size: 21, weight: .semibold)).foregroundStyle(Diseno.tinta)
                    Text(d.frase).font(.system(size: 13)).foregroundStyle(Diseno.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Diseno.borde, lineWidth: 0.8))

            HStack(spacing: 0) {
                Anillo(valor: estado.cpu, gravedad: estado.gravedadCPU, centro: Medida.porcentaje(estado.cpu),
                       titulo: "Procesador", nota: estado.cpu > 0.7 ? "muy ocupado" : (estado.cpu > 0.35 ? "trabajando" : "tranquilo"))
                Anillo(valor: estado.memoriaUsada / estado.memoriaTotal, gravedad: estado.gravedadMemoria,
                       centro: String(format: "%.0f/%.0f", estado.memoriaUsada / 1e9, estado.memoriaTotal / 1.073741824e9),
                       titulo: "Memoria",
                       nota: estado.presion >= 4 ? "al límite" : (estado.swap > 3e9 ? "+\(Medida.bytes(estado.swap)) en disco" : (estado.presion == 2 ? "apretada" : "bien")))
                Anillo(valor: estado.gpu, gravedad: estado.gravedadGPU, centro: Medida.porcentaje(estado.gpu),
                       titulo: "Gráficos", nota: estado.gpu > 0.75 ? "muy ocupados" : "bien")
                Anillo(valor: 1 - estado.discoLibre / estado.discoTotal, gravedad: estado.gravedadDisco,
                       centro: String(format: "%.0f", estado.discoLibre / 1e9), titulo: "Disco", nota: "GB libres")
                Anillo(valor: termico, gravedad: estado.gravedadTermica, centro: nil, simbolo: "thermometer.medium",
                       titulo: "Temperatura", nota: notaTermica)
            }

            VStack(alignment: .leading, spacing: 8) {
                EtiquetaSeccion(titulo: "Quién está consumiendo")
                ForEach(estado.consumidores) { c in
                    FilaConsumo(consumidor: c, memoriaTotal: estado.memoriaTotal) { control?.cerrarApp(c) }
                }
            }
        }
    }

    private var termico: Double {
        switch estado.termico {
        case .nominal: return 0.25
        case .fair: return 0.5
        case .serious: return 0.8
        case .critical: return 1
        @unknown default: return 0.25
        }
    }

    private var notaTermica: String {
        switch estado.termico {
        case .nominal: return "normal"
        case .fair: return "tibio"
        case .serious: return "caliente"
        case .critical: return "muy caliente"
        @unknown default: return "normal"
        }
    }
}

/// Anillo de progreso con el color del semáforo, valor en el centro y una nota en palabras.
private struct Anillo: View {
    let valor: Double
    let gravedad: Gravedad
    let centro: String?
    var simbolo: String?
    let titulo: String
    let nota: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Diseno.tinta.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, valor)))
                    .stroke(gravedad.color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: valor)
                if let centro {
                    Text(centro).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Diseno.tinta)
                        .contentTransition(.numericText())
                } else if let simbolo {
                    Image(systemName: simbolo).font(.system(size: 18, weight: .medium)).foregroundStyle(gravedad.color)
                }
            }
            .frame(width: 66, height: 66)
            VStack(spacing: 1) {
                Text(titulo).font(.system(size: 12, weight: .semibold)).foregroundStyle(Diseno.tinta)
                Text(nota).font(.system(size: 11)).foregroundStyle(gravedad == .bien ? Diseno.tintaSuave : gravedad.color)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FilaConsumo: View {
    let consumidor: Consumidor
    let memoriaTotal: Double
    let cerrar: () -> Void

    var body: some View {
        let c = consumidor
        HStack(spacing: 12) {
            Group {
                if let icono = c.icono {
                    Image(nsImage: icono).resizable()
                } else {
                    Image(systemName: c.simbolo).font(.system(size: 13, weight: .medium)).foregroundStyle(Diseno.tinta.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.7)))
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.nombre).font(.system(size: 13, weight: .semibold)).foregroundStyle(Diseno.tinta).lineLimit(1)
                if !c.explicacion.isEmpty {
                    Text(c.explicacion).font(.system(size: 11)).foregroundStyle(Diseno.tintaSuave).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Medida.bytes(c.memoria)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(c.memoria > memoriaTotal * 0.15 ? Gravedad.atento.color : Diseno.tinta)
                Text("\(Medida.porcentaje(c.cpu)) procesador").font(.system(size: 10.5)).monospacedDigit()
                    .foregroundStyle(c.cpu > 0.25 ? Gravedad.atento.color : Diseno.tintaSuave)
            }
            .frame(width: 104, alignment: .trailing)
            if c.esApp && c.nombre != "Dictado" && c.nombre != "Finder" {
                Button(action: cerrar) {
                    Text("Cerrar").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Diseno.tinta)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.75)))
                        .overlay(Capsule().strokeBorder(Diseno.borde, lineWidth: 0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Salir de \(c.nombre) (como ⌘Q: te pregunta si hay algo sin guardar)")
            } else {
                Color.clear.frame(width: 62, height: 26)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.32)))
    }
}

// MARK: - Limpieza

private struct PestanaLimpieza: View {
    @Bindable var estado: EstadoSalud
    let control: Salud?
    let simulado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    if estado.analizando && estado.limpiables.isEmpty {
                        Text("Midiendo tu disco…").font(.system(size: 19, weight: .semibold)).foregroundStyle(Diseno.tinta)
                        Text("Unos segundos. No se mueve nada sin que lo pidas.").font(.system(size: 12.5)).foregroundStyle(Diseno.tintaSuave)
                    } else {
                        Text("Puedes recuperar \(Medida.bytes(Double(estado.recuperable))) sin riesgo")
                            .font(.system(size: 19, weight: .semibold)).foregroundStyle(Diseno.tinta)
                        Text("Y revisar \(Medida.bytes(Double(estado.revisable))) más de cosas tuyas. Libre ahora: \(Medida.bytes(estado.discoLibre)).")
                            .font(.system(size: 12.5)).foregroundStyle(Diseno.tintaSuave)
                    }
                }
                Spacer()
                if estado.ultima != nil {
                    BotonPildora(titulo: "Deshacer", simbolo: "arrow.uturn.backward") { control?.deshacer() }
                        .help("Devuelve a su lugar lo de la última limpieza")
                }
                BotonCirculo(simbolo: "arrow.clockwise", lado: 36, ayuda: estado.analizando ? "Midiendo…" : "Medir de nuevo") { control?.analizar() }
            }
            if !estado.mensaje.isEmpty {
                Label(estado.mensaje, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Gravedad.bien.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if simulado {
                lista
            } else {
                ScrollView(showsIndicators: false) { lista }
            }
            Text("Nada se borra para siempre: va a la Papelera y puedes deshacer. El espacio se libera cuando vacías la Papelera desde el Finder.")
                .font(.system(size: 10.5)).foregroundStyle(Diseno.tintaTenue)
        }
    }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 8) {
            let indices = Array(estado.limpiables.indices)
            let seguras = indices.filter { estado.limpiables[$0].segura }
            let guiadas = indices.filter { !estado.limpiables[$0].segura }
            if !seguras.isEmpty {
                EtiquetaSeccion(titulo: "Seguro · va a la Papelera y se regenera solo")
                ForEach(seguras, id: \.self) { i in fila(i) }
            }
            if !guiadas.isEmpty {
                EtiquetaSeccion(titulo: "Revisa tú · son tus cosas").padding(.top, 4)
                ForEach(guiadas, id: \.self) { i in fila(i) }
            }
        }
    }

    private func fila(_ i: Int) -> some View {
        let l = estado.limpiables[i]
        let abierto = estado.abiertos.contains(l.id)
        return FilaLimpieza(limpiable: $estado.limpiables[i], abierto: abierto,
                            alternar: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    if abierto { estado.abiertos.remove(l.id) } else { estado.abiertos.insert(l.id) }
                                }
                            },
                            accion: { control?.ejecutar(estado.limpiables[i]) })
    }
}

/// Una categoría: qué es, cuánto pesa y su botón. Se despliega para ver (y desmarcar) cada elemento.
private struct FilaLimpieza: View {
    @Binding var limpiable: Limpiable
    let abierto: Bool
    let alternar: () -> Void
    let accion: () -> Void

    var body: some View {
        let l = limpiable
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: l.simbolo).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(l.segura ? Gravedad.bien.color : Diseno.tinta.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.7)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(l.titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(Diseno.tinta).lineLimit(1)
                        if l.items.count > 1 {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Diseno.tintaTenue)
                                .rotationEffect(.degrees(abierto ? 90 : 0))
                        }
                    }
                    Text(l.detalle).font(.system(size: 11)).foregroundStyle(Diseno.tintaSuave).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Medida.bytes(Double(l.bytes))).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Diseno.tinta)
                    .contentTransition(.numericText())
                Button(action: accion) {
                    Text(l.boton).font(.system(size: 11.5, weight: l.segura ? .semibold : .medium))
                        .foregroundStyle(l.segura ? .white : Diseno.tinta)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(l.segura ? Gravedad.bien.color : Color.white.opacity(0.75)))
                        .overlay(Capsule().strokeBorder(l.segura ? .clear : Diseno.borde, lineWidth: 0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(l.segura && l.marcados.isEmpty)
                .opacity(l.segura && l.marcados.isEmpty ? 0.4 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { if l.items.count > 1 { alternar() } }
            if abierto {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($limpiable.items) { $item in
                        HStack(spacing: 8) {
                            if l.segura {
                                Image(systemName: item.marcado ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(item.marcado ? Gravedad.bien.color : Diseno.tintaTenue)
                                    .onTapGesture { item.marcado.toggle() }
                            }
                            Text(item.nombre).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Diseno.tinta).lineLimit(1)
                            Text(item.detalle).font(.system(size: 10.5)).foregroundStyle(Diseno.tintaSuave).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(Medida.bytes(Double(item.bytes))).font(.system(size: 11, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Diseno.tintaSuave)
                            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Diseno.tintaTenue)
                                .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                .help("Mostrar en el Finder")
                        }
                    }
                }
                .padding(.leading, 42)
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.32)))
    }
}
