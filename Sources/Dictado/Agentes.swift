import Foundation
import Observation

/// Agentes que trabajan para ti fuera del Mac (por ejemplo, un agente en un servidor) y que la pestaña Agentes
/// de la isla muestra junto a las sesiones de Claude Code. Dictado solo LEE su estado: ejecuta un comando que
/// tú configuras y que imprime JSON.
///
/// Configuración (una entrada por agente):
///   defaults write app.dictado agentes -array '{ nombre = "Mi agente"; comando = "/ruta/a/estado.sh"; }'
///
/// El comando debe imprimir algo así (todo opcional salvo `estado`):
///   { "estado": "ok" | "alerta" | "caido",
///     "resumen": "10 tareas activas · todo bien",
///     "alertas": ["informe-diario falló: …"],
///     "tareas": [{ "nombre": "informe-diario", "estado": "ok" | "error" | "pausada" | "corriendo",
///                  "ultima": "2026-10-09T08:03:07-05:00", "proxima": "2026-10-10T08:00:00-05:00",
///                  "detalle": "todos los días a las 8" }] }
@MainActor @Observable
final class AgentesRemotos {
    enum Estado: String { case ok, alerta, caido, desconocido }

    struct Tarea: Identifiable, Equatable {
        var id: String { nombre }
        let nombre: String
        let estado: String          // ok · error · pausada · corriendo
        let ultima: Date?
        let proxima: Date?
        let detalle: String
    }

    struct Agente: Identifiable, Equatable {
        var id: String { nombre }
        let nombre: String
        var estado: Estado = .desconocido
        var resumen = ""
        var alertas: [String] = []
        var tareas: [Tarea] = []
        var actualizado: Date?
        var error: String?          // por qué no se pudo leer (sin conexión, comando inválido…)
    }

    var agentes: [Agente] = []
    var consultando = false
    var hayAlertas: Bool { agentes.contains { $0.estado == .alerta || $0.estado == .caido } }

    /// Aviso para la isla cuando aparece una alerta nueva: agente, alerta.
    @ObservationIgnored var alAlertar: ((String, String) -> Void)?
    @ObservationIgnored private var fuentes: [(nombre: String, comando: String)] = []
    @ObservationIgnored private var reloj: Timer?
    @ObservationIgnored private var ultimaConsulta = Date.distantPast
    @ObservationIgnored private var vistas = Set<String>()

    init(vivo: Bool = true) {
        guard vivo else { return }
        cargarFuentes()
        guard !fuentes.isEmpty else { return }
        agentes = fuentes.map { Agente(nombre: $0.nombre) }
        refrescar(forzar: true, avisar: false)
        reloj = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refrescar(forzar: true, avisar: true) }
        }
    }

    var configurados: Bool { !fuentes.isEmpty }

    private func cargarFuentes() {
        let lista = UserDefaults.dictado.array(forKey: "agentes") as? [[String: Any]] ?? []
        fuentes = lista.compactMap { d in
            guard let n = d["nombre"] as? String, let c = d["comando"] as? String, !n.isEmpty, !c.isEmpty else { return nil }
            return (n, c)
        }
    }

    /// Al abrir la pestaña se pide una lectura fresca, como mucho una cada 2 minutos.
    func refrescar(forzar: Bool = false, avisar: Bool = true) {
        guard !fuentes.isEmpty, !consultando, forzar || Date().timeIntervalSince(ultimaConsulta) > 120 else { return }
        consultando = true
        ultimaConsulta = Date()
        let fuentes = self.fuentes
        Task.detached(priority: .utility) {
            let resultados = fuentes.map { Self.consultar(nombre: $0.nombre, comando: $0.comando) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.consultando = false
                self.agentes = resultados
                for a in resultados {
                    for alerta in a.alertas where !self.vistas.contains(a.nombre + "|" + alerta) {
                        self.vistas.insert(a.nombre + "|" + alerta)
                        if avisar { self.alAlertar?(a.nombre, alerta) }
                    }
                }
            }
        }
    }

    /// Ejecuta el comando (máximo 20 s) y lee su JSON.
    nonisolated static func consultar(nombre: String, comando: String) -> Agente {
        var agente = Agente(nombre: nombre, actualizado: Date())
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", comando]
        let tubo = Pipe()
        p.standardOutput = tubo
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch {
            agente.estado = .desconocido
            agente.error = "No se pudo ejecutar el comando"
            return agente
        }
        let limite = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: limite)
        let datos = tubo.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        limite.cancel()
        guard let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any] else {
            agente.estado = .desconocido
            agente.error = p.terminationReason == .uncaughtSignal ? "No respondió en 20 s" : "Respuesta inválida"
            return agente
        }
        agente.estado = Estado(rawValue: json["estado"] as? String ?? "") ?? .desconocido
        agente.resumen = json["resumen"] as? String ?? ""
        agente.alertas = json["alertas"] as? [String] ?? []
        agente.tareas = (json["tareas"] as? [[String: Any]] ?? []).compactMap { t in
            guard let n = t["nombre"] as? String else { return nil }
            return Tarea(nombre: n, estado: t["estado"] as? String ?? "ok", ultima: fecha(t["ultima"]),
                         proxima: fecha(t["proxima"]), detalle: t["detalle"] as? String ?? "")
        }
        return agente
    }

    nonisolated private static func fecha(_ valor: Any?) -> Date? {
        guard let s = valor as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
