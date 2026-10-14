# Cranny – Finnish (suomi, fi) terminology

Register: informal *sinä*, as macOS does. Buttons and menu items in the imperative singular
(Avaa, Lisää, Poista, Kätke, Peru, Kumoa), toggles also in the imperative (“Näytä kuvake valikkorivillä”),
labels and headers as nouns. Sentence case. Quotes ”…” (U+201D on both sides) and ’…’, used sparingly —
setting names inside sentences are quoted (”Vähennä läpinäkyvyyttä”), app names are not (Pikakomennot-appi).
Ellipsis … (U+2026). Ranges and spaced dashes use the en dash (– ). Placeholders are never inflected: use
“apissa %@”, “pikakomento %@”, “Avaa %@” or a colon (“Lisätty: %@”) instead of “%@:ssa”.
Permission reasons (Permissions pane, onboarding step 5, Settings ▸ Calendar) describe what the access does, in the
3rd person without a subject: “Näyttää tapahtumasi lovessa.”, “Korvaa järjestelmän … ilmaisimen.”, “Lukee, mitä
toistetaan, …” — never an imperative addressed to the user (“Lue …”). Progress “X of Y” is “%1$lld / %2$lld”
(Apple’s VoiceOver “Sivu %@ / %@”; “2/5” is read as a fraction). Clock times take “klo” in sentences
(“päättyy klo 14.35”). “You can’t undo this.” = AppKit’s “Toimintoa ei voida perua.”

“Cranny” is never translated. Inflected only in harmony-neutral cases where unavoidable:
Crannyn (gen.), Crannyyn (ill.), Crannylle (all.); other cases are avoided by rephrasing
(reviewed: keep avoiding the harmony-dependent cases — Finns read the name both as “kranni” and “kräni”, so
*Crannyssa / Crannyssä* would look wrong to half of them; Crannyn / Crannyyn / Crannylle are enough).

| English (Cranny concept) | Finnish | Notes |
|---|---|---|
| Cranny | Cranny | also the name of the open panel (“Avaa Cranny”, “Sulje Cranny”) |
| notch | lovi (loven, loveen, lovessa, lovella) | “kameran lovi”; Apple’s Finnish word for the camera notch |
| camera housing | kameran kotelo | Notch fit footnotes |
| open panel | paneeli | |
| Home (built-in page, tab) | Etusivu | never “Koti” (Apple’s Home app) |
| page (of widgets) | sivu | “Sivu %lld” |
| Layout & Widgets (pane) | Asettelu ja widgetit | |
| layout | asettelu | “Muokkaa asettelua”, presets “aloitusasettelu” |
| widget | widget (widgetin, widgetiä, widgetit) | as Apple: “Näytä widgetit työpöydällä” |
| widget library | widgetkirjasto | |
| cell (grid) | solu | “%lld solua vapaana” (N cells left, one wording in NotchUI and Settings) |
| Tray | Hylly | hyllylle / hyllyllä / hyllyltä: “Pidä hyllyllä”, “Poista hyllyltä”, “Tyhjennä hylly” |
| item (Tray) | kohde | as Finder: “3 kohdetta” |
| pipeline | työnkulku | as Automator; “Omat työnkulut”, “Kiinnitetyt työnkulut” |
| step (pipeline) | vaihe | |
| drop zone | pudotusalue | |
| drop (files) / drag | pudota / vedä | “Pudota tiedostoja loveen”, “Vedä apit tähän” |
| Live Activities (pane, feature) | Liveseuranta | Apple’s Finnish name (Control Center settings) |
| live activity (one) | liveseuranta (pl. liveseurannat) | Apple: “Live Activity” = “Liveseuranta”; countable as in macOS’s own “Lopeta liveseuranta” |
| Pause / Resume Live Activities | Keskeytä liveseuranta / Jatka liveseurantaa | wing words: Tauolla / Jatkuu |
| peek | kurkistus | never “Pikakatsele” (= Quick Look) |
| Quick peek on hover | Pikakurkistus osoittamalla | hover = osoittaa |
| satellite | satelliitti | |
| compact (activity beside the notch) | (not named; “lovessa”, “loven vieressä”) | |
| Fold away after | Palauta loveen, kun toimettomana | Apple’s “…, kun toimettomana” pattern |
| Close after inactivity | Sulje, kun toimettomana | |
| Never (timeout 0) | Ei koskaan | |
| HUD | ilmaisin | Settings pane “Ilmaisin”; “järjestelmän ilmaisin” = the macOS HUD |
| Volume / Brightness / Keyboard brightness | Äänenvoimakkuus / Kirkkaus / Näppäimistön kirkkaus | |
| keyboard backlight | näppäimistön taustavalo | |
| Mute / Unmute / Muted | Mykistä / Poista mykistys / Mykistetty | |
| Media | Media | |
| player (media app) | soitin | |
| track / song | kappale | |
| artwork | kuvitus | as the Music app |
| visualizer | visualisoija | Off / Ambient / Live / Static = Pois / Tunnelma / Reaaliaika / Staattinen |
| media helper | media-apuohjelma | |
| Apple Events fallback | Apple Events -varakeino | |
| Now Playing | Toistossa nyt | Apple’s name |
| Calendar · Mirror · Notes · To-dos · Timer · Files | Kalenteri · Peili · Muistiinpanot · Tehtävät · Ajastin · Tiedostot | |
| note / to-do | muistiinpano / tehtävä | |
| meeting | kokous | |
| Join (meeting) | Liity | also the short capsule; VoiceOver “Liity kokoukseen” |
| Meeting soon / Meeting in progress | Kokous pian / Kokous käynnissä | |
| Quick Apps | Pika-apit | “Lisää pika-appeihin”, “Poista pika-apeista” |
| tile (Quick Apps) | ruutu | |
| app | appi (apit, apissa) | Apple’s Finnish |
| Shortcuts (Apple’s app) / a shortcut | Pikakomennot / pikakomento | “Pikakomennot-appi” |
| keyboard shortcut | (näppäin)oikotie | Apple’s “Näppäinoikotiet…” |
| Command palette | Komentopaletti | |
| Pin / Keep Cranny open / Unpin | Kiinnitä / Pidä Cranny auki / Irrota | Apple: Pin = Kiinnitä, Unpin = Irrota |
| pin button | nastapainike | |
| Demo mode | Esittelytila | |
| Settings (Cranny’s) | Asetukset | “Asetukset ▸ Luvat” |
| System Settings | Järjestelmäasetukset | |
| Permissions (pane) | Luvat | |
| Granted / Denied / Not yet / Restricted / Unknown | Sallittu / Estetty / Ei vielä / Rajoitettu / Tuntematon | |
| Allow… / Grant… | Salli… | |
| Reset to Default | Palauta oletusarvo | Apple’s “Palauta oletuksiin” |
| Reset All Settings… / Reset %@… / Reset | Palauta kaikki asetukset… / Palauta osion %@ oletukset… / Palauta | titles and banners say “oletuksiin” (“Palautetaanko kaikki asetukset oletuksiin?”); “palautettiin” alone reads as restored from a backup |
| Changed from the default | Muutettu oletusarvosta | |
| Remove (from a list) / Delete | Poista / Poista | “Poista luettelosta” when it could read as uninstalling |
| Undo / Cancel | Peru / Kumoa | Apple’s Finnish |
| Dismiss | Kätke | Apple: Hide = Kätke; banner close = Sulje |
| Done (flash, editor) | Valmis | |
| Copied (flash) | Kopioitu | |
| Failed (flash) | Virhe | |
| click / hover / pointer | klikkaa, klikkaus / osoittaa (pidä osoitinta päällä) / osoitin | Apple’s Finnish uses “klikkaa”; hover = osoittaa (“point to”), never “osoittimella”, which also covers clicking |
| Hover / Click / Shortcut only (Open Cranny with) | Osoittamalla / Klikkaamalla / Vain oikotiellä | onboarding cards: Osoittaminen / Klikkaus / Vain oikotie; Hidden until hover = Esiin osoittamalla |
| swipe / gesture | pyyhkäise / ele | |
| trackpad | ohjauslevy | |
| tutorial | opastus | English never says “tour” |
| setup (welcome) | käyttöönotto | |
| Show on (displays) | Missä näytetään | values: Sisäisellä näytöllä / Kaikilla näytöillä / Osoittimen näytöllä / Valituilla näytöillä |
| display | näyttö | |
| Floating island / Attached / Glass island | Kelluva saari / Reunassa / Lasisaari | |
| handle (no-notch displays) | kahva | |
| Ambient light / Underglow / Album glow / Progress rim | Tunnelmavalo / Alahehku / Albumin hehku / Edistymisreuna | |
| Effect: Aurora / Motes / Tide | Tehoste: Revontulet / Hiukkaset / Vuorovesi | |
| Motion: Calm / Standard / Lively / Instant | Liike: Rauhallinen / Normaali / Eloisa / Heti | |
| Density: Compact / Standard / Roomy | Tiheys: Tiivis / Normaali / Väljä | |
| Typing effect | Kirjoitustehoste | |
| Type to capture | Kirjoita suoraan | |
| Alerts / Ongoing / Passive (priority classes) | Hälytykset / Jatkuvat / Taustalla | |
| Confirmations | Vahvistukset | |
| Excluded apps | Poissuljetut apit | |
| Launch / Open at login | Avaa sisäänkirjauduttaessa | as the Dock’s “Open at Login” |
| Login Items (System Settings) | Kirjautumiskohteet | apple-terms |
| Applications folder | Apit-kansio | macOS 27 folder name |
| Downloads | Lataukset | |
| Low Power Mode | Alhaisen virran tila | apple-terms |
| Accessibility (permission, pane) | Käyttöapu | apple-terms |
| Privacy & Security | Tietosuoja ja suojaus | apple-terms |
| Reduce Motion / Reduce Transparency / Differentiate without color | ”Vähennä liikettä” / ”Vähennä läpinäkyvyyttä” / ”Erottele ilman väriä” | quoted, never paraphrased |
| Quick Look | Pikakatsele | apple-terms |
| Share… | Jaa… | Finder |
| Show / Reveal in Finder | Näytä Finderissa | Finder |
| Option / Command / Space (key names) | Optio / Komento / Väli | AppKit key names |
| macOS shortcut names (collisions) | Appi-ikkunat · Finder-hakuikkuna · Ohje-valikko · Siirry tilasta toiseen · Näyttökuvat | System Settings ▸ Keyboard Shortcuts; Spaces = tilat (“Siirry edelliseen tilaan”), not työpöydät |
| Timer alert sounds | Boop, Breeze, Bubble, Crystal… | macOS 27 keeps the English names in Finnish |
| Music (Apple’s app) | Musiikki | not quoted (Finnish macOS avoids quoting names) |
