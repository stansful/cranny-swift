#!/usr/bin/env bash
# Launch smoke test of build/Cranny.app without UI: `Cranny --diagnostics <json>` writes a report and quits.
# Checks: every CrannyKit resource bundle is embedded, the media bridge dylib is present, the Edit menu exists,
# and CrannyEffects' compiled shader library (default.metallib) loads through Bundle.module inside the app.
#
#   scripts/smoke.sh                 # uses build/Cranny.app
#   APP=/path/Cranny.app scripts/smoke.sh
source "$(dirname "$0")/lib.sh"

APP="${APP:-$BUILD_DIR/Cranny.app}"
[[ -d "$APP" ]] || die "$APP not found; run scripts/build.sh first"
OUT="$BUILD_DIR/logs/diagnostics.json"
mkdir -p "$BUILD_DIR/logs"; rm -f "$OUT"
# No `timeout` on macOS: perl's alarm kills the app if it hangs (exit 142).
/usr/bin/perl -e 'alarm shift; exec @ARGV' 60 "$APP/Contents/MacOS/Cranny" --diagnostics "$OUT" >/dev/null 2>&1 \
  || die "Cranny --diagnostics failed or timed out"
[[ -s "$OUT" ]] || die "no diagnostics written"
METALLIB="$APP/Contents/Resources/CrannyKit_CrannyEffects.bundle/Contents/Resources/default.metallib"
[[ -f "$METALLIB" ]] || die "CrannyEffects' default.metallib is not in the app (is the Metal Toolchain installed?)"
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
