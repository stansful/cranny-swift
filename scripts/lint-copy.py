#!/usr/bin/env python3
"""Copy rules for every String Catalog (docs/CONTRIBUTING.md, "Copy"). No Xcode needed.

The rules apply per language. English, the source (every key: the key itself, or its English value when the key
is an identifier or has a `defaultValue:`):

- American English: no British spellings ("colour", "customise", "licence", ...).
- Typographic punctuation: ' and " are written as ’ and “ ” and three dots as one ….
- System Settings is named by its pane ("Login Items in System Settings"), never by a ▸ path, because the
  path differs between macOS versions. Cranny's own "Settings ▸ Keyboard" paths are fine.

Every other language a catalog holds (each must be in scripts/l10n/languages.json):

- Typographic punctuation: no ASCII " or ' unless that language's quote style (languages.json "quoteStyle", as
  macOS writes it: Arabic uses straight quotes) has them; one … instead of three dots.

Every language, the source included:

- Clean room (ARCHITECTURE.md D20, §8.7 rule 8): no competitor product names ("Nook", …).

scripts/l10n/validate.py checks translations in depth (placeholders, plural forms, quote characters, "Cranny").

    python3 -I scripts/lint-copy.py                  # every catalog
    python3 -I scripts/lint-copy.py CrannyTimer App  # just these targets ("App" = App/InfoPlist.xcstrings)

Exit status 1 lists every problem as `catalog: "key": problem`.
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# British spellings and the American form to use. Matched as whole words or word starts, case-insensitively.
BRITISH = {
    r"colour": "color",
    r"customis": "customiz",
    r"grey": "gray",
    r"behaviour": "behavior",
    r"licence": "license",
    r"organis": "organiz",
    r"favourit": "favorit",
    r"analys(?=e\b|ed\b|ing\b)": "analyz",            # not "analyses", the plural of "analysis"
    r"recognis": "recogniz",
    r"minimis": "minimiz",
    r"maximis": "maximiz",
    r"optimis": "optimiz",
    r"prioritis": "prioritiz",
    r"personalis": "personaliz",
    r"summaris": "summariz",
    r"synchronis": "synchroniz",
    r"visualis": "visualiz",
    r"authoris": "authoriz",
    r"initialis": "initializ",
    r"normalis": "normaliz",
    r"categoris": "categoriz",
    r"apologis": "apologiz",
    r"realis(?=e\b|ed\b|es\b|ing\b|ation)": "realiz",
    r"centre": "center",
    r"cancell(?=ed|ing)": "cancel",
    r"labell(?=ed|ing)": "label",
    r"travell": "travel",
    r"honour": "honor",
    r"neighbour": "neighbor",
    r"catalogue": "catalog",
    r"dialogue": "dialog",
    r"acknowledgement": "acknowledgment",
    r"judgement": "judgment",
    r"programme": "program",
    r"whilst": "while",
    r"amongst": "among",
    r"defence": "defense",
    r"artefact": "artifact",
}
BRITISH_RE = [(re.compile(r"\b" + stem, re.IGNORECASE), us) for stem, us in BRITISH.items()]
DENYLIST = re.compile(r"nook|alcove|atoll|boring\.notch", re.IGNORECASE)
SETTINGS_PATH = re.compile(r"System Settings\s*▸")
LANGUAGES = os.path.join(ROOT, "scripts/l10n/languages.json")


def quote_styles():
    """{language: set of ASCII quote characters its style allows} from scripts/l10n/languages.json."""
    with open(LANGUAGES, encoding="utf-8") as handle:
        table = json.load(handle)
    return {entry["code"]: set("".join(entry["quoteStyle"]["primary"] + entry["quoteStyle"]["secondary"])) & {"'", '"'}
            for entry in table}


def catalogs(targets):
    if not targets:
        found = sorted(glob.glob(os.path.join(ROOT, "Packages/CrannyKit/Sources/*/Resources/Localizable.xcstrings")))
        return found + [os.path.join(ROOT, "App/InfoPlist.xcstrings")]
    paths = []
    for target in targets:
        path = (os.path.join(ROOT, "App/InfoPlist.xcstrings") if target == "App"
                else os.path.join(ROOT, f"Packages/CrannyKit/Sources/{target}/Resources/Localizable.xcstrings"))
        if not os.path.isfile(path):
            sys.exit(f"error: no String Catalog for {target} ({path})")
        paths.append(path)
    return paths


def values(node):
    """Every `value` string under a localization (string units, plural and device variations)."""
    if isinstance(node, dict):
        for name, child in node.items():
            if name == "value" and isinstance(child, str):
                yield child
            else:
                yield from values(child)
    elif isinstance(node, list):
        for child in node:
            yield from values(child)


def is_identifier(key):
    """Keys such as "quickapps.empty.add" or "NSCameraUsageDescription" are not English text."""
    return re.fullmatch(r"[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+|(NS|CF)[A-Za-z]+", key) is not None


def english(key, entry):
    texts = list(values(entry.get("localizations", {}).get("en", {})))
    if not is_identifier(key):
        texts.insert(0, key)
    return texts


def problems_in(text):
    for pattern, us in BRITISH_RE:
        match = pattern.search(text)
        if match:
            yield f"British spelling “{match.group(0)}…” (American: {us}…)"
    if "'" in text:
        yield "straight apostrophe (use ’)"
    if '"' in text:
        yield "straight quotation mark (use “ ”)"
    if "..." in text:
        yield "three dots (use …)"
    if SETTINGS_PATH.search(text):
        yield "System Settings path (name the pane instead: “Login Items in System Settings”)"


def translation_problems(text, language, allowed_ascii):
    """The rules for a language other than English: typographic quotes in its style, one-character ellipsis."""
    if "'" in text and "'" not in allowed_ascii:
        yield f"straight apostrophe or quote ' in {language} (use ’ or the language’s quotes)"
    if '"' in text and '"' not in allowed_ascii:
        yield f"straight quotation mark \" in {language} (use the language’s quotes)"
    if "..." in text:
        yield f"three dots in {language} (use …)"


def main(argv):
    problems = []
    styles = quote_styles()
    for path in catalogs(argv[1:]):
        name = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as handle:
            strings = json.load(handle).get("strings", {})
        for key, entry in sorted(strings.items()):
            if entry.get("extractionState") == "stale" or entry.get("shouldTranslate") is False:
                continue
            seen = set()
            for text in english(key, entry):
                for problem in problems_in(text):
                    if problem not in seen:
                        seen.add(problem)
                        problems.append(f"{name}: {json.dumps(key, ensure_ascii=False)}: {problem}")
            for language, localization in sorted(entry.get("localizations", {}).items()):
                if language == "en":
                    continue
                if language not in styles:
                    problems.append(f"{name}: {json.dumps(key, ensure_ascii=False)}: language “{language}” is not in "
                                    f"scripts/l10n/languages.json")
                    continue
                seen = set()
                for text in values(localization):
                    for problem in translation_problems(text, language, styles[language]):
                        if problem not in seen:
                            seen.add(problem)
                            problems.append(f"{name}: {json.dumps(key, ensure_ascii=False)}: {problem}")
            for text in [key, *values(entry.get("localizations", {}))]:
                match = DENYLIST.search(text)
                if match:
                    problems.append(f"{name}: {json.dumps(key, ensure_ascii=False)}: "
                                    f"competitor term “{match.group(0)}” (ARCHITECTURE.md D20)")
                    break
    if problems:
        print("\n".join(problems))
        print(f"error: {len(problems)} copy problem(s); see docs/CONTRIBUTING.md, \"Copy\"", file=sys.stderr)
        return 1
    print("Copy rules OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
