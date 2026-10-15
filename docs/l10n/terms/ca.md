# Cranny — terminologia en català (ca)

Register and style, checked against the Catalan strings of macOS 27 on this Mac (system loctables):

- Informal **tu** ("Vols…?", "Prem", "Fes clic"). Buttons, menu items and toggles are **imperative 2nd person
  singular**, as macOS writes them: "Obre", "Tanca", "Afegeix", "Mostra…", "Oculta…", "Cancel·la", "Continua",
  "Desa", "Omet", "Torna‑ho a provar", "Fet". VoiceOver hints are 3rd person ("Obre la configuració del sistema").
- Sentence case everywhere (also menus: "Cerca actualitzacions…", "Surt del Cranny").
- Apostrophe ’ (U+2019): l’osca, d’Apple. Quotes “…” (secondary ‘…’). Ellipsis … (U+2026). Geminated l·l (U+00B7).
- Pronoun hyphen as macOS writes it: non-breaking hyphen U+2011 ("Torna‑ho", "Uneix‑t’hi", "Mou‑te").
- Product names take the article, as macOS does ("el Finder", "l’AirDrop", "el macOS", "el Mac"):
  **el Cranny / del Cranny / al Cranny**. An app name in a placeholder: **l’app %@** (macOS: "l’app Música").
- System Settings in prose is lowercase, as macOS: "a la configuració del sistema"; the button is
  "Obre la configuració del sistema"; a path keeps the names: "Privacitat i seguretat ▸ Accessibilitat".
- "Couldn’t …" → "No s’ha pogut …"; "Delete “%@”?" → "Vols eliminar “%@”?"; "default" → "per omissió" (macOS).
- Plural categories one / many / other; *many* (millions) = same text as *other*. "one" is exactly 1, so
  "d’%lld" (d’1) is used in one-forms where the preposition elides.
- Pre-formatted durations (%@ = "1 min", "1 minut", "1 h 20 min") never follow a verb that must agree with them
  ("Queden %@" is wrong at one minute) or a preposition that must elide ("de %@" is wrong before "1 min"). Use the
  macOS patterns instead: "Restant: %@" (visible), "Temps restant: %@" (VoiceOver), "%@ per acabar" (meetings),
  "%@ després" (picker "After %@"), "Inicia un temporitzador: %@".
- A settings pane in running text is a "secció" (macOS: "a la secció Pantalles de la configuració del sistema").
- Key names in running text as macOS writes them: "la tecla d’opció", "la tecla d’ordre + fletxa amunt",
  "la barra espaiadora", "la tecla de retorn", "la tecla de supressió"; a shortcut hint is "Opció + 1".

_Reviewed 2026-10-14 (independent review): rows marked ★ changed or were added._

| English | Català | Note |
|---|---|---|
| Cranny | el Cranny | never translated; masculine with article: "Obre el Cranny", "Surt del Cranny" |
| notch | osca | "a l’osca", "pantalles sense osca" |
| Home (built-in page) | Inici | header tab |
| Tray | Safata | "a la safata", "Treu de la safata", "Buida la safata", "Deixa a la safata" |
| item (Tray) | ítem | macOS word ("Ítems d’inici de sessió") |
| file | arxiu | macOS ("Arxius i carpetes") |
| Layout & Widgets / layout | Disposició i ginys / disposició | |
| widget | giny | macOS ("Edita els ginys") |
| Widget library | Biblioteca de ginys | |
| live activity / Live Activities | activitat / Activitats en directe | Apple’s own name in ca (Control Center settings) |
| peek | ullada | never "Vista ràpida" (= Quick Look) |
| compact | compacte | |
| satellite | satèl·lit | |
| HUD | indicador | Settings pane "Indicador"; search terms keep "HUD", "OSD" |
| pipeline | cadena | "Les teves cadenes", "Cadenes fixades", "Cadena nova…" |
| step (pipeline) | pas | |
| drop zone | zona | "Zona %lld", "Zones per deixar anar" |
| Mirror | Mirall | |
| Notes · To-dos · Timer · Calendar · Media | Notes · Tasques · Temporitzador · Calendari · Multimèdia | to-do = tasca |
| Quick Apps | Apps ràpides | "Treu de les apps ràpides" |
| tile (Quick Apps) | rajola | |
| Shortcuts (Apple app) · a shortcut | Dreceres (l’app Dreceres) · drecera | macOS name |
| keyboard shortcut | drecera de teclat / drecera | Settings ▸ Keyboard section "Dreceres de teclat" |
| launcher | llançador | |
| Pin · Unpin · Keep Cranny open | Fixa · Deixa de fixar · Mantén el Cranny obert | macOS "Fixa la nota" / "Deixa de fixar" |
| Demo mode | Mode de demostració | |
| Settings (Cranny) | Configuració | "Configuració ▸ Permisos" |
| System Settings | Configuració del Sistema | prose: "a la configuració del sistema" |
| About (pane) · About Cranny (menu) | Informació · Sobre el Cranny | macOS: "Informació", "Sobre el Mail" |
| Appearance · General · Keyboard · Gestures · Permissions | Aspecte · General · Teclat · Gestos · Permisos | |
| Join (meeting) | Uneix‑t’hi | macOS "Join"; VoiceOver "Uneix‑te a la reunió" |
| Join (short capsule) | Entra | the only short form |
| Meeting soon · Meeting in progress | Reunió imminent · Reunió en curs | |
| Reset to Default | Restableix el valor per omissió | |
| Changed from the default | Canviat respecte del valor per omissió | |
| Denied · Granted · Not yet · Restricted | Denegat · Concedit · Encara no · Restringit | |
| Allow… / Grant… | Permet… | |
| Remove (from a list/Tray) · Delete | Treu · Elimina | "Elimina" only for real deletion |
| Dismiss | Oculta (activity, reminder) · Tanca (banner) | |
| Move up / down / left / right ★ | Mou cap amunt / cap avall / cap a l’esquerra / cap a la dreta | macOS "Mou cap amunt", "Mou cap a l’esquerra" |
| Rename | Canvia el nom | macOS |
| Typing effect | Efecte d’escriptura | |
| Instant | Instantani | |
| Preview | Previsualització | |
| drag · drop (files) | arrossegar · deixar anar | |
| click | fer clic | "Fes clic a l’osca" |
| hover / rest the pointer ★ | passar el punter / deixar el punter | never "reposar" |
| swipe · swipe sideways ★ | lliscar · lliscar lateralment | "Llisca cap avall"; "de costat" means "on its side" |
| tutorial | tutorial | |
| Show on | Mostra a | values: Totes les pantalles / Pantalla integrada / Pantalla amb el punter / Pantalles triades |
| display | pantalla | macOS "Pantalles" |
| Never (timeout 0) | Mai | |
| Close after inactivity · Fold away after | Tanca per inactivitat · Replega per inactivitat | |
| Open Cranny with (Hover / Click / Shortcut only) | Obre el Cranny (En passar el punter / Amb un clic / Només amb la drecera) | onboarding cards: Passar el punter / Clic / Només drecera |
| Accent (colour) | Color de contrast / Contrast | macOS "Color de contrast" |
| Style · Mono · Semantic (HUD colours) | Estil · Blanc · Per funció | |
| Quick Look | Vista ràpida | macOS |
| Zip · Unzip · Compress | Crea un ZIP · Descomprimeix · Comprimeix | |
| Copy path(s) | Copia el camí / els camins | |
| Copied (wing) · Done (flash) · Failed (flash) | Copiat · Fet · Error | measured: fit the wing |
| Paused · Resumed (wing words) | En pausa · Actives | "Represes" also reads as "dams" |
| N cells left | Queda %lld cel·la / Queden %lld cel·les | |
| Skip tutorial · Skip setup | Omet el tutorial · Omet la configuració | |
| Symbol | Símbol | |
| Now Playing | Ara sona | macOS |
| player (media app) | reproductor | |
| artwork | il·lustració | macOS Music |
| media helper | assistent multimèdia | |
| Apple Events fallback | alternativa amb Apple Events | |
| Low Power Mode | Mode de baix consum | macOS |
| Applications folder · Downloads | carpeta Apps · Descàrregues | Finder names |
| Login Items | Ítems d’inici de sessió | macOS |
| Accessibility · Automation · Calendars · Camera · System Audio Recording | Accessibilitat · Automatització · Calendaris · Càmera · Gravació de l’àudio del sistema | Privacy names |
| Reduce motion · Reduce transparency · Differentiate without color | Redueix el moviment · Redueix la transparència · Diferencia sense color | quoted when named |
| Music (Apple app) | l’app Música | always "l’app Música" in prose |
| Timer alert sounds | macOS names: Destapar, Brisa, Bombolla, Vidre, Funk, Heroïna, Salt, Mezzo, Còdol, Estrebada, Pong, Sonar, Sonumi, Immersió | |
| in %@ (notch band) | %@ | no room for "d’aquí a" (measured: "en 4 min" = 49 pt > 48) |
| In %@ (widget) | D’aquí a %@ | |
| %@ left ★ | Restant: %@ (visible) · Temps restant: %@ (VoiceOver) · %@ per acabar (meetings: "Ara · %@ per acabar") | never "Queden %@": a pre-formatted "1 min" breaks agreement |
| Ends %@ (timer ring) | Fi: %@ | "Fins a les 14:35" does not fit the ring caption |
| Presets · Preset %lld ★ | Preconfiguracions · Preconfiguració %lld | macOS ("Preconfiguracions" in Displays); "predefinit" is an adjective |
| Acknowledgments ★ | Reconeixements | macOS (Books, Maps); search keeps "agraïments" |
| Resize (menu) ★ | Canvia la mida | macOS; never a bare "Mida" on a menu item |
| Flip horizontally ★ | Gira horitzontalment | macOS (Preview, Photos) |
| Option-1 (key hint) · Option key ★ | Opció + 1 · la tecla d’opció | macOS writes combinations with " + " |
| Now playing: %@ by %@ ★ | Ara sona: %@ de l’artista %@ | macOS MediaRemote; avoids "de Adele" |
| %@ until full ★ | %@ per carregar‑se del tot | macOS Battery |
| After %@ (hide paused media) ★ | %@ després | values include "1 minut" ("de 1" would need elision) |
| Start timer for %@ ★ | Inicia un temporitzador: %@ | same elision problem with "de %@" |
| Attached (no-notch style) ★ | Enganxat | agrees with Automàtic / Desactivat (estil) |
| pane (in prose) ★ | secció | "Tota la configuració d’aquesta secció…" |
| sec (timer unit) ★ | s | SI symbol; "seg." is Spanish |
| Not saved (to-dos header) ★ | Sense desar | invariable |
| Quality (the light: Detailed · Efficient) | Qualitat (Detallada · Eficient) | Settings ▸ Appearance ▸ Light; search keywords memòria · rendiment |
