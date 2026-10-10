import Foundation

// Función opcional "Quitar descargas de iCloud" (Funcion.icloud, ver docs/FUNCIONES.md). Una categoría de Limpieza
// segura y reversible: archivos de 50 MB o más que ya están en iCloud y descargados en el Mac, sin abrir hace
// 7 días. Quitar la descarga deja el archivo en la nube (se vuelve a bajar al abrirlo); nunca borra nada.
// Es lo único de la limpieza que entra en "Mobile Documents", y solo para esto.

extension Escaner {
    /// iCloud Drive y, si están sincronizados con iCloud, el Escritorio y Documentos. Vacío si no hay iCloud Drive.
    static func carpetasICloud() -> [URL] {
        var raices = ["Desktop", "Documents"].map { casa.appendingPathComponent($0) }.filter(sincronizada)
        let drive = casa.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: drive.path) { raices.append(drive) }
        return raices
    }

    static func descargasICloud() -> [Limpiable] {
        let claves: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsUploadedKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentAccessDateKey,
            .contentModificationDateKey, .fileIdentifierKey,
        ]
        let limite = Date().addingTimeInterval(-7 * 86_400)
        let protegidas = carpetasProtegidasICloud()
        let drive = casa.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").path
        // Si el Escritorio o Documentos se sincronizan, ya se recorren desde ~/Desktop y ~/Documents (así también
        // valen tus carpetas protegidas escritas con esa ruta).
        let repetidas = Set(["Desktop", "Documents"].filter { sincronizada(casa.appendingPathComponent($0)) }.map { drive + "/" + $0 })
        var vistos: Set<UInt64> = []
        var items: [ItemLimpieza] = []
        for raiz in carpetasICloud() {
            guard let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: claves,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                         errorHandler: { _, _ in true }) else { continue }
            for case let u as URL in e {
                if protegidaICloud(u, protegidas) || repetidas.contains(u.path) || u.lastPathComponent == "node_modules" {
                    e.skipDescendants()
                    continue
                }
                guard let v = try? u.resourceValues(forKeys: Set(claves)), v.isSymbolicLink != true,
                      v.isDirectory != true || v.isPackage == true,
                      v.isUbiquitousItem == true, v.ubiquitousItemDownloadingStatus == .current, v.ubiquitousItemIsUploaded == true
                else { continue }
                let ultima = max(v.contentAccessDate ?? .distantPast, v.contentModificationDate ?? .distantPast)
                guard ultima < limite else { continue }
                let b = v.isPackage == true ? (bytes(u) ?? 0) : Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                guard b >= 50_000_000 else { continue }
                if let id = v.fileIdentifier, !vistos.insert(id).inserted { continue }
                items.append(ItemLimpieza(url: u, nombre: u.lastPathComponent,
                                          detalle: "\(lugarICloud(u, drive: drive)) · sin abrir desde \(fechaCorta(ultima))", bytes: b))
            }
        }
        guard !items.isEmpty else { return [] }
        items.sort { $0.bytes > $1.bytes }
        return [Limpiable(id: "icloud", titulo: "Archivos de iCloud descargados",
                          detalle: resumen(items) + " — siguen en iCloud y se descargan al abrirlos",
                          simbolo: "icloud.and.arrow.down", items: items, accion: .quitarDescarga, boton: "Quitar descargas")]
    }

    /// Tus carpetas protegidas (Ajustes.carpetasProtegidas), también con los enlaces resueltos. A diferencia de
    /// `protegido(_:)`, no excluye "Mobile Documents": esta categoría solo quita descargas, nunca borra.
    static func carpetasProtegidasICloud() -> [String] {
        Ajustes.carpetasProtegidas.flatMap { [$0, URL(fileURLWithPath: $0).resolvingSymlinksInPath().path] }
    }

    static func protegidaICloud(_ url: URL, _ protegidas: [String]) -> Bool {
        let rutas = [url.path, url.resolvingSymlinksInPath().path]
        return rutas.contains { r in protegidas.contains { r.hasPrefix($0) } } || url.path.contains("/.Trash/")
    }

    private static func sincronizada(_ carpeta: URL) -> Bool {
        (try? carpeta.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    }

    /// "iCloud Drive › Proyectos", "Escritorio", "Documentos › Informes".
    private static func lugarICloud(_ url: URL, drive: String) -> String {
        let carpeta = url.deletingLastPathComponent().path
        let raices = [(drive, "iCloud Drive"), (casa.appendingPathComponent("Desktop").path, "Escritorio"),
                      (casa.appendingPathComponent("Documents").path, "Documentos")]
        for (ruta, nombre) in raices where carpeta == ruta || carpeta.hasPrefix(ruta + "/") {
            let resto = carpeta.dropFirst(ruta.count).split(separator: "/")
            return ([nombre] + resto.map(String.init)).joined(separator: " › ")
        }
        return carpeta.replacingOccurrences(of: casa.path, with: "~")
    }
}

enum DescargasICloud {
    struct Resultado: Sendable {
        var cuantos = 0
        var bytes: Int64 = 0
    }

    /// Quita la copia local de cada archivo; sigue en iCloud y se vuelve a bajar al abrirlo. Justo antes vuelve a
    /// comprobar que esté descargado y ya subido: nunca quita algo que solo existe en este Mac.
    static func quitar(_ items: [ItemLimpieza]) -> Resultado {
        let protegidas = Escaner.carpetasProtegidasICloud()
        var r = Resultado()
        for item in items where !Escaner.protegidaICloud(item.url, protegidas) {
            let v = try? item.url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey])
            guard v?.isUbiquitousItem == true, v?.ubiquitousItemDownloadingStatus == .current, v?.ubiquitousItemIsUploaded == true,
                  (try? FileManager.default.evictUbiquitousItem(at: item.url)) != nil else { continue }
            r.cuantos += 1
            r.bytes += item.bytes
        }
        return r
    }
}
