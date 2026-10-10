import Foundation

// Papelera que libera de verdad (parte de Limpieza, sin interruptor). Mandar a la Papelera no libera espacio
// hasta vaciarla, y vaciarla borra también lo que botaste a propósito. "Liberar ya" borra para siempre
// únicamente lo que Dictado mandó a la Papelera según su bitácora, y solo si sigue allí y es lo mismo que movió.
// Aquí también vive "Espacio oculto": lo que ocupa disco sin estar en ninguna carpeta tuya (solo lectura).

extension Bitacora {
    /// Algo que Dictado mandó a la Papelera y sigue allí.
    struct Pendiente: Sendable {
        let fecha: Date                      // cuándo lo mandó Dictado (la fecha de su limpieza)
        let movimiento: RegistroLimpieza.Movimiento
        let bytes: Int64
        /// Menos de 7 días en la Papelera: todavía se puede deshacer, así que borrarlo pide una confirmación aparte.
        var reciente: Bool { Date().timeIntervalSince(fecha) < 7 * 86_400 }
    }

    struct Liberado: Sendable {
        var cuantos = 0
        var bytes: Int64 = 0
        var fallidos = 0
    }

    static var carpetaPapelera: URL { Escaner.casa.appendingPathComponent(".Trash") }

    /// Lo que Dictado dejó en la Papelera y se puede borrar sin riesgo de tocar nada tuyo. `medir` vuelve a medir
    /// cada elemento (para mostrar el tamaño exacto antes de borrar); si no, usa el tamaño anotado al moverlo.
    static func pendientes(papelera: URL = carpetaPapelera, en destino: URL = archivo, medir: Bool = false) -> [Pendiente] {
        let base = resuelta(papelera)
        return todas(destino).flatMap { r in
            r.movimientos.compactMap { m -> Pendiente? in
                guard sigueAhi(m, fecha: r.fecha, papelera: base) else { return nil }
                let bytes = medir ? (Escaner.bytes(URL(fileURLWithPath: m.papelera)) ?? m.bytes) : m.bytes
                return Pendiente(fecha: r.fecha, movimiento: m, bytes: bytes)
            }
        }
    }

    /// Borra para siempre lo elegido (vuelve a comprobar cada ruta justo antes) y quita de la bitácora lo borrado,
    /// para que "Deshacer" no ofrezca devolver algo que ya no existe.
    static func liberar(_ elegidos: [Pendiente], papelera: URL = carpetaPapelera, en destino: URL = archivo) -> Liberado {
        let base = resuelta(papelera)
        var r = Liberado()
        var borrados: Set<String> = []  // fecha del registro + ruta en la Papelera
        for p in elegidos {
            guard sigueAhi(p.movimiento, fecha: p.fecha, papelera: base) else { continue }
            do {
                try FileManager.default.removeItem(at: URL(fileURLWithPath: p.movimiento.papelera))
                r.cuantos += 1
                r.bytes += p.bytes
                borrados.insert(clave(p.fecha, p.movimiento.papelera))
            } catch {
                r.fallidos += 1
            }
        }
        guard !borrados.isEmpty else { return r }
        let lista = todas(destino).compactMap { reg -> RegistroLimpieza? in
            let quedan = reg.movimientos.filter { !borrados.contains(clave(reg.fecha, $0.papelera)) }
            return quedan.isEmpty ? nil : RegistroLimpieza(fecha: reg.fecha, titulo: reg.titulo, movimientos: quedan)
        }
        escribir(lista, en: destino)
        return r
    }

    /// Las tres condiciones para tocar algo: está directamente dentro de la Papelera (no en otra carpeta ni detrás
    /// de un enlace), existe y es lo mismo que movió Dictado. Si no se puede confirmar, no se toca.
    private static func sigueAhi(_ m: RegistroLimpieza.Movimiento, fecha: Date, papelera: String) -> Bool {
        let url = URL(fileURLWithPath: m.papelera).standardizedFileURL
        guard !url.lastPathComponent.isEmpty, url.lastPathComponent != "..", url.lastPathComponent != ".",
              resuelta(url.deletingLastPathComponent()) == papelera,
              let v = try? url.resourceValues(forKeys: [.fileIdentifierKey, .addedToDirectoryDateKey]) else { return false }
        if let id = m.identificador { return v.fileIdentifier == id }
        // Bitácoras viejas, sin identificador: tuvo que llegar a la Papelera en el momento de esa limpieza.
        guard let llegada = v.addedToDirectoryDate else { return false }
        return llegada > fecha.addingTimeInterval(-600) && llegada < fecha.addingTimeInterval(60)
    }

    private static func resuelta(_ carpeta: URL) -> String {
        carpeta.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func clave(_ fecha: Date, _ ruta: String) -> String { "\(fecha.timeIntervalSince1970)|\(ruta)" }
}

// MARK: - Espacio oculto (solo lectura)

enum EspacioOculto {
    /// ¿Hay una actualización de macOS descargada y preparada? `tmutil listlocalsnapshots /` no pide administrador.
    static func actualizacionPreparada() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        p.arguments = ["listlocalsnapshots", "/"]
        let tubo = Pipe()
        p.standardOutput = tubo
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let salida = String(data: tubo.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return actualizacionPreparada(salida)
    }

    /// El sistema que está corriendo también es una instantánea "com.apple.os.update-…", así que una sola no
    /// cuenta: hace falta la de preparación (…-MSUPrepareUpdate) o una segunda.
    static func actualizacionPreparada(_ salida: String) -> Bool {
        let lineas = salida.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.os.update-") }
        return lineas.contains { $0.hasSuffix("MSUPrepareUpdate") } || lineas.count >= 2
    }
}
