#!/usr/bin/env python3
"""Git merge driver for String Catalogs (.xcstrings).

Parallel work packages add keys to the same catalog; a line-based merge turns
that into JSON conflicts. This driver merges per key and per language instead.

Install once per clone (scripts/lib.sh does not do it for you):

    git config merge.xcstrings.name "String Catalog union merge"
    git config merge.xcstrings.driver "python3 scripts/merge-xcstrings.py %O %A %B"

`.gitattributes` maps `*.xcstrings` to this driver. Rules, per key:
- only one side touched it          -> take that side
- both sides changed it differently -> merge its localizations language by
  language; a language changed on both sides keeps ours and the merge is
  reported as a conflict (exit 1) so a human looks at it
- deleted on one side, untouched on the other -> deleted
- deleted on one side, changed on the other -> kept with the change, reported
  as a conflict (exit 1): usually the key was renamed and the change is stale
The result is written to %A (ours) in Xcode's formatting.
"""

import json
import sys


def load(path):
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except FileNotFoundError:
        return {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
    if not text.strip():
        return {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
    return json.loads(text)


def xcode_json(value, indent=""):
    """Serialise like Xcode/xcstringstool: sorted keys, ' : ' separators, 2-space indent."""
    inner = indent + "  "
    if isinstance(value, dict):
        if not value:
            return "{\n" + indent + "}"
        items = [inner + json.dumps(k, ensure_ascii=False) + " : " + xcode_json(value[k], inner) for k in sorted(value)]
        return "{\n" + ",\n".join(items) + "\n" + indent + "}"
    if isinstance(value, list):
        if not value:
            return "[\n\n" + indent + "]"
        return "[\n" + ",\n".join(inner + xcode_json(v, inner) for v in value) + "\n" + indent + "]"
    return json.dumps(value, ensure_ascii=False)


def merge_entry(key, base, ours, theirs, conflicts):
    merged = dict(ours)
    for field, value in theirs.items():
        if field == "localizations":
            continue
        if field not in ours or (base.get(field) == ours.get(field) and value != base.get(field)):
            merged[field] = value
    base_locs = base.get("localizations", {})
    our_locs = ours.get("localizations", {})
    their_locs = theirs.get("localizations", {})
    locs = dict(our_locs)
    for language, value in their_locs.items():
        if language not in our_locs:
            locs[language] = value
        elif our_locs[language] != value:
            if base_locs.get(language) == our_locs[language]:
                locs[language] = value
            elif base_locs.get(language) != value:
                conflicts.append(f"{key} [{language}]")
    if locs:
        merged["localizations"] = locs
    return merged


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("usage: merge-xcstrings.py BASE OURS THEIRS\n")
        return 2
    base_path, ours_path, theirs_path = sys.argv[1:]
    base, ours, theirs = load(base_path), load(ours_path), load(theirs_path)
    base_strings = base.get("strings", {})
    our_strings = ours.get("strings", {})
    their_strings = theirs.get("strings", {})

    conflicts = []
    result = {}
    for key in sorted(set(our_strings) | set(their_strings) | set(base_strings)):
        in_base, in_ours, in_theirs = key in base_strings, key in our_strings, key in their_strings
        if in_ours and in_theirs:
            b, o, t = base_strings.get(key, {}), our_strings[key], their_strings[key]
            if o == t or t == b:
                result[key] = o
            elif o == b:
                result[key] = t
            else:
                result[key] = merge_entry(key, b, o, t, conflicts)
        elif in_ours:
            if not in_base:
                result[key] = our_strings[key]                  # added by us
            elif base_strings[key] != our_strings[key]:
                result[key] = our_strings[key]                  # we changed it, they deleted it
                conflicts.append(f"{key} (changed here, deleted on the other branch)")
            # else: they deleted a key we left alone -> deleted
        elif in_theirs:
            if not in_base:
                result[key] = their_strings[key]                # added by them
            elif base_strings[key] != their_strings[key]:
                result[key] = their_strings[key]                # they changed it, we deleted it
                conflicts.append(f"{key} (deleted here, changed on the other branch)")
            # else: we deleted a key they left alone -> deleted

    merged = dict(ours)
    merged["strings"] = result
    try:
        with open(ours_path, "rb") as handle:
            trailing_newline = handle.read().endswith(b"\n")
    except FileNotFoundError:
        trailing_newline = True
    with open(ours_path, "w", encoding="utf-8") as handle:
        handle.write(xcode_json(merged) + ("\n" if trailing_newline else ""))

    if conflicts:
        sys.stderr.write("xcstrings: resolve by hand: " + "; ".join(conflicts) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
