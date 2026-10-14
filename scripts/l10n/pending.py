#!/usr/bin/env python3
"""Mark new English strings "pending translation" in every shipped language (make l10n-pending).

    python3 -I scripts/l10n/pending.py               # every catalog: each key a shipped language lacks
    python3 -I scripts/l10n/pending.py --dry-run     # report, write nothing

The policy (docs/TRANSLATING.md ▸ New strings): a pull request that adds or changes English text either brings its
translations or marks them pending. This script does the second: for every translatable key that has no
localization in a shipped language, it writes the English text in that language's shape (exactly its plural
categories) with every string unit in state "needs_review". The app then shows English there, as it would for a
missing key; `make strings-check` (validate.py --shipped) accepts the key and lists it as pending, and a release
(validate.py --shipped --release) refuses it. Translators find pending keys with `export.py <lang> --missing-only`,
where their "translation" is null, and import.py replaces them with state "translated".

Keys that already have a localization in a language (translated, or partly needs_review) are left as they are; the
source language and other catalogs' formatting are untouched (Xcode's serializer, like import.py).
"""

import argparse
import os
import sys

sys.dont_write_bytecode = True                     # keep the repo free of __pycache__
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l10n  # noqa: E402


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="report, write nothing")
    args = parser.parse_args(argv)
    source = l10n.source_language()
    codes = [code for code in l10n.shipped_languages() if code != source]
    marked = {}
    for path in l10n.catalog_paths():
        data, trailing_newline = l10n.load_catalog(path)
        before = l10n.serialize(data, trailing_newline)
        for key in sorted(data.get("strings", {})):
            entry = data["strings"][key]
            if not l10n.translatable(entry):
                continue
            english = l10n.english_text(key, entry)
            for code in codes:
                localizations = entry.setdefault("localizations", {})
                if code in localizations:
                    continue
                shaped = l10n.shaped_like(english, l10n.language(code)["pluralCategories"])
                localizations[code] = l10n.text_to_localization(shaped, state="needs_review")
                marked.setdefault((l10n.rel(path), key), []).append(code)
        if l10n.serialize(data, trailing_newline) != before and not args.dry_run:
            l10n.save_catalog(path, data, trailing_newline)
    for (catalog, key), langs in sorted(marked.items()):
        print(f"{catalog}: {key!r}: pending in {len(langs)} language(s)")
    verb = "would mark" if args.dry_run else "marked"
    print(f"{verb} {len(marked)} key(s) pending translation (needs_review) in {len(codes)} shipped language(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
