# Cranny — Polish (pl) terminology sheet

Register and style, as macOS writes Polish:
- Informal **Ty**, with the polite forms capitalised as macOS does: Twój, Twoje, Twoich, Ci, Cię („Twoje wydarzenia”).
- **Commands** (buttons, menu items, ⌘K commands): perfective imperative, 2nd person singular — Otwórz, Pokaż, Usuń, Dodaj, Zmień nazwę, Przypnij.
- **Settings switches and persistent options**: imperfective imperative, as in System Settings — Pokazuj…, Ukrywaj…, Zastępuj…, Otwieraj podczas logowania.
- **Progress / in-flight states**: 1st person present as macOS does — Wczytuję…, Sprawdzam…, Obliczam…; static statuses use nouns or participles (Uruchamianie, Działa, Wstrzymano).
- Sentence case. Apple's standard buttons: Anuluj, Dalej, Wróć, Pomiń, Gotowe, Zachowaj (Save), Wyzeruj (Reset), Przywróć domyślne.
- Typography: „…” (secondary «…»), apostrophe ’, ellipsis …, en dash – with spaces; no-break space (U+00A0) after the one-letter words w, z, i, o, u, a (as macOS does: „w aplikacji”).
- Placeholders are never declined: „aplikacja %@”, „w aplikacji %@”, „widżet %@”; the name is quoted „%@” when it is a free name (note, page, pane, widget) and left bare for app names and keys.
- **Cranny** stays as written and is not declined; where a case ending would be needed, the sentence is turned (Otwórz Cranny, w Cranny, aplikacja Cranny, Witaj w Cranny). Cranny is masculine wherever an adjective, participle or pronoun agrees with it („Cranny jest otwarty”, „przypnij go”, „Aby Cranny otwierał się…”).
- **Spelled-out durations** (VoiceOver and the Media picker get „1 minuta”, „4 minuty”, „5 minut” in the nominative): put them only after a colon („pozostało: %@”, „minęło: %@”, „Ustawiono: %@”), after „jeszcze”, or before „później”; never after „za”, „na”, „po” or „przez”, which need another case („za 1 minuta” is wrong). The short forms in the widget and band („4 min”) may follow „Za”.
- **Purpose clauses**: „Aby + bezokolicznik” only when the main clause has the same subject; otherwise „Aby Cranny otwierał się…, aplikacja musi…”.
- **„nigdy” always takes „nie”** with its verb, also in elliptical clauses („…i nigdy nie robi tego podczas pisania”).
- **Toggles vs. buttons**: a toggle that names a state uses a noun or participle („Odwrócony kierunek”, „Odbicie lustrzane”), a toggle that names a behaviour the imperfective („Pokazuj…”); one-off buttons the perfective („Przetestuj wykrywanie multimediów”, „Sprawdź teraz”).
- **Drag vs. drop**: „Przeciągnij pliki na wycięcie” when nothing is being dragged (empty states, tutorial); „Upuść…” in the catch state and on drop zones, where the files are already in hand.

| English (Cranny concept) | Polish | Notes |
|---|---|---|
| Cranny | Cranny | never translated or transliterated; also the open panel („Otwórz Cranny”) |
| notch | wycięcie (ekranu) | na wycięcie (direction), na wycięciu / w wycięciu (place) |
| camera housing | obudowa kamery | Notch fit footers |
| open panel / panel | panel | „Panel” section in Appearance |
| Home (built-in widget page) | Główna | tab and Settings; „strona Główna” in sentences |
| page (user page) | strona | „Strona %lld”, „Dodaj stronę” |
| Layout & Widgets (pane) | Układ i widżety | |
| layout | układ | „Edytuj układ…”, preset layouts „układ początkowy” |
| widget | widżet | Apple's spelling („Edytuj widżety”) |
| Widget library | Biblioteka widżetów | |
| cell (grid) | komórka | 1 komórka, 2 komórki, 5 komórek; „Wolne komórki: N” avoided — plural forms used |
| Tray | Półka | na półce, z półki, półkę („Zostaw na półce”, „Usuń z półki”, „Wyczyść półkę”) |
| item (Tray) | rzecz | Finder's word: 1 rzecz, 2 rzeczy, 5 rzeczy |
| Files (mini shelf widget) | Pliki | |
| pipeline | potok | „Twoje potoki”, „Przypięte potoki”, „Nowy potok…” |
| step (pipeline) | krok | |
| drop zone | strefa upuszczania | „Strefa %lld” in the pinned list |
| Keep in Tray | Zostaw na półce | drop zone |
| drag / drop (files) | przeciągnij / upuść | „Przeciągnij pliki na wycięcie” |
| Quick Look | Szybki przegląd | Apple's name |
| Zip / Unzip | Spakuj (ZIP) / Rozpakuj | Compress (images) = Kompresuj |
| Live Activities (pane, feature) | Aktywności na żywo | kept after review: Cranny's own feature name. macOS 27 Control Center says „Wydarzenia na żywo”, but in Cranny „wydarzenie” is the Calendar event that itself becomes a live activity („Ukryte kalendarze nie pojawiają się … jako aktywności na żywo”); macOS's LiveActivities module also says „Aktywność na żywo” |
| live activity | aktywność (na żywo) | short form „aktywność / aktywności” in running text |
| Pause / Resume Live Activities | Wstrzymaj / Wznów aktywności | sentences „Aktywności wstrzymane …” / „Aktywności wznowione” |
| Paused / Resumed (wing words) | Pauza / Aktywne | measured: „Wznowione” does not fit the 72-pt wing |
| peek | minipodgląd | not „Szybki przegląd” (Quick Look) nor „Podgląd” (Preview) |
| Preview (Settings stage) | Podgląd | |
| compact (state) | kompaktowy | |
| satellite | satelita | |
| priority classes: Alerts · Ongoing · Passive | Alerty · Trwające · W tle | |
| HUD | nakładka | Settings pane „Nakładka” (kept after review); „wskaźnik” is macOS's word for the pointer, so it is not used for the HUD; „wskaźnik głośności” is only a search keyword of the pane |
| pointer | wskaźnik | „Na wyświetlaczu ze wskaźnikiem” |
| display | wyświetlacz | Apple's word; „ekran” only for the screen surface |
| menu bar | pasek menu | Apple's word |
| Settings (Cranny) | Ustawienia | panes: Ogólne, Wygląd, Klawiatura, Gesty, Uprawnienia, Informacje |
| System Settings | Ustawienia systemowe | „w Ustawieniach systemowych” |
| Permissions | Uprawnienia | status pills: Przyznano · Odmówiono · Jeszcze nie · Ograniczono · Nieznany; Media/onboarding statuses: Dozwolone · Niedozwolone |
| Allow… / Grant… | Pozwól… | Apple's TCC button „Pozwól” |
| Open %@ (an app) | Otwórz aplikację %@ | the name is never declined („Otwórz Muzyka” would be wrong) |
| Reset to Default | Przywróć wartość domyślną | row menu |
| Reset (a pane / all) | Wyzeruj | Apple's „Wyzeruj”; „Wyzerować wszystkie ustawienia?” |
| Changed from the default | Zmieniono względem wartości domyślnej | |
| Demo mode | Tryb demo | Apple (Game Center) writes „Tryb demo” |
| Pin / Keep open / Unpin | Przypnij / Przypnij Cranny / Odepnij | Apple: „Przypnij kartę” |
| tutorial | samouczek | Apple („Samouczek VoiceOver”); „Pomiń samouczek” |
| Welcome (window) | Witaj w Cranny | |
| click / hover | kliknij, kliknięcie / najechanie, „zatrzymaj wskaźnik” | |
| Open Cranny with: Hover · Click · Shortcut only | Najechaniem · Kliknięciem · Tylko skrótem | onboarding cards: Najechanie · Kliknięcie · Tylko skrót |
| keyboard shortcut | skrót klawiszowy (short: skrót) | the Shortcuts **app** is „Skróty”; its items are „skróty” |
| Shortcuts (Apple app) | Skróty | Apple's name; „w aplikacji Skróty” |
| Quick Apps | Szybkie aplikacje | |
| tile | kafelek | |
| launcher (keyword) | program startowy | |
| Save (Apple's button) · Undo · Retry | Zachowaj · Cofnij · Ponów / Spróbuj ponownie | |
| Command palette | Paleta poleceń | |
| Media (widget) | Multimedia | |
| Now Playing | Odtwarzane | Apple's name |
| player (media app) | odtwarzacz | |
| media helper | pomocnik multimediów | |
| Apple Events fallback | zapasowa metoda Apple Events | |
| visualizer (Live · Ambient · Static · Off) | wizualizator (Na żywo · Łagodny · Statyczny · Wył.) | a live stream's badge is „Na żywo” too; in sentences the mode is „Tryb „Na żywo” / „Łagodny” / „Statyczny”” |
| Music (Apple app) | Muzyka | „aplikacja Muzyka” |
| Calendar · event | Kalendarz · wydarzenie | Apple Calendar's word |
| Join (meeting) | Dołącz | peek, VoiceOver („Dołącz do spotkania”), tooltip, Settings preview |
| Join (the Calendar row's short capsule) | Wejdź | the only short form: „Dołącz” is 1.5 pt too wide for the 5-cell column (FeaturedRowTests, measured) |
| Meeting soon · Meeting in progress | Wkrótce spotkanie · Trwa spotkanie | |
| Lead time | Pokazuj z wyprzedzeniem | row label before the duration picker |
| Meeting in progress ▸ Show: Time left · Time elapsed | Pozostały czas · Czas od początku | not „upłynięty” (no such participle) |
| Mirror | Lusterko | |
| Notes · To-dos · Timer | Notatki · Zadania · Minutnik | Apple's Clock app calls the timer „Minutnik” |
| preset (Timer) | gotowe ustawienie | „Gotowe ustawienia” (section), „Ustawienie %lld” (row); units under a preset: h · min · s (the symbols ICU's narrow durations use) |
| Typing effect | Efekt pisania | |
| Type to capture (Notes · To-dos · Off) | Szybkie wpisywanie (Notatki · Zadania · Wył.) | |
| Welcome layouts: Listener · Maker · Meetings · Minimal | Meloman · Twórca · Spotkania · Minimum | |
| Option key | klawisz Option („Przytrzymaj klawisz Option”) | ⌥ symbol stays a symbol |
| file-name suffixes: compressed · no background · no metadata | po kompresji · bez tła · bez metadanych | invariable, so they fit any file noun |
| Text size | Wielkość tekstu | Apple's word |
| Motion (Calm · Standard · Lively · Instant) | Ruch (Spokojnie · Standardowo · Żywo · Natychmiast) | adverbs: „Standard” and „Instant” are shared keys across pickers |
| Density (Compact · Standard · Roomy) | Gęstość (Gęsto · Standardowo · Przestronnie) | |
| Text size (Small · Medium · Large · Extra large) | Wielkość tekstu (Mała · Średnia · Duża · Bardzo duża) | |
| Ambient light (Off · Subtle · Vivid) | Światło otoczenia (Wył. · Subtelne · Intensywne) | |
| accent | akcent; Kolor akcentu | Apple's word |
| Ambient light · Underglow · Album glow | Światło otoczenia · Poświata pod spodem · Poświata albumu | |
| Effect: Aurora · Motes · Tide | Zorza · Drobinki · Fala | |
| Feel It (haptic test button) | Wypróbuj | |
| Notch fit | Dopasowanie do wycięcia | |
| floating island · attached · handle | pływająca wyspa · przy krawędzi · uchwyt | |
| Glass island | Szklana wyspa | Liquid Glass stays English |
| Reduce motion · Reduce transparency · Increase contrast · Differentiate without color | Redukuj ruch · Zmniejsz przezroczystość · Zwiększ kontrast · Różnicuj bez koloru | Apple's names, in „…” |
| Haptic feedback | Odpowiedzi haptyczne | Apple's term |
| Launch at login | Otwieraj podczas logowania | Apple's term; Login Items = „Rzeczy otwierane podczas logowania” |
| updates | uaktualnienia | Apple's word („Sprawdź uaktualnienia…”) |
| Low Power Mode | Tryb Niskie zużycie energii | Apple's name |
| Remove (from a list) | Usuń z listy / Usuń z półki / Usuń z szybkich aplikacji | never just „Usuń aplikację” (reads as uninstall) |
| App not installed | Aplikacja nie jest zainstalowana | |
| Excluded apps | Wykluczone aplikacje | |
| Done (flash) · Copied (flash) · Failed (flash) · Hi | Gotowe · Gotowe · Błąd · Cześć | measured in the wing |
| Done (Timer, band) | Koniec | ≤ 6 characters and fits the medium wing |
| macOS (grammar) | masculine (system): „macOS nie dodał” | |
