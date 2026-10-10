import SwiftUI

// Vistas de los agentes de fuera del Mac (ver Agentes.swift) en la pestaña Agentes de la isla:
// una fila junto a las sesiones de Claude Code y, al tocarla, el detalle con el día del agente.

extension AgentesRemotos.Estado {
    var color: Color { Tono.agente(self).base }
}

extension AgentesRemotos.Tarea {
    var color: Color {
        switch estado {
        case "error": return Tono.rojo.base
        case "corriendo": return .white
        case "pausada": return .white.opacity(0.25)
        default: return Tono.verde.base
        }
    }

    var activa: Bool { estado != "pausada" }
}

/// Cómo va el día de un agente: lo que ya corrió hoy, lo que falta hoy, la próxima corrida y lo que falló.
struct DiaAgente {
    let corridas: [AgentesRemotos.Tarea]     // hoy, de la más reciente a la más vieja
    let faltan: [AgentesRemotos.Tarea]       // lo que vuelve a correr más tarde hoy
    let proxima: AgentesRemotos.Tarea?
    let fallas: [AgentesRemotos.Tarea]
    let corriendo: [AgentesRemotos.Tarea]

    init(_ a: AgentesRemotos.Agente, ahora: Date = Date()) {
        let cal = Calendar.current
        let activas = a.tareas.filter(\.activa)
        corridas = activas.filter { $0.ultima.map { cal.isDate($0, inSameDayAs: ahora) && $0 <= ahora } ?? false }
            .sorted { ($0.ultima ?? .distantPast) > ($1.ultima ?? .distantPast) }
        faltan = activas.filter { $0.proxima.map { cal.isDate($0, inSameDayAs: ahora) && $0 > ahora } ?? false }
        proxima = activas.filter { ($0.proxima ?? .distantPast) > ahora }.min { $0.proxima! < $1.proxima! }
        fallas = activas.filter { $0.estado == "error" }
        corriendo = activas.filter { $0.estado == "corriendo" }
    }

    var total: Int { corridas.count + faltan.count }
    var avance: Double { total == 0 ? 1 : Double(corridas.count) / Double(total) }
}

/// Un agente de fuera del Mac en una sola línea, para que no empuje las sesiones de Claude: su dial pequeño,
/// el nombre, cómo va (o la alerta) y una cápsula líquida con lo que ya corrió hoy. Tocarla abre el detalle.
struct FilaAgente: View {
    let agente: AgentesRemotos.Agente
    let abrir: () -> Void

    var body: some View {
        let dia = DiaAgente(agente)
        let tono = Tono.agente(agente.estado)
        let mal = !agente.alertas.isEmpty || agente.estado == .caido || agente.error != nil
        Button(action: abrir) {
            HStack(spacing: 10) {
                Dial(lado: 26, valor: dia.avance, colores: tono.gradiente, marcas: 20, arco: 360, anillo: 3, brillo: 0.7, destello: false) {
                    Image(systemName: "server.rack").font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Halo.texto)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(agente.nombre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                        Text(subtitulo(dia)).font(Halo.detalle).foregroundStyle(mal ? tono.claro : Halo.texto3).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Halo.texto3)
                    }
                    Liquido(valor: max(0.06, dia.avance), tono: tono, alto: 5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ver el día de \(agente.nombre)")
    }

    private func subtitulo(_ dia: DiaAgente) -> String {
        if let alerta = agente.alertas.first { return alerta }
        if let error = agente.error { return error }
        if agente.actualizado == nil { return "Consultando…" }
        let hoy = dia.total > 0 ? "\(dia.corridas.count) de \(dia.total) hoy" : "Sin corridas hoy"
        guard let cuando = dia.proxima?.proxima else { return hoy }
        return hoy + " · próxima " + Tiempo.hora(cuando)
    }
}

/// Detalle de un agente: cómo va el día en una cápsula líquida, las corridas como marcas sobre la regla del día y
/// las tareas que importan (las que fallaron, la que corre, las últimas y la próxima). La flecha vuelve a la lista.
struct DetalleAgente: View {
    let agente: AgentesRemotos.Agente
    let consultando: Bool
    let volver: () -> Void

    var body: some View {
        let dia = DiaAgente(agente)
        let tono = Tono.agente(agente.estado)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button(action: volver) {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Halo.texto3)
                        Text(agente.nombre).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                        Rotulo(etiqueta, color: tono.claro)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Volver a Agentes")
                Spacer(minLength: 4)
                if consultando {
                    Text("actualizando…").font(Halo.detalle).foregroundStyle(Halo.texto3)
                } else if dia.total > 0 {
                    Cifra(numero: "\(dia.corridas.count)/\(dia.total)", unidad: "hoy", tamano: 13, peso: .semibold, color: Halo.texto2)
                }
            }
            if agente.tareas.isEmpty {
                Text(agente.alertas.first ?? agente.error ?? "Sin tareas programadas")
                    .font(Halo.cuerpo).foregroundStyle(tono.claro).lineLimit(2)
            } else {
                Liquido(valor: max(0.06, dia.avance), tono: tono, alto: 5)
                RielHoy(tareas: agente.tareas)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(filas(dia).prefix(2)) { FilaTarea(fila: $0) }
                }
            }
        }
    }

    private var etiqueta: String {
        switch agente.estado {
        case .ok: return "En línea"
        case .alerta: return "Alerta"
        case .caido: return "Sin conexión"
        case .desconocido: return "Sin datos"
        }
    }

    /// Lo que falló primero; luego lo que corre, las dos últimas corridas y la próxima.
    private func filas(_ dia: DiaAgente) -> [FilaTarea.Datos] {
        var filas = dia.fallas.map {
            FilaTarea.Datos(id: "e" + $0.nombre, etiqueta: "Falló", nombre: $0.nombre, hora: $0.ultima.map(Tiempo.hora) ?? "",
                            tono: .rojo, hueco: false, ayuda: $0.detalle)
        }
        filas += dia.corriendo.map {
            FilaTarea.Datos(id: "c" + $0.nombre, etiqueta: "Ahora", nombre: $0.nombre, hora: "corriendo", tono: .neutro, hueco: false,
                            ayuda: $0.detalle)
        }
        filas += dia.corridas.filter { $0.estado == "ok" }.prefix(1).map {
            FilaTarea.Datos(id: "u" + $0.nombre, etiqueta: "Corrió", nombre: $0.nombre, hora: $0.ultima.map(Tiempo.hora) ?? "",
                            tono: .verde, hueco: false, ayuda: $0.detalle)
        }
        if let p = dia.proxima, let cuando = p.proxima {
            filas.append(.init(id: "p" + p.nombre, etiqueta: "Próxima", nombre: p.nombre, hora: Tiempo.hora(cuando), tono: .neutro,
                               hueco: true, ayuda: p.detalle))
        }
        return filas
    }
}

/// "● CORRIÓ   informe-matutino          8:03 a. m."
struct FilaTarea: View {
    struct Datos: Identifiable {
        let id: String
        let etiqueta: String
        let nombre: String
        let hora: String
        let tono: Tono
        let hueco: Bool
        let ayuda: String
    }

    let fila: Datos

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if fila.hueco { Circle().strokeBorder(fila.tono.claro, lineWidth: 1.2) } else { PuntoBrillante(color: fila.tono.base, lado: 6) }
            }
            .frame(width: 6, height: 6)
            Text(fila.etiqueta.uppercased()).font(.system(size: 8.5, weight: .semibold)).tracking(0.8).foregroundStyle(Halo.texto3)
                .frame(width: 48, alignment: .leading)
            Text(fila.nombre).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Halo.texto).lineLimit(1)
            Spacer(minLength: 4)
            Text(fila.hora).font(.system(size: 10.5)).monospacedDigit()
                .foregroundStyle(fila.etiqueta == "Falló" ? fila.tono.claro : Halo.texto2).lineLimit(1)
        }
        .help(fila.ayuda)
    }
}

/// El día como una regla de marcas finas (una cada media hora), de medianoche a medianoche: cada corrida es una
/// marca alta que brilla (verde bien, roja falló), lo que falta hoy un anillo, y la hora actual una línea blanca.
struct RielHoy: View {
    let tareas: [AgentesRemotos.Tarea]
    var ahora = Date()

    private struct Marca: Identifiable {
        let id: String
        let x: Double
        let color: Color
        let hueco: Bool
    }

    var body: some View {
        let hoy = fraccion(ahora)
        let marcas = calcular()
        VStack(spacing: 3) {
            GeometryReader { g in
                let w = g.size.width, medio = g.size.height / 2
                ZStack(alignment: .topLeading) {
                    regla(w: w, medio: medio, hasta: 1).stroke(.white.opacity(0.12), lineWidth: 1)
                    regla(w: w, medio: medio, hasta: hoy).stroke(.white.opacity(0.26), lineWidth: 1)  // lo que ya pasó del día
                    ForEach(marcas) { m in
                        Group {
                            if m.hueco {
                                Circle().strokeBorder(m.color, lineWidth: 1.2).background(Circle().fill(.black)).frame(width: 7, height: 7)
                            } else {
                                Capsule().fill(m.color).frame(width: 2.5, height: 16).shadow(color: m.color, radius: 3)
                            }
                        }
                        .position(x: w * m.x, y: medio)
                    }
                    Capsule().fill(.white).frame(width: 1.5, height: 20).shadow(color: .white.opacity(0.8), radius: 3)
                        .position(x: w * hoy, y: medio)
                }
            }
            .frame(height: 20)
            GeometryReader { g in
                ZStack {
                    ForEach([(0.0, "12 A. M."), (0.25, "6 A. M."), (0.5, "12 M."), (0.75, "6 P. M."), (1.0, "12 A. M.")], id: \.0) { x, texto in
                        Text(texto).font(.system(size: 8, weight: .semibold)).foregroundStyle(Halo.texto3).fixedSize()
                            .position(x: min(max(g.size.width * x, 20), g.size.width - 20), y: g.size.height / 2)
                    }
                }
            }
            .frame(height: 10)
        }
    }

    /// Una marca cada media hora; las de cada 6 horas, más largas.
    private func regla(w: CGFloat, medio: CGFloat, hasta: Double) -> Path {
        Path { p in
            for i in 0...48 where Double(i) / 48 <= hasta {
                let x = w * CGFloat(i) / 48
                let largo: CGFloat = i % 12 == 0 ? 9 : 5
                p.move(to: CGPoint(x: x, y: medio - largo / 2))
                p.addLine(to: CGPoint(x: x, y: medio + largo / 2))
            }
        }
    }

    private func fraccion(_ fecha: Date) -> Double {
        let inicio = Calendar.current.startOfDay(for: ahora)
        return min(1, max(0, fecha.timeIntervalSince(inicio) / 86_400))
    }

    private func calcular() -> [Marca] {
        let cal = Calendar.current
        var marcas: [Marca] = []
        for t in tareas where t.activa {
            if let u = t.ultima, cal.isDate(u, inSameDayAs: ahora), u <= ahora, t.estado != "corriendo" {
                marcas.append(Marca(id: "u" + t.nombre, x: fraccion(u), color: t.estado == "error" ? Tono.rojo.base : Tono.verde.base, hueco: false))
            }
            if let p = t.proxima, cal.isDate(p, inSameDayAs: ahora), p > ahora {
                marcas.append(Marca(id: "p" + t.nombre, x: fraccion(p), color: .white.opacity(0.6), hueco: true))
            }
        }
        return marcas
    }
}
