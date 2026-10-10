import SwiftUI

// Vistas de los agentes de fuera del Mac (ver Agentes.swift) en la pestaña Agentes de la isla:
// una fila junto a las sesiones de Claude Code y, al tocarla, el detalle con el día del agente.

extension AgentesRemotos.Estado {
    var color: Color {
        switch self {
        case .ok: return Gravedad.bien.color
        case .alerta: return Gravedad.atento.color
        case .caido: return Gravedad.mal.color
        case .desconocido: return .white.opacity(0.35)
        }
    }
}

extension AgentesRemotos.Tarea {
    var color: Color {
        switch estado {
        case "error": return Gravedad.mal.color
        case "corriendo": return .white
        case "pausada": return .white.opacity(0.25)
        default: return Gravedad.bien.color
        }
    }

    var activa: Bool { estado != "pausada" }
}

/// Un agente en una fila, como las sesiones de Claude: su estado, el resumen (o la alerta) y un punto por tarea.
struct FilaAgente: View {
    let agente: AgentesRemotos.Agente
    let abrir: () -> Void

    var body: some View {
        Button(action: abrir) {
            HStack(spacing: 10) {
                IconoAgente(estado: agente.estado).frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agente.nombre).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text(subtitulo)
                        .font(.system(size: 10.5))
                        .foregroundStyle(agente.alertas.isEmpty && agente.error == nil ? .white.opacity(0.45) : agente.estado.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                PuntosTareas(tareas: agente.tareas)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ver el día de \(agente.nombre)")
    }

    private var subtitulo: String {
        if let alerta = agente.alertas.first { return alerta }
        if let error = agente.error { return error }
        if agente.actualizado == nil { return "Consultando…" }
        return agente.resumen.isEmpty ? "Sin novedades" : agente.resumen
    }
}

/// El servidor con un punto del color de su estado (verde bien, naranja alerta, rojo sin conexión).
struct IconoAgente: View {
    let estado: AgentesRemotos.Estado

    var body: some View {
        Image(systemName: "server.rack")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(estado.color).frame(width: 6, height: 6)
                    .overlay(Circle().stroke(.black, lineWidth: 1.5))
                    .offset(x: 4, y: 3)
            }
    }
}

/// Un punto por tarea activa: verde si su última corrida salió bien, rojo si falló, blanco si está corriendo.
struct PuntosTareas: View {
    let tareas: [AgentesRemotos.Tarea]

    var body: some View {
        let activas = tareas.filter(\.activa)
        HStack(spacing: 3) {
            ForEach(activas.prefix(12)) { t in
                Circle().fill(t.color).frame(width: 5, height: 5)
            }
        }
        .help(activas.map { "\($0.nombre): " + ($0.estado == "error" ? "falló" : $0.estado == "corriendo" ? "corriendo" : "bien") }
            .joined(separator: "\n"))
    }
}

/// Detalle de un agente: el día de hoy en una línea y las tareas que importan (las que fallaron, la que corre,
/// la última que corrió y la próxima). La flecha vuelve a la lista.
struct DetalleAgente: View {
    let agente: AgentesRemotos.Agente
    let consultando: Bool
    let volver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button(action: volver) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        Text(agente.nombre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Circle().fill(agente.estado.color).frame(width: 6, height: 6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Volver a Agentes")
                Spacer(minLength: 4)
                Text(pie).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
            }
            if agente.tareas.isEmpty {
                Text(agente.alertas.first ?? agente.error ?? "Sin tareas programadas")
                    .font(.system(size: 11)).foregroundStyle(agente.estado.color).lineLimit(2)
            } else {
                RielHoy(tareas: agente.tareas)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(filas.prefix(3)) { FilaTarea(fila: $0) }
                }
            }
        }
    }

    private var pie: String {
        if consultando { return "actualizando…" }
        let activas = agente.tareas.filter(\.activa).count
        let pausadas = agente.tareas.count - activas
        guard activas + pausadas > 0 else { return agente.actualizado.map { Tiempo.hace($0) } ?? "" }
        return "\(activas) activas" + (pausadas > 0 ? " · \(pausadas) en pausa" : "")
    }

    /// Lo que falló primero; luego lo que corre, la última que corrió bien y la próxima.
    private var filas: [FilaTarea.Datos] {
        let activas = agente.tareas.filter(\.activa)
        var filas = activas.filter { $0.estado == "error" }.map {
            FilaTarea.Datos(id: "e" + $0.nombre, etiqueta: "Falló", nombre: $0.nombre,
                            hora: $0.ultima.map(Tiempo.hora) ?? "", color: $0.color, hueco: false, ayuda: $0.detalle)
        }
        filas += activas.filter { $0.estado == "corriendo" }.map {
            FilaTarea.Datos(id: "c" + $0.nombre, etiqueta: "Ahora", nombre: $0.nombre, hora: "corriendo",
                            color: .white, hueco: false, ayuda: $0.detalle)
        }
        if let u = activas.filter({ $0.estado == "ok" }).max(by: { ($0.ultima ?? .distantPast) < ($1.ultima ?? .distantPast) }),
           let cuando = u.ultima {
            filas.append(.init(id: "u" + u.nombre, etiqueta: "Última", nombre: u.nombre, hora: Tiempo.hora(cuando),
                               color: u.color, hueco: false, ayuda: u.detalle))
        }
        if let p = activas.filter({ ($0.proxima ?? .distantPast) > Date() }).min(by: { $0.proxima! < $1.proxima! }),
           let cuando = p.proxima {
            filas.append(.init(id: "p" + p.nombre, etiqueta: "Próxima", nombre: p.nombre, hora: Tiempo.hora(cuando),
                               color: .white.opacity(0.6), hueco: true, ayuda: p.detalle))
        }
        return filas
    }
}

/// "● Última   informe-matutino          8:03 a. m."
struct FilaTarea: View {
    struct Datos: Identifiable {
        let id: String
        let etiqueta: String
        let nombre: String
        let hora: String
        let color: Color
        let hueco: Bool
        let ayuda: String
    }

    let fila: Datos

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if fila.hueco { Circle().stroke(fila.color, lineWidth: 1.2) } else { Circle().fill(fila.color) }
            }
            .frame(width: 6, height: 6)
            Text(fila.etiqueta).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                .frame(width: 40, alignment: .leading)
            Text(fila.nombre).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            Spacer(minLength: 4)
            Text(fila.hora).font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(fila.etiqueta == "Falló" ? fila.color : .white.opacity(0.5)).lineLimit(1)
        }
        .help(fila.ayuda)
    }
}

/// El día de hoy en una línea, de medianoche a medianoche: lo que ya corrió en puntos llenos (verde bien,
/// rojo falló), lo que falta hoy en anillos y una marca en la hora actual. Las tareas a la misma hora se apilan.
struct RielHoy: View {
    let tareas: [AgentesRemotos.Tarea]
    var ahora = Date()

    private struct Marca: Identifiable {
        let id: String
        let x: Double        // fracción del día (0–1)
        let color: Color
        let hueco: Bool
        var carril = 0
    }

    var body: some View {
        let marcas = apiladas()
        let hoy = fraccion(ahora)
        VStack(spacing: 2) {
            GeometryReader { g in
                let w = g.size.width
                let centro = g.size.height / 2
                ZStack(alignment: .topLeading) {
                    Capsule().fill(.white.opacity(0.1)).frame(width: w, height: 2).position(x: w / 2, y: centro)
                    Capsule().fill(.white.opacity(0.28)).frame(width: w * hoy, height: 2).position(x: w * hoy / 2, y: centro)
                    ForEach(marcas) { m in
                        Group {
                            if m.hueco {
                                Circle().stroke(m.color, lineWidth: 1.2).background(Circle().fill(.black))
                            } else {
                                Circle().fill(m.color).overlay(Circle().stroke(.black, lineWidth: 1))
                            }
                        }
                        .frame(width: 7, height: 7)
                        .position(x: w * m.x, y: centro + [0, -6, 6][min(m.carril, 2)])
                    }
                    Capsule().fill(.white).frame(width: 1.5, height: 14).position(x: w * hoy, y: centro)
                }
            }
            .frame(height: 20)
            GeometryReader { g in
                ZStack {
                    ForEach([(0.25, "6 a.m."), (0.5, "12 m."), (0.75, "6 p.m.")], id: \.0) { x, texto in
                        Text(texto).font(.system(size: 8.5)).foregroundStyle(.white.opacity(0.3)).fixedSize()
                            .position(x: g.size.width * x, y: g.size.height / 2)
                    }
                }
            }
            .frame(height: 10)
        }
    }

    private func fraccion(_ fecha: Date) -> Double {
        let inicio = Calendar.current.startOfDay(for: ahora)
        return min(1, max(0, fecha.timeIntervalSince(inicio) / 86_400))
    }

    /// Hoy: la última corrida (si fue hoy) y la próxima (si es hoy) de cada tarea activa.
    private func apiladas() -> [Marca] {
        let cal = Calendar.current
        var marcas: [Marca] = []
        for t in tareas where t.activa {
            if t.estado == "corriendo" {
                marcas.append(Marca(id: "c" + t.nombre, x: fraccion(ahora), color: .white, hueco: false))
            } else if let u = t.ultima, cal.isDate(u, inSameDayAs: ahora), u <= ahora {
                marcas.append(Marca(id: "u" + t.nombre, x: fraccion(u), color: t.color, hueco: false))
            }
            if let p = t.proxima, cal.isDate(p, inSameDayAs: ahora), p > ahora {
                marcas.append(Marca(id: "p" + t.nombre, x: fraccion(p), color: .white.opacity(0.6), hueco: true))
            }
        }
        // Dos puntos a menos de ~20 min se apilan en otro carril (al centro, arriba, abajo).
        marcas.sort { $0.x < $1.x }
        var ultimoPorCarril = [Double](repeating: -1, count: 3)
        for i in marcas.indices {
            let carril = (0..<3).first { marcas[i].x - ultimoPorCarril[$0] > 0.014 } ?? 2
            marcas[i].carril = carril
            ultimoPorCarril[carril] = marcas[i].x
        }
        return marcas
    }
}
