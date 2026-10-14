# Translating Cranny

Cranny's text lives in String Catalogs: one per CrannyKit target
(`Packages/CrannyKit/Sources/<Target>/Resources/Localizable.xcstrings`) plus `App/InfoPlist.xcstrings` (the
permission prompts). English is the source; Russian is complete and reviewed. These tools let you translate all
of it as one JSON file, check it, and write it back. They need only the Python 3 that ships with macOS
(`/usr/bin/python3`, standard library) and no Xcode.

| Command | Does |
|---|---|
| `python3 -I scripts/l10n/export.py de -o de.json` | Every string for German translators (`--missing-only`: only what German lacks) |
| `python3 -I scripts/l10n/apple-terms.py de -o de-terms.json` | Apple's own German names for Apple's apps, panes and settings, read from this Mac |
| `python3 -I scripts/l10n/validate.py de de.json --glossary de-terms.json` | Checks the file; exit status 1 on errors |
| `python3 -I scripts/l10n/import.py de de.json` | Writes the translations into the catalogs (validates first) |
| `python3 -I scripts/l10n/validate.py de --catalogs` | Checks what the catalogs hold for German |
| `make l10n-check` (= `validate.py --shipped`) | Every shipped language complete and valid; part of `make strings-check` and CI |

`languages.json` lists the languages Cranny is translated into — every language macOS 27 itself ships, except
English variants and regional variants that fall back on their own (es-419 → es, fr-CA → fr, zh-HK → zh-Hant) —
with each language's CLDR plural categories, the categories that stand for a single number
(`pluralExactValues`), its quotation marks as macOS writes them (`quoteStyle`) and notes on its typography.
`"shipped": true` marks the languages that must be complete; a new language is added to the catalogs first and
flipped to shipped when it is complete and reviewed. `App/Info.plist` (`CFBundleLocalizations`) and the Xcode
project (`knownRegions`) list every language of the file; `scripts/smoke.sh` checks the built app.

## The file

`export.py` writes `{"language", "languageInfo", "howTo", "strings": [...]}`. Translate only the
`"translation"` field of each item:

```json
{
  "catalog": "Packages/CrannyKit/Sources/CrannyTray/Resources/Localizable.xcstrings",
  "key": "%lld items · %@",
  "comment": "Tray chip row with nothing selected: number of items and their total size",
  "surface": "Tray chip row with nothing selected",
  "english": {"plural": {"one": "%lld item · %@", "other": "%lld items · %@"}},
  "placeholders": [{"arg": 1, "specifier": "%lld", "type": "integer", "plural": true},
                   {"arg": 2, "specifier": "%@", "type": "text"}],
  "russian": {"plural": {"one": "%lld объект · %@", "few": "%lld объекта · %@", "many": "%lld объектов · %@", "other": "%lld объекта · %@"}},
  "translation": {"plural": {"one": "%lld Objekt · %@", "other": "%lld Objekte · %@"}},
  "state": null,
  "constrained": false
}
```

- **comment** says where the text appears and what it does (`"<surface>: <purpose>"`). Read it first.
- **english** is a string, `{"plural": {category: text}}`, or `{"value": "… %2$#@cells@ …", "substitutions":
  {"cells": {"argNum": 2, "formatSpecifier": "lld", "plural": {…}}}}` (each `%#@name@` in the value is replaced by
  the plural form chosen by argument `argNum`; `%arg` in a form is that number). Answer in the same shape.
- **Plural forms**: exactly the categories in `languageInfo.pluralCategories` (German: one, other; Russian: one,
  few, many, other; Arabic: zero, one, two, few, many, other; Japanese: other only). Every count in Cranny's English
  is a plural, also where English writes both forms the same ("+%lld more"). A form whose category stands for a
  single number (`pluralExactValues`, e.g. Arabic two = 2) may leave the number out ("عنصران"); then any other
  placeholder in that form must be positional (`%2$@`).
- **Placeholders**: keep every one (`%@` text, `%lld` integer, `%#@name@`); change their order with positions
  (`%2$@ … %1$lld`); never mix positional and plain specifiers in one string. Numbers, dates and durations arrive
  already formatted for the user's region — don't write digits into a translation.
- **russian** is the reviewed Russian translation, an extra reference for meaning and tone.
- **translation** already holds the language's text where the catalogs have it; `state` is `"translated"` then.
- **constrained** / **maxWidth**: the text sits in a fixed-width place. `maxWidth.hint` says how much room there is
  (the compact wing beside the camera holds ≈ 48 pt — one short word; a header tab ≈ 12 characters before tabs
  collapse to icons; chips and picker segments one or two short words). Measured-width tests
  (`FlashLabelFitTests`, `BandCopyTests`, `FeaturedRowTests`, the header tab test) render these strings in every
  language and fail when one does not fit, so prefer the shortest natural wording.

How the exporter decides `constrained` (`l10n.SURFACE_RULES`): it reads the comment; text only VoiceOver speaks,
tooltips and Settings search keywords are never constrained; otherwise the first of these that the comment
mentions decides — the compact wing (`wing`, `Notch flash`, `in the notch band`), an explicit limit ("at most 48
pt", "≤ 10 characters"), the Join capsule, "keep it short" / "very short", a header tab, a chip, a picker
segment, a table column header, a 2-cell widget (`…widget, 2 cells`, Mirror / Timer / AirDrop widget text).

## Rules for every language

- **Cranny** is a name: never translate or transliterate it, keep its spelling and capital C. Attach grammar
  around it the way the language does with foreign names (Turkish “Cranny’yi”, Finnish “Crannyn”).
- Never write **Nook**, NotchNook, Alcove, Atoll or boring.notch — not even as a translation of an English word
  (clean room, ARCHITECTURE.md D20). Never look at other notch apps' translations.
- **Apple's names for Apple's things**: apps, System Settings panes, privacy services, accessibility settings,
  Finder places and alert sounds are written exactly as macOS shows them in your language — take them from
  `apple-terms.py` (`--details` shows where each one comes from and the alternatives macOS also uses, such as
  an app's longer bundle name: pt-BR “Ajustes” / “Ajustes do Sistema”). People look for these words on screen.
- Cranny's own names keep a capital in English (Home, Tray, Quick Apps, Live Activities, Layout & Widgets): give
  each one fixed translation and use it everywhere (see the Russian glossary in docs/ARCHITECTURE.md §8.7 for how
  the reviewed translation does it).
- Sentence case everywhere, except where the language capitalizes otherwise (German nouns) and where English uses
  title case for standard macOS menus and buttons — follow your language's macOS convention there.
- Typography: your language's quotation marks (`quoteStyle`), the apostrophe ’, one-character ellipsis …, the
  no-break spaces your language uses (French before : ; ! ? and inside « »). No straight quotes unless macOS uses
  them in your language (Arabic).
- Use the register macOS uses in your language (du/Sie, tu/vous… — the `notes` in `languages.json`).

## Checks (`validate.py`)

Errors (exit status 1): a key without a translation; a placeholder lost, added or of another type; positional and
plain specifiers mixed; plural categories that are not exactly the language's; an empty string; "Nook" and the
other denylisted names; "Cranny" missing or misspelled; quotation marks of another language or straight quotes;
three dots; French spaces. Warnings: a string identical to English (unless it is only names macOS keeps, such as
AirDrop or Finder), a constrained string much longer than English, English that changed since the export, plural
forms collapsed into one string where English varies, and (with `--glossary`) an Apple term left in English.
`import.py` refuses a file with errors (`--force` writes only the items without errors).
