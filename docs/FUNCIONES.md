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
| Tecla hyper | (por completar) | Bloq Mayús | Accesibilidad | [↓](#tecla-hyper) |
| Ventanas por teclado | (por completar) | Hyper + flechas | Accesibilidad | [↓](#ventanas-por-teclado) |
| Buscador de ventanas | (por completar) | Hyper + Espacio | Accesibilidad | [↓](#buscador-de-ventanas) |
| Dictado pulido con IA local | (por completar) | — (automático al dictar) | — | [↓](#dictado-pulido-con-ia-local) |
| Acciones sobre texto seleccionado | (por completar) | Hyper + T | Accesibilidad | [↓](#acciones-sobre-texto-seleccionado) |
| Quitar descargas de iCloud | `ICloud.swift` (+ enganches en `Salud.swift` y `VistaSalud.swift`) | — (en Limpieza) | — | [↓](#quitar-descargas-de-icloud) |
| Papelera que libera de verdad | `Papelera.swift`, `Salud.swift`, `VistaSalud.swift` | — (en Limpieza) | — | [↓](#papelera-que-libera-de-verdad) |

> La papelera que libera de verdad es parte de Limpieza, no un módulo con interruptor: el botón "Liberar ya" solo aparece cuando hay algo que liberar.

## Atajos con la tecla hyper

Hyper es Bloq Mayús mantenida, que equivale a ⌃⌥⌘⇧ pulsadas juntas. Pulsada sola funciona como Esc.

| Atajo | Acción |
|---|---|
| (por completar) | |

---

<!-- Cada módulo completa su ficha con: qué hace, cómo usarlo, archivos, permiso, cómo se apaga, cómo se quita y límites conocidos. -->

## Tecla hyper

## Ventanas por teclado

## Buscador de ventanas

## Dictado pulido con IA local

## Acciones sobre texto seleccionado

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
