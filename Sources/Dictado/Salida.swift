import AppKit
import Carbon.HIToolbox
import os

private let log = Logger(subsystem: "app.dictado", category: "salida")

enum Salida {
    enum Resultado { case pegado, copiado, sinPermiso }

    /// El texto siempre queda en el portapapeles y se pega donde está el cursor. No se intenta adivinar si hay
    /// un campo de texto: Chrome y las apps Electron (Claude, Slack, WhatsApp, Notion) no se lo cuentan a
    /// Accesibilidad, y un ⌘V sin campo de texto no hace nada. Solo se salta en campos de contraseña.
    @MainActor
    static func entregar(_ texto: String) async -> Resultado {
        let portapapeles = NSPasteboard.general
        portapapeles.clearContents()
        portapapeles.setString(texto, forType: .string)
        guard AXIsProcessTrusted() else { return .sinPermiso }
        guard !focoEsContrasena() else { return .copiado }
        await simularPegar()
        return .pegado
    }

    /// ⌘V en la app con el foco. Espera a que sueltes ⌥/⇧/⌘: si siguen presionadas, llegaría como ⌘⌥V.
    @MainActor
    static func simularPegar() async {
        var espera = 0
        while !NSEvent.modifierFlags.intersection([.option, .shift, .control, .command]).isEmpty, espera < 30 {
            try? await Task.sleep(for: .milliseconds(50))
            espera += 1
        }
        let fuente = CGEventSource(stateID: .combinedSessionState)
        for abajo in [true, false] {
            let evento = CGEvent(keyboardEventSource: fuente, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: abajo)
            evento?.flags = .maskCommand
            evento?.post(tap: .cghidEventTap)
        }
    }

    /// ¿El cursor está en un campo de contraseña? Ahí no se pega un dictado.
    @MainActor
    static func focoEsContrasena() -> Bool {
        let sistema = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sistema, 0.3)
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sistema, kAXFocusedUIElementAttribute as CFString, &valor) == .success,
              let valor, CFGetTypeID(valor) == AXUIElementGetTypeID() else { return false }
        var rol: CFTypeRef?
        AXUIElementCopyAttributeValue(valor as! AXUIElement, kAXRoleAttribute as CFString, &rol)
        var subrol: CFTypeRef?
        AXUIElementCopyAttributeValue(valor as! AXUIElement, kAXSubroleAttribute as CFString, &subrol)
        return (rol as? String) == "AXSecureTextField" || (subrol as? String) == "AXSecureTextField"
    }
}

/// Ideas por voz (⌥⇧Espacio): una nota idea-<slug>-<YYYYMMDDHHmm>.md en tu carpeta de ideas; si esa carpeta está
/// dentro de un repositorio git, se hace commit al instante para no perder nada.
enum Inbox {
    static func guardar(_ texto: String, en carpeta: URL) throws -> URL {
        let ahora = Date()
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "en_US_POSIX")
        formato.dateFormat = "yyyyMMddHHmm"
        let sello = formato.string(from: ahora)
        formato.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let fecha = formato.string(from: ahora)

        let slug = slug(de: texto)
        var url = carpeta.appendingPathComponent("idea-\(slug)-\(sello).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = carpeta.appendingPathComponent("idea-\(slug)-\(sello)-\(n).md")
            n += 1
        }
        let contenido = "---\ndate: \(fecha)\nsource: dictado-mac\n---\n\n\(texto)\n"
        try contenido.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func slug(de texto: String) -> String {
        let base = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
        let palabras = base.split { !$0.isLetter && !$0.isNumber }.prefix(6)
        let slug = String(palabras.joined(separator: "-").prefix(48)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "dictado" : slug
    }

    /// Commit solo de ese archivo (no arrastra lo que otras sesiones tengan en staging). No hace push:
    /// el ritual diario sincroniza con GitHub. Bloquea: llamar fuera del hilo principal.
    @discardableResult
    static func commitear(_ archivo: URL) -> Bool {
        let carpeta = archivo.deletingLastPathComponent().path
        let nombre = archivo.lastPathComponent
        for intento in 1...3 {
            if git(carpeta, ["add", "--", nombre]),
               git(carpeta, ["commit", "-q", "-m", "captura: \(nombre) (dictado Mac)", "--", nombre]) {
                return true
            }
            log.error("commit de \(nombre, privacy: .public) falló (intento \(intento))")
            Thread.sleep(forTimeInterval: 2)  // otra sesión puede tener el index.lock
        }
        return false
    }

    private static func git(_ carpeta: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", carpeta] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
