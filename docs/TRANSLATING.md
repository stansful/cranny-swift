# Translating Cranny

Cranny ships in 35 languages: English, the source, and every UI language macOS 27 ships (the list is in
`scripts/l10n/languages.json` and in the README). **The translations were produced and cross-reviewed by AI.**
Each language was translated, then checked by a second, independent review pass against Apple's own wording in that
language, and every string passes the automated checks below (placeholders, plural forms, quotation marks, measured
widths). What they have not had is a native speaker's review. If something in your language is wrong, stiff, too
long or not what macOS says, a correction is very welcome: an issue that quotes the text is enough, a pull request is
better.

This guide covers fixing or reviewing a language, adding strings in code (the policy that keeps CI green), and
adding a language. The file format and the checks in detail: [`scripts/l10n/README.md`](../scripts/l10n/README.md).
Strategy and rules for code: [ARCHITECTURE.md §8.7](ARCHITECTURE.md).

## Where things are

| What | Where |
|---|---|
| Strings, one String Catalog per module | `Packages/CrannyKit/Sources/<Target>/Resources/Localizable.xcstrings` |
| Permission prompts (Info.plist usage strings) | `App/InfoPlist.xcstrings` |
| Languages: codes, plural categories, quotation marks, register notes, `shipped` | `scripts/l10n/languages.json` |
| Terminology sheet per language: Cranny's names, Apple's names, register, typography, decisions | [`docs/l10n/terms/<code>.md`](l10n/terms/) |
| Russian glossary (the reference translation) | [ARCHITECTURE.md §8.7](ARCHITECTURE.md), rule 7 |
| Tools: export, validate, import, pending, Apple's terms | `scripts/l10n/` (Python 3 from macOS, no Xcode needed) |

Keys are the English text itself. Every key has a comment `"<surface>: <purpose>"` that says where the text appears
and what it does; read it before translating.

## Improving a language

The tools work on one JSON file per language, so you never edit the catalogs by hand. Run them from the repository
root (`-I` keeps Python from importing anything from the current directory):

```sh
python3 -I scripts/l10n/export.py de -o de.json              # every string, with English, comment, Russian, current German
python3 -I scripts/l10n/apple-terms.py de -o de-terms.json   # Apple's own German names, read from this Mac
# edit the "translation" fields in de.json (only those)
python3 -I scripts/l10n/validate.py de de.json --glossary de-terms.json   # errors stop here; read the warnings too
python3 -I scripts/l10n/import.py de de.json                 # writes the catalogs (validates first)
make strings-check                                           # catalogs in sync, copy rules, every shipped language valid
make test                                                    # includes the measured-width tests (below)
```

`export.py de --missing-only` exports only what German lacks or has pending. Small fixes can also be made in
Xcode's String Catalog editor; then run `python3 -I scripts/l10n/validate.py de --catalogs` and `make strings-check`.
When you change a term, change every string that uses it (search the export for the old word) and update the
language's sheet in `docs/l10n/terms/`, so the next translator keeps it.

What to look at when you review a language:

- **The terminology sheet first.** Cranny's own names (Home, Tray, Quick Apps, Live Activities, Layout & Widgets,
  peek, pipeline…) have one fixed translation each; the sheet lists them with the reasons. Disagree with one? Change
  it everywhere at once.
- **Apple's words.** People look for System Settings panes, privacy services, accessibility settings, apps, Finder
  places and alert sounds by the name macOS shows them. `apple-terms.py <lang>` reads those names from this Mac
  (`--details` shows where each comes from); `validate.py --glossary` warns when an Apple term stayed English.
- **Register and tone** as macOS uses them in your language (du/Sie, tu/vous, siz…; the `notes` in
  `languages.json` and the sheet say which). Buttons and menu items follow macOS's form (infinitive, imperative or
  noun, whatever your language's macOS does).
- **Fit.** Text in the notch has very little room. Look at the app (below), not only at the file.

To see the app in a language, build Debug and launch it with the language, an isolated home and a settings suite of
its own (docs/CONTRIBUTING.md ▸ Visual QA hooks):

```sh
QA=(--qa-defaults-suite app.cranny.Cranny.qa)
scripts/run.sh -- "${QA[@]}" -AppleLanguages "(de)" -AppleLocale de_DE --qa-state open --qa-page nook \
  --qa-media playing --qa-calendar sample --qa-snapshot /tmp/home-de.png --qa-exit-after 6
scripts/run.sh -- "${QA[@]}" -AppleLanguages "(ar)" -AppleTextDirection YES -AppleLocale ar_SA --qa-state open \
  --qa-page nook --qa-snapshot /tmp/home-ar.png --qa-exit-after 6     # Arabic and Hebrew need -AppleTextDirection YES
defaults delete app.cranny.Cranny.qa
```

## The rules

These hold in every language. `validate.py` checks the mechanical ones; the rest need a reader.

- **Cranny** is a name: never translated or transliterated, always with its capital C. Attach grammar around it the
  way your language does with foreign names (Turkish “Cranny’yi”, Finnish “Crannyn”).
- **Never write “Nook”** — nor NotchNook, Notch Nook, Alcove, Atoll or boring.notch — not even as the translation
  of an English word, and never look at other notch apps' translations. Cranny is a clean-room project
  (ARCHITECTURE.md D20); `validate.py` and `scripts/lint-copy.py` reject these names in every language. The built-in
  page is “Home”.
- **Placeholders** stay: every `%@`, `%lld`, `%#@name@` of the English, with the same types. Reorder with positions
  (`%2$@ … %1$lld`), and never mix positional and plain specifiers in one string. Numbers, dates, times and durations
  arrive already formatted for the user's region: never write digits or units into a translation.
- **Plurals.** Every count has plural variations, also where English writes both forms alike (“+%lld more”).
  Answer with exactly your language's CLDR categories (`languageInfo.pluralCategories` in the export: German one,
  other; Russian one, few, many, other; Arabic zero, one, two, few, many, other; Japanese other). A category listed
  in `pluralExactValues` stands for one number and may leave the number out (Arabic two: “عنصران”); then every other
  placeholder in that form must be positional.
- **Quotation marks and typography** as macOS writes them in your language (`quoteStyle`: „…“ in German, « … » with
  no-break spaces in French, 「…」 in Traditional Chinese, straight quotes in Arabic). The apostrophe is ’ (in
  Ukrainian ʼ U+02BC between letters, as macOS: памʼять), the ellipsis one character …; French puts a no-break space
  before : ; ! ?. No ASCII quotes unless your macOS uses them.
- **Case.** Sentence case, except where your language capitalizes otherwise (German nouns) and where English uses
  title case for standard macOS menus and buttons — follow your macOS there.
- **Constrained strings.** Items with `"constrained": true` sit in a fixed-width place; `maxWidth.hint` says how
  much room there is: the compact wing beside the camera holds one short word (≈ 48 pt), a header tab about
  12 characters before the tabs collapse to icons, chips and picker segments one or two short words, the calendar
  row's Join capsule one short word. Prefer the shortest natural wording; let a glyph carry the meaning (“Copied”
  beside the copy glyph can be “Done”). The full wording still reaches people: tooltips, VoiceOver labels and peeks
  have their own keys and are never constrained.
- **Measured-width tests** render the constrained strings of every language in the module bundles and fail when one
  does not fit, at every notch size, density and text size: `FlashLabelFitTests` (the wing words), `BandCopyTests`
  and `FeaturedRowTests` (calendar band and row), `DayHeaderFitTests` (the calendar header line),
  `SceneAndHeaderTests.tabsAlwaysFitTheirZone` (header tabs) and the longest tutorial bubble in
  `RenderedSurfacesTests`. A failure names the language, the size and the measured widths. Shorten the
  wording; changing a layout to make room is a code change with its own review.
- **Right to left.** Arabic and Hebrew get a mirrored layout from the system; Cranny's code keeps media controls and
  clock rings left to right and isolates names and key combinations inside sentences (ARCHITECTURE.md §8.7 rule 10).
  Translate naturally; do not add direction marks yourself.

## New strings in code

A pull request that adds or changes English text (a new key; changing a key's English makes it a new key) has two
choices for each shipped language: **translate it, or mark it pending.** Either keeps CI green.

1. Write the code with `String(localized: "…", bundle: .module, comment: "<surface>: <purpose>")` or
   `Text("…", bundle: .module, comment: …)` (ARCHITECTURE.md §8.7) and run `make strings`: it adds the English keys
   to the module's catalog.
2. Either **translate**: for a language you know, `export.py <lang> --missing-only -o <lang>.json`, fill in, validate,
   import (above). Or **mark it pending**: `make l10n-pending` (`scripts/l10n/pending.py`) gives every shipped
   language that lacks the key the English text, in that language's plural shape, with state `needs_review`.
   Do both: translate what you can, then mark the rest pending.
3. `make strings-check` must pass. It fails on a key that a shipped language has **no entry** for, and accepts a
   pending key, listing the pending keys per language as a warning. Pending text shows in English in that language
   until it is translated, exactly as a missing key would.

Pending keys are translated before a release: `export.py <lang> --missing-only` lists them with `"translation":
null` (the English placeholder is not offered as a translation), and `import.py` replaces them with state
`translated`. The release workflow runs `validate.py --shipped --release`, which fails while any key is pending.
Russian follows the same rule; the Russian terminology tests skip pending keys until they are translated.

Only Cranny's own strings count: text that comes from the system (app names, display names, file names) is never in
a catalog.

## Adding a language

`languages.json` already lists every language macOS 27 offers for its UI (English variants and regional variants
that fall back on their own, such as es-419 → es, are left out). When macOS adds one:

1. Add its entry to `scripts/l10n/languages.json`: code, macOS's `.lproj` name (`appleCode`), names, `rtl`, the
   CLDR plural categories (`validate.py` warns when they differ from this Mac's ICU), `pluralExactValues`,
   `quoteStyle` as macOS writes it, register and typography `notes`, and `"shipped": false`.
2. Add the code to `CFBundleLocalizations` in `App/Info.plist` and to `knownRegions` in the Xcode project
   (`make smoke` checks the built app advertises every language of the file).
3. `export.py <code> -o <code>.json`, `apple-terms.py <code>`, translate everything, write the language's sheet in
   `docs/l10n/terms/<code>.md` (start from a related language's sheet), validate, import.
4. `make test`: the measured-width tests pick up the new `.lproj` on their own. Fix what does not fit by wording.
5. Look at the app in the language (snapshots above), then set `"shipped": true`. From then on `make strings-check`
   requires the language to be complete (or pending) for every key.

## Checks at a glance

| Command | Checks |
|---|---|
| `python3 -I scripts/l10n/validate.py <lang> <file>` | a translator file: completeness, placeholders, plural categories, quotes, “Cranny”, no competitor names, French spacing, the Ukrainian apostrophe ʼ (U+02BC) |
| `python3 -I scripts/l10n/validate.py <lang> --catalogs` | the same for what the catalogs hold now |
| `make l10n-check` (`validate.py --shipped`) | every shipped language complete and valid; pending keys are warnings |
| `validate.py --shipped --release` | the same, and no key pending (release workflow) |
| `make copy-check` (`scripts/lint-copy.py`) | English copy rules; quotes and ellipses per language; competitor denylist |
| `make strings-check` | catalogs in sync with the code + copy rules + `l10n-check` (CI) |
| `make test` | the measured-width and terminology tests, among all others |
