#!/usr/bin/env bash
# Launch smoke test of build/Cranny.app without UI: `Cranny --diagnostics <json>` writes a report and quits.
# Checks: every CrannyKit resource bundle is embedded, the media bridge dylib is present, the Edit menu exists,
# CrannyEffects' compiled shader library (default.metallib) loads through Bundle.module inside the app, no
# shader source or header ships, the signed entitlements and usage strings match the permission matrix, and the
# main bundle advertises every language of scripts/lib/l10n/languages.json (CFBundleLocalizations).
#
#   scripts/lib/smoke.sh                 # uses build/Cranny.app
#   APP=/path/Cranny.app scripts/lib/smoke.sh
# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/common.sh"

APP="${APP:-$BUILD_DIR/Cranny.app}"
[[ -d "$APP" ]] || die "$APP not found; run scripts/lib/build.sh first"
OUT="$BUILD_DIR/logs/diagnostics.json"
mkdir -p "$BUILD_DIR/logs"; rm -f "$OUT"
# No `timeout` on macOS: perl's alarm kills the app if it hangs (exit 142).
# `--diagnostics` writes no preference; a Debug build also reads its settings from a suite of its own
# (`--qa-defaults-suite`, docs/CONTRIBUTING.md ▸ Visual QA hooks), never from the user's; Release ignores the switch.
/usr/bin/perl -e 'alarm shift; exec @ARGV' 60 "$APP/Contents/MacOS/Cranny" --qa-defaults-suite app.cranny.Cranny.smoke \
  --diagnostics "$OUT" >/dev/null 2>&1 || die "Cranny --diagnostics failed or timed out"
[[ -s "$OUT" ]] || die "no diagnostics written"
METALLIB="$APP/Contents/Resources/CrannyKit_CrannyEffects.bundle/Contents/Resources/default.metallib"
[[ -f "$METALLIB" ]] || die "CrannyEffects' default.metallib is not in the app (is the Metal Toolchain installed?)"
# Only the compiled library ships: no shader sources or headers in any bundle (ARCHITECTURE.md §8.8).
sources="$(find "$APP/Contents" \( -name '*.metal' -o -name '*.h' \) -print | head -5)"
[[ -z "$sources" ]] || die "shader sources or headers are in the app: $sources"
# Privacy surface (ARCHITECTURE.md §7.13): only the hardened-runtime entitlements a feature uses, each with its
# usage string, and every usage string translated into every shipped language (scripts/lib/l10n/languages.json "shipped").
# The Live visualizer's process tap is System Audio Recording:
# NSAudioCaptureUsageDescription and no entitlement; nothing records the microphone, so neither
# device.audio-input nor NSMicrophoneUsageDescription ships.
ENTITLEMENTS="$BUILD_DIR/logs/entitlements.plist"
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null || die "codesign could not read $APP's entitlements"
/usr/bin/python3 -I - "$APP" "$ENTITLEMENTS" "$ROOT/scripts/lib/l10n/languages.json" <<'PY' || die "the app's entitlements, usage strings or languages are wrong (see above)"
import json, os, plistlib, subprocess, sys
app, entitlements_path, languages_path = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(entitlements_path, "rb").read()
entitlements = {k for k, v in (plistlib.loads(raw) if raw.strip() else {}).items() if v}
info = plistlib.load(open(os.path.join(app, "Contents/Info.plist"), "rb"))
languages = json.load(open(languages_path, encoding="utf-8"))
shipped = [l["code"] for l in languages if l.get("shipped") and not l.get("source")]

def info_strings(code):
    # Xcode writes the localized InfoPlist.strings as UTF-16 XML that claims UTF-8: let plutil read it.
    path = os.path.join(app, f"Contents/Resources/{code}.lproj/InfoPlist.strings")
    return json.loads(subprocess.run(["/usr/bin/plutil", "-convert", "json", "-o", "-", path], check=True,
                                     capture_output=True).stdout) if os.path.exists(path) else {}
# entitlement -> the usage string its TCC prompt shows
needs = {
    "com.apple.security.automation.apple-events": "NSAppleEventsUsageDescription",
    "com.apple.security.device.camera": "NSCameraUsageDescription",
    "com.apple.security.personal-information.calendars": "NSCalendarsFullAccessUsageDescription",
}
debug_only = {"com.apple.security.get-task-allow"}
problems = [f"unexpected entitlement {e}" for e in sorted(entitlements - set(needs) - debug_only)]
problems += [f"{e} without {key}" for e, key in needs.items() if e in entitlements and not info.get(key)]
if not info.get("NSAudioCaptureUsageDescription"):
    problems.append("NSAudioCaptureUsageDescription missing (the Live visualizer's tap records silence without it)")
if "NSMicrophoneUsageDescription" in info:
    problems.append("NSMicrophoneUsageDescription present, but nothing records the microphone")
usage = sorted(k for k in info if k.endswith("UsageDescription"))
for code in shipped:
    translated = info_strings(code)
    problems += [f"{k} has no {code} translation" for k in usage if not translated.get(k)]
advertised = info.get("CFBundleLocalizations", [])
missing = [l["code"] for l in languages if l["code"] not in advertised]
if missing:
    problems.append("CFBundleLocalizations lacks " + ", ".join(missing) + " (App/Info.plist; macOS would show the "
                    "packages' translations in English)")
problems += [f"CFBundleLocalizations has {c}, which is not in scripts/lib/l10n/languages.json"
             for c in advertised if c not in {l["code"] for l in languages}]
print("\n".join(problems) or "privacy OK: entitlements %s; %d usage strings, all in %s; %d languages advertised"
      % (", ".join(sorted(e.rsplit(".", 1)[-1] for e in entitlements - debug_only)), len(usage), ", ".join(shipped),
         len(advertised)))
sys.exit(1 if problems else 0)
PY
expected=$(find "$PACKAGE_DIR/Sources" -mindepth 2 -maxdepth 2 -name Resources -type d | wc -l | tr -d ' ')
/usr/bin/python3 -I - "$OUT" "$expected" <<'PY' || die "smoke test failed (see $OUT)"
import json, sys
r = json.load(open(sys.argv[1])); expected = int(sys.argv[2])
problems = []
if len(r.get("resourceBundles", [])) != expected: problems.append(f"bundles {len(r.get('resourceBundles', []))} != {expected}")
if r.get("bridge", "(missing)") == "(missing)": problems.append("media bridge dylib missing")
if not any(len(items) >= 4 for m in r.get("mainMenu", []) for items in m.values()): problems.append("no Edit menu key equivalents")
shaders = r.get("shaders", "(missing key)")
if shaders != "ok":
    if shaders.startswith(("no Metal device", "CrannyDisableShaders")):
        print("note: Metal effects off here (%s); the SwiftUI fallbacks are used" % shaders)
    else:
        problems.append("shader library: " + shaders)
print("\n".join(problems) or "smoke OK: %d bundles, bridge present, Edit menu present, shaders %s" % (expected, shaders))
sys.exit(1 if problems else 0)
PY
log "Smoke test passed ($OUT)"
