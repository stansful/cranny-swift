# Cranny — Hebrew (he) terminology sheet

Direction: right to left. No bidi control characters are added (not even the U+200F that some of Apple's
loctable values start with). Quotes: gershayim ״…״ (U+05F4) around names; geresh ׳ (U+05F3) in abbreviations
and loanwords (וידג׳ט, דק׳). Prefix letters attach directly to a quoted name, as macOS does («ב״נגישות״»,
«ו״כיבוי״»), and with a hyphen to Latin words and placeholders («ב-Cranny», «ל-%@», «וה-Dock»).
Ellipsis is one character (…). Apple spelling where Apple has one: «גירסה», «תיקיה».

**First word (review rule).** SwiftUI and AppKit take a paragraph's direction from its first strong letter (Unicode
P2/P3; checked with CoreText and a SwiftUI render on macOS 27). A string that starts with a Latin word (Cranny,
macOS, GitHub, Liquid Glass) or with a key combination (⌃⌥N) is laid out left to right: the Latin word lands on
the left and the final period or colon on the right, so a Hebrew reader meets the period first. Never start a
string that contains Hebrew with a Latin word, a key combination or a placeholder that may hold Latin text
(shortcut names, keys): move a Hebrew word to the front («כעת Cranny מטפל במקשים.», «הקיצור %1$@ מוגדר גם עבור
״%2$@״.», «בצג הזה Cranny כבוי.»). This includes the permission prompts in InfoPlist. Strings that are only a
name (Cranny, AirDrop) and VoiceOver-only labels are exempt. Parentheses around Latin text are fine (bracket
pairs resolve correctly).

**Paths.** Apple's Hebrew writes Settings paths with ">" (mirrored, so it points along the reading direction)
between quoted names: «ב״פרטיות ואבטחה״ > ״נגישות״», «ב״הגדרות״ > ״מקלדת״». Never "▸": it does not mirror and
points backwards in right-to-left text.

**System Settings** is quoted as an app name in running text and in buttons, as Apple does: «ב״הגדרות המערכת״»,
«פתיחת ״הגדרות המערכת״». Only the bare menu-style item «הגדרות המערכת…» stays unquoted.

## Register

| Surface | Form | Example |
|---|---|---|
| Buttons, menu items, ⌘K commands, toggles, picker labels | verbal noun (שם פעולה), as macOS («פתיחה בכל זאת», «העברה לפח», «הפחתת תזוזות») | «פתיחת Cranny», «הצגת הערך» |
| Settings footnotes, errors, empty states, tooltips | impersonal «יש ל…» / «ניתן ל…» + infinitive | «יש לנסות שוב מאוחר יותר.» |
| Welcome window and tutorial bubbles (direct, friendly coaching) | plural imperative (gender-neutral) | «לחצו על המגרעת», «גררו קובץ כלשהו אל המגרעת» |
| Questions in confirmations | infinitive question, as macOS | «לאפס את כל ההגדרות?» |
| Status words | masculine singular impersonal past/participle | «אושר», «נדחה», «מושהה» |

Grammatical gender: Cranny = masculine («Cranny פתוח», «Cranny מציג»); macOS = feminine, and as a subject it is
written «מערכת macOS» + feminine verb, as Apple does («מערכת macOS מבקשת…»; «מערכת macOS לא הוסיפה…»);
notch (מגרעת) = feminine; Tray (מדף) = masculine; widget (וידג׳ט) = masculine; activity (פעילות) = feminine.

## Cranny's own concepts

| English | Hebrew | Notes |
|---|---|---|
| Cranny | Cranny | never translated or transliterated; «ב-Cranny», «ל-Cranny», «כש-Cranny» |
| notch | מגרעת | «על המגרעת», «במגרעת», «אל המגרעת» |
| panel (the open Cranny) | חלונית | «החלונית הפתוחה»; Settings ▸ Appearance ▸ Panel = «חלונית». Reserved for the panel: a Settings pane is named («בהגדרות ״כללי״») or «כאן» |
| Home (the built-in page) | ראשי | tab and page name; in running text «העמוד ״ראשי״» |
| page | עמוד / עמודים | «עמוד %lld», «הוספת עמוד» |
| Layout & Widgets (pane) | פריסה ווידג׳טים | |
| layout | פריסה | «עריכת הפריסה»; never «פריסה» for unzip |
| widget | וידג׳ט / וידג׳טים | Apple's spelling |
| cell (grid) | תא / תאים | one «תא אחד» |
| Widget library | ספריית וידג׳טים | |
| Tray | מדף | «על המדף», «מהמדף», «ניקוי המדף», «שמירה על המדף» |
| item (Tray) | פריט / פריטים | one «פריט אחד» |
| pipeline | תהליך / תהליכים | «תהליך חדש…», «תהליכים מוצמדים» |
| step (pipeline) | שלב / שלבים | |
| drop zone | אזור גרירה | |
| drop / drag (files) | גרירה / לגרור | «יש לגרור לכאן קבצים» |
| Live Activities (pane, menu, proper name) | פעילויות בזמן אמת | Apple's own Hebrew term |
| live activity / activity | פעילות / פעילויות | column header «פעילויות» |
| peek | הצצה / הצצות | Quick Look stays Apple's «הצצה מהירה»; «Quick peek on hover» = «הצצה בריחוף» (no «מהירה») |
| satellite | לוויין | |
| compact (state) | מצומצם | not used as free text; density option «צפופה» |
| HUD | מחוון | «מחוון עוצמת הקול», «המחוון של המערכת» |
| Paused / Resumed (wing words) | הושהו / חודשו | past plural, agree with «הפעילויות»; both fit the 48-pt medium slot (36 pt). Status lines keep «מושהות» |
| Copied (wing word) | הועתק | as iOS shows it |
| Done (Quick Apps wing) · Failed | בוצע · נכשל | |
| Demo mode | מצב הדגמה | |
| Keep Cranny open | השארת Cranny פתוח | |
| pin / unpin / pinned | הצמדה / ביטול הצמדה / מוצמד | Apple Notes wording |
| Settings | הגדרות | Cranny's Settings window |
| tutorial | הדרכה | search word «סיור» for "tour" |
| Welcome (window) | מסך הפתיחה | |
| Quick Apps | יישומים מהירים | |
| tile (Quick Apps) | אריח / אריחים | |
| shortcut (Shortcuts app item) | קיצור / קיצורים | |
| keyboard shortcut | קיצור מקלדת / קיצורי מקלדת | always with «מקלדת» to tell it apart from a Shortcuts item |
| Mirror (widget) | ראי | NOT «מראה»: that spelling is also Apple's «Appearance» |
| Notes · To-dos · Timer · Calendar · Media | פתקים · משימות · טיימר · לוח שנה · מדיה | Apple's «פתקים», «לוח שנה»; to-do = «משימה» |
| Join (meeting) | הצטרפות | «הצטרפות לפגישה» |
| Join (short capsule) | כניסה | only the capsule |
| meeting | פגישה | «פגישה בקרוב», «פגישה מתקיימת» |
| event | אירוע | |
| player (media app) | נגן | |
| media helper | רכיב העזר למדיה | |
| Apple Events fallback | חלופת Apple Events | |
| visualizer · Live · Ambient · Static | ויזואלייזר · חי · רגוע · סטטי | «ויזואלייזר» is Apple Music's word |
| artwork | עטיפה | Apple Music |
| Now Playing | מופעל כעת | Apple's term |
| Reset to Default | חזרה לברירת המחדל | |
| Changed from the default | שונה מברירת המחדל | |
| Granted · Denied · Not yet · Restricted · Unknown | אושר · נדחה · עדיין לא · מוגבל · לא ידוע | permission pills |
| Allow… / Grant… | אישור… | Apple's Allow = «אישור» |
| Never (timeout 0) | אף פעם | Apple |
| Off | כבוי (masc.) / כבויה (camera) | Apple; as the value of a feminine picker («אזהרה ראשונה») use «ללא» |
| Move up / down | הזזה למעלה / למטה | Apple |
| Move left / right, earlier / later | הזזה למקום הקודם / הבא | direction-neutral on purpose: the grid is an HStack and mirrors in RTL |
| Undo | ביטול | |
| Try again | ניסיון נוסף | Apple |
| Open %@ | פתיחת ״%@״ | |
| Open in %@ | פתיחה ב״%@״ | |
| Remove (from a list) | הסרה | |
| Show … (toggles) | הצגת … | «הצגת הערך» |
| Show on (displays) | היכן להציג | values «בצג המובנה», «בצג עם המצביע», «בכל הצגים», «בצגים שנבחרו» |
| Open Cranny with | פתיחת Cranny | values «בריחוף», «בלחיצה», «בקיצור מקלדת בלבד» |
| Hover · Click | ריחוף · לחיצה | |
| Fold away after / Close after inactivity | קיפול בהיעדר פעילות / סגירה בהיעדר פעילות | |
| floating island · attached | אי צף · צמוד | |
| handle | ידית | |
| Ambient light | אור סביבה | values כבוי · עדין · עז |
| Accent | צבע הדגשה | Apple's "Accent color" |
| Motion · Density | תנועה · צפיפות | values agree (fem.): רגועה · רגילה · תוססת · מיידית; צפופה · רגילה · מרווחת |
| Text size | גודל המלל | Apple; values קטן · בינוני · גדול · גדול מאוד |
| Presets (Timer) | זמנים מוגדרים מראש | «זמן מוגדר %lld» |
| hr · min · sec (≤ 4 letters) | שע׳ · דק׳ · שנ׳ | |

## Apple's names (from `apple-terms.py he` and Apple's own Hebrew strings on this Mac)

| English | Hebrew |
|---|---|
| System Settings | הגדרות המערכת (quoted ״הגדרות המערכת״ in running text and in «פתיחת ״הגדרות המערכת״») |
| Privacy & Security ▸ Accessibility | פרטיות ואבטחה ▸ נגישות |
| Automation | פעולות אוטומטיות |
| Calendars · Camera · Bluetooth | לוחות שנה · מצלמה · Bluetooth |
| System Audio Recording | הקלטת שמע המערכת |
| Login Items | פריטי התחברות |
| Open at Login / Launch at login | פתיחה בעת ההתחברות |
| Applications · Downloads · Desktop | יישומים · הורדות · מכתבה |
| menu bar | שורת התפריטים |
| display / displays · built-in display | צג / צגים · צג מובנה |
| pointer · trackpad | מצביע · משטח מגע |
| Low Power Mode | מצב חיסכון באנרגיה |
| Reduce motion · Reduce transparency · Differentiate without color | הפחתת תזוזות · הפחתת השקיפות · הבחנה ללא צבע |
| Music · Shortcuts · Calendar (apps) | ״מוזיקה״ · ״קיצורים״ · ״לוח שנה״ (quoted as app names) |
| Quick Look | הצצה מהירה |
| Finder · Dock · Spotlight · Mission Control · AirDrop · FaceTime | kept in Latin |
| Alert sounds | בופ, בריזה, בועה, קריסטל, צלילי פאנק, גיבורים, דילוג, מזו, חלוק נחל, פריטה, פונג, סונאר, סוסומי, צוללת (exactly as System Settings ▸ Sound) |
| About (pane) / About Cranny | מידע / מידע על Cranny |
| Quit | סיום |
| Done · Cancel · Continue · Skip · Back | סיום · ביטול · המשך · דילוג · הקודם |
| Version | גירסה |

## RTL and fit notes (measured on this Mac, SF at the band sizes)

- Wing words: «הושהו» 36 pt at 1u (review: replaces «מושהות», 47 pt, which needed the wide slot); «חודשו» 36,
  «הועתק» 40, «בוצע» 29, «נכשל» 32, «שלום» 32 (all fit the 48-pt medium slot).
- Calendar band: "in %@" drops «בעוד» as Russian drops «через» («4 דק׳» 31 pt); «−12 דק׳» is 51 pt at 13 pt and
  44 pt at the allowed 0.85 shrink — the same situation as Russian «−59 мин».
- Join capsule «כניסה» 30 pt at 11-pt semibold (Russian «Войти» 35 pt). Tabs «ראשי» / «מדף» are shorter than English.
- Arrows in running text follow reading order: «שינוי גודל ← המרה ל-JPEG ← העתקת נתיבים».
- Move left/right are written as «הזזה למקום הקודם / הבא» because the editors are HStacks that mirror under RTL.
  The resize handle sits on the trailing edge, which is the left edge in Hebrew, so "drag the right edge" is
  «לגרור את הידית שבקצה הכרטיס» (names the handle, not a side).
- Key combinations in running text show mirrored in visual order (⌃⌥N reads right to left as ⌃, ⌥, N); that is
  expected. Ranges with an en dash («2–4 תאים») read correctly right to left (checked with CoreText).
- "25 or 90s" keeps the Latin «s» («25 או 90s»): DurationParser accepts only English and Russian units.
- Other fixed choices: Type to capture = «יעד ההקלדה»; Progress rim = «קו התקדמות»; Feel It = «בדיקת רטט»;
  Hold ⌥ to pass over = «ללא פתיחה בהחזקת ⌥»; Listener / Maker / Meetings / Minimal presets = «האזנה / יצירה /
  פגישות / מינימלי» (activities, so no gendered person nouns).
