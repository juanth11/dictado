# Dictado

Una sola app nativa de macOS, liviana (unos 40 MB de memoria y 0 % de procesador en reposo), que reemplaza media docena de utilidades. Incluye:

- **Dictado por voz** local, que pega donde está el cursor.
- **Portapapeles** con historial.
- **Capturas** de pantalla con OCR.
- **Una isla en el notch** con música, agenda, llamadas, sesiones de Claude Code, volumen y brillo.
- **Un monitor y limpiador del Mac** honesto.

Todo funciona en el Mac, sin cuentas, sin suscripciones y sin mandar tu voz ni tus archivos a ningún servidor.

![La isla abierta: música con los colores de la carátula, sesiones de Claude Code y la llamada en curso](docs/isla-abierta.jpg)

> **Instalación en un paso:** abre [Claude Code](https://claude.com/claude-code) en esta carpeta y escribe *«instala y configura Dictado»*. Claude sigue las instrucciones de [`CLAUDE.md`](CLAUDE.md), te hace tres preguntas y te guía con los permisos.

---

## Qué hace

| | Cómo se usa | Reemplaza a |
|---|---|---|
| **Dictado** | Mantén **⌥Espacio**, habla y suelta: el texto se pega donde está el cursor (en cualquier app). **⌥⇧Espacio** guarda la idea como nota en tu carpeta de ideas. **Esc** cancela. | Handy, superwhisper, MacWhisper |
| **Portapapeles** | **⌘⌥V**. Historial con búsqueda, filtros, varios elementos a la vez (⌘clic), arrastrar a otras apps, cuadrícula de imágenes, pegado con o sin formato, ⌘1–9. Ignora contraseñas. | Raycast, Paste, Maccy |
| **Captura** | **⌘↩**. Área, ventana, pantalla, texto de una zona (OCR), grabación y temporizador. Destino: portapapeles, Escritorio, Descargas o una carpeta. | CleanShot X (lo básico), TextSniper |
| **Isla del notch** | Siempre visible. Al pasar el mouse se abre. | Atoll, NotchNook, Boring Notch |
| **Salud del Mac** | Pestaña **Mac** de la isla (el ícono ↗ abre el panel) o el menú de Dictado. | CleanMyMac, iStat Menus |
| **Dictado pulido con IA local** (opcional) | Automático al dictar: el modelo de Apple en el Mac quita muletillas y arregla la puntuación, con el tono de la app al frente (chat, correo, prompt, documento). [Ficha](docs/FUNCIONES.md#dictado-pulido-con-ia-local) | Wispr Flow, superwhisper (modos) |
| **Acciones sobre texto seleccionado** (opcional) | **Hyper + T** sobre un texto: traducir, corregir, resumir, más formal, mandar a Claude o guardar como idea; luego Reemplazar o Copiar. [Ficha](docs/FUNCIONES.md#acciones-sobre-texto-seleccionado) | PopClip, Raycast AI |

### La isla

![Todas las vistas de la isla](docs/isla.jpg)

- **Música (Spotify):** carátula, progreso y controles, con un degradado sacado de la carátula. Cuando cambia la canción, aparece "Ahora suena".
- **Agenda:** tus próximos eventos del Calendario de macOS, también de Google si agregas la cuenta en Ajustes → Cuentas de internet. A los 5 minutos de una reunión salen una cuenta regresiva y un botón **Unirse** que abre el Meet, Zoom o Teams del evento.
- **Llamadas:** cuando una app usa el micrófono o la cámara, la isla muestra el ícono de la app, un cronómetro verde y el punto verde (cámara) o naranja (micrófono), como en el iPhone.
- **Claude Code:** tus sesiones abiertas.
  - Qué está haciendo cada una ("Editando App.swift · 4 min").
  - Cuándo te necesita (qué permiso o qué pregunta), con un botón que abre justo esa sesión.
  - Cuándo terminó y con qué frase.
  - El contexto de cada chat y los tokens del día.

  Se lee `~/.claude` en solo lectura.
- **Volumen y brillo:** las teclas del teclado muestran una barra en el notch en lugar del cuadro de macOS.
- **Cargador, dictado en vivo y avisos de salud** del Mac.

### Salud del Mac

![Salud del Mac: Ahora y Limpieza](docs/salud.jpg)

- **Ahora:** un semáforo con la causa en una frase ("El disco está casi lleno", "La memoria está al límite: Claude usa 3,6 GB"). Tiene anillos de procesador, memoria (presión real), gráficos, disco y temperatura, y muestra **quién está consumiendo**: las apps con todos sus procesos sumados y los servicios del sistema explicados en palabras simples.
- **Limpieza honesta**:
  - **Seguro:** cachés de apps cerradas, cachés internas de apps tipo Chrome/Electron, cachés de programación (uv, npm, Playwright…), dependencias (`node_modules`, `.venv`) de proyectos sin tocar hace 60 días, registros y versiones viejas. Todo va **a la Papelera** y se puede **deshacer**. Cada categoría se despliega para marcar y desmarcar elemento por elemento.
  - **Cerrar y limpiar:** para apps abiertas con cachés grandes (como Arc), las cierra como ⌘Q, limpia y las vuelve a abrir como estaban.
  - **Revisa tú:** lo que es tuyo (fotos de WhatsApp, Notas de Voz, archivos grandes o duplicados, descargas viejas, apps grandes) **nunca se borra solo**: te muestra cuánto ocupa y te lleva al lugar.
  - **Nunca toca:** iCloud, contenedores de otras apps, nada que esté en uso, ni tus carpetas protegidas. Tampoco hace "liberar RAM", escaneos de malware de mentira ni cambios al sistema.
- **Avisos en la isla** si el disco baja de 10 GB, la memoria llega al límite, el Mac se calienta o una app pasa 2 minutos al máximo.

### Portapapeles, captura y dictado

![Portapapeles con tres imágenes elegidas](docs/portapapeles.jpg)

![Panel de captura](docs/captura.jpg)

![El indicador de dictado en sus tres momentos](docs/dictado.jpg)

---

## Instalación

### Con Claude Code (recomendado)

```bash
git clone https://github.com/juanth11/dictado.git
```

```bash
cd dictado && claude "instala y configura Dictado"
```

Claude revisa los requisitos, compila, instala, te pregunta tu idioma, tu carpeta de ideas y las palabras que más usas, y te guía para dar los permisos. Los pasos exactos están en [`CLAUDE.md`](CLAUDE.md).

### A mano

**Requisitos:** Mac con Apple Silicon, **macOS 26 o posterior** y las herramientas de línea de comandos de Apple. No hace falta Xcode completo. Si no las tienes, instálalas con:

```bash
xcode-select --install
```

1. **(Recomendado) Crea un certificado para firmar.** Así macOS recuerda los permisos entre actualizaciones. Abre **Acceso a Llaveros** → menú Acceso a Llaveros → Asistente de certificados → **Crear un certificado…**. Nombre: `Dictado Local`. Tipo de identidad: **Raíz autofirmada**. Tipo de certificado: **Firma de código**. Luego, Crear.
2. **Compila e instala** en `~/Applications/Dictado.app` y ábrela:

   ```bash
   ./instalar.sh
   ```
3. **Da los permisos** que pide (Ajustes del Sistema → Privacidad y seguridad):
   - **Micrófono**, para dictar.
   - **Accesibilidad**, para pegar, usar las teclas de volumen y brillo y que los botones de la isla respondan al primer clic.
   - **Calendarios**, para la agenda y el botón Unirse.
4. Opcional: en el menú de Dictado, marca **Abrir al iniciar sesión**.

Para revisar que todo quedó bien:

```bash
cat ~/Library/Application\ Support/Dictado/estado.txt
```

## Personalización

| Qué | Cómo |
|---|---|
| Idioma del dictado | `defaults write app.dictado idioma es-MX` (por defecto `es-US`; también `es-ES`, `en-US`…) |
| Carpeta de ideas (⌥⇧Espacio) | `defaults write app.dictado inbox "$HOME/Documents/Ideas"`. Si la carpeta está en un repositorio git, cada idea se guarda con commit. |
| Carpetas que la limpieza no toca | `defaults write app.dictado protegidas -array "$HOME/Documents/Trabajo"` |
| Nombres y términos que el dictado debe reconocer | Edita `~/Library/Application Support/Dictado/vocabulario.txt` (menú → Editar vocabulario…) |
| Correcciones automáticas | `~/Library/Application Support/Dictado/correcciones.txt`, una línea por regla con la forma `lo que transcribe = lo correcto` |
| Estilo del indicador de dictado | Menú → Estilo (Prisma por defecto) |
| Volumen y brillo en la isla | Menú → Volumen y brillo en la isla |

Después de cambiar un ajuste con `defaults`, reinicia Dictado (menú → Salir y ábrela de nuevo).

## Privacidad

- La voz se transcribe **en el Mac** con el modelo de Apple (SpeechAnalyzer) y no se guarda ningún audio.
- El pulido del dictado y las acciones sobre texto (traducir, corregir, resumir) también corren en el Mac, con el modelo y la traducción de Apple. Solo "A Claude" manda el texto a Claude, cuando lo eliges.
- El portapapeles vive en `~/Library/Application Support/Dictado/Portapapeles` y salta lo que las apps marcan como contraseña.
- Lo único que sale a internet es la consulta de la carátula de Spotify (el oEmbed público de Spotify).
- La parte de Claude Code **solo lee** `~/.claude/sessions` y los transcriptos; nunca escribe ahí.
- La limpieza mueve a la Papelera y anota cada movimiento en `limpiezas.json` para poder deshacer. Vaciar la Papelera lo decides tú desde el Finder.

## Cómo está hecho

Es un paquete de Swift (Swift 6, SwiftUI y AppKit), sin dependencias externas, que se compila con `swift build`. `instalar.sh` arma el `.app`, lo firma y lo copia a `~/Applications`.

| Archivo | Qué contiene |
|---|---|
| `App.swift` | Menú, atajos, flujo del dictado |
| `Transcripcion.swift`, `Salida.swift` | Voz a texto, pegado e ideas |
| `Portapapeles.swift`, `VistaPortapapeles.swift` | Historial y panel |
| `Captura.swift` | Panel de capturas y OCR |
| `Isla.swift`, `VistaIsla.swift` | La isla del notch (música, agenda, llamadas, actividades) |
| `Claude.swift` | Sesiones de Claude Code (solo lectura) |
| `Privacidad.swift`, `Niveles.swift` | Cámara y micrófono en uso; volumen y brillo |
| `Salud.swift`, `VistaSalud.swift` | Medidor, escáner de limpieza y bitácora para deshacer |
| `HUD.swift`, `Estilos*.swift`, `Diseno.swift` | Indicador de dictado y lenguaje visual |
| `Pruebas.swift`, `CLI.swift` | Renders de las vistas y diagnósticos (`--salud`, `--claude`, `--vista-isla salida.png`) |

## Desinstalar

1. Menú de Dictado → Salir.
2. Mueve `~/Applications/Dictado.app` a la Papelera.
3. Si quieres, borra también `~/Library/Application Support/Dictado` y los ajustes con `defaults delete app.dictado`.

## Licencia

[MIT](LICENSE).
