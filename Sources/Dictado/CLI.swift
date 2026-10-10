import AppKit
import AVFoundation
import Foundation
import Speech
import SwiftUI

/// Hoja comparativa: cada estilo (filas) en tres momentos (columnas), sobre el fondo de pantalla (--estilos).
@MainActor
func hojaEstilos(_ destino: URL, estilos: [Estilo] = Estilo.allCases) -> Bool {
    let fondo = fondoDeMuestra()
    let momentos: [(titulo: String, fase: EstadoHUD.Fase, nivel: Double, t: Double)] = [
        ("Hablas suave", .escuchando, 0.35, 2.1), ("Hablas fuerte", .escuchando, 0.95, 3.4), ("Transcribiendo", .transcribiendo, 0, 5.2),
    ]
    let hoja = VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 0) {
            Color.clear.frame(width: 130)
            ForEach(momentos.indices, id: \.self) { j in
                Text(momentos[j].titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 400, height: 34)
            }
        }
        ForEach(estilos) { estilo in
            HStack(spacing: 0) {
                Text(estilo.nombre).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 130, alignment: .leading).padding(.leading, 16)
                ForEach(momentos.indices, id: \.self) { j in
                    let e = EstadoHUD()
                    let _ = { e.estilo = estilo; e.fase = momentos[j].fase; e.nivel = momentos[j].nivel }()
                    ZStack {
                        Image(nsImage: fondo).resizable().scaledToFill().frame(width: 400, height: 140, alignment: .bottom).clipped()
                        Visual(estado: e, t: momentos[j].t).frame(width: 380, height: 118)
                    }
                    .frame(width: 400, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(4)
                }
            }
        }
    }
    .padding(.vertical, 10)
    .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    let renderer = ImageRenderer(content: hoja.environment(\.colorScheme, .dark))
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Hoja de diseño del HUD en sus estados, sobre el fondo de pantalla y sobre una ventana clara (--vista-hud).
@MainActor
func hojaHUD(_ destino: URL) -> Bool {
    func estado(_ fase: EstadoHUD.Fase, _ nivel: Double, _ texto: String,
                _ icono: String? = nil, _ nota: String? = nil) -> EstadoHUD {
        let e = EstadoHUD()
        e.fase = fase
        e.nivel = nivel
        e.texto = texto
        e.icono = icono
        e.nota = nota
        return e
    }
    let estados = [
        estado(.escuchando, 0.35, ""),
        estado(.escuchando, 0.9, "Recordar enviar la propuesta al cliente antes del"),
        estado(.transcribiendo, 0, "Idea: armar un caso de estudio con los resultados", "tray.and.arrow.down", "A Ideas"),
        estado(.resultado, 0, "Recordar enviar la propuesta al cliente antes del viernes.",
               "doc.on.clipboard", "Copiado al portapapeles"),
    ]
    let fondo = fondoDeMuestra()
    let hoja = HStack(spacing: 0) {
        ForEach([true, false], id: \.self) { sobreFondo in
            VStack(spacing: 0) {
                ForEach(estados.indices, id: \.self) { i in
                    ZStack(alignment: .bottom) {
                        if sobreFondo {
                            Image(nsImage: fondo).resizable().scaledToFill()
                                .frame(width: VistaHUD.ancho, height: VistaHUD.alto, alignment: .bottom).clipped()
                        } else {
                            Color(white: 0.96)
                        }
                        VistaHUD(estado: estados[i], tiempoFijo: 1.3 + Double(i) * 0.37)
                    }
                    .frame(width: VistaHUD.ancho, height: VistaHUD.alto)
                }
            }
        }
    }
    let renderer = ImageRenderer(content: hoja.environment(\.colorScheme, .dark))
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Modo de prueba sin interfaz:
///   Dictado --idiomas
///   Dictado --archivo audio.wav [--motor speech|dictation] [--idioma es-CO]
enum CLI {
    static func ejecutar(_ args: [String]) async -> Int32 {
        func valor(_ bandera: String) -> String? {
            guard let i = args.firstIndex(of: bandera), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let idioma = valor("--idioma") ?? Ajustes().idioma

        if args.contains("--idiomas") {
            print("SpeechTranscriber.isAvailable:", SpeechTranscriber.isAvailable)
            for motor in Motor.allCases {
                let soportados: [Locale]
                let instalados: [Locale]
                switch motor {
                case .speech:
                    soportados = await SpeechTranscriber.supportedLocales
                    instalados = await SpeechTranscriber.installedLocales
                case .dictation:
                    soportados = await DictationTranscriber.supportedLocales
                    instalados = await DictationTranscriber.installedLocales
                }
                let es = { (l: [Locale]) in l.map(\.identifier).filter { $0.hasPrefix("es") }.sorted().joined(separator: ", ") }
                print("\n[\(motor.rawValue)] soportados es*: \(es(soportados))")
                print("[\(motor.rawValue)] instalados es*: \(es(instalados))")
                if let locale = await Transcripcion.localeSoportado(motor, para: idioma) {
                    let estado = await AssetInventory.status(forModules: [Transcripcion.crearModulo(motor, locale: locale).modulo])
                    print("[\(motor.rawValue)] \(idioma) → \(locale.identifier), modelo: \(estado)")
                } else {
                    print("[\(motor.rawValue)] \(idioma) → no soportado")
                }
            }
            return 0
        }

        let ajustes = Ajustes()
        let motores = valor("--motor").flatMap(Motor.init(rawValue:)).map { [$0] } ?? Motor.allCases

        if let ruta = valor("--archivo") {
            for motor in motores {
                let t0 = Date()
                do {
                    let texto = try await Transcripcion.transcribirArchivo(
                        URL(fileURLWithPath: ruta), motor: motor, idioma: idioma, vocabulario: ajustes.vocabulario())
                    let corregido = Transcripcion.corregir(texto, con: ajustes.correcciones())
                    print(String(format: "[%@] %.2fs → %@", motor.rawValue, Date().timeIntervalSince(t0), corregido))
                } catch {
                    print("[\(motor.rawValue)] error: \(error.localizedDescription)")
                }
            }
            return 0
        }

        // Mismo camino que el push-to-talk (flujo + conversión + finalización), alimentado desde un archivo.
        if let ruta = valor("--vivo") {
            for motor in motores {
                do {
                    let t0 = Date()
                    let r = try await Reconocedor.preparar(motor: motor, idioma: idioma, vocabulario: ajustes.vocabulario())
                    let tPreparar = Date().timeIntervalSince(t0)
                    let archivo = try AVAudioFile(forReading: URL(fileURLWithPath: ruta))
                    let sesion = SesionEnVivo(r)
                    sesion.iniciarAnalisis()
                    let bloque: AVAudioFrameCount = 1600  // 100 ms a 16 kHz, como llegaría del micrófono
                    while let buffer = AVAudioPCMBuffer(pcmFormat: archivo.processingFormat, frameCapacity: bloque),
                          (try? archivo.read(into: buffer, frameCount: bloque)) != nil, buffer.frameLength > 0 {
                        sesion.alimentar(buffer)
                        if valor("--ritmo") == "real" { try await Task.sleep(for: .milliseconds(100)) }
                    }
                    let t1 = Date()
                    let texto = Transcripcion.corregir(try await sesion.terminar(), con: ajustes.correcciones())
                    print(String(format: "[%@ vivo] preparar %.2fs · tras soltar %.2fs → %@",
                                 motor.rawValue, tPreparar, Date().timeIntervalSince(t1), texto))
                } catch {
                    print("[\(motor.rawValue) vivo] error: \(error.localizedDescription)")
                }
            }
            return 0
        }

        // Salud del Mac con datos reales: dos muestras (2 s) y el análisis de limpieza.
        if args.contains("--salud") {
            let medidor = Medidor()
            _ = medidor.medir()
            try? await Task.sleep(for: .seconds(2))
            let m = medidor.medir()
            print(String(format: "procesador %.0f %% · gráficos %.0f %% · memoria %.1f GB · swap %.1f GB · presión %d · disco libre %.1f GB",
                         m.cpu * 100, m.gpu * 100, m.memoriaUsada / 1e9, m.swap / 1e9, m.presion, m.disco.disponible / 1e9))
            for p in m.procesos.sorted(by: { $0.cpu > $1.cpu }).prefix(6) {
                print(String(format: "  %5.1f %% · %6.0f MB · %@ (dueño %d)", p.cpu * 100, p.memoria / 1e6, p.nombre, p.responsable))
            }
            let t0 = Date()
            let abiertas = await MainActor.run { Escaner.appsAbiertas() }
            let icloud = Funcion.icloud.activa
            let lista = Escaner.analizar(abiertas: abiertas, icloud: icloud)
            for l in lista {
                print("  \(l.segura ? "✓" : "·") \(l.titulo): \(Medida.bytes(Double(l.bytes))) — \(l.detalle) [\(l.items.count)]")
            }
            print(String(format: "análisis de limpieza: %.1f s", Date().timeIntervalSince(t0)))
            // Quitar descargas de iCloud: si la categoría aparece y por qué no, sin listar archivos.
            let raices = Escaner.carpetasICloud()
            let nube = lista.first(where: \.esNube)
            print("iCloud: función \(icloud ? "activa" : "apagada") · iCloud Drive \(raices.isEmpty ? "no está" : "sí (\(raices.count) carpeta\(raices.count == 1 ? "" : "s"))")"
                  + " · categoría: " + (nube.map { "aparece, \($0.items.count) archivos, \(Medida.bytes(Double($0.total)))" } ?? "no aparece"))
            // Espacio oculto y lo que Dictado dejó en la Papelera (solo lectura).
            let d = medidor.disco(fresco: true)
            print("espacio oculto: actualización de macOS lista: \(EspacioOculto.actualizacionPreparada() ? "sí" : "no")"
                  + " · memoria de reserva en disco: \(Medida.bytes(m.swap))"
                  + " · macOS puede liberar solo: \(Medida.bytes(max(0, d.disponible - d.libre)))")
            let pendientes = Bitacora.pendientes()
            let viejos = pendientes.filter { !$0.reciente }
            print("papelera de Dictado: \(pendientes.count) elementos · \(Medida.bytes(Double(pendientes.reduce(0) { $0 + $1.bytes })))"
                  + " (más de 7 días: \(Medida.bytes(Double(viejos.reduce(0) { $0 + $1.bytes }))))")
            return 0
        }

        // Agentes remotos configurados en el ajuste `agentes`, como los ve la pestaña Agentes.
        if args.contains("--agentes") {
            let lista = UserDefaults(suiteName: "app.dictado")?.array(forKey: "agentes") as? [[String: Any]] ?? []
            if lista.isEmpty { print("sin agentes configurados (defaults write app.dictado agentes …)") }
            for d in lista {
                guard let n = d["nombre"] as? String, let cmd = d["comando"] as? String else { continue }
                let a = AgentesRemotos.consultar(nombre: n, comando: cmd)
                print("· \(a.nombre): \(a.estado.rawValue) — \(a.resumen)\(a.error.map { " (\($0))" } ?? "")")
                a.alertas.forEach { print("  ⚠︎ \($0)") }
                a.tareas.forEach { print("  \($0.estado) \($0.nombre)") }
            }
            return 0
        }

        // Sesiones de Claude y tokens de hoy, como los ve la isla (solo lectura de ~/.claude).
        if args.contains("--claude") {
            let sesiones = await MainActor.run { () -> [SesionesClaude.Sesion] in
                let c = SesionesClaude(vivo: false)
                c.leer(avisar: false)
                return c.sesiones
            }
            for var s in sesiones {
                let t0 = Date()
                s.aplicar(Transcripto.leer(s.id))
                print(String(format: "· %@ — %@ %@ — hace: \"%@\" — última frase: \"%@\" (%.0f ms)", s.nombre, "\(s.estado)", s.espera,
                             s.actividad, s.resumen, Date().timeIntervalSince(t0) * 1000))
            }
            let t0 = Date()
            let uso = UsoClaude().calcular(sesiones: sesiones.map(\.id))
            print(String(format: "hoy: %d respuestas · %d tokens escritos · %.2f s", uso.respuestas, uso.tokens, Date().timeIntervalSince(t0)))
            for (id, ctx) in uso.contexto { print("  contexto", sesiones.first { $0.id == id }?.nombre ?? id, ctx) }
            return 0
        }

        // ¿Pegaría ahora? Siempre, salvo en un campo de contraseña.
        if args.contains("--foco") {
            let contrasena = await MainActor.run { Salida.focoEsContrasena() }
            print("accesibilidad:", AXIsProcessTrusted(), "· pegaría:", !contrasena)
            return 0
        }

        // OCR de una imagen (mismo motor que "Texto de un área"): --ocr imagen.png
        if let ruta = valor("--ocr") {
            let texto = (try? await Captura.reconocerTexto(URL(fileURLWithPath: ruta))) ?? ""
            print(texto.isEmpty ? "(sin texto)" : texto)
            return 0
        }

        // Prueba de la captura a _inbox: --guardar "texto" [--carpeta /ruta/_inbox]
        if let texto = valor("--guardar") {
            let carpeta = valor("--carpeta").map { URL(fileURLWithPath: $0) } ?? ajustes.carpetaInbox
            do {
                let archivo = try Inbox.guardar(texto, en: carpeta)
                print("guardado:", archivo.path, "· commit:", Inbox.commitear(archivo) ? "ok" : "falló")
                return 0
            } catch {
                print("error:", error.localizedDescription)
                return 1
            }
        }

        // Pulido con IA local, sin abrir la app: --pulir "texto" [--app bundle.id] [--titulo "título de la pestaña"]
        // [--vocabulario "Término1,Término2"] (sin --vocabulario usa tu vocabulario.txt)
        if let texto = valor("--pulir") {
            print("FoundationModels:", IALocal.problema ?? "disponible")
            let modo = TablaModos.modo(app: valor("--app"), titulo: valor("--titulo"))
            let vocabulario = valor("--vocabulario").map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                ?? ajustes.vocabulario()
            let t0 = Date()
            let r = await PulidoIA.pulir(texto, modo: modo, vocabulario: vocabulario)
            print(String(format: "[%@ · %.2f s · %@]", modo.rawValue, Date().timeIntervalSince(t0), r.motivo))
            print(r.texto)
            return 0
        }

        // Acciones sobre texto seleccionado, sin panel: --accion traducir|corregir|resumir|formal "texto"
        if let i = args.firstIndex(of: "--accion"), i + 2 < args.count {
            let nombres: [String: AccionTexto] = ["traducir": .traducir, "corregir": .corregir, "resumir": .resumir, "formal": .formal]
            guard let accion = nombres[args[i + 1]] else {
                print("acciones: traducir, corregir, resumir, formal")
                return 64
            }
            let texto = args[i + 2]
            let t0 = Date()
            do {
                let (resultado, detalle) = accion == .traducir
                    ? try await AccionesTexto.traducir(texto) : try await AccionesTexto.transformar(texto, accion)
                print(String(format: "[%@ · %.2f s]", detalle, Date().timeIntervalSince(t0)))
                print(resultado)
                return 0
            } catch {
                print("[\(accion.titulo)] \(AccionesTexto.mensaje(error))")
                return 1
            }
        }

        if args.contains("--probar-acciones") {
            return await probarAcciones() ? 0 : 1
        }

        print("uso: Dictado [--idiomas] [--archivo|--vivo audio.wav [--motor speech|dictation] [--idioma es-US] [--ritmo real]]")
        print("     Dictado --pulir \"texto\" [--app bundle.id] [--titulo \"pestaña\"] · --accion traducir|corregir|resumir|formal \"texto\"")
        return 64
    }
}
