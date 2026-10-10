import AppKit

let argumentos = CommandLine.arguments
// SwiftUI necesita renderizar en el hilo principal, sin saltos asíncronos.
if argumentos.count > 2, argumentos[1] == "--vista-isla" {
    let ok = MainActor.assumeIsolated { hojaIsla(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-salud" {
    let ok = MainActor.assumeIsolated { hojaSalud(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-captura" {
    let ok = MainActor.assumeIsolated { hojaCaptura(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--probar-portapapeles" {
    let ok = MainActor.assumeIsolated { probarPortapapeles() }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-portapapeles" {
    let ok = MainActor.assumeIsolated { hojaPortapapeles(URL(fileURLWithPath: argumentos[2]), modoLista: argumentos.count > 3) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--estilos" {
    let lista = argumentos.count > 3 ? argumentos[3].split(separator: ",").compactMap { Estilo(rawValue: String($0)) } : Estilo.allCases
    let ok = MainActor.assumeIsolated { hojaEstilos(URL(fileURLWithPath: argumentos[2]), estilos: lista) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-hud" {
    let ok = MainActor.assumeIsolated { hojaHUD(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
// Tecla hyper, ventanas por teclado y buscador (PruebasTeclado.swift).
if let codigo = MainActor.assumeIsolated({ cliTeclado(argumentos) }) { exit(codigo) }
if argumentos.count > 1, argumentos[1].hasPrefix("--") {
    Task {
        let codigo = await CLI.ejecutar(argumentos)
        exit(codigo)
    }
    dispatchMain()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegado = App()
    app.delegate = delegado
    app.setActivationPolicy(.accessory)
    app.run()
}
