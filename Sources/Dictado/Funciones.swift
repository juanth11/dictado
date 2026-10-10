import AppKit

/// Funciones opcionales de Dictado. Cada una vive en su propio archivo, se prende o apaga desde el menú
/// "Funciones" y está documentada en docs/FUNCIONES.md (qué hace, qué archivos toca, qué permiso usa y cómo
/// quitarla del todo).
enum Funcion: String, CaseIterable {
    case hyper, ventanas, buscador, pulido, acciones, icloud

    var titulo: String {
        switch self {
        case .hyper: return "Tecla hyper (Bloq Mayús)"
        case .ventanas: return "Ventanas por teclado"
        case .buscador: return "Buscador de ventanas"
        case .pulido: return "Dictado pulido con IA local"
        case .acciones: return "Acciones sobre texto seleccionado"
        case .icloud: return "Quitar descargas de iCloud (limpieza)"
        }
    }

    var detalle: String {
        switch self {
        case .hyper: return "Mantén Bloq Mayús = ⌃⌥⌘⇧ para atajos que no chocan con nada; sola = Esc"
        case .ventanas: return "Hyper + flechas: mitades, tercios, casi maximizar, otra pantalla, restaurar"
        case .buscador: return "Hyper + Espacio: busca una ventana por su título y salta a ella"
        case .pulido: return "Limpia muletillas y puntuación del dictado según la app (todo en el Mac)"
        case .acciones: return "Hyper + T: traducir, corregir, resumir o mandar a Claude el texto seleccionado"
        case .icloud: return "En Limpieza, libera archivos grandes que ya están en iCloud (siguen en la nube)"
        }
    }

    var activa: Bool {
        UserDefaults(suiteName: "app.dictado")?.object(forKey: "funcion." + rawValue) as? Bool ?? true
    }

    func poner(_ si: Bool) {
        UserDefaults(suiteName: "app.dictado")?.set(si, forKey: "funcion." + rawValue)
        NotificationCenter.default.post(name: .funcionesCambiaron, object: nil, userInfo: ["funcion": rawValue])
    }
}

extension Notification.Name {
    /// Se publica cuando prendes o apagas una función en el menú; userInfo["funcion"] = rawValue.
    static let funcionesCambiaron = Notification.Name("dictado.funcionesCambiaron")
}

/// Lo que un módulo puede usar de la app sin depender de sus detalles internos.
@MainActor
struct ContextoModulos {
    /// Aviso corto en la isla (o en el indicador si no hay isla): texto, símbolo SF, nota opcional.
    let avisar: (String, String, String?) -> Void
    /// Guarda una idea en la carpeta de ideas (como ⌥⇧Espacio).
    let guardarIdea: (String) -> Void
    let abrirPortapapeles: () -> Void
    let abrirCaptura: () -> Void
    let abrirSalud: () -> Void
    /// Abre el enlace de la reunión en curso o la próxima (Meet, Zoom, Teams).
    let unirseAProxima: () -> Void
    /// El módulo de pulido registra aquí su transformación: recibe el texto dictado y devuelve el final.
    let registrarPulido: (@escaping @MainActor (String) async -> String) -> Void
}
