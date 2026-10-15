import AppKit
import Observation
import SwiftUI

/// Bloques de foco: un tiempo para una sola cosa (por ejemplo, una prioridad del brief). Mientras corre, la isla
/// muestra el anillo y los minutos; al terminar suena una campana suave y la isla pregunta si quedó hecha, y la
/// pregunta sigue ahí (anillo lleno, "¿Hecha?") hasta que respondes. Lo de hoy se ve en el Centro.
/// Todo queda en el Mac (las preferencias de Dictado). Mientras corre no hay nada en bucle: un temporizador al final.
@MainActor @Observable
final class Foco {
    struct Bloque: Codable, Equatable {
        var titulo: String
        var vertical: String?
        var inicio: Date
        var minutos: Int
        var fin: Date { inicio.addingTimeInterval(Double(minutos) * 60) }
    }

    struct Registro: Codable, Equatable {
        var titulo: String
        var minutos: Int
        var hecha: Bool
        var fin: Date
    }

    private(set) var activo: Bloque?
    private(set) var hoy: [Registro] = []
    /// Lo avisa la isla (la pregunta "¿quedó hecha?").
    @ObservationIgnored var alTerminar: ((Bloque) -> Void)?

    @ObservationIgnored private var reloj: Timer?
    @ObservationIgnored private let vivo: Bool

    init(vivo: Bool = true) {
        self.vivo = vivo
        guard vivo else { return }
        let d = UserDefaults.dictado
        if let datos = d.data(forKey: "foco.activo"), let b = try? JSONDecoder().decode(Bloque.self, from: datos) { activo = b }
        if let datos = d.data(forKey: "foco.hoy"), let r = try? JSONDecoder().decode([Registro].self, from: datos) {
            hoy = r.filter { Calendar.current.isDateInToday($0.fin) }
        }
        programar()
    }

    /// Ya pasó el tiempo y falta tu respuesta.
    var terminado: Bool { activo.map { Date() >= $0.fin } ?? false }
    var minutosHoy: Int { hoy.reduce(0) { $0 + $1.minutos } }
    /// Lo que quedó hecho hoy (para marcar las prioridades del brief).
    var hechas: Set<String> { Set(hoy.filter(\.hecha).map(\.titulo)) }

    func restante(en ahora: Date) -> TimeInterval { max(0, (activo?.fin ?? ahora).timeIntervalSince(ahora)) }

    func fraccion(en ahora: Date) -> Double {
        guard let b = activo, b.minutos > 0 else { return 0 }
        return min(1, max(0, ahora.timeIntervalSince(b.inicio) / (Double(b.minutos) * 60)))
    }

    /// `inicio` solo cambia en los renders (un bloque que ya va por la mitad).
    func empezar(_ titulo: String, minutos: Int, vertical: String? = nil, inicio: Date = Date()) {
        let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        activo = Bloque(titulo: t.isEmpty ? "Bloque de foco" : t, vertical: vertical, inicio: inicio, minutos: max(5, min(120, minutos)))
        guardar()
        programar()
    }

    /// Unos minutos más (también después de terminado: vuelve a correr).
    func extender(_ minutos: Int) {
        guard var b = activo else { return }
        let ahora = Date()
        if ahora >= b.fin {
            b.minutos = Int(ahora.timeIntervalSince(b.inicio) / 60) + minutos
        } else {
            b.minutos += minutos
        }
        activo = b
        guardar()
        programar()
    }

    /// Cierra el bloque: hecha (true), sin terminar (false) o cancelado (nil, no cuenta).
    func cerrar(hecha: Bool?) {
        guard let b = activo else { return }
        if let hecha {
            let minutos = max(1, Int(min(Date(), b.fin).timeIntervalSince(b.inicio) / 60))
            hoy.append(Registro(titulo: b.titulo, minutos: minutos, hecha: hecha, fin: Date()))
        }
        activo = nil
        reloj?.invalidate()
        reloj = nil
        guardar()
    }

    private func programar() {
        reloj?.invalidate()
        reloj = nil
        guard vivo, let b = activo, b.fin > Date() else { return }
        reloj = Timer.scheduledTimer(withTimeInterval: b.fin.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let b = self.activo else { return }
                NSSound(named: "Glass")?.play()
                self.alTerminar?(b)
            }
        }
    }

    private func guardar() {
        guard vivo else { return }
        let d = UserDefaults.dictado
        if let activo, let datos = try? JSONEncoder().encode(activo) { d.set(datos, forKey: "foco.activo") } else { d.removeObject(forKey: "foco.activo") }
        if let datos = try? JSONEncoder().encode(hoy) { d.set(datos, forKey: "foco.hoy") }
    }

    /// El siguiente bloque que propone Hyper + F: la primera prioridad del brief que no esté hecha (con sus minutos),
    /// o el foco del día; sin brief, un bloque genérico de 25 minutos.
    static func propuesta(_ estado: EstadoCentro?, hechas: Set<String>) -> (titulo: String, minutos: Int, vertical: String?) {
        if let b = estado?.brief {
            if let p = b.prioridades.first(where: { !$0.hecha && !hechas.contains($0.texto) }) {
                return (p.texto, p.minutos.map { max(10, min(90, $0)) } ?? 25, p.vertical)
            }
            if !b.foco.titulo.isEmpty { return (b.foco.titulo, 25, nil) }
        }
        return ("Bloque de foco", 25, nil)
    }
}

// MARK: - En la isla

/// Anillo de foco: lo que va del bloque en ámbar (el tono del foco del día). Lleno, pide tu respuesta.
struct AnilloFoco: View {
    let fraccion: Double
    var lado: CGFloat = 16
    var grosor: CGFloat = 2.2

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: grosor)
            Circle().trim(from: 0, to: fraccion)
                .stroke(Tono.ambar.claro, style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Tono.ambar.base.opacity(0.7), radius: 2)
        }
        .frame(width: lado, height: lado)
    }
}

/// "18 min" a la derecha de la isla compacta; "¿Hecha?" cuando terminó. Se actualiza una vez por minuto.
struct MinutosFoco: View {
    let foco: Foco

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let falta = foco.restante(en: ctx.date)
            Text(falta <= 0 ? "¿Hecha?" : "\(Int((falta / 60).rounded(.up))) min")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Tono.ambar.claro)
                .fixedSize()
        }
    }
}

/// La isla abierta durante un bloque: el anillo grande con lo que falta, la tarea y los controles. Terminado, la
/// pregunta: hecha, aún no, o unos minutos más.
struct FocoIsla: View {
    let foco: Foco
    let responder: (Bool?) -> Void
    let extender: (Int) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let falta = foco.restante(en: ctx.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        AnilloFoco(fraccion: foco.fraccion(en: ctx.date), lado: 50, grosor: 3)
                        Text(falta <= 0 ? "0" : Tiempo.reloj(falta))
                            .font(.system(size: falta >= 600 ? 11 : 12, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(Halo.texto)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Rotulo(falta <= 0 ? "Terminó el bloque" : "En foco", color: Tono.ambar.claro)
                        Text(foco.activo?.titulo ?? "").font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 6) {
                    if falta <= 0 {
                        BotonHalo(titulo: "Hecha", icono: "checkmark", alto: 26) { responder(true) }
                        BotonHalo(titulo: "Aún no", secundario: true, alto: 26) { responder(false) }
                        BotonHalo(titulo: "+10", secundario: true, alto: 26) { extender(10) }
                    } else {
                        BotonHalo(titulo: "Terminé", icono: "checkmark", alto: 26) { responder(true) }
                        BotonHalo(titulo: "+5", secundario: true, alto: 26) { extender(5) }
                        BotonHalo(titulo: "Soltar", secundario: true, alto: 26) { responder(nil) }
                    }
                }
            }
        }
    }
}
