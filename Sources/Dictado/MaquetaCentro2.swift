import AppKit
import SwiftUI

// Render del centro de mando con las MISMAS vistas de la ventana real (CentroVistas.swift), para revisar el diseño
// sin abrir la app:
//   Dictado --vista-centro2 salida.png [hoy|metas|orquesta]      con DICTADO_CENTRO_ESTADO=<carpeta con los JSON sueltos>
//   Dictado --vista-centro-real salida.png [hoy|metas|orquesta]  con el comando configurado (defaults app.dictado centro)

@MainActor
func hojaCentro2(_ destino: URL, escena: String?) -> Bool {
    let estado = ProcessInfo.processInfo.environment["DICTADO_CENTRO_ESTADO"]
        .flatMap { EstadoCentro.deCarpeta(URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) }
    return renderCentro(estado, destino: destino, escena: escena, ctx: ContextoCentro(sesiones: sesionesAhora()))
}

@MainActor
func hojaCentroReal(_ destino: URL, escena: String?) -> Bool {
    guard let comando = CentroStore.comando else {
        FileHandle.standardError.write(Data("Sin configurar: defaults write app.dictado centro -dict comando …\n".utf8))
        return false
    }
    let inicio = Date()
    let (datos, fallo) = CentroStore.ejecutar(comando)
    guard let datos, let estado = EstadoCentro.decodificar(datos) else {
        FileHandle.standardError.write(Data("No se pudo leer el centro: \(fallo ?? "respuesta inválida")\n".utf8))
        return false
    }
    print(String(format: "centro leído en %.1f s · VPS: %@ · brief: %@ · metas: %@ · noticias: %d · orquesta: %@ · finanzas: %@",
                 Date().timeIntervalSince(inicio), estado.vps ? "sí" : "no", estado.brief == nil ? "no" : "sí",
                 estado.metas == nil ? "no" : "sí", estado.noticias?.items.count ?? 0,
                 estado.orquesta == nil ? "no" : "sí", estado.finanzas == nil ? "no" : "sí"))
    let c = SesionesClaude(vivo: false)
    c.leer(avisar: false)
    return renderCentro(estado, destino: destino, escena: escena,
                        ctx: ContextoCentro(sesiones: c.sesiones, leido: Date(), puedeActuar: CentroStore.acciones != nil,
                                            tokensHoy: c.tokensHoy, respuestasHoy: c.respuestasHoy))
}

@MainActor
private func sesionesAhora() -> [SesionesClaude.Sesion] {
    let c = SesionesClaude(vivo: false)
    c.leer(avisar: false)
    return c.sesiones
}

@MainActor
private func renderCentro(_ estado: EstadoCentro?, destino: URL, escena: String?, ctx: ContextoCentro) -> Bool {
    let medidas = (ProcessInfo.processInfo.environment["DICTADO_LIENZO"] ?? "").split(separator: "x").compactMap { Double($0) }
    let lienzo = medidas.count == 2 ? CGSize(width: medidas[0], height: medidas[1]) : CGSize(width: 1600, height: 1000)
    let seccion = SeccionCentro(rawValue: escena ?? "hoy") ?? .hoy
    let vista = ZStack {
        FondoEspacio(imagen: fondoDeMuestra())
        VistaCentro(estado: estado, ctx: ctx, seccion: .constant(seccion))
    }
    .frame(width: lienzo.width, height: lienzo.height)
    .environment(\.vidrioSimulado, true)
    .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: vista)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}
