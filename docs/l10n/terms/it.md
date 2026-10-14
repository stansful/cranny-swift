# Cranny — Italian (it) terminology

Base: Apple's own Italian macOS wording (`apple-terms.py it`: System Settings, Finder, TCC, AppKit loctables).
Where Apple has a word for a concept, Cranny uses it; Cranny's own concepts get one fixed Italian term each.

## Voice and typography

- Informal **tu**, as macOS: "Fai clic…", "Trascina…", "i tuoi eventi", "Vuoi…?".
- **Menu items, buttons, toggles, commands: imperative tu**, as Apple's Italian menus ("Apri", "Chiudi finestra",
  "Mostra barra laterale", "Riduci movimento", "Verifica aggiornamenti…"). Confirmation titles use the infinitive
  question ("Ripristinare tutte le impostazioni?", "Eliminare “%@”?"). Footnotes and statuses: indicative, 3rd person.
- To-do sample items use the infinitive, as Italian lists do ("Annaffiare le piante").
- Sentence case everywhere; English title-case menu items become sentence case ("Check for Updates…" →
  "Verifica aggiornamenti…"). Apple's own names keep Apple's capitals ("Impostazioni di Sistema", "Comandi Rapidi",
  "Centro di Controllo").
- Quotes “…” (secondary ‘…’); apostrophe ’ (U+2019): l’app, dell’album, un’altra; one-character ellipsis ….
  Apple's settings and Cranny's option names quoted in running text: “Riduci movimento”, “Elementi login”,
  “Tieni sul ripiano”. App names are not quoted (Apple style: "Apri Comandi Rapidi", "Mostra nel Finder").
  Cranny's pane names in running text are quoted too: "in “Attività in tempo reale”". Buttons that open a pane do
  not quote it ("Apri Elementi login…", "Mostra in Layout e widget").
- Errors: "Impossibile …" (Apple Italian: "Impossibile salvare il risultato").
- Units: "min", "h", "s"/"sec", "ms", "px", "pt". Durations and times arrive formatted ("4 min", "1 h 30 min").
- Gender: **Cranny** masculine ("Cranny è aperto / aggiornato"); **app** feminine, invariable ("l’app", "le app");
  **widget** masculine, invariable ("il widget", "i widget"); **macOS** masculine ("macOS non ha aggiunto").
- Plurals: one / many / other; many (millions) always has the same wording as other.
- Key names as Apple Italian: Opzione, Comando, A capo, Spazio, Esc, Elimina.

## Cranny's own vocabulary

| English | Italian | Note |
|---|---|---|
| Cranny | Cranny | never translated; masculine; also the open panel ("Apri Cranny") |
| notch | tacca | Apple Italian support term ("tacca della fotocamera"); "sulla tacca", "nella tacca" |
| camera housing | area della fotocamera | Notch fit footnotes |
| open panel | pannello | "il pannello aperto" |
| Settings pane | sezione | avoids a clash with the open panel ("Tutte le impostazioni di questa sezione…") |
| Home (built-in page, tab) | Home | as Italian UIs say it; tab ≤ 12 characters |
| Tray (page, pane) | Ripiano | lower case in running text: "sul ripiano", "Svuota ripiano", "Rimuovi dal ripiano", "Tieni sul ripiano" |
| item (Tray) | elemento / elementi | as Finder ("12 elementi") |
| Files (widget) | File | |
| Live Activities (pane, feature) | Attività in tempo reale | Apple's own Italian term; one live activity = "attività" |
| Pause / Resume Live Activities | Sospendi / Riprendi attività in tempo reale | menu: "Per 1 ora / Fino a domani / Finché non riprendo" |
| Paused / Resumed (wing words) | In pausa / Attive | measured: "In pausa" 53 pt (wide wing), "Attive" 37 pt; "Riprese" also means "video takes" |
| Confirmations (Live Activities row) | Conferme | |
| peek | occhiata | never "Anteprima" (= Preview) or "Visualizzazione rapida" (= Quick Look); "Occhiata al passaggio del puntatore" |
| compact | compatto | |
| satellite | satellite | |
| dismiss (an activity) | nascondi | "Scorri in alto per nascondere" |
| fold away | richiudi | "Richiudi dopo" |
| HUD | indicatore | pane "Indicatore"; "indicatore del volume", "indicatore di sistema"; search terms keep "HUD", "OSD" |
| widget | widget | invariable |
| Widget library | Libreria widget | |
| layout | layout | masculine; "Modifica layout", "Scegli un layout iniziale" |
| Layout & Widgets (pane) | Layout e widget | |
| page | pagina | "Pagina 2", "Aggiungi pagina" |
| cell / cells | cella / celle | "%lld celle libere", "%lld celle in eccesso" |
| Keep open / Keep Cranny open (pin) | Mantieni aperto / Mantieni Cranny aperto | "Non mantenere Cranny aperto"; the tutorial says "fissalo con il pulsante della puntina" |
| Demo mode | Modalità demo | |
| Settings (Cranny's) | Impostazioni | "Impostazioni ▸ Tastiera" |
| tutorial | tutorial | masculine; "Mostra tutorial", "Salta tutorial", "Ripeti tutorial" |
| Welcome / setup | Benvenuto / configurazione | "Salta la configurazione" |
| Command palette | Riquadro comandi | "Cerca comandi", "Nessun comando corrispondente" |
| keyboard shortcut | scorciatoia (da tastiera) | macOS 27 Italian: "Scorciatoie da tastiera…" |
| Type to capture | Digitazione diretta | |
| pipeline | sequenza | feminine: "Le tue sequenze", "Nuova sequenza…", "Sequenze fissate" |
| step (pipeline) | passaggio | "Aggiungi passaggio" |
| Resize (Tray pipeline) · Resize (widget) | Riduci · Ridimensiona | Tray images only shrink ("Riduci a 1600 px", as Russian «Уменьшить»); the layout editor keeps "Ridimensiona" |
| Zip · Unzip · Compress (images) | Crea zip · Decomprimi · Comprimi | "Comprimi" is Finder's word for zip, so Zip gets "Crea zip" |
| drop zone | zona di rilascio | short "Zona %lld" |
| drag / drop | trascina / rilascia | "Trascina i file sulla tacca" |
| click | fai clic / clic | Apple Italian; never "clicca" |
| hover / rest the pointer | passaggio del puntatore / tieni il puntatore | "Apri Cranny con: Passaggio del puntatore / Clic / Solo scorciatoia" |
| Hover delay | Ritardo al passaggio | presets "Istantaneo / Breve / Standard / Lungo" |
| Instant | Istantaneo | motion and hover delay |
| Never (timeout 0) | Mai | |
| Off (option) | No | ambient light, display style, shortcut; Media visualizer/shuffle "Disattivato"; first warning "Nessuno" |
| swipe | scorri / scorrimento | "Scorri in basso per aprire, in alto per chiudere" |
| Mirror | Specchio | camera on/off for VoiceOver: "accesa" / "spenta" |
| Notes | Note | same as Apple's Notes app, as Russian does |
| To-dos (module) / a to-do | Da fare / cosa da fare | "Nuova cosa da fare", "Ancora niente da fare", header "%lld da fare"; avoids "attività" (= Live Activities) and "Promemoria" (= Apple's Reminders) |
| Timer | Timer | |
| Calendar (module) | Calendario | Apple's app name too |
| All day (widget time column) · all-day events (toggle) | Giornata · eventi di tutto il giorno | the 2-cell agenda's time column is fixed-width: "Tutto il giorno" (77 pt) left no room for the title; "Giornata" 47 pt |
| meeting | riunione | "Riunione a breve", "Riunione in corso" |
| Join (button, VoiceOver) | Partecipa | "Partecipa alla riunione" |
| Join (Calendar row capsule) | Entra | measured 30 pt (Russian «Войти» 36 pt passes) |
| Lead time | Preavviso | |
| Media (module) | Media | as Apple Italian "Media e acquisti" |
| player | lettore | "Apri il lettore" |
| track / song | brano | Apple Music Italian |
| Now Playing | In riproduzione | Apple's own term |
| visualizer | visualizzatore | modes "Ambientale / Dal vivo / Statico / Disattivato" |
| media helper | helper multimediale | "Helper MediaRemote (perl)" |
| Apple Events fallback | alternativa Apple Events | "Prova l’alternativa Apple Events" |
| Quick Apps | App rapide | "Aggiungi ad App rapide", "Rimuovi da App rapide" |
| tile (Quick Apps) | riquadro | "Modifica riquadri" |
| Shortcuts (Apple's app, Settings pane) · a shortcut | Comandi Rapidi · comando rapido | Apple's Italian names |
| Permissions (pane) | Autorizzazioni | statuses: Consentito / Negato / Non ancora / Limitato / Sconosciuto |
| Allow… · Grant… | Consenti… | Apple's "Consenti" |
| Reset to Default | Ripristina valore predefinito | |
| Changed from the default | Modificato rispetto al valore predefinito | |
| Reset (pane, all) | Ripristina | "Ripristina tutte le impostazioni…" |
| Remove (from a list) | Rimuovi | "Rimuovi dal ripiano", "Rimuovi app"; Delete = "Elimina" (notes, to-dos, pipelines) |
| Cancel · Undo | Annulla · Annulla | Apple Italian uses one word for both |
| Done (button) · Done (flash) · Done (timer band) | Fine · Fatto · Finito | "Finito" ≤ 6 characters |
| Copied (flash) | Copiato | measured 49 pt: fits the 72-pt wide wing |
| Failed (flash) | Errore | |
| Hi | Ciao | |
| Stop | Interrompi | as Apple's Clock |
| Accent (colour) | Colore dettagli · Dettagli | Apple's Italian term (Appearance intents, settings search: "Colore dettagli"; Wallpaper and menu commands: "Dettagli"). Settings row "Colore dettagli", HUD colour segment "Dettagli", footnotes "nel colore dettagli". Never "Accento" (= stress mark, regional accent) |
| Floating island · Attached · Glass island | Isola fluttuante · Agganciato · Isola di vetro | "Agganciato" agrees with "stile" (no-notch style) |
| Handle | Maniglia | |
| Ambient light · Underglow · Album glow · Progress rim | Luce ambientale · Bagliore inferiore · Alone della copertina · Bordo di avanzamento | the glow sits behind the artwork ("copertina") |
| Ambient light options Off / Subtle / Vivid | No / Tenue / Intensa | not "Vivace": that is Motion's Lively |
| Motion options Calm / Standard / Lively / Instant | Calmo / Standard / Vivace / Istantaneo | |
| Notch fit | Adattamento tacca | |
| Excluded apps | App escluse | |
| Show on | Mostra su | "Tutti gli schermi / Schermo integrato / Schermo con il puntatore / Schermi scelti" |
| display | schermo | Apple's "Schermi" pane |
| full screen | a tutto schermo | "Nelle app a tutto schermo" |
| Launch / Open at login | Apri al login | Apple's Dock menu wording; pane "Elementi login" |
| Check for updates | Verifica aggiornamenti | |
| Inside Cranny (Keyboard section) | In Cranny | |
| upload (never uploads) | caricare online | "non li modifica né li carica mai online"; bare "caricare" reads as "load" |
| Login Items footnotes | autorizza Cranny nella sezione “Elementi login” di Impostazioni di Sistema | "consentire" needs "a qualcuno"; one locative only |
| macOS shortcut names (Keyboard collisions) | Finestre applicazione · Screenshot · Menu Aiuto · Finestra di ricerca del Finder · Mission Control · Spotlight | as macOS 27 Italian Keyboard Shortcuts; "Screenshot" also in Tray footnotes |
| Alerts · Ongoing · Passive (priority classes) | Avvisi · In corso · In secondo piano | |

## Apple's names used (from apple-terms.py it)

Impostazioni di Sistema · Privacy e sicurezza · Accessibilità · Automazione · Calendari · Fotocamera · Elementi login ·
Generali · Aspetto · Barra dei menu · Batteria · Risparmio energetico · Riduci movimento · Riduci la trasparenza ·
Differenzia senza colore · Visualizzazione rapida · Finder · Download · Musica · Comandi Rapidi · Calendario ·
Registrazione schermo e audio di sistema · alert sounds (Boop, Brezza, Fumetto, Cristallo, Funky, Eroe, Salto,
Mezzo, Ciottolo, Pizzico, Pong, Sonar, Sonumi, Immersione).

## Review rulings (independent review)

- **notch = tacca** — confirmed: the native word, used consistently (sulla / nella tacca). Many Italian users also
  say "notch"; it could be added as a search word later.
- **Tray = Ripiano** — confirmed. Reads naturally in every phrase ("Tieni sul ripiano", "Svuota ripiano"); "Vassoio"
  is the literal tray but sounds like kitchenware and gains nothing.
- **peek = occhiata** — confirmed as a fixed term ("Occhiata al passaggio del puntatore", column "Occhiate"). Apple's
  "Peek" was never translated and "anteprima" / "visualizzazione rapida" are taken (Preview, Quick Look).
- **To-dos = Da fare / cosa da fare** — confirmed ("3 da fare", "Nuova cosa da fare", "Ancora niente da fare").
- **Paused / Resumed flash = In pausa / Attive**, menu "Sospendi / Riprendi" — confirmed; "Riprese" stays out of the
  wing. The mix is normal Italian (a paused thing is "in pausa"; the command is "sospendi").
- **HUD = Indicatore** — confirmed (singular, as Russian «Индикатор»); search terms keep "HUD" and "OSD".
- **Times: "fino alle %@", "alle %2$@"** — confirmed. The Italian short time is 24-hour H:mm, so only 1:00–1:59
  gives "alle 1:00" (strictly "all’una"), the usual written form in Italian interfaces.
- **Timer "Ends %@" = "Fine: %@"** on the ring and peek (short); the VoiceOver line now says "termina alle %2$@".
- **Keep open / Unpin / Toggle pin** — confirmed ("Mantieni Cranny aperto", "Non mantenere Cranny aperto",
  "Attiva/disattiva “Mantieni aperto”"); the tutorial's "pulsante della puntina" names the pin glyph.
- **Command palette = Riquadro comandi** — confirmed (VS Code Italian). "riquadri" is also Quick Apps' tiles, in
  another module; they never share a screen.
- **Visualizer segments Ambientale / Dal vivo / Statico / Disattivato** — confirmed: the segmented row has
  equal-width segments and plenty of room (Settings ▸ Media snapshot).
- **Resize = Riduci, Zip = Crea zip** — confirmed.
- **"Access is off" = "Nessun accesso"** — confirmed (14 columns; Russian 15 passes in the same card).
