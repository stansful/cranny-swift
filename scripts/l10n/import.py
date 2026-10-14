#!/usr/bin/env python3
"""Write a translator file (export.py format, "translation" filled in) into the String Catalogs.

    python3 -I scripts/l10n/import.py de de.json              # validate, then write every translated key
    python3 -I scripts/l10n/import.py de de.json --dry-run    # report what would change, write nothing
    python3 -I scripts/l10n/import.py de de.json --force      # write the items without errors although others have some

Every item whose "translation" is not null becomes the key's localization for the language, with every string
unit in state "translated": a plain string unit, plural variations with exactly the language's CLDR categories,
or a string unit with substitutions. Everything else in the catalogs (other languages, comments, extraction
state, keys not in the file) stays as it is, and the files keep Xcode's formatting (the serializer of
scripts/merge-xcstrings.py), so `make strings-check` sees no formatting change.

The file is checked with validate.py first: with errors nothing is written, unless --force, which still skips
the items that have errors. Keys that are no longer in the catalogs are skipped with a warning. Afterwards run
`make strings-check`; the language counts as shipped once scripts/l10n/languages.json says "shipped": true.
"""

import argparse
import json
import os
import sys

sys.dont_write_bytecode = True                     # keep the repo free of __pycache__
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l10n  # noqa: E402
import validate  # noqa: E402


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("language", help="language code from scripts/l10n/languages.json")
    parser.add_argument("file", help="translator JSON from export.py with \"translation\" filled in")
    parser.add_argument("--dry-run", action="store_true", help="report, write nothing")
    parser.add_argument("--force", action="store_true", help="write the valid items even when others have errors")
    parser.add_argument("-q", "--quiet", action="store_true", help="hide validation warnings")
    args = parser.parse_args(argv)
    code = args.language
    info = l10n.language(code)
    if info.get("source"):
        l10n.die(f"{code} is the source language; edit the code and run make strings instead")
    with open(args.file, encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("language") not in (None, code):
        l10n.die(f"{args.file} is for {data.get('language')!r}, not {code!r}")

    current = validate.current_items()
    report = validate.Report(show_warnings=not args.quiet)
    accepted = []
    skipped = 0
    for item in data.get("strings", []):
        ident = (item.get("catalog"), item.get("key"))
        translation = item.get("translation")
        if translation is None:
            continue
        if ident not in current:
            report.warn(validate.where(code, *ident), "no longer in the catalogs: skipped")
            skipped += 1
            continue
        comment, english, _ = current[ident]
        if validate.check_item(report, code, info, ident[0], ident[1], comment, english, translation):
            accepted.append((ident, translation))
        else:
            skipped += 1
    if report.errors and not args.force:
        print(f"error: {report.errors} error(s) in {args.file}; nothing written (fix them, or --force to skip those items)",
              file=sys.stderr)
        return 1

    by_catalog = {}
    for (catalog, key), translation in accepted:
        by_catalog.setdefault(catalog, []).append((key, translation))
    changed_keys = 0
    for catalog, items in sorted(by_catalog.items()):
        path = os.path.join(l10n.ROOT, catalog)
        data_catalog, trailing_newline = l10n.load_catalog(path)
        before = l10n.serialize(data_catalog, trailing_newline)
        for key, translation in items:
            entry = data_catalog["strings"][key]
            localization = l10n.text_to_localization(translation, state="translated")
            if entry.get("localizations", {}).get(code) != localization:
                changed_keys += 1
            entry.setdefault("localizations", {})[code] = localization
        after = l10n.serialize(data_catalog, trailing_newline)
        if after != before:
            if args.dry_run:
                print(f"would update {catalog} ({len(items)} keys)")
            else:
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write(after)
                print(f"updated {catalog} ({len(items)} keys)")
    verb = "would change" if args.dry_run else "changed"
    print(f"{code}: {len(accepted)} translations accepted, {changed_keys} keys {verb}, {skipped} skipped, "
          f"{report.warnings} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
