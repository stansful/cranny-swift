#!/usr/bin/env python3
"""Check a translation before it goes into the String Catalogs (exit status 1 on errors; warnings are printed).

    python3 -I scripts/lib/l10n/validate.py de de.json            # a translator file (from export.py)
    python3 -I scripts/lib/l10n/validate.py de --catalogs         # what the catalogs hold for German now
    python3 -I scripts/lib/l10n/validate.py --shipped             # every language marked "shipped" (make strings-check)
    python3 -I scripts/lib/l10n/validate.py --shipped --release   # … and no key pending translation (build-release.sh)
    python3 -I scripts/lib/l10n/validate.py de de.json --glossary de-terms.json   # also compare with Apple's terms

Errors:
- completeness: every key of the export has a translation (a file made with --missing-only must still hold every key
  the catalogs lack), and in --catalogs mode every form is in state "translated" — except keys pending translation
  (every form "needs_review", written by pending.py), which are listed as one warning per language, and are errors
  with --release;
- placeholders: the same arguments as English (%@, %lld, %#@name@ …), same types, none lost or added; positions
  (%1$@, %2$lld) may reorder them; one string may not mix positional and sequential specifiers; a plural form may
  leave its number out only in a category of languages.json "pluralExactValues" (Arabic zero/one/two, Hebrew two…),
  and then every other specifier of that form must be positional;
- plural variations with exactly the language's CLDR categories (languages.json "pluralCategories");
- no empty values; no competitor names ("Nook" …, ARCHITECTURE.md D20) in any language;
- "Cranny" kept as written wherever English has it (never translated or transliterated);
- quote characters of the language (languages.json "quoteStyle"; no ASCII quotes unless macOS uses them there);
  French no-break spaces inside « » and before : ; ! ?; "..." instead of "…";
- the English source (language "en"): every count has plural variations (one/other), except the numbers listed in
  NOT_COUNTS (labels, positions, codes).
Warnings: a translation identical to English (unless it only holds names macOS keeps, see KEEP_AS_IS), a constrained
key much longer than English (export.py "maxWidth"), English changed since the export, plural forms dropped where
English varies, French punctuation without a space, and, with --glossary, an Apple term left in English where macOS
translates it.
"""

import argparse
import ctypes
import json
import os
import re
import sys

sys.dont_write_bytecode = True                     # keep the repo free of __pycache__
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l10n  # noqa: E402

# Integer arguments that are not counts, so their keys need no plural variations: (catalog target, key) -> why.
NOT_COUNTS = {
    ("CrannyAppShell", "GitHub answered with an error (%lld). Try again later."): "an HTTP status code",
    ("CrannyNotchUI", "%@, position %lld"): "a position (ordinal)",
    ("CrannyNotes", "Untitled %lld"): "a numbered name",
    ("CrannyOnboarding", "%lld of %lld"): "a position in a total",
    ("CrannyOnboarding", "Step %lld of %lld"): "a position in a total",
    ("CrannyQuickApps", "Option-%lld"): "a key name (⌥1–⌥9)",
    ("CrannySettingsUI", "Page %lld"): "a numbered name",
    ("CrannyTimer", "Preset %lld"): "a numbered name",
    ("CrannyTray", "Drop zone %lld"): "a numbered name",
}

# Words macOS keeps in English in (nearly) every language: a translation that equals English and holds only these
# (plus numbers, placeholders and punctuation) is not suspicious.
KEEP_AS_IS = {
    "Cranny", "AirDrop", "Spotify", "Finder", "Bluetooth", "Wi-Fi", "Wi‑Fi", "macOS", "Mac", "MacBook", "iCloud", "Siri",
    "Spotlight", "Mission", "Control", "Dock", "Safari", "FaceTime", "GitHub", "Zoom", "Microsoft", "Teams", "Webex",
    "Google", "Meet", "Apple", "Events", "Music", "MonitorControl", "SoundSource", "BetterDisplay", "Lunar", "Option",
    "Command", "Shift", "Esc", "Fn", "OK", "Zip", "ZIP", "PNG", "JPEG", "HEIC", "PDF", "URL", "ID", "HUD", "Metal",
    "Cmd", "Ctrl", "Opt", "Tab", "Return", "Space", "pt", "px", "MB", "GB", "KB", "ms", "AM", "PM", "Wi", "Fi",
    "Liquid", "Glass",
}
QUOTES = set("“”„‟«»‹›「」『』״\"‘‚‛'")      # ’ (U+2019) is also the apostrophe: never checked
NO_BREAK = "  "


class Report:
    def __init__(self, show_warnings=True):
        self.errors = 0
        self.warnings = 0
        self.show_warnings = show_warnings

    def error(self, where, message):
        self.errors += 1
        print(f"error: {where}: {message}")

    def warn(self, where, message):
        self.warnings += 1
        if self.show_warnings:
            print(f"warning: {where}: {message}")


def target(catalog):
    parts = catalog.split("/")
    return parts[3] if catalog.startswith("Packages/") and len(parts) > 3 else "App"


def where(code, catalog, key, form=None):
    suffix = f" [{form}]" if form and form != "value" else ""
    return f"{catalog}: {json.dumps(key, ensure_ascii=False)} ({code}){suffix}"


# MARK: Checks of one item

def _shape_ok(text):
    if isinstance(text, str):
        return True
    if not isinstance(text, dict):
        return False
    if "plural" in text:
        return isinstance(text["plural"], dict) and all(isinstance(v, str) for v in text["plural"].values())
    if "value" in text and isinstance(text["value"], str):
        subs = text.get("substitutions", {})
        return isinstance(subs, dict) and all(
            isinstance(s, dict) and isinstance(s.get("plural"), dict) and isinstance(s.get("argNum"), int)
            and isinstance(s.get("formatSpecifier"), str) and all(isinstance(v, str) for v in s["plural"].values())
            for s in subs.values())
    return False


def count_argument(english):
    """The English argument a top-level plural varies by: its only integer argument."""
    union, _ = l10n.argument_map(english)
    integers = [n for n, c in union.items() if l10n.INTEGER.match(c or "")]
    return integers[0] if len(integers) == 1 else None


def check_item(report, code, info, catalog, key, comment, english, translation, glossary=None):
    """Every check of one translation against its English source. Returns False when it has errors."""
    before = report.errors
    at = where(code, catalog, key)
    if not _shape_ok(translation):
        report.error(at, "not a string, {\"plural\": …} or {\"value\": …, \"substitutions\": …}")
        return False
    categories = set(info["pluralCategories"])
    exact = set(info.get("pluralExactValues", {}))
    en_union, _ = l10n.argument_map(english)
    en_forms = l10n.forms(english)                      # (label, string, category, substitution)
    tr_union, tr_forms = l10n.argument_map(translation)  # (label, string, category, substitution, Specifiers)
    english_plural = isinstance(english, dict)
    english_by_category = {cat: s for _, s, cat, sub in en_forms if cat and sub is None}
    english_main = english_by_category.get("other") or next((s for _, s, cat, _ in en_forms if cat is None), None) \
        or en_forms[0][1]

    # Plural structure.
    for label, block in l10n.plural_blocks(translation):
        missing = [c for c in l10n.PLURAL_ORDER if c in categories and c not in block]
        extra = sorted(set(block) - categories)
        if missing or extra:
            report.error(at, f"{label}: categories must be exactly {', '.join(info['pluralCategories'])}"
                             + (f"; missing {', '.join(missing)}" if missing else "")
                             + (f"; not in {code}: {', '.join(extra)}" if extra else ""))
    if isinstance(translation, dict) and "plural" in translation and not english_plural and count_argument(english) is None:
        report.error(at, "plural variations, but English has no count to vary by")
    if isinstance(translation, str) and english_plural and len(categories) > 1:
        texts = {s for _, s, cat, _ in en_forms if cat}
        if len(texts) > 1:
            report.warn(at, "English varies by count; give the plural forms "
                            f"({', '.join(info['pluralCategories'])}) unless {code} really needs none")
    if isinstance(translation, dict) and "substitutions" in translation:
        used = set(re.findall(r"#@([A-Za-z_][A-Za-z0-9_]*)@", translation.get("value", "")))
        for name, sub in translation["substitutions"].items():
            if name not in used:
                report.error(at, f"substitution {name!r} is defined but %#@{name}@ is not in the value")
            if en_union.get(sub["argNum"]) != sub["formatSpecifier"]:
                report.error(at, f"substitution {name!r}: argument {sub['argNum']} is "
                                 f"%{en_union.get(sub['argNum'], '(none)')} in English, not %{sub['formatSpecifier']}")

    # Placeholders.
    for number in sorted(set(en_union) - set(tr_union)):
        report.error(at, f"placeholder %{en_union[number]} (argument {number}) is missing")
    for number in sorted(set(tr_union) - set(en_union)):
        report.error(at, f"placeholder %{tr_union[number]} (argument {number}) is not in English")
    count_arg = count_argument(english) if not (isinstance(translation, dict) and "substitutions" in translation) else None
    subs = translation.get("substitutions", {}) if isinstance(translation, dict) else {}
    en_percent = max((l10n.Specifiers(s).percent for _, s, _, _ in en_forms), default=0)
    for label, string, category, sub, specs in tr_forms:
        here = where(code, catalog, key, label)
        if specs.mixed:
            report.error(here, "mixes positional (%1$@) and sequential (%@) specifiers")
        if specs.conflicts:
            report.error(here, f"argument {specs.conflicts[0]} used with two different types")
        if specs.unknown_substitutions:
            report.error(here, f"%#@{specs.unknown_substitutions[0]}@ has no substitution")
        if specs.misnumbered:
            report.error(here, f"substitution {specs.misnumbered[0]!r}: its argNum does not match its position")
        # A substitution's form holds only its own number (%arg); every other string holds every argument.
        expected = {subs[sub]["argNum"]} if sub is not None else set(en_union)
        for number, conversion in sorted(specs.args.items()):
            if number in en_union and conversion != en_union[number]:
                report.error(here, f"argument {number} is %{en_union[number]} in English but %{conversion} in this form")
        lost = sorted(n for n in expected if n not in specs.args and n in tr_union)   # absent everywhere: reported above
        if lost:
            allowed = category in exact and (lost == [subs[sub]["argNum"]] if sub is not None else lost == [count_arg])
            if not allowed:
                if not category:
                    why = ""
                elif exact:
                    why = (f" (only {', '.join(c for c in l10n.PLURAL_ORDER if c in exact)}, which stand for a single "
                           f"number in {code}, may leave the number out)")
                else:
                    why = f" (no plural category of {code} stands for a single number, so every form keeps it)"
                report.error(here, "leaves out " + ", ".join(f"argument {n}" for n in lost) + why)
            elif specs.sequential:
                report.error(here, "leaves its number out, so the other specifiers must be positional (%2$@)")
        if specs.percent != en_percent and sub is None:
            report.warn(here, f"English has {en_percent} literal %% here, this form {specs.percent}")

    # Text rules for every form.
    english_has_brand = any(l10n.BRAND in s for _, s, _, _ in en_forms)
    allowed_quotes = set("".join(info["quoteStyle"]["primary"] + info["quoteStyle"]["secondary"])) - set(NO_BREAK + " ")
    for label, string, category, sub, specs in tr_forms:
        here = where(code, catalog, key, label)
        if not string.strip():
            report.error(here, "empty")
            continue
        match = l10n.DENYLIST.search(string)
        if match:
            report.error(here, f"competitor term “{match.group(0)}” (ARCHITECTURE.md D20)")
        for found in re.findall(r"cranny", string, re.IGNORECASE):
            if found != l10n.BRAND:
                report.error(here, f"“{found}”: write the name exactly as “Cranny”")
        if "..." in string:
            report.error(here, "three dots: use the ellipsis character … (U+2026)")
        for character in sorted(set(string) & QUOTES - allowed_quotes):
            report.error(here, f"quote character {character} (U+{ord(character):04X}) is not {code} style: use "
                               f"{''.join(info['quoteStyle']['primary'])} / {''.join(info['quoteStyle']['secondary'])}")
        if code == "fr":
            if re.search(r"«(?![  ])|(?<![  ])»", string):
                report.error(here, "French guillemets need a no-break space inside: « … » (U+00A0 or U+202F)")
            if re.search(r" [:;!?»]", string):
                report.error(here, "French: a plain space before : ; ! ? — use a no-break space (U+00A0 or U+202F)")
            if re.search(r"(?<=[^\s\d/  %])[;!?](?=\s|$)|(?<=[A-Za-zÀ-ÿ])[:](?=\s|$)", string):
                report.warn(here, "French: no space before : ; ! ? (macOS writes a no-break space)")
        if code == "uk" and re.search(r"(?<=[Ѐ-ӿ])[’'](?=[Ѐ-ӿ])", string):
            report.error(here, "Ukrainian apostrophe: write ʼ (U+02BC) between letters, as macOS does (памʼять), "
                               "not ’ or ' (search also splits words at them)")
    if english_has_brand and not any(l10n.BRAND in s for _, s, *_ in tr_forms):
        report.error(at, "“Cranny” is missing: the name is never translated or transliterated")
    elif english_has_brand:
        for label, string, category, sub, specs in tr_forms:
            counterpart = english_by_category.get(category) if category else english_main
            if sub is None and counterpart and l10n.BRAND in counterpart and l10n.BRAND not in string:
                report.error(where(code, catalog, key, label), "“Cranny” is missing in this form")

    # Warnings.
    if code != l10n.source_language():
        for label, string, category, sub, specs in tr_forms:
            counterpart = english_by_category.get(category, english_main) if sub is None else None
            if sub is not None:
                en_sub = next((s for _, s, cat, sb in en_forms if sb is not None and cat in (category, "other")), None)
                counterpart = en_sub
            if counterpart and string == counterpart and not keeps_english(string):
                report.warn(where(code, catalog, key, label), "same as English (translate it, or it is a name macOS keeps?)")
        constrained, limit = l10n.constraint(comment)
        if constrained:
            for label, string, category, sub, specs in tr_forms:
                if sub is not None:
                    continue
                counterpart = english_by_category.get(category, english_main) if category else english_main
                ours, theirs = l10n.display_width(string), l10n.display_width(counterpart)
                budget = limit.get("budget")
                if budget and ours > max(budget, theirs):
                    report.warn(where(code, catalog, key, label),
                                f"{ours} display columns where about {budget} fit — {limit['hint']}")
                elif not budget and theirs and ours > theirs * limit["ratio"] and ours - theirs >= 4:
                    report.warn(where(code, catalog, key, label),
                                f"{ours / theirs:.0%} of the English length in a fixed-width place — {limit['hint']}")
        if glossary:
            for term, localized in glossary.items():
                if not localized or localized == term or len(term) < 4:
                    continue
                pattern = re.compile(r"(?<![\w-])" + re.escape(term) + r"(?![\w-])")
                if any(pattern.search(s) for _, s, _, _ in en_forms) and \
                        any(pattern.search(s) for _, s, *_ in tr_forms) and not any(localized in s for _, s, *_ in tr_forms):
                    report.warn(at, f"“{term}” left in English; macOS calls it “{localized}” in {code}")
    return report.errors == before


def keeps_english(string):
    """True when a string has no words other than names macOS keeps (KEEP_AS_IS), numbers and placeholders."""
    words = re.findall(r"[^\W\d_]+(?:[-‑'’][^\W\d_]+)*", l10n.SPECIFIER.sub(" ", string))
    keep = {word.lower() for word in KEEP_AS_IS}
    return all(word.lower() in keep or len(word) == 1 for word in words)


def check_source(report, catalog, key, english):
    """The English source: counts vary by plural (one/other), no empty strings, no competitor names."""
    code = "en"
    at = where(code, catalog, key)
    union, forms = l10n.argument_map(english)
    has_count = any(l10n.INTEGER.match(c or "") for c in union.values())
    varies = isinstance(english, dict) and ("plural" in english or english.get("substitutions"))
    if has_count and not varies and (target(catalog), key) not in NOT_COUNTS:
        report.error(at, "a count without plural variations: give the en localization one/other forms "
                         "(or list the key in validate.py NOT_COUNTS if the number is not a count)")
    for label, block in l10n.plural_blocks(english):
        if set(block) != {"one", "other"}:
            report.error(at, f"{label}: English plural forms must be exactly one, other (has {', '.join(block)})")
    for label, string, category, sub, specs in forms:
        if not (string or "").strip():
            report.error(where(code, catalog, key, label), "empty")
        elif l10n.DENYLIST.search(string):
            report.error(where(code, catalog, key, label), "competitor term (ARCHITECTURE.md D20)")
        if specs.mixed:
            report.error(where(code, catalog, key, label), "mixes positional and sequential specifiers")


# MARK: Modes

def current_items():
    """{(catalog, key): (comment, english, entry)} for every translatable key now in the catalogs."""
    return {(l10n.rel(path), key): (entry.get("comment", ""), l10n.english_text(key, entry), entry)
            for path, key, entry in l10n.entries()}


def complete_in_catalog(entry, code):
    states = l10n.localization_states(entry.get("localizations", {}).get(code, {}))
    return bool(states) and all(state == "translated" for state in states)


def validate_catalogs(report, code, glossary=None, release=False):
    info = l10n.language(code)
    pending = []
    for (catalog, key), (comment, english, entry) in sorted(current_items().items()):
        if code == l10n.source_language():
            check_source(report, catalog, key, english)
            continue
        localization = entry.get("localizations", {}).get(code)
        if localization is None:
            report.error(where(code, catalog, key), "no translation (translate it, or mark it pending: make l10n-pending; "
                                                    "docs/TRANSLATING.md)")
            continue
        if l10n.is_pending(localization):
            if release:
                report.error(where(code, catalog, key), "pending translation (needs_review): translate it before a release")
            else:
                pending.append(f"{target(catalog)}: {json.dumps(key, ensure_ascii=False)}")
            continue
        if not complete_in_catalog(entry, code):
            report.error(where(code, catalog, key), "not every form is in state “translated”")
        try:
            translation = l10n.localization_to_text(localization)
        except ValueError as problem:
            report.error(where(code, catalog, key), str(problem))
            continue
        check_item(report, code, info, catalog, key, comment, english, translation, glossary)
    if pending:
        shown = "; ".join(pending[:5]) + (f"; … {len(pending) - 5} more" if len(pending) > 5 else "")
        report.warn(f"{code}", f"{len(pending)} key(s) pending translation (needs_review; export.py {code} --missing-only "
                               f"lists them): {shown}")


def validate_file(report, code, path, glossary=None):
    info = l10n.language(code)
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("language") not in (None, code):
        report.error(path, f"the file is for {data.get('language')!r}, not {code!r}")
    items = data.get("strings", [])
    current = current_items()
    seen = set()
    for item in items:
        ident = (item.get("catalog"), item.get("key"))
        seen.add(ident)
        if ident not in current:
            report.warn(where(code, *ident), "no longer in the catalogs (import.py skips it)")
            continue
        comment, english, entry = current[ident]
        if item.get("english") is not None and item.get("english") != english:
            report.warn(where(code, *ident), "English changed since the export: check the translation, then export again")
        translation = item.get("translation")
        if translation is None:
            report.error(where(code, *ident), "no translation")
            continue
        check_item(report, code, info, ident[0], ident[1], comment, english, translation, glossary)
    if data.get("missingOnly"):
        absent = [ident for ident, (_, _, entry) in current.items() if ident not in seen and not complete_in_catalog(entry, code)]
    else:
        absent = [ident for ident in current if ident not in seen]
    for ident in sorted(absent):
        report.error(where(code, *ident), "not in the file (export again)")


def icu_plural_categories(code):
    """The plural categories of this Mac's ICU (libicucore), or None where it cannot be read."""
    try:
        icu = ctypes.CDLL("/usr/lib/libicucore.A.dylib")
        icu.uplrules_open.restype = ctypes.c_void_p
        icu.uplrules_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
        icu.uplrules_getKeywords.restype = ctypes.c_void_p
        icu.uplrules_getKeywords.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int)]
        icu.uenum_next.restype = ctypes.c_char_p
        icu.uenum_next.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
        status = ctypes.c_int(0)
        rules = icu.uplrules_open(code.replace("-", "_").encode(), ctypes.byref(status))
        keywords = icu.uplrules_getKeywords(rules, ctypes.byref(status))
        found = set()
        while True:
            length = ctypes.c_int(0)
            word = icu.uenum_next(keywords, ctypes.byref(length), ctypes.byref(status))
            if not word:
                break
            found.add(word.decode())
        return found or None
    except (OSError, AttributeError):
        return None


def check_language_entry(report, code):
    info = l10n.language(code)
    icu = icu_plural_categories(code)
    if icu and icu != set(info["pluralCategories"]):
        report.warn(f"languages.json ({code})", f"pluralCategories {info['pluralCategories']} differ from this Mac’s ICU: "
                                                f"{sorted(icu, key=l10n.PLURAL_ORDER.index)}")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("language", nargs="?", help="language code from scripts/lib/l10n/languages.json")
    parser.add_argument("file", nargs="?", help="translator JSON (from export.py, \"translation\" filled in)")
    parser.add_argument("--catalogs", action="store_true", help="check what the String Catalogs hold for the language")
    parser.add_argument("--shipped", action="store_true", help="check every language marked shipped in languages.json")
    parser.add_argument("--release", action="store_true", help="with --shipped or --catalogs: keys pending translation "
                                                               "(needs_review) are errors")
    parser.add_argument("--glossary", help="apple-terms.py output for the language: warn on Apple terms left in English")
    parser.add_argument("-q", "--quiet", action="store_true", help="print errors only")
    args = parser.parse_args(argv)
    report = Report(show_warnings=not args.quiet)
    glossary = None
    if args.glossary:
        with open(args.glossary, encoding="utf-8") as handle:
            glossary = json.load(handle)
    if args.shipped:
        codes = l10n.shipped_languages()
        for code in codes:
            check_language_entry(report, code)
            validate_catalogs(report, code, glossary, args.release)
        label = "shipped languages " + ", ".join(codes)
    elif args.language and args.catalogs:
        check_language_entry(report, args.language)
        validate_catalogs(report, args.language, glossary, args.release)
        label = f"{args.language} in the catalogs"
    elif args.language and args.file:
        check_language_entry(report, args.language)
        validate_file(report, args.language, args.file, glossary)
        label = f"{args.language} in {args.file}"
    else:
        parser.error("give LANGUAGE FILE, LANGUAGE --catalogs or --shipped")
    summary = f"{label}: {report.errors} error(s), {report.warnings} warning(s)"
    if report.errors:
        print(f"error: {summary}", file=sys.stderr)
        return 1
    print(f"Localization OK — {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
