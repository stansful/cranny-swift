# Cranny — Slovak (slovenčina, sk) terminology

Register and typography, as macOS 27 writes Slovak (checked in the system's own loctables):

- Formal *vy*, lower case mid-sentence ("vaše udalosti"). Buttons and menu items in the **infinitive** ("Otvoriť", "Zrušiť", "Vyhľadať aktualizácie…"); instructions in the imperative ("Potiahnite…", "Kliknite…"). Switches that describe ongoing behaviour use the imperfective infinitive ("Zobrazovať…", "Skrývať…"), one-off commands the perfective ("Zobraziť…").
- Sentence case everywhere, also where English uses title case for menus ("Vyhľadať aktualizácie…", "Pripnúť Cranny").
- "app" is **apka** (apky, apiek, apkou), as System Settings writes it in macOS 27 ("Správa apiek", "Apka %@ žiada o prístup…"); the one exception is Apple's menu convention "O aplikácii Cranny" / pane "O aplikácii".
- Apple's names of settings, panes and apps are written **without quotes**, introduced by a classifier noun: "funkcia Obmedziť pohyb", "apka Hudba", "Súkromie a bezpečnosť ▸ Prístupnosť" (as macOS: "Keď je zapnutá funkcia Obmedziť priehľadnosť…"). User content (note titles, pipeline names, file names, search queries) goes in „…“ (‚…‘ inside), as Apple does ("Vymazať „%@“?").
- Placeholders are never declined: a noun in front carries the case ("apka %@", "na displeji %@", "postup „%@“").
- Durations arrive in the nominative ("4 min", "2 minúty 11 sekúnd"): never after a preposition that needs another case. Abbreviated forms ("4 min", "1 h 30 min") may follow "o"/"na"; spelled-out ones use "ešte %@", "%@ od začiatku", "Zostávajúci čas: %@", "%@ po pozastavení".
- Plurals: one = 1, few = 2–4, other = 0 and 5+ (genitive plural: "5 buniek", "5 položiek"); many (fractions only) is filled with the same text as other.
- One-character ellipsis …; spaced en dash " – " where English has an em dash; no-break space (U+00A0) after the one-letter prepositions and conjunctions k, s, v, z, o, u, a, i (added by the build script).
- "Cranny" is never translated, transliterated or declined; "apka Cranny" when a case is needed. Where grammar needs a gender it is **neuter** like other indeclinable names ("Cranny je otvorené"), and that is avoided where possible. macOS is masculine ("macOS nepridal").

| English | Slovak | Note |
|---|---|---|
| Cranny | Cranny | never declined; neuter agreement; "apka Cranny" |
| notch | výrez | vo výreze, na výrez (drop onto), nad výrezom; "displej s výrezom" |
| camera housing | oblasť kamery | "zarovnať s oblasťou kamery" |
| display | displej | as System Settings ▸ Displeje; "vstavaný displej", "displej s kurzorom" |
| pointer · hover | kurzor · podržanie kurzora | Apple uses kurzor ("Presnosť kurzora") and podržanie ("Farby pri podržaní") |
| click · drag · drop | kliknúť / kliknutie · potiahnuť · pustiť | "Potiahnite súbory na výrez" |
| menu bar | lišta | Apple: "Zobraziť v lište"; "ikona v lište" |
| full screen | celá obrazovka | "apky na celej obrazovke" |
| open panel | panel | "otvorený panel" |
| Home (built-in page/tab) | Domov | tab label; in sentences "stránka Domov" |
| page | stránka | "Pridať stránku", "Stránka %lld" |
| Tray | Polica | na polici, z police, na policu: "Ponechať na polici", "Odstrániť z police", "Vyčistiť policu" |
| item (Tray) | položka | 1 položka, 2 položky, 5 položiek |
| Files (widget) | Súbory | |
| live activity · Live Activities | aktivita · Aktivity naživo | Apple's own term (Ovládacie centrum ▸ Aktivity naživo) for the pane and the feature; a single one is "aktivita" |
| Pause / Resume Live Activities | Pozastaviť / Obnoviť aktivity naživo | wing words: Paused → "Pauza", Resumed → "Obnovené" (measured: fit the 72-pt wing) |
| peek | nahliadnutie | never "náhľad" (= Preview) or "Rýchly náhľad" (= Quick Look); "Nahliadnutie pri zmene" |
| compact (activity in the wings) | kompaktný | |
| satellite | satelit | |
| HUD | indikátor | "indikátor hlasitosti a jasu", "systémový indikátor"; search keywords keep HUD/OSD |
| widget · widget library | widget · knižnica widgetov | widgety, vo widgete |
| Layout & Widgets (pane) | Rozloženie a widgety | |
| layout | rozloženie | "Upraviť rozloženie", "úvodné rozloženie" |
| cell (grid) | bunka | 1 bunka, 2 bunky, 5 buniek; "3 voľné bunky", "5 voľných buniek" (numeral first) |
| Mirror | Zrkadlo | widget Zrkadlo |
| Notes · To-dos · Timer · Calendar · Media | Poznámky · Úlohy · Časovač · Kalendár · Médiá | to-do = úloha; Timer as the Clock app |
| Quick Apps | Rýchle apky | "do Rýchlych apiek", "z Rýchlych apiek" |
| tile | dlaždica | |
| Shortcuts (Apple's app) · a shortcut in it | Skratky (apka Skratky) · skratka | Apple: "Spustiť skratku" |
| keyboard shortcut | klávesová skratka | "skratka" alone only where it is unambiguous |
| Command palette | Paleta príkazov | |
| Settings (Cranny) · System Settings | Nastavenia · Systémové nastavenia | "v Systémových nastaveniach" |
| pane (Settings ▸ X) | Nastavenia ▸ X | the ▸ path is kept |
| pin / unpin · Keep Cranny open | pripnúť / odopnúť · Pripnúť Cranny | Apple's Pin Note = Pripnúť poznámku |
| Demo mode | Prezentačný režim | for screen sharing; search keywords add "demo" |
| tutorial (1-minute interactive tour) | kurz | Apple's word for an interactive tutorial (Kurz VoiceOveru, Otvoriť kurz…): "Spustiť kurz", "Preskočiť kurz", "Prejsť si minútový kurz"; never "návod" (= manual) or "prehliadka"; both stay as search keywords |
| Welcome · setup | Vitajte v Cranny · úvodné nastavenie | "Preskočiť úvodné nastavenie" |
| permission | povolenie | statuses: Povolené, Zamietnuté, Zatiaľ nie, Obmedzené, Neznáme |
| Allow / Allow… / Grant… | Povoliť / Povoliť… | Apple's TCC button |
| Reset to Default · Changed from the default | Obnoviť predvolenú hodnotu · Zmenené oproti predvolenej hodnote | |
| Reset … / Reset All | Resetovať … / Resetovať všetko | |
| Remove (from a list) · Delete | Odstrániť · Vymazať | as AppKit (Remove = Odstrániť, Delete = Vymazať) |
| Undo | Odvolať | as AppKit |
| Cancel · Done · OK | Zrušiť · Hotovo | as AppKit |
| App not installed | Apka nie je nainštalovaná | |
| player (media app) | prehrávač | |
| track · Next / Previous track | skladba · Ďalšia / Predchádzajúca skladba | |
| Now Playing | Práve hrá | Apple's Control Center name |
| pipeline · step | postup · krok | "Nový postup…", "Vaše postupy", "Pripnuté postupy" |
| chip | tlačidlo | |
| drop zone | zóna | "Zóna %lld" |
| Join (meeting) | Pripojiť sa | peek, tooltip; VoiceOver "Pripojiť sa na stretnutie" (Apple Calendar's own label) |
| Join (Calendar row capsule) | Vojsť | the only short form (= Russian «Войти»); "Vstúpiť" (40 pt) failed FeaturedRowTests at standard density, 5 cells, "Vojsť" is 29 pt |
| meeting | stretnutie | Apple Calendar's term (Pripojiť sa na stretnutie, pozvánky a stretnutia); never "schôdzka" (= appointment or date): "Prebiehajúce stretnutie", "Blíži sa stretnutie", "Odkazy na stretnutia" |
| Typing effect | Efekt písania | |
| Instant | Okamžité | onboarding preset and Settings picker value, neuter like the neighbouring values (Krátke, Štandardné, Dlhé) |
| Never · Off | Nikdy · Vypnuté | |
| Show on (Settings, menu bar) | Kde zobrazovať | values read as phrases: "Na všetkých displejoch", "Na vstavanom displeji", "Na displeji s kurzorom", "Na vybratých displejoch" |
| Open Cranny with | Otvárať Cranny | values "Podržaním kurzora / Kliknutím / Len klávesovou skratkou"; onboarding cards "Podržanie kurzora / Kliknutie / Len skratka" |
| Fold away after · Close after inactivity | Zbaľovať po nečinnosti · Zatvárať po nečinnosti | imperfective like every switch; "Zatvárať, keď kurzor opustí panel" |
| Show … (every show switch) | Zobrazovať … | likewise "Nahrádzať systémový indikátor", "Zahŕňať predbežné verzie", "Skrývať potiahnutím nahor", "Obrátený smer" |
| Style · Mono · Semantic (HUD colours) | Štýl · Biela · Podľa významu | |
| Accent | Akcent / Farba akcentu | Apple: "Farba akcentu"; colour names feminine as Appearance ("Modrá", "Grafitová") |
| Preview (Settings preview stage) | Náhľad | as Apple ("Zobrazovať náhľady") |
| Quick Look | Rýchly náhľad | Finder |
| Zip · Unzip · Compress (images) | Archivovať · Rozbaliť · Komprimovať | Finder's "Stlačiť" is avoided next to "Komprimovať" |
| Resize (images) · Convert | Zmenšiť · Konvertovať | |
| Reveal in Finder / Show in Finder | Zobraziť vo Finderi | Finder |
| Share… | Zdieľať… | Finder |
| Login Items | Položky a rozšírenia spúšťané pri prihlásení | Apple's pane name in General |
| launch at login | otvárať po prihlásení | Apple: "Otvoriť po prihlásení" |
| System settings named in copy | funkcia Obmedziť pohyb · Obmedziť priehľadnosť · Rozlíšiť bez farby | never paraphrased, never quoted |
| Music (Apple's app) | apka Hudba | |
| Timer alert sounds | Apple's names (Sound ▸ Boop → Pípnutie, Crystal → Kryštál, Mezzo → Mezzo…) | glossary |
| Spaces | plochy | Apple: "Posunúť o plochu doľava" |
| ambient light · underglow · album glow | svetlo v pozadí · žiara pod panelom · žiara albumu | |
| handle (no-notch) | úchyt | |
| floating island · attached | plávajúci ostrov · pripojené | |
| density: compact / standard / roomy | Kompaktné / Štandardné / Priestranné | picker values neuter |
| motion: calm / lively | Pokojné / Živé | |
| visualizer: ambient / live / static | Ambientné / Živé / Statické | neuter (zobrazenie) to match "Vypnuté" |
| Live (a stream) | Naživo | |
| sensitivity · haptic feedback | citlivosť · haptická odozva | |
| release · pre-release · release notes | vydanie · predbežná verzia · Poznámky k vydaniu | |
| Check for updates · Last checked · Not checked yet | Vyhľadať aktualizácie · Posledná kontrola: %@ · Kontrola ešte neprebehla | "Posledná kontrola" is Apple's own status line |
| Apple Events fallback | záložné ovládanie cez Apple Events | in the toggle, footnotes, warnings and test results alike |
| Timer units under a preset (uppercase) | h · min · s | Apple's Clock (HRS → H, sec → s); Start button "Spustiť" |
| Hover delay | Oneskorenie pri podržaní kurzora | "pri podržaní" alone would also mean holding a key |
| Quality (the light: Detailed · Efficient) | Kvalita (Podrobná · Úsporná) | Settings ▸ Appearance ▸ Light; search keywords pamäť · výkon |

Review (independent review pass): 79 strings changed.

Verification: `validate.py sk` exits 0 (13 warnings, all names or units Slovak writes like English: Symbol, Panel, Trackpad, video, min, +1 min, and the alert sounds Funky, Mezzo, Pong, Sonar, Sonumi as macOS names them). With `sk` imported, the measured-width tests (FlashLabelFitTests, BandCopyTests, FeaturedRowTests, the header tab test, the longest tutorial bubble) pass for `sk`, and `scripts/lint-copy.py` passes.
