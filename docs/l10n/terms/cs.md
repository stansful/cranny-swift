# Cranny — Czech (čeština, cs) terminology

Register and typography (as macOS 27 in Czech):

- Formal *vy*, lower case mid-sentence ("vaše události"). Buttons and menu items in the **infinitive** ("Otevřít", "Přeskočit", "Vyhledat aktualizace…"); instructions in the imperative ("Přetáhněte…", "Klikněte…"). Settings switches and timeout rows that describe ongoing behaviour use the imperfective infinitive ("Zobrazovat…", "Skrývat…", "Nahrazovat systémový indikátor", "Zavírat po nečinnosti", "Sbalovat po nečinnosti", "Zahrnovat předběžné verze", "Skrývat přejetím nahoru"), or an adjective for a state ("Obrácený směr"); one-off commands the perfective ("Zobrazit…"). Permission reasons use the same imperfective ("Zobrazovat…", "Nahrazovat…", "Ovládat…"). A label or header never ends in a preposition.
- Settings panes in running text as macOS writes them: "v nastavení Obecné", "v nastavení Soukromí a zabezpečení ▸ Zpřístupnění" (never "v sekci" / "v části"); "sekce" only as the plain noun ("v této sekci"). Cranny's own paths keep "v Nastavení ▸ Klávesnice". System setting names after "volba" without quotes, as macOS: "Při zapnuté volbě Snížit průhlednost".
- "Chcete‑li" with a no-break hyphen (U+2011), as macOS writes it.
- Sentence case everywhere, also where English uses title case for menus ("Vyhledat aktualizace…", "Připnout Cranny").
- Quotes „…“ (and ‚…‘); names of panes, buttons, settings and user content in „…“ only where Apple would quote them in running text. Ellipsis … (U+2026). Spaced en dash " – " for the English em dash. No-break space after one-letter prepositions and conjunctions (k, s, v, z, o, u, a, i) — added automatically by the build script.
- Placeholders are never declined: put a noun in front ("aplikace %@", "zkratka „%@“", "na monitoru „%@“").
- Durations come formatted in the nominative ("1 minuta", "4 min"); never put them after a preposition that needs another case ("po 1 minutě" ✗). Use "Za %@" only with short forms ("za 4 min"), otherwise colon forms ("Zbývající čas: %@", "Uplynulý čas: %@") or "ještě %@" / "%@ po pozastavení".
- Plurals: one = 1, few = 2–4, other = 0 and 5+ (genitive plural: "5 buněk", "5 položek"); many (decimals only) is filled with the same text as other.
- "Cranny" is never translated, transliterated or declined; where grammar needs a gender it is masculine ("Cranny je otevřený", "aby se Cranny otevíral") — kept in review: Czech treats program names as masculine (Apple: "macOS spuštěný", "Finder nemůže"), and "Cranny" is also the name of the open panel (masculine "panel"). Every agreement in the file is masculine; neuter would read like an unknown foreign word ("taxi"), and "aplikace Cranny" everywhere would be wordy and wrong for the panel ("aplikace je otevřená").

| English | Czech | Note |
|---|---|---|
| Cranny | Cranny | never declined; "v aplikaci Cranny" when a case is needed |
| notch | výřez | ve výřezu, na výřez (drop onto), nad výřezem; "displej s výřezem" |
| camera housing | kamera / oblast kamery | "zarovnat s kamerou" |
| display (screen) | monitor | as System Settings ▸ Monitory; "vestavěný monitor", "monitor s ukazatelem" |
| open panel | panel | "otevřený panel" |
| Home (built-in page/tab) | Domů | tab label; in sentences „Domů“ or "stránka Domů" |
| page | stránka | "Přidat stránku", "Stránka %lld" |
| Tray | Přihrádka | v přihrádce, do přihrádky, z přihrádky: "Nechat v přihrádce", "Odebrat z přihrádky", "Vyprázdnit přihrádku" |
| item (Tray) | položka | 1 položka, 2 položky, 5 položek |
| Files (widget) | Soubory | |
| live activity / Live Activities | živá aktivita / Živé aktivity | Apple's own term (Control Center); pane „Živé aktivity" |
| Pause / Resume Live Activities | Pozastavit / Obnovit živé aktivity | wing words: Paused → „Pauza", Resumed → „Obnoveno" (measured: fit the 72-pt wing) |
| peek | nahlédnutí | never „náhled" (= Preview) or „Rychlý náhled" (= Quick Look); "Nahlédnutí při změně" |
| compact (activity in the wings) | kompaktní | |
| satellite | satelit | |
| HUD | indikátor | "indikátor hlasitosti a jasu"; never „ukazatel" (= pointer); search keywords may keep HUD/OSD |
| widget | widget | widgety, ve widgetu |
| widget library | knihovna widgetů | |
| Layout & Widgets (pane) | Rozvržení a widgety | |
| layout | rozvržení | "Upravit rozvržení", "počáteční rozvržení" |
| cell (grid) | buňka | 1 buňka, 2 buňky, 5 buněk |
| Mirror | Zrcadlo | widget „Zrcadlo" |
| Notes · To-dos · Timer · Calendar · Media | Poznámky · Úkoly · Časovač · Kalendář · Média | to-do = úkol |
| Quick Apps | Rychlé aplikace | "do rychlých aplikací", "z rychlých aplikací" |
| tile | dlaždice | |
| Shortcuts (Apple's app) · a shortcut in it | Zkratky (aplikace Zkratky) · zkratka | glossary; "Spustit zkratku" |
| keyboard shortcut | klávesová zkratka | plain „zkratka" only inside Settings ▸ Klávesnice where it is unambiguous |
| Command palette | Paleta příkazů | |
| Settings (Cranny) · System Settings | Nastavení · Nastavení systému | "v Nastavení systému" |
| pane (Settings ▸ X) | Nastavení ▸ X | the ▸ path is kept |
| pin / unpin / Keep Cranny open | připnout / odepnout / Připnout Cranny | Apple's Pin = Připnout |
| Demo mode | Ukázkový režim | |
| tutorial (1-minute interactive tour) | kurz | Apple's word (Kurz VoiceOveru, „Otevřít kurz…“, interaktivní kurz): "Spustit kurz", "Přeskočit kurz", "Projít minutový kurz", "Kurz skončil"; "výuka" and "prohlídka" only as search keywords (review: „výuka" reads as school teaching) |
| Welcome (window) / setup | Vítá vás Cranny · uvítání / průvodce | "Přeskočit průvodce", "Pokračovat v průvodci" (avoids a clash with Nastavení = Settings) |
| permission | oprávnění | statuses: Povoleno, Zamítnuto, Zatím ne, Omezeno, Nezjištěno |
| Allow / Allow… / Grant… | Povolit / Povolit… | |
| Accessibility · Automation · Calendars · Camera · System Audio Recording | Zpřístupnění · Automatizace · Kalendáře · Kamera · Záznam systémového zvuku | Apple's names (glossary) |
| Privacy & Security | Soukromí a zabezpečení | |
| Login Items | položky přihlášení | Apple's own wording („Obecné → Položky přihlášení“ in its Shortcuts actions); the macOS 27 pane is „Aktivace položek a rozšíření při přihlášení“, but the name differs between macOS versions and English names it loosely too, so the copy keeps the generic words |
| click (verb / noun) | kliknout / kliknutí | Apple Czech says „klikněte" |
| hover / rest the pointer | podržení ukazatele / podržte ukazatel | Apple: Hover Text = „Text při podržení ukazatele“, "hover" = „podržení ukazatele“; pointer = ukazatel; Apple also writes „Podržením ⌃⌥ dočasně přepínat…“ (instrumental + infinitive) |
| swipe | přejetí / přejeďte | Apple: „Přejeďte doleva dvěma prsty" |
| drag / drop | přetáhnout / pustit (přetáhnout na) | |
| haptic feedback | haptická odezva | |
| menu bar | řádek nabídek | v řádku nabídek |
| full-screen apps | aplikace na celé obrazovce | |
| pipeline (Tray) | postup | as Automator's „pracovní postup"; step = krok; "Nový postup…", "Připnuté postupy" |
| drop zone | zóna (pro přetažení) | "Zóna %lld" |
| chip | tlačítko | |
| Quick Look | Rychlý náhled | Apple |
| Preview (Settings stage) | Náhled | |
| Zip / Unzip | Archivovat / Rozbalit | |
| Compress (images) / Resize | Komprimovat / Zmenšit | |
| Join (meeting) | Připojit se | VoiceOver „Připojit se ke schůzce" |
| Join (short capsule) | Vejít | an infinitive like every button (= Russian «Войти»), 26 pt in the 12-pt label font; „Připojit" (41 pt) fails FeaturedRowTests by 3.5 pt at 5 cells (standard density/text); not „Vstup" (a noun, and „vstup" = input: Vstupní zdroje); the peek, tooltip and VoiceOver keep „Připojit se" |
| meeting | schůzka | "Nadcházející schůzka", "Probíhající schůzka" |
| track / song | skladba | Apple Music |
| player | přehrávač | |
| media helper | pomocník pro média | |
| Apple Events fallback | záložní ovládání přes Apple Events | |
| artwork | grafika alba | Apple Music |
| visualizer | vizualizér | modes Ambientní · Živý · Statický · Vypnuto |
| Now Playing | Právě hraje | Apple |
| Live (stream) | Živě | Apple Music „ŽIVĚ" |
| accent colour | barevný akcent / barva akcentu | Apple; swatches feminine (Modrá, Grafitová…) |
| Reset to Default | Obnovit výchozí hodnotu | |
| Changed from the default | Změněno oproti výchozí hodnotě | |
| Remove (from a list/page) / Delete | Odebrat / Smazat | „Odstranit" for background/metadata/steps |
| Cancel · Done · Undo | Zrušit · Hotovo · Odvolat | Apple |
| Copied (wing) · Done (Quick Apps wing) · Failed | Hotovo · Hotovo · Chyba | measured to fit the wing |
| Hi (greeting) | Ahoj | as the Mac's own hello |
| typographic point | b. | "%@ b." as Apple Czech |
| Never (timeout 0) | Nikdy | |
| Off / On | Vypnuto / Zapnuto | |
| Show on (displays) | Kde zobrazovat | values „Na všech monitorech", „Na vestavěném monitoru", „Na monitoru s ukazatelem", „Na vybraných monitorech" |
| Type to capture | Rychlý zápis | |
| Motion / Density options | Klidně · Standardně · Živě · Okamžitě / Kompaktně · Standardně · Prostorně | adverbs, because "Standard" and "Instant" are shared keys |
| hover-delay presets (Welcome) | Žádná · Krátká, %@ · Standardní, %@ · Dlouhá, %@ | agree with „Prodleva" |

Verified after the independent review: `validate.py cs` exits 0 (13 warnings, all Czech words identical to English or Apple's own Czech names: Panel, Symbol, Trackpad, video, min, +1 min, Funky, Mezzo, Pong, Sonar, Sonumi). With cs imported, the catalogs pass `lint-copy.py` and FlashLabelFitTests, BandCopyTests, FeaturedRowTests, SceneAndHeaderTests (header tabs), RenderedSurfacesTests (tutorial bubble) and WingTextMetricsTests for cs.
