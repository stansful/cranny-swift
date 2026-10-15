# Cranny — Spanish (es) terminology

One Spanish for Spain and Latin America (es-419 falls back here). Base: Apple's own `es` macOS wording
(`apple-terms.py es`, AppKit/Finder/System Settings loctables), which is Spain-flavoured; where Spain and Latin
America differ, prefer the neutral word, but keep Apple's term where people look for it on screen.

## Voice and typography

- Informal **tú**, as macOS: "Haz clic…", "Arrastra…", "tus eventos".
- **Buttons, menu items, toggles, commands: infinitive** ("Abrir Cranny", "Mostrar el valor", "Buscar actualizaciones…").
  **Instructions to the user: imperative tú** ("Suelta archivos en la muesca…", "Pulsa el atajo de teclado").
  Footnotes and statuses: present indicative, third person.
- Sentence case everywhere (English title-case menu items become sentence case: "Check for Updates…" → "Buscar actualizaciones…").
- Quotes “…” (secondary ‘…’); one-character ellipsis …; opening ¿ and ¡. App names are not quoted (Apple style:
  "Abrir en Calendario", "Mostrar en el Finder"); Cranny's own mode/pane/page names and Apple's settings and panes in
  running text are quoted: “Reducir movimiento”, “En vivo”, “Unirse”, “Actividades en directo”, “General”, “Ítems de inicio”,
  la página “Bandeja”. Not quoted: Settings paths with ▸ ("Ajustes ▸ Permisos", "Privacidad y seguridad ▸ Accesibilidad"),
  a widget name after "widget" ("el widget Espejo"), button titles ("Abrir Ítems de inicio…").
- Statuses about the future: future / subjunctive ("Se iniciará cuando suene música", "Se pedirá cuando haga falta").
  Confirmation messages describe what will happen: future ("volverán a su valor predeterminado", "Se eliminarán…").
- Errors: "No se ha podido…" (Apple es). Unit symbols: "min", "h", "ms", "px", "pt"; numbers and durations come formatted.
- Key names (Apple es: Terminal "⌫ Suprimir", Calculator "Comando + Suprimir"): Comando (⌘), Opción (⌥), Control (⌃),
  Mayúsculas (⇧), Retorno (↩), **Suprimir (⌫)** — never "Eliminar" for the key —, Espacio, Esc, Flecha arriba / abajo.
  Combinations: "Opción + 1", "Comando + Flecha arriba". Hold a key = "mantener pulsada (la tecla) ⌥".
- Regional neutrality: avoid Peninsular-only phrasing where a neutral one exists ("Intenta…", not "Prueba a…";
  "almuerzo", not "comida"); keep Apple es terms people see on screen (ratón, vídeo, mando de videojuegos, Cuenta atrás).
- Gender: **Cranny** masculine ("Cranny está abierto / cerrado / desactivado"); **macOS** masculine ("macOS no ha añadido…");
  **app** feminine ("la app", "las apps"); **el Mac**.
- Plurals: es = one / many / other; many (millions) always has the same wording as other.

## Cranny's own vocabulary

| English | Spanish | Note |
|---|---|---|
| Cranny | Cranny | never translated; masculine; also the open panel ("Abrir Cranny") |
| notch | muesca | "en la muesca", "sobre la muesca" |
| camera housing | zona de la cámara | |
| open panel | panel | "el panel abierto" |
| Home (built-in page, tab) | Inicio | tab ≤ 12 characters |
| Tray (page, pane) | Bandeja | lower case in running text: "en la bandeja", "Vaciar la bandeja", "Quitar de la bandeja" |
| item (Tray) | ítem / ítems | as Finder ("12 ítems") |
| Files (widget) | Archivos | |
| Live Activities (pane, feature) | Actividades en directo | Apple's own Spanish term; one = actividad en directo; short = actividad |
| Pause Live Activities | Pausar actividades en directo | menu: "Durante 1 hora / Hasta mañana / Hasta que las reanude" |
| Live Activities paused … / resumed (confirmation sentences) | Actividades en pausa … / Actividades reanudadas | short form, as Russian «Активности приостановлены»: fits the 380-pt peek and the header side; "en pausa" (Apple es Paused), never "pausadas" |
| Paused / Resumed (wing words) | En pausa / Activas | measured: both fit the wide wing; "Reanudadas" (77 pt) fits none |
| peek | vistazo | never "Vista rápida" (= Quick Look) |
| compact (state) | compacto | |
| satellite | satélite | |
| HUD | indicador | pane "Indicador"; "indicador de volumen", "indicador del sistema"; search terms keep "HUD", "OSD" |
| widget | widget | "Biblioteca de widgets" |
| cell (grid) | celda | "Quedan 3 celdas", "Sobran 2 celdas" |
| page | página | |
| layout | disposición | "Disposición y widgets", "Editar disposición", "disposición inicial" |
| Keep open / pin | Mantener abierto / fijar | "Mantener Cranny abierto"; "Dejar de fijar Cranny"; pin button = "el botón de fijar" (it has no "Fijar" label) |
| pipeline | flujo | "Tus flujos", "Flujos fijados", "Nuevo flujo…"; step = paso |
| drop zone | zona para soltar | |
| drag / drop | arrastrar / soltar | |
| click | hacer clic / clic | never "pinchar" |
| press (keys) | pulsar | "Mantén pulsada la tecla ⌘" |
| hover / rest the pointer | pasar el puntero / dejar el puntero sobre | Settings value "Al pasar el puntero" |
| keyboard shortcut | atajo de teclado (short: atajo) | Apple es: "Atajos de teclado…" |
| Shortcuts (Apple's app) | Atajos | an item of it = atajo; the Keyboard pane's section is "Atajos de teclado" to tell them apart |
| Quick Apps | Apps rápidas | "Añadir a Apps rápidas", "Quitar de Apps rápidas" |
| tile (Quick Apps) | mosaico | |
| launcher | lanzador | |
| Command palette (⌘K) | Paleta de comandos | |
| Settings | Ajustes | as Apple es ("Ajustes…"); System Settings = Ajustes del Sistema |
| Permissions | Permisos | Allow… / Grant… = Permitir…; Denied = Denegado; Granted = Concedido |
| Demo mode | Modo demo | |
| tutorial | tutorial | Skip = Omitir tutorial; Show = Mostrar tutorial |
| Welcome | bienvenida | window title "Te damos la bienvenida a Cranny" (Apple es formula) |
| Done (button) | Aceptar | macOS es "Done" buttons (≈ 45 system strings; "OK" only in Shortcuts); Welcome/tutorial button that VoiceOver also reads as the completed-step word, and the flash: Hecho; Timer done label: Fin |
| Accent / accent color | color de contraste | Apple es (Ajustes del Sistema ▸ Aspecto ▸ "Color de contraste"); Settings picker and HUD option "Color de contraste"; "acento" only as a search word |
| Purple (accent swatch, tile colour) | Morado | Apple es accent swatch (Azul, Morado, Rosa, Rojo, Naranja, Amarillo, Verde, Grafito) |
| Copied / Failed / Hi (flash) | Copiado / Error / Hola | measured against the wings |
| Remove (from a list, page, Tray) | Quitar | "Quitar app", "Quitar página"; Delete (destroy) = Eliminar |
| App not installed | App no instalada | |
| Reset to Default | Restablecer valor predeterminado | "Cambiado respecto al valor predeterminado" |
| Media (module) | Multimedia | Apple es ("Multimedia y Apple Music") |
| Now Playing | Ahora suena | Apple es |
| player | reproductor | |
| track / song | pista / canción | |
| media helper | asistente multimedia | |
| Apple Events fallback | alternativa con Apple Events | |
| visualizer modes Live · Ambient · Static · Off | En vivo · Ambiente · Estático · Desactivado | a live stream = "En directo" |
| artwork | portada | |
| Calendar · event · meeting | Calendario · evento · reunión | |
| Join | Unirse | the row's short capsule: Entrar (measured narrower than Russian «Войти») |
| Meeting soon / in progress | Próxima reunión / Reunión en curso | |
| time left (meeting) | faltan %@ | "Ahora · faltan 12 min" (narrower than the Russian row) |
| time left (timer, battery) | quedan %@ | |
| Lead time | Antelación | |
| Mirror | Espejo | |
| Notes · note | Notas · nota | Focus (the widget's own mode) = Modo enfoque / Salir del modo enfoque, never Apple's "Concentración" ("Enfocar" = focus a lens) |
| To-dos · to-do | Tareas · tarea | "%lld pendientes" |
| Timer | Temporizador | presets = Preajustes (Apple Clock); Timer done = Tiempo agotado (Apple Clock) |
| Start / Pause / Resume / Stop | Iniciar / Pausar / Reanudar / Detener | |
| Display (screen) | pantalla | built-in = pantalla integrada; Display with the pointer = Pantalla con el puntero |
| Show on | Mostrar en | |
| full screen | pantalla completa | "apps a pantalla completa" |
| Excluded apps | Apps excluidas | |
| Floating island · Attached | Isla flotante · Adosado | Glass island = Isla de cristal; Liquid Glass stays |
| handle | tirador | |
| ambient light | luz ambiental | Off / Subtle / Vivid = Desactivado / Sutil / Intensa |
| Accent · Mono · Semantic (HUD colors) | Color de contraste · Blanco · Por tipo | |
| Typing effect | Efecto de escritura | |
| Instant | Instantáneo | |
| Preview (Settings stage) | Previsualización | never "Vista previa" (= the Preview app "Vista Previa") |
| Fold away after | Contraer tras inactividad | |
| Make way for the menu bar | Dejar paso a la barra de menús | |
| Alerts · Ongoing · Passive | Avisos · En curso · Pasivas | |
| Dismiss | Descartar | (a banner's close button: Cerrar) |
| Zip · Unzip · Compress | Crear ZIP · Descomprimir · Comprimir | Finder's "Comprimir" makes a zip, so the image/video step keeps "Comprimir" and Zip says "Crear ZIP" |
| archive (zip) | archivo ZIP | dated base name "Archivo" (as Finder's "Archivo.zip") |
| Quick Look | Vista rápida | Apple es |
| Show / Reveal in Finder | Mostrar en el Finder | Apple es |
| Type to capture | Captura al escribir | |
| Quality (the light: Detailed · Efficient) | Calidad (Detallada · Eficiente) | Settings ▸ Appearance ▸ Light; search keywords memoria · rendimiento |

## Apple names used (from `apple-terms.py es`)

Ajustes del Sistema · Privacidad y seguridad · Accesibilidad · Automatización · Calendarios · Cámara · Bluetooth ·
Grabación del audio del sistema · Ítems de inicio · Descargas · Aplicaciones (folder) · Batería · Modo de bajo consumo ·
Música · Calendario · Atajos · Finder · Spotlight · Mission Control · Dock · Vista rápida · “Reducir movimiento” ·
“Reducir transparencia” · “Diferenciar sin color” · Ventanas de la aplicación · Capturas de pantalla · Spaces ·
Color de contraste (accent colour) · Morado · Grafito · Mando de videojuegos · Tiempo agotado (Clock) · Cuenta atrás ·
Aceptar (Done buttons) · key names Comando, Opción, Retorno, Suprimir ·
alert sounds Boop, Brisa, Burbuja, Cristal, Funky, Líder, Salto, Mezzo, Piedrecita, Punteo, Pong, Sonda, Sonumi, Inmersión.

## Review notes (independent review, 2026-10-14)

Main decisions: accent colour = “color de contraste”; Done button = Aceptar;
⌫ = Suprimir; Purple = Morado; Game controller = Mando de videojuegos; Notes Focus = Modo enfoque; pause/resume
confirmations in the short form “Actividades en pausa…”; pane/page names quoted in running text.
