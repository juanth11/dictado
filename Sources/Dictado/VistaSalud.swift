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

/// Salud del Mac (⌃⌘M) en Halo, sobrio: blanco con opacidades sobre vidrio oscuro y un solo tono por pestaña.
/// En Ahora, el de la gravedad del diagnóstico (la tarjeta y el dial que lo causa); en Limpieza, el verde de lo
/// recuperable (la luz de la tarjeta y sus marcas en la regla del disco).
struct VistaSalud: View {
    @Bindable var estado: EstadoSalud
    let control: Salud?
    var simulado = false
    /// Solo renders: la lista de Limpieza se muestra bajada hasta el final (no hay desplazamiento).
    var alFinal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                BotonCirculo(simbolo: "xmark", lado: 32, ayuda: "Cerrar (Esc)") { control?.cerrar() }
                Text("Salud del Mac").font(.system(size: 15, weight: .semibold)).foregroundStyle(Halo.texto)
                Spacer()
                Segmentado(opciones: [(0, "Ahora"), (1, "Limpieza")], valor: $estado.pestana)
            }
            // Las pestañas se cambian dentro del resorte de Segmentado: la nueva entra con desenfoque.
            Group {
                if estado.pestana == 0 {
                    PestanaAhora(estado: estado, control: control).transition(.blurReplace)
                } else {
                    PestanaLimpieza(estado: estado, control: control, simulado: simulado, alFinal: alFinal).transition(.blurReplace)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(24)
        .frame(width: Salud.ancho, height: Salud.alto)
        .modifier(PanelVidrio(radio: 30, simulado: simulado))
    }
}

/// "8,9 GB" → ("8,9", "GB"), para la cifra fina con su unidad en versalitas.
private func partes(_ bytes: Double) -> (numero: String, unidad: String) {
    let texto = Medida.bytes(bytes)
    guard let i = texto.lastIndex(of: " ") else { return (texto, "") }
    return (String(texto[..<i]), String(texto[texto.index(after: i)...]))
}

/// Separador de medio punto (un píxel en pantallas Retina) entre filas de una tarjeta.
private struct Filo: View {
    var sangria: CGFloat = 0

    var body: some View {
        Rectangle().fill(Halo.linea).frame(height: 0.5).padding(.leading, sangria)
    }
}

// MARK: - Ahora

private struct PestanaAhora: View {
    let estado: EstadoSalud
    let control: Salud?

    var body: some View {
        let d = estado.diagnostico
        VStack(alignment: .leading, spacing: 24) {
            Diagnostico(gravedad: d.gravedad, titulo: d.titulo, frase: d.frase)

            HStack(spacing: 0) {
                DialSalud(valor: estado.cpu, gravedad: estado.gravedadCPU, momento: d.gravedad,
                          numero: "\(Int((estado.cpu * 100).rounded()))", unidad: "%", titulo: "Procesador",
                          nota: estado.cpu > 0.7 ? "muy ocupado" : (estado.cpu > 0.35 ? "trabajando" : "tranquilo"))
                DialSalud(valor: estado.memoriaUsada / max(1, estado.memoriaTotal), gravedad: estado.gravedadMemoria,
                          momento: d.gravedad, numero: String(format: "%.0f", estado.memoriaUsada / 1e9),
                          unidad: String(format: "/%.0f GB", estado.memoriaTotal / 1.073741824e9), titulo: "Memoria",
                          nota: estado.presion >= 4 ? "al límite"
                              : (estado.swap > 3e9 ? "+\(Medida.bytes(estado.swap)) en disco" : (estado.presion == 2 ? "apretada" : "bien")))
                DialSalud(valor: estado.gpu, gravedad: estado.gravedadGPU, momento: d.gravedad,
                          numero: "\(Int((estado.gpu * 100).rounded()))", unidad: "%", titulo: "Gráficos",
                          nota: estado.gpu > 0.75 ? "muy ocupados" : "bien")
                DialSalud(valor: 1 - estado.discoLibre / max(1, estado.discoTotal), gravedad: estado.gravedadDisco,
                          momento: d.gravedad, numero: Self.gigas(estado.discoLibre), unidad: "GB", titulo: "Disco",
                          nota: "libres")
                DialSalud(valor: termico, gravedad: estado.gravedadTermica, momento: d.gravedad, simbolo: "thermometer.medium",
                          titulo: "Temperatura", nota: notaTermica)
            }

            VStack(alignment: .leading, spacing: 8) {
                EtiquetaSeccion(titulo: "Quién está consumiendo").padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(Array(estado.consumidores.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Filo(sangria: 56) }
                        FilaConsumo(consumidor: c) { control?.cerrarApp(c) }
                    }
                }
                .padding(.vertical, 4)
                .tarjetaHalo(radio: Halo.radioTarjeta)
                .animation(Halo.cambio, value: estado.consumidores.map(\.id))
            }
        }
    }

    /// Menos de 10 GB con un decimal ("8,9"), como en la isla.
    private static func gigas(_ bytes: Double) -> String {
        let g = bytes / 1e9
        return g < 10 ? String(format: "%.1f", g).replacingOccurrences(of: ".", with: ",") : String(format: "%.0f", g)
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

/// El semáforo: tarjeta oscura con la insignia del tono de la gravedad y una luz tenue que sube por la derecha.
/// Al cambiar el diagnóstico, la luz se funde al tono nuevo y el texto cambia con un fundido.
private struct Diagnostico: View {
    let gravedad: Gravedad
    let titulo: String
    let frase: String

    var body: some View {
        let tono = Tono.gravedad(gravedad)
        HStack(alignment: .center, spacing: 16) {
            Insignia(icono: .simbolo(gravedad.simbolo), tono: tono, lado: 48)
            VStack(alignment: .leading, spacing: 4) {
                Rotulo("Diagnóstico")
                Text(titulo).font(.system(size: 20, weight: .semibold)).foregroundStyle(Halo.texto)
                    .contentTransition(.opacity)
                Text(frase).font(.system(size: 12.5)).foregroundStyle(Halo.texto2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuzBorde(tono: tono, fuerza: 0.22, alto: 0.95, centro: 0.82, ancho: 0.55))
        .tarjetaHalo(radio: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(Halo.fundido, value: titulo)
    }
}

/// Un dial de Salud: marcas finas encendidas hasta el uso y la cifra fina en el centro. Solo el dial que causa el
/// diagnóstico lleva el tono; los demás son blancos (si piden atención, su nota va en blanco pleno).
private struct DialSalud: View {
    let valor: Double
    let gravedad: Gravedad
    /// La gravedad del diagnóstico: el tono del momento.
    let momento: Gravedad
    var numero: String?
    var unidad = ""
    var simbolo: String?
    let titulo: String
    let nota: String

    var body: some View {
        let entonado = gravedad != .bien && gravedad == momento
        let tono = entonado ? Tono.gravedad(gravedad) : nil
        VStack(spacing: 12) {
            DialFino(lado: 80, valor: valor, tono: tono) {
                if let numero {
                    NumeroFino(texto: numero, unidad: unidad, tamano: 21, peso: .thin, valor: valor)
                } else if let simbolo {
                    Image(systemName: simbolo).font(.system(size: 20, weight: .ultraLight)).foregroundStyle(Halo.texto)
                }
            }
            .animation(Halo.cambio, value: valor)
            VStack(spacing: 2) {
                Text(titulo).font(.system(size: 12, weight: .medium)).foregroundStyle(Halo.texto)
                Text(nota).font(.system(size: 11))
                    .foregroundStyle(tono?.claro ?? (gravedad == .bien ? Halo.texto3 : Halo.texto2))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Dial fino (candidato a Halo.swift): el anillo de marcas de `Dial` con trazos de 1 pt y sin resplandor. Blanco,
/// o del tono si lo lleva; la última marca encendida es blanca y un poco más larga (la punta). Las marcas se
/// encienden con el resorte del cambio (Marcas es animable).
private struct DialFino<Centro: View>: View {
    let lado: CGFloat
    let valor: Double
    var tono: Tono?
    var marcas = 44
    var arco = 300.0
    var anillo: CGFloat = 6
    @ViewBuilder var centro: () -> Centro

    var body: some View {
        let v = max(0, min(1, valor))
        let n = Double(marcas)
        let encendidas = Int((v * n).rounded())
        let inicio = Marcas.inicio(arco)
        let disco = lado - 2 * (anillo + 4)
        let trazo = StrokeStyle(lineWidth: 1, lineCap: .round)
        ZStack {
            Marcas(cuenta: marcas, arco: arco, desde: v, hasta: 1, largo: anillo)
                .stroke(Color.white.opacity(0.13), style: trazo)
                .frame(width: lado, height: lado)
            if encendidas > 1 {
                let encendido: AnyShapeStyle = tono.map {
                    AnyShapeStyle(AngularGradient(colors: [$0.base, $0.claro], center: .center, startAngle: .degrees(inicio),
                                                  endAngle: .degrees(inicio + arco)))
                } ?? AnyShapeStyle(Color.white.opacity(0.72))
                Marcas(cuenta: marcas, arco: arco, desde: 0, hasta: Double(encendidas - 1) / n, largo: anillo)
                    .stroke(encendido, style: trazo)
                    .frame(width: lado, height: lado)
                    .shadow(color: (tono?.base ?? .white).opacity(tono == nil ? 0.25 : 0.6), radius: 1.5)
            }
            if encendidas > 0 {  // la punta: blanca y 2 pt más larga hacia fuera
                Marcas(cuenta: marcas, arco: arco, desde: Double(encendidas - 1) / n, hasta: Double(encendidas) / n,
                       largo: anillo + 2)
                    .stroke(Color.white, style: trazo)
                    .frame(width: lado + 4, height: lado + 4)
                    .shadow(color: (tono?.claro ?? .white).opacity(0.8), radius: 2)
            }
            Disco().frame(width: disco, height: disco)
            centro().frame(width: disco, height: disco)
        }
        .frame(width: lado, height: lado)
    }
}

private struct FilaConsumo: View {
    let consumidor: Consumidor
    let cerrar: () -> Void

    var body: some View {
        let c = consumidor
        let memoria = partes(c.memoria)
        HStack(spacing: 12) {
            Group {
                if let icono = c.icono {
                    Image(nsImage: icono).resizable()
                } else {
                    Insignia(icono: .simbolo(c.simbolo), tono: .neutro, lado: 32)
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.nombre).font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                if !c.explicacion.isEmpty {
                    Text(c.explicacion).font(.system(size: 11)).foregroundStyle(Halo.texto2).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Cifra(numero: memoria.numero, unidad: memoria.unidad, tamano: 16, peso: .light, color: Halo.texto, valor: c.memoria)
                Text("\(Medida.porcentaje(c.cpu)) procesador").font(.system(size: 10.5)).monospacedDigit()
                    .foregroundStyle(c.cpu > 0.25 ? Halo.texto2 : Halo.texto3)
            }
            // El hueco del botón se guarda aunque no haya (servicios del sistema): las cifras quedan en columna.
            ZStack(alignment: .trailing) {
                if c.esApp && c.nombre != "Dictado" && c.nombre != "Finder" {
                    BotonHalo(titulo: "Cerrar", secundario: true, alto: 28, accion: cerrar)
                        .help("Salir de \(c.nombre) (como ⌘Q: te pregunta si hay algo sin guardar)")
                }
            }
            .frame(width: 72, height: 28, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Limpieza

private struct PestanaLimpieza: View {
    @Bindable var estado: EstadoSalud
    let control: Salud?
    let simulado: Bool
    var alFinal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Recuperable(estado: estado, control: control)
            if !estado.mensaje.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle").foregroundStyle(Halo.texto)
                    Text(estado.mensaje).foregroundStyle(Halo.texto2).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Group {
                if simulado {  // render: lo que no cabe se corta, como la lista desplazable de la app
                    lista.padding(.vertical, 12)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: alFinal ? .bottom : .top).clipped()
                } else {
                    ScrollView(showsIndicators: false) { lista.padding(.vertical, 12) }
                }
            }
            // Los bordes de la lista se funden en el vidrio en vez de cortarse en seco.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 12)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
                }
            }
            .padding(.top, -12)
            .layoutPriority(1)  // la lista ocupa todo el alto: la nota queda abajo, pegada al borde
            Text("Nada se borra sin preguntarte: va a la Papelera y puedes deshacer. El espacio se libera con «Liberar ya», que solo borra lo que mandó Dictado.")
                .font(.system(size: 10.5)).foregroundStyle(Halo.texto3).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .animation(Halo.entrada, value: estado.mensaje)
    }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 8) {
            let indices = Array(estado.limpiables.indices)
            let seguras = indices.filter { estado.limpiables[$0].segura && !estado.limpiables[$0].esNube }
            let nube = indices.filter { estado.limpiables[$0].esNube }
            let guiadas = indices.filter { !estado.limpiables[$0].segura }
            if !seguras.isEmpty {
                seccion("Seguro · va a la Papelera y se regenera solo", primera: true)
                ForEach(seguras, id: \.self) { i in fila(i) }
            }
            if !nube.isEmpty {
                seccion("iCloud · sigue en la nube y se baja al abrirlo", primera: seguras.isEmpty)
                ForEach(nube, id: \.self) { i in fila(i) }
            }
            if !guiadas.isEmpty {
                seccion("Revisa tú · son tus cosas", primera: seguras.isEmpty && nube.isEmpty)
                ForEach(guiadas, id: \.self) { i in fila(i) }
            }
            let ocultos = espacioOculto
            if !ocultos.isEmpty {
                seccion("Espacio oculto · solo para que sepas", primera: indices.isEmpty)
                VStack(spacing: 0) {
                    ForEach(Array(ocultos.enumerated()), id: \.element.titulo) { i, o in
                        if i > 0 { Filo(sangria: 56) }
                        FilaInfo(simbolo: o.simbolo, titulo: o.titulo, detalle: o.detalle, bytes: o.bytes)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Halo.radioTarjeta, style: .continuous)
                    .strokeBorder(Halo.linea, lineWidth: 1))
            }
        }
    }

    private func seccion(_ titulo: String, primera: Bool) -> some View {
        EtiquetaSeccion(titulo: titulo).padding(.leading, 4).padding(.top, primera ? 0 : 8)
    }

    /// Lo que ocupa disco sin estar en ninguna carpeta tuya, en palabras simples. Solo lectura.
    private var espacioOculto: [(simbolo: String, titulo: String, detalle: String, bytes: Double?)] {
        var lista: [(simbolo: String, titulo: String, detalle: String, bytes: Double?)] = []
        if estado.actualizacionLista {
            lista.append(("arrow.down.circle", "Actualización de macOS descargada y lista",
                          "Instálala o descártala en Ajustes → General → Actualización de software", nil))
        }
        if estado.swap >= 500e6 {
            lista.append(("memorychip", "Memoria de reserva en disco", "macOS la usa cuando falta memoria; se libera al reiniciar", estado.swap))
        }
        if estado.discoPurgable >= 500e6 {
            lista.append(("sparkles", "Lo que macOS puede liberar solo",
                          "Cachés que macOS borra por su cuenta cuando necesita espacio; ya cuentan como libres", estado.discoPurgable))
        }
        return lista
    }

    private func fila(_ i: Int) -> some View {
        let l = estado.limpiables[i]
        let abierto = estado.abiertos.contains(l.id)
        return FilaLimpieza(limpiable: $estado.limpiables[i], abierto: abierto,
                            alternar: {
                                withAnimation(Halo.cambio) {
                                    if abierto { estado.abiertos.remove(l.id) } else { estado.abiertos.insert(l.id) }
                                }
                            },
                            accion: { control?.ejecutar(estado.limpiables[i]) })
    }
}

/// Lo que se puede recuperar, en grande y fino; debajo, el disco en una regla de marcas donde lo recuperable se
/// enciende en verde y una luz tenue sube justo debajo. Deshacer (vidrio) y Liberar ya (el botón principal,
/// blanco sólido) a la derecha. La cifra rueda y las marcas cambian al marcar o desmarcar elementos.
private struct Recuperable: View {
    let estado: EstadoSalud
    let control: Salud?

    var body: some View {
        let midiendo = estado.analizando && estado.limpiables.isEmpty
        let total = partes(Double(estado.recuperable))
        let usado = max(0, estado.discoTotal - estado.discoLibre)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Rotulo(midiendo ? "Midiendo tu disco" : "Puedes recuperar sin riesgo")
                if midiendo {
                    Text("Unos segundos…").font(.system(size: 32, weight: .thin)).foregroundStyle(Halo.texto)
                        .frame(height: 52, alignment: .leading)
                } else {
                    Cifra(numero: total.numero, unidad: total.unidad, tamano: 46, valor: Double(estado.recuperable))
                        .frame(height: 52, alignment: .leading)
                }
                Text(midiendo ? "No se mueve nada sin que lo pidas."
                              : "Y revisar \(Medida.bytes(Double(estado.revisable))) más de cosas tuyas.")
                    .font(.system(size: 12.5)).foregroundStyle(Halo.texto2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                BotonCirculo(simbolo: "arrow.clockwise", lado: 32, ayuda: estado.analizando ? "Midiendo…" : "Medir de nuevo") {
                    control?.analizar()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    if estado.ultima != nil {
                        BotonHalo(titulo: "Deshacer", icono: "arrow.uturn.backward", secundario: true, alto: 32) { control?.deshacer() }
                            .help("Devuelve a su lugar lo de la última limpieza")
                    }
                    // Solo si Dictado dejó algo en la Papelera: lo borra para siempre (pregunta antes, con el tamaño).
                    if estado.papeleraTotal > 0 {
                        BotonHalo(titulo: "Liberar ya", icono: "trash", teclas: Medida.bytes(Double(estado.papeleraTotal)), alto: 32) {
                            control?.liberar()
                        }
                        .help("Borra para siempre solo lo que Dictado mandó a la Papelera; lo tuyo no se toca. Te pregunta antes.")
                    }
                }
            }
            VStack(spacing: 8) {
                ReglaDisco(usado: usado / max(1, estado.discoTotal),
                           recuperable: Double(estado.recuperable) / max(1, estado.discoTotal))
                HStack {
                    Rotulo("Disco · \(Medida.bytes(usado)) en uso")
                    Spacer()
                    Rotulo("\(Medida.bytes(estado.discoLibre)) libres", color: Halo.texto2)
                }
            }
        }
        .padding(20)
        .background(LuzBorde(tono: .verde, fuerza: 0.22, alto: 0.9, centro: 0.82, ancho: 0.5))
        .tarjetaHalo(radio: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(Halo.cambio, value: estado.recuperable)
    }
}

/// Regla del disco: lo usado en marcas blancas tenues; al final de lo usado, en verde, lo que la limpieza puede
/// recuperar; lo libre, apagado. Trazos de 1 pt; las marcas cambian con el resorte corto.
private struct ReglaDisco: View {
    let usado: Double        // 0–1
    let recuperable: Double  // 0–1, parte de lo usado
    var cuantas = 72
    var alto: CGFloat = 12

    var body: some View {
        let fin = Int((max(0, min(1, usado)) * Double(cuantas)).rounded())
        let verdes = recuperable > 0 ? min(fin, max(1, Int((recuperable * Double(cuantas)).rounded()))) : 0
        let desde = fin - verdes
        HStack(spacing: 0) {
            ForEach(0..<cuantas, id: \.self) { i in
                let verde = i >= desde && i < fin
                Capsule()
                    .fill(verde ? Tono.verde.claro : Color.white.opacity(i < desde ? 0.3 : 0.1))
                    .frame(width: 1, height: verde ? alto + 4 : alto)
                    .shadow(color: verde ? Tono.verde.base.opacity(0.9) : .clear, radius: 2)
                if i < cuantas - 1 { Spacer(minLength: 0) }
            }
        }
        .frame(height: alto + 4)
        .animation(Halo.cambio, value: desde)
    }
}

/// Un dato informativo (espacio oculto): sin botón ni fondo, solo dentro de un filo tenue.
private struct FilaInfo: View {
    let simbolo: String
    let titulo: String
    let detalle: String
    let bytes: Double?

    var body: some View {
        HStack(spacing: 12) {
            Insignia(icono: .simbolo(simbolo), tono: .neutro, lado: 32).opacity(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                Text(detalle).font(.system(size: 11)).foregroundStyle(Halo.texto3).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let bytes {
                let b = partes(bytes)
                Cifra(numero: b.numero, unidad: b.unidad, tamano: 15, peso: .light, color: Halo.texto2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Botón de una categoría: vidrio con filo de 1 pt. Las seguras (limpiar) llevan la letra en el verde de la
/// pestaña; lo tuyo, en blanco. Sin relleno de color ni brillo: el único botón sólido es Liberar ya.
private struct BotonFila: View {
    let titulo: String
    let seguro: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Text(titulo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(seguro ? Tono.verde.claro : Halo.texto)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(.white.opacity(0.07)))
                .overlay(Capsule().strokeBorder(seguro ? Tono.verde.claro.opacity(0.3) : .white.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
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
        let peso = partes(Double(l.bytes))
        let apagado = l.segura && l.marcados.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Insignia(icono: .simbolo(l.simbolo), tono: .neutro, lado: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(l.titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                        if l.items.count > 1 {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Halo.texto3)
                                .rotationEffect(.degrees(abierto ? 90 : 0))
                        }
                    }
                    Text(l.detalle).font(.system(size: 11)).foregroundStyle(Halo.texto2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Cifra(numero: peso.numero, unidad: peso.unidad, tamano: 16, peso: .light, color: Halo.texto, valor: Double(l.bytes))
                BotonFila(titulo: l.boton, seguro: l.segura, accion: accion)
                    .disabled(apagado)
                    .opacity(apagado ? 0.4 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { if l.items.count > 1 { alternar() } }
            if abierto {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($limpiable.items) { $item in
                        HStack(spacing: 8) {
                            if l.segura {
                                Image(systemName: item.marcado ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .light))
                                    .foregroundStyle(item.marcado ? Halo.texto : Halo.texto3)
                                    .onTapGesture { withAnimation(Halo.cambio) { item.marcado.toggle() } }
                            }
                            Text(item.nombre).font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(item.marcado || !l.segura ? Halo.texto : Halo.texto2).lineLimit(1)
                            Text(item.detalle).font(.system(size: 10.5)).foregroundStyle(Halo.texto3).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Medida.bytes(Double(item.bytes))).font(.system(size: 11)).monospacedDigit()
                                .foregroundStyle(item.marcado || !l.segura ? Halo.texto2 : Halo.texto3)
                            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Halo.texto3)
                                .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                .help("Mostrar en el Finder")
                        }
                    }
                }
                .padding(.leading, 44)
                .padding(.trailing, 4)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .tarjetaHalo(radio: Halo.radioTarjeta, activa: abierto)
    }
}
