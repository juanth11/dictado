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
| Dictado pulido con IA local | (por completar) | — (automático al dictar) | — | [↓](#dictado-pulido-con-ia-local) |
| Acciones sobre texto seleccionado | (por completar) | Hyper + T | Accesibilidad | [↓](#acciones-sobre-texto-seleccionado) |
| Quitar descargas de iCloud | (por completar) | — (en Limpieza) | — | [↓](#quitar-descargas-de-icloud) |
| Papelera que libera de verdad | `Salud.swift`, `VistaSalud.swift` | — (en Limpieza) | — | [↓](#papelera-que-libera-de-verdad) |

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
| Hyper + T | Reservada para las acciones sobre texto seleccionado |
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

## Acciones sobre texto seleccionado

## Quitar descargas de iCloud

## Papelera que libera de verdad
