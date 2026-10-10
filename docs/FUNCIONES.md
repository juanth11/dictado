# Funciones opcionales

Cada función opcional de Dictado es un módulo independiente:

- vive en su propio archivo en `Sources/Dictado/`;
- se prende o apaga desde el menú **Funciones** (ícono de micrófono → Funciones);
- se instala con una línea en `App.instalarModulos()`.

Apagarla desde el menú la desactiva al instante, sin reiniciar. Para quitarla del todo:

1. Borra su archivo (o archivos).
2. Borra su línea en `App.instalarModulos()`.
3. Borra su caso en el `enum Funcion` (`Funciones.swift`).
4. Compila con `swift build -c release` y reinstala con `./instalar.sh`.

| Función | Archivo(s) | Atajo | Permiso | Ficha |
|---|---|---|---|---|
| Tecla hyper | `TeclaHyper.swift` | Bloq Mayús | Accesibilidad | [↓](#tecla-hyper) |
| Ventanas por teclado | `Ventanas.swift` | Hyper + flechas, N, ↩ | Accesibilidad | [↓](#ventanas-por-teclado) |
| Buscador de ventanas | `BuscadorVentanas.swift`, `VistaBuscador.swift` | Hyper + Espacio | Accesibilidad | [↓](#buscador-de-ventanas) |
| Dictado pulido con IA local | `PulidoIA.swift`, `IALocal.swift` | — (automático al dictar) | — (necesita Apple Intelligence) | [↓](#dictado-pulido-con-ia-local) |
| Acciones sobre texto seleccionado | `AccionesTexto.swift`, `VistaAcciones.swift`, `IALocal.swift` | Hyper + T | Accesibilidad | [↓](#acciones-sobre-texto-seleccionado) |
| Quitar descargas de iCloud | `ICloud.swift` (+ enganches en `Salud.swift` y `VistaSalud.swift`) | — (en Limpieza) | — | [↓](#quitar-descargas-de-icloud) |
| Papelera que libera de verdad | `Papelera.swift`, `Salud.swift`, `VistaSalud.swift` | — (en Limpieza) | — | [↓](#papelera-que-libera-de-verdad) |

> La papelera que libera de verdad es parte de Limpieza, no un módulo con interruptor: el botón "Liberar ya" solo aparece cuando hay algo que liberar.

## Atajos con la tecla hyper

Hyper es Bloq Mayús mantenida, que equivale a ⌃⌥⌘⇧ pulsadas juntas. Pulsada sola funciona como Esc.

Los atajos se registran con los cuatro modificadores, así que también funcionan pulsando ⌃⌥⌘⇧ a mano (por ejemplo, si apagas la tecla hyper).

| Atajo | Acción |
|---|---|
| Bloq Mayús sola | Esc |
| Hyper + V | Abre el portapapeles |
| Hyper + C | Abre la captura |
| Hyper + M | Abre Salud del Mac |
| Hyper + U | Unirse a la reunión en curso o a la próxima |
| Hyper + Espacio | Buscador de ventanas |
| Hyper + ← / → | Mitad, tercio y dos tercios del lado (en ciclo al repetir) |
| Hyper + ↑ | Casi maximizar; otra vez, vuelve al tamaño previo |
| Hyper + ↓ | Restaurar el tamaño previo |
| Hyper + N | Mandar la ventana a la siguiente pantalla |
| Hyper + ↩ | Centrar la ventana |
| Hyper + T | Acciones sobre el texto seleccionado (traducir, corregir, resumir, más formal, a Claude, guardar idea) |
| Hyper + . (punto) | No la uses: macOS la reserva para un diagnóstico del sistema (sysdiagnose) y no se puede cambiar |

---

<!-- Cada módulo completa su ficha con: qué hace, cómo usarlo, archivos, permiso, cómo se apaga, cómo se quita y límites conocidos. -->

## Tecla hyper

**Qué hace.** Convierte Bloq Mayús en una tecla hyper:

- **Mantenida** equivale a ⌃⌥⌘⇧ pulsadas juntas: una combinación que casi ninguna app usa, así que tus atajos no chocan con nada.
- **Pulsada sola** (menos de un segundo, sin tocar otra tecla) es **Esc**.
- Trae cuatro atajos: Hyper + V (portapapeles), Hyper + C (captura), Hyper + M (Salud del Mac) y Hyper + U (unirse a la próxima reunión).

**Cómo usarla.** Mantén Bloq Mayús y pulsa la otra tecla. Para Esc, tócala sola. En cualquier app que deje grabar atajos (Raycast, Keyboard Maestro, Ajustes → Teclado → Atajos de teclado), mantén Bloq Mayús al grabar y queda como Hyper + tecla.

**Cómo funciona.**

1. **Mapeo de la tecla.** Con el `UserKeyMapping` del sistema HID (lo mismo que hace `hidutil`), Bloq Mayús llega al sistema como F18. Así macOS nunca prende el bloqueo de mayúsculas. El mapeo se mezcla con los que ya tengas, sin pisarlos. Si Bloq Mayús ya tenía un mapeo tuyo (por ejemplo, a Control), se guarda y se devuelve al apagar la función.
   - Se aplica al prender la función, al despertar el Mac y al conectar un teclado (con un aviso de IOKit, sin nada en bucle).
   - Se quita al apagar la función y al salir de Dictado: menú Salir, `pkill`, Ctrl+C en la terminal o cierre de sesión.
   - Solo se pone si el event tap está funcionando. Sin permiso, Bloq Mayús sigue siendo Bloq Mayús.
2. **Event tap.** F18 abajo activa hyper y no llega a las apps. Mientras está activa, cada tecla lleva los cuatro modificadores. F18 arriba sin otra tecla en medio manda Esc.
   - **Dónde se intercepta:** en el punto HID (`kCGHIDEventTap`), donde los eventos entran al WindowServer. Es el primer punto de la cadena, así que todo lo que viene después ve la combinación ya armada: los atajos de Carbon (`RegisterEventHotKey`, los de Dictado y los de otras apps como Raycast), los event taps de sesión de otras apps y la app al frente. En el punto de sesión, en cambio, los taps HID de otras apps verían la tecla sin modificadores. Si macOS no deja crear el tap HID, se usa el de sesión como respaldo.
   - Corre en un hilo propio: si Dictado está ocupado (transcribiendo, dibujando o esperando a otra app), el teclado del Mac no se traba.
   - Si macOS apaga el tap por demora, se vuelve a prender y hyper se suelta, para que no quede pegada.
3. **Atajos del módulo.** Se registran con Carbon y los cuatro modificadores.

**Archivos.**

- `Sources/Dictado/TeclaHyper.swift`: el módulo, la máquina de estados, el event tap, el mapeo y el aviso de teclados nuevos.
- Pruebas en `Sources/Dictado/PruebasTeclado.swift`:
  - `Dictado --probar-hyper`: la máquina de estados con eventos construidos a mano (sin publicarlos) y la mezcla del mapeo, sin tocar el sistema.
  - `Dictado --estado-hyper`: solo lectura. Muestra el mapeo actual, si lo puso Dictado, si hay Entrada Segura y quién la tiene.
  - `Dictado --quitar-hyper`: devuelve Bloq Mayús a mano.

**Permiso.** Accesibilidad, para el event tap. No pide Monitoreo de entrada ni `sudo`. Sin el permiso, Dictado reintenta cada 5 s. Si quitas el permiso con la función prendida, en menos de 15 s Dictado lo nota y quita el mapeo, porque un tap sin permiso puede trabar el teclado.

**Cómo apagarla.** Menú → Funciones → Tecla hyper. Bloq Mayús vuelve a ser Bloq Mayús al instante.

**Cómo quitarla.** Sigue los pasos generales con `TeclaHyper.swift`, la línea `modulos.append(TeclaHyper(contexto))` y el caso `.hyper`. En `PruebasTeclado.swift`, borra también `probarHyper`, `estadoHyper` y sus casos en `cliTeclado`.

**Límites y riesgos.**

- **Si Dictado se cierra mal** (se cuelga o fuerzas la salida desde el Monitor de Actividad), el mapeo queda puesto y Bloq Mayús no hace nada. Hay tres formas de recuperarla:
  - reiniciar el Mac;
  - volver a abrir Dictado;
  - ejecutar `~/Applications/Dictado.app/Contents/MacOS/Dictado --quitar-hyper`.
- **Entrada Segura.** En los campos de contraseña, y con "Entrada segura de teclado" de Terminal, macOS oculta el teclado a todos los event taps. Ahí Bloq Mayús no hace nada y Hyper + letra escribe la letra; ⌃⌥⌘⇧ a mano sí funciona. A veces `loginwindow` deja la Entrada Segura prendida tras desbloquear y hyper deja de responder en todas partes. Para comprobarlo, usa `--estado-hyper`; bloquear y desbloquear la pantalla la apaga.
- Los modificadores van en cada tecla, no en el estado global del teclado. Una app que pregunte qué modificadores están presionados (en vez de leerlos de la tecla) no ve hyper. Es poco común.
- Hyper + . (punto) lanza un diagnóstico de macOS y no se puede redefinir.
- Si tu teclado tiene una tecla F18 de verdad, también hace de hyper.
- Si ya usas Karabiner-Elements u otra app para Bloq Mayús, apaga esta función.
- Los mapeos por teclado hechos con `hidutil --matching` no se mezclan: Dictado lee y escribe el mapeo global.
- Mantenida más de un segundo sin tocar otra tecla, no manda Esc al soltarla.

**Protecciones añadidas tras la revisión de código:**

- Si algún teclado tiene su propio mapeo de teclas (hecho con `hidutil --matching`) y no hay uno global, la tecla hyper no se aplica. Escribir un mapeo global copiaría ese mapeo a todos los teclados. Bloq Mayús sigue normal y los atajos con ⌃⌥⌘⇧ a mano siguen funcionando.
- El "soltar perdido" de Bloq Mayús (pasa en campos de contraseña) solo se da por hecho si hyper lleva más de medio segundo abajo. Así un Hyper+↩ soltado muy rápido nunca llega a la app como un ↩ solo, que enviaría el mensaje o el formulario.

## Ventanas por teclado

**Qué hace.** Acomoda la ventana al frente con el teclado. Solo trae lo que macOS 26 no hace de serie (su mosaico ya tiene mitades y cuartos con fn ⌃ + flechas):

| Atajo | Qué hace |
|---|---|
| Hyper + ← / → | Mitad del lado. Al repetir: tercio, dos tercios y otra vez mitad |
| Hyper + ↑ | Casi maximizar, con 12 pt de margen. Al repetir, vuelve al tamaño previo |
| Hyper + ↓ | Restaurar el tamaño que tenía antes de los atajos |
| Hyper + N | Mandarla a la siguiente pantalla, con la misma posición y tamaño relativos |
| Hyper + ↩ | Centrarla en la pantalla, sin cambiar su tamaño |

**Cómo usarla.** Con la ventana al frente, pulsa el atajo. Sin la tecla hyper también funciona con ⌃⌥⌘⇧ a mano.

**Cómo funciona.**

- Toma la ventana enfocada de la app al frente por Accesibilidad y escribe su posición y tamaño.
- Usa el área visible de cada pantalla (sin barra de menús ni Dock) y convierte coordenadas: Accesibilidad mide desde arriba a la izquierda de la pantalla principal; `NSScreen`, desde abajo.
- Aplica en orden tamaño → posición → tamaño, para que la app no recorte la ventana al llegar a una pantalla más chica.
- En apps Chromium y Electron, apaga `AXEnhancedUserInterface` mientras mueve la ventana (con él, cada cambio es lento y animado) y lo deja como estaba.
- Recuerda el marco previo de cada ventana (las últimas 40) para restaurar y para seguir el ciclo. Si mueves la ventana a mano, el ciclo empieza de nuevo y ese pasa a ser el tamaño previo.
- Si una app impone un tamaño mínimo, el ciclo sigue igual con el tamaño que la app aceptó.

**Archivos.**

- `Sources/Dictado/Ventanas.swift`: el módulo, la geometría en funciones puras (`GeometriaVentanas`) y las ayudas de Accesibilidad (`AX`), que también usa el buscador.
- Pruebas en `PruebasTeclado.swift`: `Dictado --probar-ventanas` imprime los marcos de cada atajo sobre pantallas de ejemplo (un portátil con notch y un monitor) y comprueba el ciclo, restaurar, el cambio de pantalla y el centrado. No mueve ninguna ventana.

**Permiso.** Accesibilidad. Sin él, el atajo avisa en la isla.

**Cómo apagarla.** Menú → Funciones → Ventanas por teclado.

**Cómo quitarla.** Sigue los pasos generales con la línea `modulos.append(VentanasTeclado(contexto))` y el caso `.ventanas`. En `PruebasTeclado.swift`, borra `probarVentanas` y su caso en `cliTeclado`. Si conservas el buscador, no borres `Ventanas.swift` entero: deja el `enum AX` (o muévelo a `BuscadorVentanas.swift`).

**Límites y riesgos.**

- No mueve ventanas en pantalla completa (avisa).
- Las ventanas que no dejan cambiar su tamaño solo se mueven.
- Si una app no responde en 0,3 s, el atajo no hace nada.
- La memoria de tamaños previos se pierde al salir de Dictado.

## Buscador de ventanas

**Qué hace.** Hyper + Espacio abre un panel de vidrio con las ventanas de todas las apps, incluidas las minimizadas y las de apps ocultas. Cada fila muestra el ícono de la app, el título de la ventana y el nombre de la app.

**Cómo usarlo.**

- Escribe para filtrar por título o por app. No importan las tildes ni las mayúsculas, y si escribes varias palabras, todas tienen que aparecer. Arriba salen las que tienen una palabra que empieza como lo que escribiste.
- ↑↓ para moverte, ↩ para saltar, Esc para cerrar. También puedes hacer clic en una fila.
- Al abrir, la selección empieza en la segunda ventana: Hyper + Espacio, ↩ te devuelve a la ventana anterior (como ⌘Tab).
- Al elegir una ventana, Dictado le quita el minimizado, la trae al frente y activa su app.

**Cómo funciona.**

- Lee por Accesibilidad la lista de ventanas, el título y si está minimizada.
- Consulta todas las apps a la vez y fuera del hilo principal, con 0,2 s de espera por app: la que no responde se salta y el panel no se traba.
- Ordena las apps según lo que se ve en pantalla (de adelante hacia atrás). Para eso usa solo el dueño de cada ventana, que macOS entrega sin Grabación de pantalla. Las minimizadas y las de apps ocultas van al final.
- No hace capturas ni miniaturas: no pide Grabación de pantalla.

**Archivos.**

- `Sources/Dictado/BuscadorVentanas.swift`: el módulo, la lectura de ventanas, el filtro y el salto.
- `Sources/Dictado/VistaBuscador.swift`: el panel.
- Usa `AX` de `Ventanas.swift` y `PanelClave` de `Portapapeles.swift`.
- Pruebas en `PruebasTeclado.swift`:
  - `Dictado --probar-buscador`: el filtro y el orden. Si el proceso tiene Accesibilidad, también cuenta cuántas ventanas lee y cuánto tarda, sin imprimir títulos.
  - `Dictado --vista-buscador salida.png`: render del panel con datos de ejemplo.

**Permiso.** Accesibilidad. Sin él, el atajo avisa en la isla.

**Cómo apagarlo.** Menú → Funciones → Buscador de ventanas.

**Cómo quitarlo.** Sigue los pasos generales con los dos archivos, la línea `modulos.append(BuscadorVentanas(contexto))` y el caso `.buscador`. En `PruebasTeclado.swift`, borra `ventanasDeMuestra`, `probarBuscador`, `hojaBuscador` y sus casos en `cliTeclado`.

**Límites y riesgos.**

- Solo ve las ventanas del Escritorio (Space) actual y las minimizadas. Las de otros Escritorios y las de pantalla completa no aparecen: Accesibilidad no las entrega sin APIs privadas de macOS.
- Las apps que no responden en 0,2 s no aparecen esa vez.
- Las ventanas sin título se muestran con el nombre de la app.
- Las apps de barra de menús (sin ícono en el Dock) no aparecen.

## Dictado pulido con IA local

**Qué hace.** Antes de pegar un dictado (⌥Espacio) o de guardarlo como idea (⌥⇧Espacio), el modelo de lenguaje de Apple que corre en el Mac (Apple Intelligence, framework FoundationModels) lo limpia:

- quita muletillas ("eh", "o sea", "este", "pues"…), repeticiones y frases empezadas y abandonadas;
- arregla la puntuación, las mayúsculas y las tildes;
- mantiene el idioma, el sentido y las palabras de tu vocabulario (`vocabulario.txt`);
- no agrega contenido ni responde lo que dictas: si dictas una pregunta, pega la pregunta limpia.

El tono depende de la app que está al frente:

| Modo | Apps | Tono |
|---|---|---|
| Chat | WhatsApp, Mensajes, Slack, Discord, Telegram, Signal, Messenger, Teams | Natural y breve |
| Correo | Mail, Outlook, Spark, Superhuman, Mimestream; Gmail y Outlook en el navegador | Profesional |
| Prompt | Claude, ChatGPT, Terminal, iTerm, Warp, Ghostty, VS Code, Cursor, Zed, Windsurf, Xcode, JetBrains; Claude, ChatGPT, Gemini y Perplexity en el navegador | Claro y ordenado, sin adornos |
| Documento | Word, Pages; Google Docs en el navegador | Formal y cuidado |
| Neutro | El resto | Mantiene el tono |

En los navegadores (Safari, Chrome, Arc, Dia, Brave, Edge, Firefox, Opera, Vivaldi, Orion) el modo sale del título de la pestaña activa. La tabla vive en un solo lugar, fácil de editar: `TablaModos`, al inicio de `PulidoIA.swift`.

**Cómo usarla.** No hay nada que hacer: dicta como siempre. Los dictados de menos de 4 palabras se pegan tal cual. Para probarlo desde la terminal, sin abrir la app:

```bash
.build/release/Dictado --pulir "eh bueno o sea mañana nos vemos a las tres" --app net.whatsapp.WhatsApp
.build/release/Dictado --pulir "eh mándales el enlace" --app com.google.Chrome --titulo "Recibidos - Gmail"
.build/release/Dictado --pulir "…" --vocabulario "Término1,Término2"   # sin esta bandera usa tu vocabulario.txt
```

La salida dice el modo, el tiempo y el motivo: `pulido`, `corto`, `sin modelo`, `tardó` o `descartado` (con la razón).

**El dictado nunca se pierde ni se bloquea.** El modelo tiene unos 3 s (hasta el doble en dictados muy largos). Si no está, tarda, falla o se niega, se pega el texto original. Si tu Mac suele estar muy ocupado y el pulido se salta seguido, sube el límite con `defaults write app.dictado pulidoLimite -float 4`. También se pega el original si la respuesta:

- agrega más de un 30 % de palabras o recorta más de dos tercios;
- pierde un término del vocabulario que estaba en el dictado;
- cambia de idioma;
- empieza como una negativa ("Lo siento…").

**Archivos.**

- `PulidoIA.swift`: el módulo, la tabla de modos, las instrucciones y las comprobaciones.
- `IALocal.swift`: acceso al modelo con tiempo límite. Lo comparte con Acciones sobre texto seleccionado.

Se engancha con `registrarPulido` de `ContextoModulos`. `App.entregar` lo llama solo si la función está prendida.

**Permiso.** Ninguno nuevo. Necesita Apple Intelligence activado (Ajustes del Sistema → Apple Intelligence y Siri). Para leer el título de la pestaña del navegador usa la Accesibilidad que Dictado ya tiene para pegar.

**Cómo apagarla.** Menú → Funciones → Dictado pulido con IA local. Se apaga al instante.

**Cómo quitarla.** Borra `PulidoIA.swift`, la línea `modulos.append(PulidoIA(contexto))` en `App.instalarModulos()`, el caso `.pulido` de `Funcion` y el bloque `--pulir` de `CLI.swift`. Si también quitas Acciones, borra `IALocal.swift`.

**Límites.**

- **Sin Apple Intelligence** (apagado, modelo descargándose o Mac no compatible) no pule: pega el texto tal cual. Al prender la función, la isla avisa por qué.
- **Idiomas:** los de Apple Intelligence (español, inglés, portugués, francés, alemán, italiano, japonés, coreano, chino y otros). Mantiene el idioma del dictado; en un idioma no soportado pega el original.
- **Tiempo:** agrega entre 0,5 y 2,5 s a cada dictado de 4 palabras o más (medido en un Mac con chip de Apple; lo más lento, con el Mac compilando a la vez). Al abrir la app se precalienta el modelo, pero con el Mac muy ocupado un dictado puede pasar de 3 s y pegarse sin pulir.
- **Modelo pequeño:** a veces quita una frase corta que sí decía algo ("si puedes") o pasa de tú a usted en modo correo. Si te molesta en una app, ponla en neutro en la tabla.
- **Privacidad:** todo corre en el Mac. El texto no sale del equipo y no se guarda nada aparte del dictado.

## Acciones sobre texto seleccionado

**Qué hace.** Seleccionas un texto en cualquier app y pulsas **Hyper + T** (Bloq Mayús + T, o ⌃⌥⌘⇧T). Junto a la selección, o junto al puntero si la app no dice dónde está, aparece un panel de vidrio con un extracto del texto y seis acciones:

| Tecla | Acción | Con qué |
|---|---|---|
| 1 | **Traducir:** español → inglés; cualquier otro idioma → español | Traducción de Apple (framework Translation), en el Mac. El idioma se detecta con NaturalLanguage |
| 2 | **Corregir:** ortografía y gramática, sin cambiar el estilo | Modelo de Apple (FoundationModels) |
| 3 | **Resumir** | Modelo de Apple |
| 4 | **Más formal** | Modelo de Apple |
| 5 | **A Claude:** abre un chat nuevo en Claude para Mac con el texto | Enlace `claude://claude.ai/new?q=…` |
| 6 | **Guardar idea:** lo guarda en tu carpeta de ideas, como ⌥⇧Espacio | — |

El resultado aparece en el mismo panel con dos botones:

- **Reemplazar** (↩): lo pega encima de la selección y deja tu portapapeles como estaba.
- **Copiar** (⌘C).

**Esc** cierra el panel; hacer clic fuera, también.

**Cómo lee la selección.** Primero por Accesibilidad (el texto seleccionado del elemento con el foco). Chrome y las apps Electron no lo cuentan; ahí copia con ⌘C, lee el texto y devuelve el portapapeles como estaba. Durante esa copia de paso el historial del portapapeles se pausa, para no guardarla. Nunca lee campos de contraseña.

**El enlace a Claude.** Claude para Mac acepta `claude://claude.ai/new?q=<texto>`: es el mismo enlace que usa su propio servicio "Ask Claude" (revisado en su `app.asar`). Si el texto pasa de 14 000 caracteres, empieza por "/" (Claude rechaza ese `q`) o no tienes la app, Dictado copia el texto y abre un chat nuevo para que lo pegues con ⌘V.

**Cómo probarla sin abrir la app.**

```bash
.build/release/Dictado --accion corregir "ola, la reunion es el jueves"
.build/release/Dictado --accion traducir "Nos vemos el viernes."
.build/release/Dictado --vista-acciones /tmp/acciones.png   # render del panel con un ejemplo
.build/release/Dictado --probar-acciones                    # comprobaciones; no toca tu portapapeles
```

**Archivos.**

- `AccionesTexto.swift`: atajo, lectura de la selección, acciones, Reemplazar y Copiar, enlace a Claude.
- `VistaAcciones.swift`: el panel, su render y las comprobaciones.
- `IALocal.swift`: acceso al modelo de Apple, compartido con el pulido.

Usa `guardarIdea` y `pausarHistorial` de `ContextoModulos`; este último llama a `Historial.pausar` (`Portapapeles.swift`).

**Permiso.** Accesibilidad, la misma que usa Dictado para pegar: sirve para leer la selección y simular ⌘C y ⌘V. Corregir, Resumir y Más formal necesitan Apple Intelligence; Traducir necesita los idiomas descargados.

**Atajo.** Hyper + T (id 50 en `Atajos`). Si otra app lo tiene, Dictado avisa al prender la función.

**Cómo apagarla.** Menú → Funciones → Acciones sobre texto seleccionado. Suelta el atajo al instante.

**Cómo quitarla.** Borra:

1. `AccionesTexto.swift` y `VistaAcciones.swift`;
2. la línea `modulos.append(AccionesTexto(contexto))` en `App.instalarModulos()`;
3. el caso `.acciones` de `Funcion`;
4. los bloques `--accion` y `--probar-acciones` de `CLI.swift` y `--vista-acciones` de `main.swift`.

`pausarHistorial` puede quedarse (no estorba) o borrarse de `ContextoModulos`, `App` y `Historial`.

**Límites.**

- **Sin Apple Intelligence**, Corregir, Resumir y Más formal muestran en el panel por qué no funcionan (apagado, modelo descargándose o Mac no compatible). Traducir, A Claude y Guardar idea siguen funcionando.
- **Traducción:** solo con los idiomas descargados en el Mac. Si faltan, el panel lo dice y ofrece **Descargar** (macOS pide confirmación) o **Abrir Ajustes** (General → Idioma y región → Idiomas de traducción).
- **Texto largo:** el modelo del Mac admite unas 1500 palabras. Con más, el panel avisa.
- **Reemplazar** pega con ⌘V: la selección tiene que seguir marcada en la app de origen. Tu portapapeles se restaura medio segundo después.
- **Sin selección,** la isla dice "Selecciona un texto primero". Algunos editores (VS Code) copian la línea entera con ⌘C cuando no hay selección.
- **Privacidad:** traducir, corregir, resumir y volver formal corren en el Mac; el texto no sale del equipo. Solo "A Claude" manda el texto a Claude, y únicamente cuando lo eliges.

## Quitar descargas de iCloud

**Qué hace.** Agrega a Limpieza la categoría **Archivos de iCloud descargados**: archivos de 50 MB o más que ya están en iCloud, tienen copia descargada en el Mac y no se abren hace 7 días. **Quitar descargas** borra solo la copia local. El archivo sigue en iCloud, aparece igual en el Finder (con el ícono de nube) y se vuelve a bajar al abrirlo. Nunca borra nada.

**Cómo usarla.** Salud del Mac → Limpieza → sección **iCloud**. Despliega la categoría para desmarcar lo que quieras conservar descargado y pulsa **Quitar descargas**. El mensaje dice cuánto espacio ganó el disco de verdad, medido antes y después: «Liberé X GB: siguen en iCloud y se descargan al abrirlos».

**Dónde busca.** En iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs`). También en el Escritorio y Documentos si están sincronizados con iCloud. Un archivo entra solo si cumple las tres condiciones:

- macOS lo marca como de iCloud (`isUbiquitousItem`);
- está descargado y al día (`ubiquitousItemDownloadingStatus == .current`);
- ya está subido (`ubiquitousItemIsUploaded`).

Justo antes de quitar cada descarga lo vuelve a comprobar. Así nunca quita algo que solo existe en este Mac.

**Archivos.**

- `Sources/Dictado/ICloud.swift`: búsqueda (`Escaner.descargasICloud`) y acción (`DescargasICloud.quitar`, que usa `FileManager.evictUbiquitousItem`).
- Enganches: en `Salud.swift`, el caso `.quitarDescarga` de `Limpiable.Accion`, la línea en `Escaner.analizar`, `Salud.quitarDescargas` y `Salud.cambioICloud`; en `VistaSalud.swift`, la sección iCloud.

**Permiso.** Ninguno especial. Si macOS pregunta si Dictado puede acceder a iCloud Drive, elige Permitir.

**Cómo se apaga.** Menú de Dictado → Funciones → *Quitar descargas de iCloud (limpieza)*. La categoría desaparece al instante; al prenderla de nuevo, busca solo en iCloud y la suma al análisis.

**Cómo se quita.**

1. Borra `ICloud.swift`.
2. Borra el caso `.quitarDescarga` en `Salud.swift` (y sus usos: `segura`, `esNube`, `ejecutar`, `quitarDescargas`), la línea `icloud ? descargasICloud() : []` de `Escaner.analizar` y `cambioICloud` con su observador.
3. Borra la sección iCloud en `VistaSalud.swift`.
4. Borra el caso `.icloud` del `enum Funcion`.

**Límites.**

- Es la única parte de la limpieza que entra en `Mobile Documents`, y solo para quitar descargas. Respeta tus carpetas protegidas (`defaults write app.dictado protegidas …`).
- "Sin abrir" usa la fecha de último acceso o de modificación, la más reciente. macOS no siempre actualiza la de acceso al instante.
- Si iCloud tiene activado *Optimizar almacenamiento*, macOS ya quita descargas por su cuenta. Entonces la categoría suele salir vacía y no aparece.
- Los archivos abiertos en una app, o que iCloud está sincronizando, pueden fallar. Se dejan como están.
- Si el Mac no tiene iCloud Drive o no hay nada que cumpla las condiciones, la categoría no aparece.

## Papelera que libera de verdad

**Qué hace.** Mandar a la Papelera no libera espacio hasta vaciarla, y vaciarla borra también lo que botaste a propósito. Esta parte de Limpieza tiene cuatro piezas:

- **Liberar ya.** Borra para siempre **solo** lo que Dictado mandó a la Papelera según su bitácora (`~/Library/Application Support/Dictado/limpiezas.json`), y solo si sigue allí. Lo que botaste tú no se toca.
- **Espacio real liberado.** Al terminar una limpieza, al liberar y al quitar descargas de iCloud, mide el espacio libre antes y después con una medición fresca (sin la pausa de 60 s del medidor). Si macOS tarda en reflejarlo, vuelve a medir hasta tres veces. El mensaje dice el número real: ir a la Papelera casi nunca libera nada todavía, y el mensaje lo dice así.
- **Espacio oculto.** Una sección informativa, solo de lectura, con tres datos:
  - si hay una actualización de macOS descargada y lista (`tmutil listlocalsnapshots /`, sin administrador);
  - la memoria de reserva en disco (`vm.swapusage`), que se libera al reiniciar;
  - lo que macOS puede liberar solo (la diferencia entre `volumeAvailableCapacityForImportantUsage` y `volumeAvailableCapacity`).
- **Aviso en la isla.** Si lo que Dictado tiene en la Papelera suma 1 GB o más y el disco está en amarillo o rojo, avisa «X GB listos para liberar», como mucho una vez cada 24 h.

**Cómo usarla.** Salud del Mac → Limpieza → **Liberar ya** (junto a Deshacer). El botón solo aparece si hay algo que liberar y muestra el total. Antes de borrar, siempre pregunta con el tamaño: «Se borrarán para siempre X GB. No se podrá deshacer.»

- Por defecto entra solo lo que lleva **más de 7 días** en la Papelera.
- Lo más reciente se incluye solo si eliges *Incluir lo reciente…* y lo confirmas en una segunda pregunta.

Después, la bitácora deja de anotar lo borrado y **Deshacer** solo ofrece lo que todavía se puede devolver.

**Cómo decide qué borrar.** Cada elemento debe cumplir tres condiciones, que se comprueban otra vez justo antes de borrar:

1. Está directamente dentro de `~/.Trash`, no en otra carpeta ni detrás de un enlace.
2. Existe.
3. Es lo mismo que movió Dictado: el número del archivo en el disco coincide. En bitácoras anteriores a esta función, que no lo guardaban, debe haber llegado a la Papelera en el momento de esa limpieza.

Si algo no se puede confirmar, no se toca.

**Archivos.**

- `Sources/Dictado/Papelera.swift`: `Bitacora.pendientes`, `Bitacora.liberar` y `EspacioOculto`.
- `Sources/Dictado/Salud.swift`: `Salud.liberar` con sus preguntas, la medición fresca (`Medidor.disco(fresco:)`), el aviso en `revisarAlertas()` y el identificador en `RegistroLimpieza.Movimiento`.
- `Sources/Dictado/VistaSalud.swift`: botón **Liberar ya** y sección **Espacio oculto**.
- Prueba: `Sources/Dictado/Pruebas.swift` (`--probar-papelera`).

**Permiso.** Ninguno.

**Cómo se apaga.** No tiene interruptor: es parte de Limpieza. Si no usas **Liberar ya**, nada cambia: la Papelera se vacía como siempre, desde el Finder.

**Cómo se quita.**

1. Borra `Papelera.swift`.
2. En `Salud.swift`, borra `liberar`, `confirmarLiberar`, el aviso `"papelera"` de `revisarAlertas()` y los campos `pendientes` y `actualizacionLista` de `EstadoSalud`.
3. En `VistaSalud.swift`, borra el botón y la sección **Espacio oculto**.
4. En `Pruebas.swift`, borra `probarPapelera` (y su línea en `main.swift`).

**Probarla sin tocar tu Papelera.** `.build/debug/Dictado --probar-papelera` arma una Papelera y una bitácora falsas en `/tmp`. Comprueba que solo se borra lo de Dictado (por defecto lo de más de 7 días), que no se tocan tus archivos, rutas de fuera ni archivos con el mismo nombre, y que Deshacer queda coherente.

**Límites.**

- Solo conoce lo que Dictado anotó: la bitácora guarda las últimas 50 limpiezas.
- Lo que va a la Papelera de otro disco (`/Volumes/…/.Trashes`) no se borra.
- Si macOS no deja entrar a `~/.Trash`, lo dice y no borra nada.
- El tamaño de la actualización de macOS no se puede saber sin permisos de administrador: solo se indica que está lista.
