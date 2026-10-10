# CLAUDE.md: instalar y configurar Dictado

Instrucciones para Claude Code. Si te piden «instala y configura Dictado», sigue estos pasos en orden. Habla con la persona en su idioma, en frases cortas y sin jerga. Explica cada permiso antes de pedirlo.

## Reglas

- **Nunca** cambies ajustes de seguridad del sistema por tu cuenta: ni permisos de Privacidad, ni el llavero, ni certificados. Abre el panel correcto y explica qué tocar; la persona lo hace.
- **Nunca** escribas datos personales de la persona en el código ni en el repositorio. Todo lo personal (carpeta de ideas, vocabulario, carpetas protegidas, idioma) va en `defaults` o en `~/Library/Application Support/Dictado/`.
- No uses `sudo`.

## 1. Revisar requisitos

```bash
sw_vers -productVersion   # 26.0 o mayor
uname -m                  # arm64
xcode-select -p           # debe existir
swift --version           # Swift 6 o mayor
```

- Si macOS es anterior a 26 o el Mac no es Apple Silicon, detente y explica que Dictado necesita macOS 26 o posterior en un Mac con chip de Apple.
- Si faltan las herramientas de línea de comandos, pide a la persona que ejecute `xcode-select --install`, acepte el diálogo y te avise cuando termine.

## 2. Preguntar (una sola vez, todo junto)

1. **Idioma del dictado:** `es-US` (español latinoamericano, por defecto), `es-MX`, `es-ES`, `en-US`…
2. **Carpeta para las ideas** dictadas con ⌥⇧Espacio. Por defecto `~/Documents/Ideas`. Si eligen una carpeta dentro de un repositorio git, cada idea se guarda con commit.
3. **Palabras que el dictado debe reconocer:** nombres propios, empresas, clientes, términos de su oficio.
4. **Carpetas que la limpieza nunca debe tocar** (opcional): por ejemplo, la de su trabajo.

## 3. Certificado (recomendado, lo hace la persona)

Sin certificado, cada actualización de Dictado hace que macOS pida de nuevo los permisos. Explica estos pasos:

> Abre **Acceso a Llaveros** → menú Acceso a Llaveros → Asistente de certificados → **Crear un certificado…**. Nombre: `Dictado Local`. Tipo de identidad: **Raíz autofirmada**. Tipo de certificado: **Firma de código**. Luego, Crear.

Comprueba con `security find-certificate -c "Dictado Local"`. Si no lo quieren crear, sigue igual: `instalar.sh` firma sin certificado.

## 4. Compilar e instalar

```bash
./instalar.sh
```

Compila (tarda 1 o 2 minutos la primera vez), arma `~/Applications/Dictado.app`, la firma y la abre. Si macOS pregunta si `codesign` puede usar la llave "Dictado Local", la persona debe elegir **Permitir siempre**.

## 5. Configurar

Ejemplo de comandos; reemplaza los valores por los que eligió la persona:

```bash
defaults write app.dictado idioma es-US
mkdir -p "$HOME/Documents/Ideas"
defaults write app.dictado inbox "$HOME/Documents/Ideas"
defaults write app.dictado protegidas -array "$HOME/Documents/Trabajo"
```

Vocabulario: el archivo `~/Library/Application Support/Dictado/vocabulario.txt` se crea al abrir la app. Agrega al final una palabra o frase por línea, sin borrar lo que ya tiene.

Después de configurar, reinicia la app:

```bash
pkill -x Dictado; sleep 1; open ~/Applications/Dictado.app
```

## 6. Permisos (los da la persona)

Abre cada panel y explica qué hacer:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
```

- **Accesibilidad:** activar Dictado. Si ya estaba de una instalación anterior, quitarlo con "−" y volver a agregarlo con "+" desde `~/Applications`.
- **Micrófono y Calendarios:** suelen pedirse solos con un diálogo al abrir la app; elegir Permitir.

Comprueba el estado hasta ver `accesibilidad: sí · micrófono: sí`:

```bash
cat ~/Library/Application\ Support/Dictado/estado.txt
```

Sugiere también: menú de Dictado (ícono de micrófono en la barra) → **Abrir al iniciar sesión**.

## 7. Comprobar y enseñar

```bash
~/Applications/Dictado.app/Contents/MacOS/Dictado --salud    # mide el Mac y lista lo que se puede limpiar
~/Applications/Dictado.app/Contents/MacOS/Dictado --claude   # sesiones de Claude Code abiertas
```

Para terminar, enséñale a la persona:

- **⌥Espacio** (mantener): dicta y pega donde está el cursor. **⌥⇧Espacio**: guarda una idea. **Esc**: cancela.
- **⌘⌥V**: portapapeles.
- **⌘↩**: capturas.
- **Isla del notch**: pasar el mouse por el notch. Pestañas Claude, Agenda y Mac; el ícono ↗ abre Salud del Mac.
- Para Google Calendar: Ajustes del Sistema → Cuentas de internet → Google → activar Calendarios.

## Problemas comunes

| Síntoma | Causa y solución |
|---|---|
| Copia el dictado pero no lo pega | Falta Accesibilidad, o quedó de una versión anterior: quitar con "−" y volver a agregar |
| "⌥Espacio lo usa otra app" | Otra app de dictado o un lanzador tiene ese atajo: cerrarla |
| "⌘⌥V ocupado" | Raycast u otro gestor de portapapeles: desactivar su atajo o cerrarlo |
| No aparece la isla | Solo existe en Macs con notch, en la pantalla integrada |
| La agenda está vacía | Falta el permiso de Calendarios, o no hay cuentas en Ajustes → Cuentas de internet |
| Pide permisos en cada actualización | No hay certificado "Dictado Local" (paso 3) |

## Para desarrollar

- Compilar: `swift build -c release`. Instalar: `./instalar.sh`.
- Renders de las vistas sin abrir la app: `.build/release/Dictado --vista-isla /tmp/isla.png` (también `--vista-salud`, `--vista-portapapeles`, `--vista-captura`, `--vista-hud`). Para usar una imagen de fondo: `DICTADO_FONDO=~/ruta/imagen.jpg`.
- Pruebas del portapapeles: `.build/release/Dictado --probar-portapapeles`. De "Liberar ya" (Papelera falsa en `/tmp`): `--probar-papelera`.
- El código, los nombres y los comentarios están en español. Mantén ese estilo.
- En reposo la app no debe consumir CPU: nada de animaciones continuas ni consultas en bucle; usa avisos del sistema (FSEvents, CoreAudio, EventKit, IOKit).
