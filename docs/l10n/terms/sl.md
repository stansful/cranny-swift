# Cranny — Slovenian (sl) terminology sheet

Register and style, following macOS 27 in Slovenian (checked in the system's own loctables):

- Buttons, menu items, commands and toggles: **imperative, 2nd person singular**, as Apple writes them
  (“Odpri”, “Prikaži odstotek”, “Premakni v koš”, “Zapri aplikacijo Koledar”, “Pripni zapisek”).
- Sentences, footnotes, coach marks, tutorial steps and VoiceOver hints: **formal vi** (“Kliknite”, “Povlecite”,
  “Če zaprete zdaj, boste izgubili …”, “Vaši dogodki”).
- Confirmation titles: **“Želite …?”** (Apple: “Želite izbrisati zbirko?”) → “Želite izbrisati »%@«?”,
  “Želite ponastaviti vse nastavitve?”.
- Sentence case everywhere; Slovenian has no title case (Apple: “O aplikaciji Koledar”, “Zapri okno”).
- Quotes: **»…«** (macOS 27), inner „…“. Names of apps/panes/settings in running text either quoted or after a
  generic noun (Apple: “aplikacija Vreme”, “razdelek »Zasloni«”, “mapa Aplikacije”).
- Ellipsis: **no-break space + …** exactly as macOS writes it (“Nastavitve …”, “Preverjanje …”, “Dovoli …”;
  confirmed in Battery.loctable: “Nastavitve baterije …”). A “(…)” standing for the ⋯ button keeps no space.
  ▸ for Cranny's own Settings paths.
- Units: a space before units (“90 s”, “12 min”); “h” for hours, “min”, “s”, “ms”, “pt”, “px”.
- Placeholders are not declined: a noun in front carries the case (“v aplikaciji %@”, “na zaslonu »%@«”).
- Plurals: one (1, 101), **two (dual: 2, 102)**, few (3–4), other (0, 5–20, 100): “1 element, 2 elementa,
  3 elementi, 5 elementov”; “1 celica, 2 celici, 3 celice, 5 celic”; “1 dan, 2 dneva, 3 dnevi, 5 dni”.
- **Cranny** is never translated or transliterated. Grammatically masculine, inanimate (“Cranny je odprt”).
  Nominative/accusative preferred (“Odpri Cranny”); declines like Sydney when a case is unavoidable
  (Crannyja, Crannyju, Crannyjem), used sparingly. Where the *application* is meant, Apple's pattern
  “aplikacija Cranny” (“O aplikaciji Cranny”, “Zapri aplikacijo Cranny”).
- Apple's names from `apple-terms.py sl`: Nastavitve sistema (v Nastavitvah sistema), Zasebnost in varnost, Dostopnost,
  Elementi prijave, Menijska vrstica, Način nizke porabe, Hitri pregled, Glasba, Bližnjice, Koledar, Zapiski,
  Prenosi, Aplikacije, Zmanjšaj dinamičnost animacij, Zmanjšaj prosojnost, Razlikuj brez barv, Predvaja se,
  Snemanje sistemskega zvoka, alert sounds (Sapica, Mehurček, Kristal, Funk, Junakinja, Skok, Prodnik, Puljenje,
  Potop; Boop, Mezzo, Pong, Sonar, Sonumi unchanged).

| English (Cranny concept) | Slovenian | Notes |
|---|---|---|
| Cranny (also the open panel: “Open Cranny”) | Cranny | “Odpri Cranny”, “Zapri Cranny” (panel); the app: “Zapri aplikacijo Cranny”, “O aplikaciji Cranny” |
| notch | zareza (zaslona) | na zarezi, na zarezo, ob zarezi, brez zareze; “zaslon z zarezo” |
| camera housing | ohišje kamere | |
| open panel / Panel (Appearance section) | plošča | “Odmik plošče”, “odprta plošča” |
| Home (built-in widget page, tab) | Domov | Apple Books' tab; “stran Domov” in sentences; tab ≤ 12 characters |
| page | stran | “Dodaj stran”, “Stran %lld”, “Vse strani” |
| Layout & Widgets (pane) | Postavitev in gradniki | Apple Books “Postavitev” |
| layout | postavitev | “Uredi postavitev”, “Izberite začetno postavitev” |
| widget / widget library | gradnik / knjižnica gradnikov | Apple: “Gradniki”, “Uredi gradnike” |
| cell (grid) | celica | 1 celica · 2 celici · 3 celice · 5 celic |
| Tray | Polica | na polici, s police, polico: “Obdrži na polici”, “Odstrani s police”, “Počisti polico” |
| item (Tray) | element | Apple's word (“Elementi prijave”): 1 element · 2 elementa · 3 elementi · 5 elementov |
| keep (files in the Tray) | obdržati | “Obdrži na polici”, “Obdrži največ”, “…, da jih obdržite tukaj” (not “shraniti”, which is Save) |
| N selected (chip row) | Izbrano: N | Apple's “Izbrano: %d”; no participle that would have to agree with a noun |
| Files (widget) | Datoteke | |
| pipeline | cevovod | “Vaši cevovodi”, “Pripeti cevovodi”, “Nov cevovod …” |
| step (pipeline) | korak | |
| drop zone | območje za spuščanje | “Območje za spuščanje %lld”, “Območje AirDrop” |
| drag / drop (files) | povleči / spustiti | “Povlecite datoteke na zarezo”; drag-and-drop = povleci in spusti |
| live activity / Live Activities | aktivnost v živo / Aktivnosti v živo | Apple's own term; pane name capitalised; short “aktivnost” in running text |
| compact (activity beside the camera) | strnjeni prikaz | not user-facing except footnotes |
| peek | vpogled | “Vpogled ob spremembi”, “Trajanje vpogleda”; not “predogled” (= Preview) nor “Hitri pregled” (= Quick Look) |
| satellite | satelit | |
| Pause / Resume Live Activities | Začasno ustavi / Nadaljuj aktivnosti v živo | Apple: Pause = “Začasno ustavi”, Resume = “Nadaljuj” |
| Paused (pause flash) · Resumed (resume flash) | Premor · Aktivne | wing words (measured: 45 / 48 pt, wide slot) |
| HUD | indikator | Settings pane “Indikator”; search terms keep “HUD” and “OSD” |
| Now Playing (activity) | Predvaja se | Apple Control Center |
| player (media app) | predvajalnik | “Odpri predvajalnik” |
| track / song | posnetek / skladba | Apple: “Naslednji posnetek” |
| media helper | pomožni program za predstavnost | “Pomožni program MediaRemote (perl)” |
| Apple Events fallback | rezervni način prek Apple Events | |
| visualizer (Ambient / Live / Static / Off) | vizualizator (Ambientni / V živo / Statični / Izklopljeno) | in running text after the noun: “Način Ambientni …”, “Način V živo …”, “vizualizator V živo”; moves “v ritmu zvoka / glasbe” |
| Media (widget, pane) | Predstavnost | Apple: “Predstavnost in Apple Music” |
| Mirror | Ogledalo | |
| Notes · note | Zapiski · zapisek | Apple's Notes words (“Nov zapisek”) |
| Focus (Notes widget) · Exit focus | Fokus · Zapri način fokusa | Apple “Način fokusa” (Books), “Zapri celozaslonski način” |
| code highlighting | poudarjanje skladnje | “Hitri zapiski s poudarjanjem skladnje” |
| typing effect: “then settle” | “nato dobijo običajno barvo” | not “se umirijo” |
| To-dos · to-do | Opravila · opravilo | “Novo opravilo”, “Še %lld” |
| Timer | Časovnik | Apple Clock; “Zaženi časovnik”, “Časovnik je potekel” |
| preset (Timer) | prednastavitev | Apple's word |
| Calendar | Koledar | |
| Join (meeting; peek, VoiceOver) | Pridruži se | Apple: “Pridruži se sestanku” |
| Join (short capsule in a widget row) | Vstopi | the only short form (34-pt capsule) |
| meeting | sestanek | “Sestanek kmalu”, “Sestanek poteka” |
| Quick Apps | Hitre aplikacije | “Dodaj med hitre aplikacije”, “Odstrani iz hitrih aplikacij” |
| Running (an open app, a running shortcut) | se izvaja | “Se izvaja”, “bližnjica, ki se izvaja” (not “teče”; a timer still “teče”) |
| Move earlier / Move later (tile order, VoiceOver) | Premakni na prejšnje mesto / na naslednje mesto | “naprej / nazaj” is ambiguous |
| Dock | vrstica Dock | Apple: “v vrstici Dock”, “iz vrstice Dock” |
| tile (Quick Apps) | ploščica | |
| Shortcuts (Apple's app) · a shortcut | Bližnjice · bližnjica | Apple's name; Settings pane “Bližnjice” |
| keyboard shortcut | bližnjica na tipkovnici / bližnjica | Apple: “Bližnjice na tipkovnici …”; in Settings ▸ Keyboard just “bližnjica” |
| launcher (search keyword) | zaganjalnik | |
| Settings · Settings… | Nastavitve · Nastavitve … | Apple's menu item |
| System Settings | Nastavitve sistema | “v Nastavitvah sistema” |
| Permissions · permission | Dovoljenja · dovoljenje | statuses: Dovoljeno · Zavrnjeno · Omejeno · Še ne · Neznano |
| Allow… / Grant… | Dovoli … | |
| Demo mode | Predstavitveni način | Apple's “Demo Mode” |
| tutorial | vadnica | “Prikaži vadnico”, “Preskoči vadnico”, search word “vodič” for tour |
| Welcome / setup | Dobrodošli / nastavitev | “Preskoči nastavitev” |
| Keep open / Pin · Unpin | Pripni · Odpni | Apple Notes “Pripni zapisek”; “Pripni Cranny”, “Pripni/odpni” |
| Show … (every show-switch) | Prikaži … | Apple: “Prikaži odstotek” |
| Hover (Open Cranny with) | Lebdenje | Apple's word (“lebdenje”, “Lebdeče besedilo”); descriptions “Pustite kazalnik na zarezi”; VoiceOver “Odprto z lebdenjem kazalnika” |
| Hold ⌥ to pass over (toggle) | Pridrži ⌥ za prehod čez zarezo | footnote: “…, ne da bi odprli Cranny” |
| Click | Klik / kliknite | Apple: “Kliknite …” |
| pointer | kazalnik | Apple's word (not “kazalec”) |
| swipe | podrsljaj / podrsnite | Apple's words |
| trackpad | sledilna ploščica | Apple; “sledilna ploščica Force Touch” |
| haptic feedback | haptični odziv | Apple |
| display / screen | zaslon | “Vgrajeni zaslon”, “Zaslon s kazalnikom” |
| Show on (which displays) | Kje prikazati | values “Na vgrajenem zaslonu”, “Na zaslonu s kazalnikom”, “Na vseh zaslonih”, “Na izbranih zaslonih” |
| full-screen apps | celozaslonske aplikacije | Apple: “celozaslonski način” |
| menu bar · menu bar icon | menijska vrstica · ikona v menijski vrstici | Apple |
| Excluded apps | Izključene aplikacije | |
| app | aplikacija | Apple's word |
| Remove (from a list) | Odstrani | “Odstrani s seznama” where it could read as uninstall |
| App not installed | Aplikacija ni nameščena | |
| Reset to Default · Changed from the default | Ponastavi na privzeto · Spremenjeno glede na privzeto | Apple “Ponastavi na privzeto” |
| Never (a timeout) | Nikoli | |
| Off / On / Automatic / None | Izklopljeno / Vklopljeno / Samodejno / Brez | Apple |
| Accent (colour) | Barva poudarka / poudarek | Apple “Barva poudarka”; colours feminine: Modra, Vijolična, Rožnata, Rdeča, Oranžna, Rumena, Zelena, Grafitna, Zelenomodra; Quick Apps tiles also Rjava, Siva, Indigo, Pastelno zelena (Apple's Mint) |
| Ambient light (Off / Subtle / Vivid) | Ambientna svetloba (Izklopljeno / Nežna / Živa) | |
| Quality (the light: Detailed · Efficient) | Kakovost (Podrobna · Varčna) | Settings ▸ Appearance ▸ Light; search keywords pomnilnik · zmogljivost |
| Motion (Calm / Standard / Lively / Instant) | Gibanje (Umirjeno / Standardno / Živahno / Takoj) | “Takoj” also for an instant hover delay |
| Density (Compact / Standard / Roomy) | Gostota (Strnjeno / Standardno / Prostorno) | |
| floating island · attached | plavajoči otok · pritrjeno | no-notch styles |
| handle (no-notch) | ročica | “Vidna”, “Skrita do lebdenja” |
| command palette | paleta ukazov | |
| Copied (flash) · Done (Quick Apps flash) · Failed | Kopirano · Končano · Napaka | wing words, wide slot (measured 56 / 55 / 48 pt) |
| Live Activities priority classes (Alerts / Ongoing / Passive) | Opozorila / V teku / Pasivne | not “Tekoče” (reads as “liquid”) |
| Release notes | Opombe o izdaji | Apple |
| Game controller · charging case (Bluetooth) | Igralni kontroler · škatlica | Apple (“Igralni kontrolerji”, “Škatlica za slušalke AirPods”) |
| Plugged in · Connected to power | Napajalnik je priključen · Priključeno na napajanje | Apple “Napajalnik” |
| Hi (greeting in the notch) | Zdravo | medium slot (44 pt) |
| Timer done (≤ 6 characters) | Konec | |
| %@ left (time) | še %@ | “Zdaj · še 12 min” |
| in %@ (wing) | %@ | the preposition does not fit the wing (“čez 30 min” is 63 pt; the slot holds 48) |
| After %@ (Hide paused media: 10 s … 5 min) | %@ | spelled-out durations come in the nominative (“1 minuta”), so no preposition; the picker label carries the meaning |
| file kinds in “Needs %@, but the step before makes %@.” | accusative plural: slike, PDF-je, videoposnetke, arhive ZIP, poljubne datoteke | the kind keys are used only in that sentence |
| Quick Look | Hitri pregled | Apple |
| Reveal in Finder / Show in Finder | Prikaži v aplikaciji Finder | Apple Mail/OBEX: “Prikaži v aplikaciji Finder” |
| Zip / Unzip · Compress (images, video) · Resize (images) | Arhiviraj / Razpakiraj · Stisni · Pomanjšaj | “Pomanjšaj na %@ px”; Apple “Odstrani ozadje”, “Pretvori”, “Ustvari PDF”, “Deli …” |

## Review notes (independent review, 2026-10-14)

- Kept after review: zareza (macOS has no Slovenian word for the notch; “zareza” is what Slovenian tech press uses),
  vpogled (peek), Polica (in “na polici / s police / polico” it never reads as an insurance policy), Indikator (HUD),
  cevovod (the established computing term; the Tray footnote explains it as a chain of steps), Domov, Lebdenje,
  Vstopi (Join capsule), the bare duration for “After %@” (the formatter gives the nominative, so no preposition fits
  every form), accusative file kinds (PipelineTitles.content is only used in the “Needs …” sentence), Cranny masculine.
- Timer hint “25 ali 90 s” now has a (no-break) space before the unit; DurationParser skips spaces, so it parses.
- Open for the code: DurationParser has no Slovenian unit words (sekund, minut, ur…); “25 min” and “90 s” work.
