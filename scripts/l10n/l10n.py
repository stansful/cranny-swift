"""Shared code of the localization tools in scripts/l10n (Python 3 standard library only).

The tools (export.py, import.py, validate.py, apple-terms.py) import this module; it is not a tool itself.
It knows where the String Catalogs are, reads scripts/l10n/languages.json, converts catalog entries to the
translator JSON format and back, extracts format specifiers and classifies fixed-width surfaces.

Translator JSON ("text") format, used for the English source, the Russian reference and the translation:

    "Done"                                                  a plain string
    {"plural": {"one": "%lld item", "other": "%lld items"}} plural variations (CLDR categories of the language)
    {"value": "%1$@, %2$#@cells@",                          a string with substitutions: each %#@name@ token is
     "substitutions": {"cells": {"argNum": 2,               replaced by the plural form chosen by argument argNum;
        "formatSpecifier": "lld",                           %arg in a form is that number
        "plural": {"one": "%arg cell", "other": "%arg cells"}}}}
"""

import glob
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
LANGUAGES_PATH = os.path.join(HERE, "languages.json")
PLURAL_ORDER = ["zero", "one", "two", "few", "many", "other"]

# Competitor names (ARCHITECTURE.md D20, §8.7 rule 8); also in scripts/lint-copy.py.
DENYLIST = re.compile(r"nook|alcove|atoll|boring\.notch", re.IGNORECASE)
BRAND = "Cranny"


def die(message):
    sys.stderr.write(f"error: {message}\n")
    sys.exit(2)


# MARK: Languages

def languages():
    """languages.json as {code: entry}, in file order."""
    with open(LANGUAGES_PATH, encoding="utf-8") as handle:
        return {entry["code"]: entry for entry in json.load(handle)}


def language(code):
    table = languages()
    if code not in table:
        die(f"unknown language {code!r}; scripts/l10n/languages.json has: {', '.join(table)}")
    return table[code]


def shipped_languages():
    return [code for code, entry in languages().items() if entry.get("shipped")]


def source_language():
    return next(code for code, entry in languages().items() if entry.get("source"))


# MARK: Catalogs

def catalog_paths():
    """Every String Catalog: one per CrannyKit target, then App/InfoPlist.xcstrings."""
    found = sorted(glob.glob(os.path.join(ROOT, "Packages/CrannyKit/Sources/*/Resources/*.xcstrings")))
    return found + [os.path.join(ROOT, "App/InfoPlist.xcstrings")]


def rel(path):
    return os.path.relpath(path, ROOT)


def load_catalog(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    return json.loads(text), text.endswith("\n")


def _merge_driver():
    spec = importlib.util.spec_from_file_location("merge_xcstrings", os.path.join(ROOT, "scripts/merge-xcstrings.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def serialize(data, trailing_newline=True):
    """Xcode/xcstringstool formatting (the serializer of scripts/merge-xcstrings.py)."""
    return _merge_driver().xcode_json(data) + ("\n" if trailing_newline else "")


def save_catalog(path, data, trailing_newline=True):
    text = serialize(data, trailing_newline)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def translatable(entry):
    return entry.get("extractionState") != "stale" and entry.get("shouldTranslate") is not False


def entries():
    """(catalog path, key, entry) for every translatable key of every catalog."""
    for path in catalog_paths():
        data, _ = load_catalog(path)
        for key in sorted(data.get("strings", {})):
            entry = data["strings"][key]
            if translatable(entry):
                yield path, key, entry


def git_revision():
    try:
        return subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True,
                              check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


# MARK: Catalog localization <-> translator text

def _unit(node):
    unit = node.get("stringUnit") if isinstance(node, dict) else None
    return unit.get("value") if isinstance(unit, dict) else None


def _plural(variations):
    plural = variations.get("plural") if isinstance(variations, dict) else None
    if not isinstance(plural, dict):
        return None
    return {category: _unit(form) for category, form in plural.items()}


def localization_to_text(localization):
    """A catalog localization ({"stringUnit": …} / {"variations": …} / substitutions) as translator text."""
    if not isinstance(localization, dict):
        return None
    if "variations" in localization:
        plural = _plural(localization["variations"])
        if plural is None:
            raise ValueError(f"unsupported variations {sorted(localization['variations'])} (only plural)")
        return {"plural": plural}
    value = _unit(localization)
    if "substitutions" in localization:
        subs = {}
        for name, sub in localization["substitutions"].items():
            plural = _plural(sub.get("variations", {}))
            if plural is None:
                raise ValueError(f"substitution {name!r} has no plural variations")
            subs[name] = {"argNum": sub.get("argNum"), "formatSpecifier": sub.get("formatSpecifier"), "plural": plural}
        return {"value": value, "substitutions": subs}
    return value


def _string_unit(value, state):
    return {"stringUnit": {"state": state, "value": value}}


def text_to_localization(text, state="translated"):
    """Translator text as a catalog localization; plural forms are written in the order Xcode sorts them."""
    if isinstance(text, str):
        return _string_unit(text, state)
    if isinstance(text, dict) and "plural" in text:
        return {"variations": {"plural": {c: _string_unit(v, state) for c, v in text["plural"].items()}}}
    if isinstance(text, dict) and "value" in text:
        localization = _string_unit(text["value"], state)
        subs = {}
        for name, sub in text.get("substitutions", {}).items():
            subs[name] = {"argNum": sub["argNum"], "formatSpecifier": sub["formatSpecifier"],
                          "variations": {"plural": {c: _string_unit(v, state) for c, v in sub["plural"].items()}}}
        if subs:
            localization["substitutions"] = subs
        return localization
    raise ValueError(f"not a translation: {json.dumps(text, ensure_ascii=False)[:120]}")


def english_text(key, entry):
    """The English source: the `en` localization when there is one (plural, positional or `defaultValue:` keys),
    else the key itself."""
    english = entry.get("localizations", {}).get("en")
    text = localization_to_text(english) if english else None
    return key if text is None else text


def localization_states(localization):
    """Every stringUnit state in a localization."""
    states = []

    def walk(node):
        if isinstance(node, dict):
            for name, child in node.items():
                if name == "stringUnit" and isinstance(child, dict):
                    states.append(child.get("state"))
                else:
                    walk(child)
    walk(localization)
    return states


def forms(text):
    """(label, string, plural category or None, substitution name or None) for every string in a text."""
    if isinstance(text, str):
        return [("value", text, None, None)]
    if not isinstance(text, dict):
        return []
    if "plural" in text:
        return [(f"plural.{c}", v, c, None) for c, v in _ordered(text["plural"])]
    result = [("value", text.get("value"), None, None)]
    for name, sub in sorted(text.get("substitutions", {}).items()):
        result += [(f"{name}.{c}", v, c, name) for c, v in _ordered(sub.get("plural", {}))]
    return result


def _ordered(plural):
    return sorted(plural.items(), key=lambda item: PLURAL_ORDER.index(item[0]) if item[0] in PLURAL_ORDER else 99)


def plural_blocks(text):
    """(label, {category: string}) for each plural variation set in a text."""
    if isinstance(text, dict) and "plural" in text:
        return [("plural", text["plural"])]
    if isinstance(text, dict):
        return [(f"substitution {name}", sub.get("plural", {})) for name, sub in sorted(text.get("substitutions", {}).items())]
    return []


# MARK: Format specifiers

SPECIFIER = re.compile(
    r"%(?:(?P<subpos>\d+)\$)?#@(?P<sub>[A-Za-z_][A-Za-z0-9_]*)@"      # substitution token %#@cells@ / %2$#@cells@
    r"|(?P<percent>%%)"
    r"|(?P<arg>%arg)"
    r"|%(?:(?P<pos>\d+)\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
    r"(?P<conv>(?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoOfFeEgGaAcCsSp])")
INTEGER = re.compile(r"(?:hh|h|ll|l|q|z|t|j)?[dDiuUxXoO]$")
TYPE_NAMES = {"@": "text", "f": "number", "g": "number", "e": "number", "c": "character", "s": "C string"}


def type_name(conversion):
    return "integer" if INTEGER.match(conversion) else TYPE_NAMES.get(conversion[-1], conversion)


class Specifiers:
    """The format specifiers of one string: argument number -> conversion, as Foundation consumes them."""

    def __init__(self, string, substitutions=None):
        self.args = {}
        self.positional = 0
        self.sequential = 0
        self.percent = 0
        self.arg_tokens = 0
        self.tokens = []
        self.conflicts = []
        self.unknown_substitutions = []
        self.misnumbered = []
        next_arg = 1
        for match in SPECIFIER.finditer(string or ""):
            if match.group("percent"):
                self.percent += 1
                continue
            if match.group("arg"):
                self.arg_tokens += 1
                continue
            if match.group("sub"):
                name = match.group("sub")
                position = match.group("subpos")
                sub = (substitutions or {}).get(name)
                if sub is None:
                    self.unknown_substitutions.append(name)
                    sub = {}
                conversion = sub.get("formatSpecifier") or "?"
                if position:
                    number = int(position)
                    self.positional += 1
                else:                                       # a bare %#@name@ takes the next argument, like %@
                    number = next_arg
                    next_arg += 1
                    self.sequential += 1
                if sub and sub.get("argNum") != number:
                    self.misnumbered.append(name)
            else:
                conversion = match.group("conv")
                if match.group("pos"):
                    number = int(match.group("pos"))
                    self.positional += 1
                else:
                    number = next_arg
                    next_arg += 1
                    self.sequential += 1
            self.tokens.append(match.group(0))
            if number in self.args and self.args[number] != conversion:
                self.conflicts.append(number)
            self.args[number] = conversion

    @property
    def mixed(self):
        return self.positional and self.sequential


def argument_map(text):
    """Every argument of a text (all forms): {argument number: conversion}, and per-form Specifiers."""
    subs = text.get("substitutions", {}) if isinstance(text, dict) else {}
    per_form = []
    union = {}
    for label, string, category, sub in forms(text):
        specs = Specifiers(string, subs)
        if sub is not None:                                  # %arg is the substitution's own argument
            owner = subs[sub]
            if specs.arg_tokens:
                specs.args[owner.get("argNum")] = owner.get("formatSpecifier")
        per_form.append((label, string, category, sub, specs))
        union.update(specs.args)
    return union, per_form


def placeholders(text):
    """The English placeholders for translators: [{"arg": 1, "specifier": "%@", "type": "text"}, …]."""
    union, per_form = argument_map(text)
    plural_args = set()
    if isinstance(text, dict) and "plural" in text:
        plural_args = {n for n, c in union.items() if INTEGER.match(c or "")}
    if isinstance(text, dict):
        plural_args |= {sub.get("argNum") for sub in text.get("substitutions", {}).values()}
    result = []
    for number in sorted(union):
        conversion = union[number]
        item = {"arg": number, "specifier": f"%{conversion}", "type": type_name(conversion or "?")}
        if number in plural_args:
            item["plural"] = True
        result.append(item)
    return result


# MARK: Fixed-width surfaces

# How export.py marks keys shown in fixed-width places. The comment of every key starts with its surface
# ("Notch flash: …", "Settings ▸ Tray: …"); the rules below read that comment, first match wins. Widths come
# from DESIGN.md: the compact wing's slots (§9.1, `SlotWidth`: medium 68u − 20u = 48 pt of content at notch
# unit 1, wide 92u − 20u = 72 pt; FlashLabelFitTests and BandCopyTests measure them from 0.8u to 1.25u), the
# Join capsule (§9.2, 34 × 20 pt), the open panel's header tabs (§6.2: the tab track shares a 140-pt side zone
# at the 14″ minimum and collapses to icons), chips and segmented pickers (capsules sized to their text, sharing a
# row), and the 2-cell widgets (§6.7: 120 pt wide, ≈ 96 pt of content). Text that only VoiceOver speaks, tooltips
# and Settings search keywords are never constrained. `ratio` is the length ratio over English (in display
# columns, CJK counted double) above which validate.py warns when there is no `budget`; `budget` is a rough number of
# display columns (≈ 6 pt each) the place holds. These are warnings only: the fit tests measure the real widths.
_VOICE_ALWAYS = re.compile(r"^(voiceover|settings search)|\(voiceover\)|tooltip|search (keyword|words)", re.IGNORECASE)
_VOICE_UNLESS_SHOWN = re.compile(r"voiceover (label|value|hint|action|announcement)", re.IGNORECASE)
SURFACE_RULES = [
    # (kind, pattern, maxWidthPt, hint, ratio, budget in display columns or None)
    ("wing", re.compile(r"\bwings?\b|compact wing|notch flash|in the notch band|^notch: short word", re.I),
     48, "Compact wing: ≤ 48 pt at notch unit 1 (medium slot; a flash word may use the 72-pt wide slot) in the "
         "13-pt rounded compact style, about 6–8 letters. Measured by FlashLabelFitTests / BandCopyTests.", 1.15, 8),
    ("explicit", re.compile(r"at most (\d+) ?pt", re.I), None, "At most {0} pt (stated in the comment).", 1.15, None),
    ("explicit", re.compile(r"≤ ?(\d+) (?:characters|letters)", re.I), None, "At most {0} characters (stated in the comment).", 1.2,
     None),
    ("capsule", re.compile(r"\bjoin capsule\b", re.I), 34,
     "Capsule button (Join: 34 × 20 pt in the band, sized to the word in rows): one short word.", 1.2, 7),
    ("short", re.compile(r"\bkeep it (as )?short\b|\bvery short\b|\bas short as possible\b|\bone short word\b|"
                         r"\ba word or two\b", re.I),
     None, "The comment asks for a very short text: one or two short words.", 1.3, 10),
    ("tab", re.compile(r"\(tab\)|\btab\b", re.I), 140,
     "Header tab: up to five tabs share a 140-pt zone; titles that do not fit collapse to icons. Keep ≤ ~12 characters.",
     1.4, 12),
    ("chip", re.compile(r"\bchips?\b(?! row)", re.I), None,
     "Chip (capsule button sized to its text, several share a row): one or two short words, ≈ 16 characters.", 1.4, 16),
    ("segment", re.compile(r"\bsegment\b|picker segment", re.I), None,
     "Segment of a segmented picker: shares the row with its siblings; one or two short words.", 1.4, 12),
    ("column", re.compile(r"column header", re.I), None, "Table column header: one or two words.", 1.4, 12),
    ("widget-2", re.compile(r"widget, 2 cells|^(mirror|timer|airdrop) widget: (?!.*\bmenu\b)", re.I), 96,
     "2-cell widget: ≈ 96 pt of content width; short phrases, longer text truncates.", 1.4, None),
]


def surface(comment):
    """The comment's surface prefix ("Settings ▸ Tray"), or None."""
    if comment and ":" in comment:
        return comment.split(":", 1)[0].strip()
    return None


def constraint(comment):
    """(constrained, {"kind", "maxWidthPt", "hint", "ratio"} or None) for a key's comment."""
    comment = comment or ""
    if _VOICE_ALWAYS.search(comment) or (_VOICE_UNLESS_SHOWN.search(comment)
                                         and not re.search(r"\bwings?\b|notch flash|\bchip\b|segment", comment, re.I)):
        return False, None
    for kind, pattern, width, hint, ratio, budget in SURFACE_RULES:
        match = pattern.search(comment)
        if not match:
            continue
        if kind == "explicit":
            number = int(match.group(1))
            in_points = "pt" in match.group(0)
            return True, {"kind": kind, "maxWidthPt": number if in_points else None, "hint": hint.format(number),
                          "ratio": ratio, "budget": max(number // 6, 4) if in_points else number}
        return True, {"kind": kind, "maxWidthPt": width, "hint": hint, "ratio": ratio, "budget": budget}
    return False, None


def display_width(string):
    """A rough display width: CJK, Hangul and full-width characters count double; placeholders count 3."""
    string = SPECIFIER.sub("xxx", string or "")
    width = 0
    for character in string:
        code = ord(character)
        if (0x1100 <= code <= 0x115F or 0x2E80 <= code <= 0xA4CF or 0xAC00 <= code <= 0xD7A3
                or 0xF900 <= code <= 0xFAFF or 0xFE30 <= code <= 0xFE4F or 0xFF00 <= code <= 0xFF60):
            width += 2
        elif not (0x0300 <= code <= 0x036F or 0x0E31 == code or 0x0E34 <= code <= 0x0E3A or 0x0E47 <= code <= 0x0E4E):
            width += 1                                       # combining marks (incl. Thai vowels/tones) take no column
    return width
