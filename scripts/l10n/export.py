#!/usr/bin/env python3
"""Export every translatable string for translators, as one JSON file per language.

    python3 -I scripts/l10n/export.py de                    # every key -> stdout
    python3 -I scripts/l10n/export.py de -o de.json         # … into a file
    python3 -I scripts/l10n/export.py de --missing-only     # only keys German does not have yet (or has untranslated)

The file covers every String Catalog (Packages/CrannyKit/Sources/*/Resources/Localizable.xcstrings and
App/InfoPlist.xcstrings). Each item of "strings" is:

    catalog        the catalog the key lives in (repo-relative)
    key            the catalog key (usually the English text itself)
    comment        "<surface>: <purpose>" — where the text appears and what it does
    surface        the comment's surface prefix ("Settings ▸ Tray", "Notch flash")
    english        the English source (a string, {"plural": …} or {"value": …, "substitutions": …}; see l10n.py)
    placeholders   the arguments: [{"arg": 1, "specifier": "%@", "type": "text"}, {"arg": 2, …, "plural": true}]
    russian        the reviewed Russian translation, as an extra reference (same structure)
    translation    the existing translation in this language, or null — translators fill this in
    state          "translated" when every form of the existing translation is translated, else null
    constrained    true when the text sits in a fixed-width place (compact wing, tab, chip, segment, capsule…)
    maxWidth       for constrained keys: {"kind", "maxWidthPt", "hint", "ratio"} (see l10n.SURFACE_RULES)

Translate "translation" in the same structure as "english" (plural keys: one form per category listed in
"language.pluralCategories"), then check with validate.py and write it back with import.py. See README.md.
"""

import argparse
import json
import os
import sys

sys.dont_write_bytecode = True                     # keep the repo free of __pycache__
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l10n  # noqa: E402


def item(path, key, entry, code):
    localizations = entry.get("localizations", {})
    comment = entry.get("comment", "")
    constrained, limit = l10n.constraint(comment)
    english = l10n.english_text(key, entry)
    existing = localizations.get(code)
    translation = l10n.localization_to_text(existing) if existing and code != "en" else None
    states = l10n.localization_states(existing) if existing else []
    complete = bool(states) and all(state == "translated" for state in states)
    result = {
        "catalog": l10n.rel(path),
        "key": key,
        "comment": comment,
        "surface": l10n.surface(comment),
        "english": english,
        "placeholders": l10n.placeholders(english),
        "russian": l10n.localization_to_text(localizations.get("ru")) if code != "ru" else None,
        "translation": translation,
        "state": "translated" if complete else None,
        "constrained": constrained,
    }
    if limit:
        result["maxWidth"] = limit
    return result, complete


def export(code, missing_only=False):
    info = l10n.language(code)
    items = []
    for path, key, entry in l10n.entries():
        result, complete = item(path, key, entry, code)
        if missing_only and complete:
            continue
        items.append(result)
    meta = {k: info[k] for k in ("code", "englishName", "nativeName", "rtl", "pluralCategories", "pluralExactValues",
                                 "quoteStyle", "notes") if k in info}
    return {
        "format": "cranny-l10n/1",
        "language": code,
        "languageInfo": meta,
        "sourceRevision": l10n.git_revision(),
        "missingOnly": missing_only,
        "howTo": [
            "Fill in \"translation\" for every item, in the structure of \"english\"; leave every other field as it is.",
            "Plural keys: {\"plural\": {…}} with exactly the categories in languageInfo.pluralCategories. "
            "A category listed in pluralExactValues stands for that one number and may leave the number out.",
            "Keep every placeholder of \"placeholders\" (%@, %lld, %#@name@); reorder with positions: %1$@, %2$lld.",
            "Cranny is never translated or transliterated; never write “Nook”.",
            "Name Apple’s apps, panes and settings exactly as macOS does in your language (apple-terms.py glossary).",
            "constrained: the text sits in a fixed-width place; maxWidth.hint says how much room there is.",
            "Check: python3 -I scripts/l10n/validate.py <lang> <file>; write back: python3 -I scripts/l10n/import.py <lang> <file>.",
        ],
        "strings": items,
    }


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("language", help="language code from scripts/l10n/languages.json (de, pt-BR, zh-Hans…)")
    parser.add_argument("--missing-only", action="store_true", help="only keys without a complete translation")
    parser.add_argument("-o", "--output", help="write to this file instead of stdout")
    args = parser.parse_args(argv)
    data = export(args.language, args.missing_only)
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(text)
        print(f"{args.output}: {len(data['strings'])} strings for {args.language}", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
