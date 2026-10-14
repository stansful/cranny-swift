# Cranny – German terminology (de)

Register: informal **du**, lowercase in running text ("dein", "deine Kamera"), as macOS since 2020.
Buttons, menu items, commands and toggles: **infinitive at the end** ("Cranny beenden", "Nach Updates suchen …",
"Symbol in der Menüleiste anzeigen"). Instructions and footnotes: **du-imperative** ("Klicke auf die Notch").
Typography: „…“ (secondary ‚…‘), apostrophe ’, ellipsis … preceded by a **no-break space** in menu items, buttons and
progress text ("Einstellungen …", "Laden …") as AppKit/Finder write it; en dash with spaces " – " for a parenthetical
dash (English "—"); "&" only where Apple uses it (pane names). Nouns capitalized; compounds with names take a hyphen
("Cranny-Einstellungen", "Bluetooth-Gerät", "Live-Aktivitäten").

## Apple names (from apple-terms.py, `apple-terms.py de` – never paraphrased)

| English | German |
|---|---|
| System Settings | Systemeinstellungen |
| Privacy & Security | Datenschutz & Sicherheit |
| Accessibility (privacy service / pane) | Bedienungshilfen |
| Automation | Automation |
| Calendars (privacy) | Kalender |
| Camera / Microphone / Bluetooth | Kamera / Mikrofon / Bluetooth |
| System Audio Recording | Aufnahme von Systemaudio (SecurityPrivacy AUDIO_CAPTURE) |
| Login Items | Anmeldeobjekte |
| Battery / Low Power Mode | Batterie / Stromsparmodus |
| Live Activities (Apple) | Live-Aktivitäten |
| Now Playing | Jetzt läuft |
| Reduce motion / Reduce transparency / Differentiate without color | „Bewegung reduzieren“ / „Transparenz reduzieren“ / „Ohne Farben differenzieren“ |
| Quick Look | Schnellansicht |
| Music · Calendar · Shortcuts (apps) | „Musik“ · Kalender · „Kurzbefehle“ (quoted where the bare word would read as a common noun) |
| Applications folder · Downloads | „Programme“ · „Downloads“ |
| Show in Finder / Reveal in Finder | Im Finder anzeigen (Dock) |
| Open at Login | Bei der Anmeldung öffnen (Dock) |
| Settings… | Einstellungen … (AppKit) |
| Cancel · Delete · Undo · Done | Abbrechen · Löschen · Widerrufen · Fertig |
| Allow / Don’t Allow | Erlauben / Nicht erlauben |
| swipe (gesture) | streichen (Trackpad: „Mit Streichen …“) |
| haptic feedback · Force Touch | haptisches Feedback · Force Touch-Trackpad |
| pointer | Zeiger |
| accent colours | Blau, Lila, Rosa, Rot, Orange, Gelb, Grün, Graphit (AccentColorNames) |
| Timer alert sounds | Buup, Brise, Blase, Kristall, Funky, Heldin, Springen, Mezzo, Kiesel, Zupfen, Pong, Sonar, Sonumi, Untertauchen |
| Option key | **Option-Taste** (⌥) – macOS 27 (AppKit FunctionKeyNames, Keyboard settings, VoiceOver ModKey.option). „Wahltaste“ is the old name: don’t use it (review) |
| keys as VoiceOver speaks them | Command-Taste · Control-Taste · Umschalttaste · Zeilenschalter (Return) · Rückschritttaste (Delete) · Leertaste · Aufwärtspfeil / Abwärtspfeil (SCROutputSpeechComponent). In a hint, write „Option-Taste 1“ with a space, never „…-1“ (read as “minus”) |
| Save (files, notes, settings) | Sichern / gesichert / „Sichern fehlgeschlagen“ (AppKit Document.loctable still says „Sichern …“, „Nicht sichern“); „speichern“ only in the privacy sentences about audio and video |
| Shuffle · Repeat · Repeat all · Repeat one | Zufällige Wiedergabe · Wiederholen · Alle wiederholen · Einen Titel wiederholen (Music.app) |
| Play · Pause · Nothing playing | Wiedergeben (Cranny’s verb style; Control Center: „Wiedergabe“) · Pause · Keine Wiedergabe (Music.app) |
| Charging · Fully charged · Low battery | Lädt · Vollständig geladen · Batterie fast leer (Battery/BatteryUI loctables) |
| On battery · power adapter | Im Batteriebetrieb · Am Netzteil / Netzteil angeschlossen |
| Game controller | Spielecontroller (System Settings pane) |
| AirPods charging case | Case (battery gauge label; „Ladecase“ in Apple’s prose) |

## Cranny's own concepts

| English | German | Note |
|---|---|---|
| Cranny | Cranny | never translated; neuter when a pronoun is unavoidable ("es"); also the open panel ("Cranny öffnen") |
| notch | Notch (die) | "auf die Notch", "in der Notch"; German press and users say Notch |
| panel (the open Cranny) | Panel (das) | "Panelabstand" |
| Home (built-in page) | Startseite | tab, Settings, tutorial |
| page | Seite | "Seite 2", "Alle Seiten" |
| Layout & Widgets (pane) | Layout & Widgets | |
| layout | Layout (das) | "Layout bearbeiten", "Start-Layout" |
| widget · widget library | Widget (das) · Widget-Galerie | Apple's name for the widget picker |
| cell (grid) | Zelle | "3 Zellen", "Noch 2 Zellen frei" |
| Tray | Ablage | "In der Ablage behalten", "Aus der Ablage entfernen", "Ablage leeren" |
| item (in the Tray) | Objekt | as Finder |
| drop / drag | ablegen / ziehen | "Dateien hier ablegen"; never "fallen lassen" |
| pipeline | Ablauf (pl. Abläufe) | "Neuer Ablauf …", "Angepinnte Abläufe" |
| step (pipeline) | Schritt | |
| drop zone | Ablagezone | |
| live activity / Live Activities | Live-Aktivität / Live-Aktivitäten | "Aktivität" alone where the context is clear |
| Pause / Resume Live Activities | Live-Aktivitäten pausieren / fortsetzen | wing words: Pausiert / Aktiv (measured) |
| peek | Kurzansicht | not "Schnellansicht" (= Quick Look), not "Vorschau" (= Preview) |
| compact (activity in the wings) | kompakt | |
| wings | Seiten der Notch | rarely named |
| satellite | Satellit | |
| HUD (volume/brightness overlay) | Overlay (das) | pane, column, toggles; search terms keep HUD, OSD |
| Confirmations | Bestätigungen | |
| Alerts · Ongoing · Passive (priority classes) | Hinweise · Laufend · Passiv | |
| Mirror | Spiegel | |
| Notes · note | Notizen · Notiz | |
| To-dos · to-do | Aufgaben · Aufgabe | |
| Timer · preset | Timer · Vorgabe | |
| Calendar | Kalender | |
| Media · player · track · artwork | Medien · Player · Titel · Cover | |
| media helper | Medien-Hilfsprogramm | "MediaRemote-Hilfsprogramm (perl)" |
| Apple Events fallback | Ausweichlösung über Apple Events | |
| visualizer · Live · Ambient · Static | Visualizer · Live · Sanft · Statisch | |
| Quick Apps | Schnellstart (der) | "Zum Schnellstart hinzufügen" |
| tile | Kachel | |
| Shortcuts (Apple's app) · a shortcut in it | Kurzbefehle · Kurzbefehl | Settings pane "Kurzbefehle" |
| keyboard shortcut | Tastenkombination | never "Kurzbefehl" (= Shortcuts app) |
| Settings (Cranny's) | Einstellungen | "Einstellungen ▸ Tastatur" |
| Keep Cranny open / pin | Cranny geöffnet lassen / anpinnen | unpin = lösen (Notes: „Notiz lösen“) |
| Demo mode | Demomodus | |
| Join (meeting) | Beitreten / „Meeting beitreten“ (VoiceOver, tooltip) | capsule short form: Rein (measured; colloquial “come on in”, sits next to the join glyph; „Los“ is the fallback if it reads too casual) |
| Try again / Retry | Wiederholen (Mirror chip, Calendar, Notes, To-dos – the standard German retry button) · Erneut versuchen (Media, whose Repeat is already „Wiederholen“; Quick Apps picker) | |
| Swipe … to … (gesture toggles) | „Zum Öffnen nach unten, zum Schließen nach oben streichen“, „Zum Titelwechsel seitwärts streichen“, „Zum Ausblenden nach oben streichen“ | purpose first, verb last – same as the onboarding tasks |
| Reset to Default | Auf Standard zurücksetzen | |
| Changed from the default | Vom Standard abweichend | |
| Granted · Denied · Not yet · Restricted · Unknown | Erlaubt · Verweigert · Noch nicht · Eingeschränkt · Unbekannt | |
| Allow… / Grant… | Erlauben … | |
| Preview | Vorschau | |
| click | klicken | |
| hover / rest the pointer | Darüberfahren / den Zeiger ruhen lassen | "Öffnungsverzögerung" for Hover delay |
| tutorial | Einführung | never "Tour" |
| Welcome / setup | Willkommen / Einrichtung | |
| Show on · Display with the pointer | Anzeigen auf · Display mit dem Zeiger | |
| Never (timeout 0) · Off | Nie · Aus | |
| Fold away after | Einklappen nach | |
| Open Cranny with | Cranny öffnen durch | Darüberfahren / Klicken / Nur Tastenkombination |
| Open %@ | „%@“ öffnen | |
| Style · Mono · Semantic (Overlay colours) | Stil · Weiß · Nach Typ | |
| Show … (toggles, buttons, actions) | … anzeigen | never bare „zeigen“ („Auf der Notch anzeigen“, „Tastenkombinationen anzeigen“) |
| Typing effect | Tippeffekt | |
| Instant | Sofort | |
| Remove (from a list) · Delete | Entfernen · Löschen | |
| App not installed | App nicht installiert | |
| Symbol | Symbol | |
| Command palette | Befehlspalette | |
| Excluded apps | Ausgeschlossene Apps | |
| Type to capture | Tippen zum Erfassen | |
| Ambient light · Subtle · Vivid | Umgebungslicht · Dezent · Kräftig | |
| Effect: Aurora · Motes · Tide | Polarlicht · Funken · Gezeiten | |
| floating island · attached · handle | schwebende Insel · angedockt · Griff | |
| Notch fit | Notch-Anpassung | |
| Copied · Done · Failed · Hi (flash words) | Kopiert · Fertig · Fehler · Hallo | measured against the wings |

## Review notes (independent review, 2026-10-14)

Kept after review: Overlay (HUD), Kurzansicht (peek), Ablage (Tray – Cranny shows no File menu, and „Ablage“ is the
usual German word for an in-tray), Startseite (Home), Schnellstart (Quick Apps), Abläufe (pipelines),
Tastenkombination vs. Kurzbefehl, „Sichern“ for files/notes/settings, the wing words Pausiert / Aktiv / Kopiert, the
band countdown without preposition („4 Min.“). Changed: Option-Taste and the VoiceOver key names, battery and Music
terms from macOS, gesture-toggle word order, „anzeigen“ everywhere.
