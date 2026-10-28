#!/usr/bin/env bash
# Tests of scripts/build-release.sh against a fake tree in a temp dir (TMPDIR), never this repository and never the
# real Xcode. Each fake root has the script, scripts/lib/{common,version}.sh and a VERSION file, plus stubs:
#   scripts/lib/{build,smoke,dist,check-modules,name-probe,sync-strings}.sh log how they ran and the environment they
#     got; build.sh writes a fake build/Cranny.app (Info.plist, a binary naming its architectures, a signature) and
#     dist.sh the release files into dist/, as the STUB_* variables say
#   scripts/lib/lint-copy.py and scripts/lib/l10n/validate.py are real Python (the script runs them with
#     /usr/bin/python3 -I) that log their arguments and fail when STUB_FAIL names them
#   plutil, lipo, codesign and xcrun, first on PATH, read the fake app; python3 and xcodebuild there only fail, so
#     the script must use neither
# sha256sum or shasum are the real ones. Runs the script under $TEST_BASH (default: bash from PATH).
#
#   scripts/tests/build-release_test.sh          KEEP=1 keeps the temp dir
#
# Needs a working /usr/bin/python3 (macOS, the GitHub ubuntu runner); without one it prints a skip line and exits 0.
# Prints 'ok <name>' / 'not ok <name>: <why>' and exits non-zero on a failure.
# The conditions of check() are eval'd when it runs: single quotes on purpose, and the variables they read are
# set outside them.
# shellcheck disable=SC2016,SC2034
set -u
# SIGPIPE ignored, as on the GitHub runner (every step inherits that from its Node.js), for these tests and the
# scripts they run: a reader that stops early makes its writer fail with "Broken pipe" there instead of dying quietly
trap "" PIPE

HERE="$(cd "$(dirname "$0")" && pwd -P)"
TREE="$(cd "$HERE/../.." && pwd -P)"
BASH_BIN="${TEST_BASH:-bash}"

# build-release.sh runs its Python checks with /usr/bin/python3, whatever PATH says
if [ ! -x /usr/bin/python3 ] || ! /usr/bin/python3 -I -c '' >/dev/null 2>&1; then
  echo "# skip scripts/tests/build-release_test.sh: no working /usr/bin/python3, which build-release.sh runs its checks with"
  exit 0
fi

# no temp dir stops here: an empty WORK would make the current directory (the checkout) the work dir, and the
# EXIT trap would delete it
if ! WORK="$(mktemp -d "${TMPDIR:-/tmp}/build-release-test.XXXXXX")" || ! WORK="$(cd "$WORK" && pwd -P)"; then
  echo "not ok no temp dir in ${TMPDIR:-/tmp}"
  exit 1
fi
if [ -z "${KEEP:-}" ]; then trap 'rm -rf "$WORK"' EXIT; else echo "# work dir: $WORK"; fi

V=1.2.3
ASSETS="Cranny-$V.dmg Cranny-$V.zip Cranny-$V.sha256"
ID="Developer ID Application: Jane Doe (TEAMID1234)"

# The environment of every run; a test changes a variable for one run with `VAR=value br ...`
export HOME="$WORK/home" STUB_LOG="$WORK/stub.log" STUB_DIR="$WORK/stubs" PATH="$WORK/bin:$PATH"
unset SIGN_IDENTITY TEAM_ID NOTARY_PROFILE NOTARY_KEYCHAIN BUILD_NUMBER JOBS CDPATH
unset CONFIGURATION ARCHS MARKETING_VERSION APP REBUILD TEST CHECK ALLOW_WARNINGS
unset STUB_FAIL STUB_NOAPP STUB_BUILT_VERSION STUB_BUILD_NUMBER STUB_ARCHS STUB_SIGNATURE STUB_TEAM STUB_UNSTAPLED STUB_DIST
mkdir -p "$HOME" "$WORK/bin" "$STUB_DIR"

pass=0 fail=0
ok() {
  echo "ok $1"
  pass=$((pass + 1))
}
nok() {
  echo "not ok $1: $2"
  fail=$((fail + 1))
}
check() {
  if eval "$2"; then ok "$1"; else nok "$1" "rc=$RC; condition: $2; output:
$OUT
stubs:
$(cat "$STUB_LOG" 2>/dev/null)"; fi
}
has() { case $OUT in *"$1"*) return 0 ;; esac; return 1; }
# has_line <line>: the output has exactly this line
has_line() { grep -qxF -- "$1" <<<"$OUT"; }
logged() { grep -qxF -- "$1" "$STUB_LOG" 2>/dev/null; }
# ran <stub>: the stub ran (its "run <stub> [args]" line)
ran() { grep -Eq "^run $1( |\$)" "$STUB_LOG" 2>/dev/null; }
nothing_ran() { [ ! -e "$STUB_LOG" ]; }
# order: the stubs that ran, in order, one line
order() { sed -n 's/^run \([^ ]*\).*/\1/p' "$STUB_LOG" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
# refused <message>: the script stopped with this error after the build, printing no summary
refused() { [ "$RC" = 1 ] && has "error:" && has "$1" && ran dist && ! has "Release $V (build"; }
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}
# listing <dir>: the names in dir, hidden ones too, sorted, one line
# shellcheck disable=SC2012 # the release files have plain names
listing() { (cd "$1" && ls -A | LC_ALL=C sort | tr '\n' ' '); }
sorted() { printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' '; }
# size_line <dir> <file>: the summary's line of a release file
size_line() { printf '  %11s  %s' "$(wc -c <"$1/$2" | tr -d ' ')" "$2"; }
# same_files <dir1> <dir2>: the release files in both are the same, and the sums hold in dir2
same_files() {
  local f
  for f in $ASSETS; do cmp -s "$1/$f" "$2/$f" || return 1; done
  (cd "$2" && sha256 -c "Cranny-$V.sha256" >/dev/null 2>&1)
}
# stale_dist: release files of $V from an older build in dist/; stale_kept: they are still there
stale_dist() {
  local f
  mkdir -p "$DIST"
  for f in $ASSETS; do echo stale >"$DIST/$f"; done
}
stale_kept() {
  local f
  for f in $ASSETS; do [ "$(cat "$DIST/$f" 2>/dev/null)" = stale ] || return 1; done
}

echo "# scripts/build-release.sh under $("$BASH_BIN" -c 'echo "bash $BASH_VERSION"')"

# --- the stubs of scripts/lib
cat >"$STUB_DIR/stub-lib.sh" <<'EOF'
# Sourced by the scripts/lib stubs. stub_run <name> [args...]: logs "run <name> [args...]", then "env <name>
# VAR=value" (or "env <name> VAR unset") for every variable build-release.sh sets or passes on; exits 1 when
# STUB_FAIL names the stub
stub_run() {
  stub_name=$1
  shift
  echo "run $stub_name${*:+ $*}" >>"$STUB_LOG"
  for k in CONFIGURATION ARCHS MARKETING_VERSION APP REBUILD TEST JOBS CHECK ALLOW_WARNINGS SIGN_IDENTITY TEAM_ID NOTARY_PROFILE BUILD_NUMBER; do
    if eval "[ -n \"\${$k+x}\" ]"; then
      eval "v=\${$k}"
      echo "env $stub_name $k=$v"
    else
      echo "env $stub_name $k unset"
    fi
  done >>"$STUB_LOG"
  if [ "${STUB_FAIL:-}" = "$stub_name" ]; then
    echo "$stub_name: failed (stub)" >&2
    exit 1
  fi
}
# plist_get <key> <plist>: the string value of key in the fake Info.plist; fails without one
plist_get() {
  awk -v key="<key>$1</key>" '
    want { if (match($0, /<string>[^<]*<\/string>/)) { print substr($0, RSTART + 8, RLENGTH - 17); found = 1 }; exit }
    index($0, key) { want = 1 }
    END { if (!found) exit 1 }' "$2"
}
EOF
for s in check-modules name-probe sync-strings smoke; do
  cat >"$STUB_DIR/$s.sh" <<EOF
#!/bin/sh
# scripts/lib/$s.sh stub: logs how it ran; fails when STUB_FAIL=$s
. "\$STUB_DIR/stub-lib.sh"
stub_run $s "\$@"
EOF
done
cat >"$STUB_DIR/build.sh" <<'EOF'
#!/bin/sh
# scripts/lib/build.sh stub: logs how it ran and what dist/ held then, and writes build/Cranny.app as a build with
# that environment would: Info.plist (CFBundleShortVersionString MARKETING_VERSION, else VERSION; CFBundleVersion
# BUILD_NUMBER, else 1), Contents/MacOS/Cranny ("archs=" ARCHS, else both; the lipo stub prints it) and the lines
# the codesign stub prints (Developer ID with SIGN_IDENTITY and TEAM_ID, else ad-hoc). Overrides: STUB_NOAPP=1 (no
# app), STUB_BUILT_VERSION and STUB_BUILD_NUMBER (a value, or "none": no such key), STUB_ARCHS, STUB_SIGNATURE
# (adhoc or devid), STUB_TEAM (the Developer ID team)
. "$STUB_DIR/stub-lib.sh"
root=$(cd "$(dirname "$0")/../.." && pwd -P)
stub_run build "$@"
echo "build saw dist: $(cd "$root/dist" 2>/dev/null && ls -A | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" >>"$STUB_LOG"
app="$root/build/Cranny.app"
rm -rf "$app"
[ -z "${STUB_NOAPP:-}" ] || exit 0
mkdir -p "$app/Contents/MacOS" "$app/Contents/_CodeSignature"
v=${STUB_BUILT_VERSION-${MARKETING_VERSION:-$(tr -d '[:space:]' <"$root/VERSION")}}
b=${STUB_BUILD_NUMBER-${BUILD_NUMBER:-1}}
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  echo '<plist version="1.0">'
  echo '<dict>'
  printf '\t<key>CFBundleIdentifier</key>\n\t<string>app.cranny.Cranny</string>\n'
  [ "$v" = none ] || printf '\t<key>CFBundleShortVersionString</key>\n\t<string>%s</string>\n' "$v"
  [ "$b" = none ] || printf '\t<key>CFBundleVersion</key>\n\t<string>%s</string>\n' "$b"
  echo '</dict>'
  echo '</plist>'
} >"$app/Contents/Info.plist"
printf 'archs=%s\n' "${STUB_ARCHS-${ARCHS:-arm64 x86_64}}" >"$app/Contents/MacOS/Cranny"
kind=${STUB_SIGNATURE:-}
if [ -z "$kind" ]; then
  if [ -n "${SIGN_IDENTITY:-}" ]; then kind=devid; else kind=adhoc; fi
fi
if [ "$kind" = adhoc ]; then
  printf 'Signature=adhoc\nTeamIdentifier=not set\n'
else
  echo 'Signature size=9046'
  echo "Authority=${SIGN_IDENTITY:-Developer ID Application: Someone Else (OTHERTEAM9)}"
  echo 'Authority=Developer ID Certification Authority'
  echo 'Authority=Apple Root CA'
  echo 'Timestamp=28 Oct 2026 at 21:00:00'
  echo "TeamIdentifier=${STUB_TEAM:-${TEAM_ID:-OTHERTEAM9}}"
fi >"$app/Contents/_CodeSignature/stub"
EOF
cat >"$STUB_DIR/dist.sh" <<'EOF'
#!/bin/sh
# scripts/lib/dist.sh stub: logs how it ran, then writes Cranny-<the app's version>.{zip,dmg} and their sums
# (.sha256, as shasum -a 256 writes them) into dist/; nothing without an app. STUB_DIST: none (no files), nozip,
# emptydmg, nosums, emptysums, othernames (the sums of the zip and of Cranny-0.9.0.dmg, which it writes too),
# onename (of the zip only), twice (the zip twice), binary (sums with the binary-mode "*"), mismatch (the zip
# changes after the sums)
. "$STUB_DIR/stub-lib.sh"
root=$(cd "$(dirname "$0")/../.." && pwd -P)
stub_run dist "$@"
app="$root/build/Cranny.app"
[ -d "$app" ] || exit 0
v=$(plist_get CFBundleShortVersionString "$app/Contents/Info.plist")
n="Cranny-$v"
mkdir -p "$root/dist"
cd "$root/dist" || exit 1
rm -f "$n.zip" "$n.dmg"
mode=${STUB_DIST:-}
[ "$mode" != none ] || exit 0
printf 'zip of Cranny %s\n' "$v" >"$n.zip"
printf 'disk image of Cranny %s, a bit larger\n' "$v" >"$n.dmg"
sums() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
case $mode in
othernames)
  cp "$n.dmg" Cranny-0.9.0.dmg
  sums "$n.zip" Cranny-0.9.0.dmg
  ;;
onename) sums "$n.zip" ;;
twice) sums "$n.zip" "$n.dmg" "$n.zip" ;;
binary) sums "$n.zip" "$n.dmg" | sed 's/  / */' ;;
*) sums "$n.zip" "$n.dmg" ;;
esac >"$n.sha256"
case $mode in
nozip) rm "$n.zip" ;;
emptydmg) : >"$n.dmg" ;;
nosums) rm "$n.sha256" ;;
emptysums) : >"$n.sha256" ;;
mismatch) echo changed >>"$n.zip" ;;
esac
EOF
cat >"$STUB_DIR/check.py" <<'EOF'
# Stub of scripts/lib/lint-copy.py and scripts/lib/l10n/validate.py (its name is the file's): logs its arguments
# and whether Python runs isolated (-I); fails when STUB_FAIL names it
import os
import sys

name = os.path.basename(sys.argv[0])[:-3]
with open(os.environ["STUB_LOG"], "a") as log:
    log.write("run %s%s\n" % (name, "".join(" " + a for a in sys.argv[1:])))
    log.write("env %s isolated=%d\n" % (name, sys.flags.isolated))
if os.environ.get("STUB_FAIL") == name:
    sys.stderr.write("%s: failed (stub)\n" % name)
    sys.exit(1)
EOF
chmod +x "$STUB_DIR"/*.sh

# --- the stubs on PATH
cat >"$WORK/bin/plutil" <<'EOF'
#!/bin/sh
# plutil -extract KEY raw -o - FILE: the value of KEY in the fake Info.plist
echo "tool plutil $*" >>"$STUB_LOG"
. "$STUB_DIR/stub-lib.sh"
if [ $# != 6 ] || [ "$1" != -extract ] || [ "$3 $4 $5" != "raw -o -" ]; then
  echo "plutil stub: unexpected arguments: $*" >&2
  exit 64
fi
plist_get "$2" "$6" || {
  echo "$6: Could not extract value, error: No value at that key path or invalid key path: $2" >&2
  exit 1
}
EOF
cat >"$WORK/bin/lipo" <<'EOF'
#!/bin/sh
# lipo -archs FILE: the architectures the fake binary names; fails when STUB_FAIL=lipo
echo "tool lipo $*" >>"$STUB_LOG"
if [ $# != 2 ] || [ "$1" != -archs ]; then
  echo "lipo stub: unexpected arguments: $*" >&2
  exit 64
fi
if [ "${STUB_FAIL:-}" = lipo ] || [ ! -f "$2" ]; then
  echo "fatal error: lipo: can't figure out the architecture type of: $2" >&2
  exit 1
fi
sed -n 's/^archs=//p' "$2"
EOF
cat >"$WORK/bin/codesign" <<'EOF'
#!/bin/sh
# codesign --verify ... APP (fails when STUB_FAIL=verify) and codesign -dv / -dvv APP (prints the fake signature to
# stderr, as codesign does, the Authority lines only at -dvv; fails when STUB_FAIL=dv)
echo "tool codesign $*" >>"$STUB_LOG"
for a; do app=$a; done
sig="$app/Contents/_CodeSignature/stub"
case $1 in
--verify)
  if [ "${STUB_FAIL:-}" = verify ] || [ ! -f "$sig" ]; then
    echo "$app: a sealed resource is missing or invalid" >&2
    exit 1
  fi
  ;;
-dv | -dvv)
  if [ "${STUB_FAIL:-}" = dv ] || [ ! -f "$sig" ]; then
    echo "$app: code object is not signed at all" >&2
    exit 1
  fi
  {
    echo "Executable=$app/Contents/MacOS/Cranny"
    echo "Identifier=app.cranny.Cranny"
    echo "Format=app bundle with Mach-O universal (x86_64 arm64)"
    echo "CodeDirectory v=20500 size=1234 flags=0x10000(runtime) hashes=27+7 location=embedded"
    if [ "$1" = -dvv ]; then cat "$sig"; else grep -v '^Authority=' "$sig"; fi
    echo "Info.plist entries=31"
    echo "Sealed Resources version=2 rules=13 files=42"
    echo "Internal requirements count=1 size=180"
  } >&2
  ;;
*)
  echo "codesign stub: unexpected arguments: $*" >&2
  exit 64
  ;;
esac
EOF
cat >"$WORK/bin/xcrun" <<'EOF'
#!/bin/sh
# xcrun stapler validate PATH: fails for the app when STUB_UNSTAPLED=app, for a disk image when STUB_UNSTAPLED=dmg
echo "tool xcrun $*" >>"$STUB_LOG"
if [ $# != 3 ] || [ "$1 $2" != "stapler validate" ]; then
  echo "xcrun stub: unexpected arguments: $*" >&2
  exit 64
fi
case ${STUB_UNSTAPLED:-}:$3 in
app:*.app | dmg:*.dmg)
  echo "$3 does not have a ticket stapled to it." >&2
  exit 65
  ;;
esac
echo "Processing: $3"
echo "The validate action worked!"
EOF
for t in python3 xcodebuild; do
  cat >"$WORK/bin/$t" <<EOF
#!/bin/sh
# $t from PATH: the script must not run it
echo "run path-$t \$*" >>"\$STUB_LOG"
echo "$t: not in this test" >&2
exit 1
EOF
done
chmod +x "$WORK/bin"/*

# new_root <name> [version]: a fake tree ROOT with the script, its libraries, the stubs and VERSION; DIST is its
# dist/, APPDIR its build/Cranny.app
new_root() {
  ROOT="$WORK/$1"
  DIST="$ROOT/dist"
  APPDIR="$ROOT/build/Cranny.app"
  rm -rf "$ROOT"
  mkdir -p "$ROOT/scripts/lib/l10n"
  cp "$TREE/scripts/build-release.sh" "$ROOT/scripts/"
  cp "$TREE/scripts/lib/common.sh" "$TREE/scripts/lib/version.sh" "$ROOT/scripts/lib/"
  cp "$STUB_DIR/build.sh" "$STUB_DIR/smoke.sh" "$STUB_DIR/dist.sh" "$STUB_DIR/check-modules.sh" \
    "$STUB_DIR/name-probe.sh" "$STUB_DIR/sync-strings.sh" "$ROOT/scripts/lib/"
  cp "$STUB_DIR/check.py" "$ROOT/scripts/lib/lint-copy.py"
  cp "$STUB_DIR/check.py" "$ROOT/scripts/lib/l10n/validate.py"
  printf '%s\n' "${2:-$V}" >"$ROOT/VERSION"
}
# br [args...]: build-release.sh of ROOT, run from WORK with a fresh stub log; sets OUT and RC
br() {
  rm -f "$STUB_LOG"
  OUT="$(cd "$WORK" && "$BASH_BIN" "$ROOT/scripts/build-release.sh" "$@" 2>&1)"
  RC=$?
}

# --- a release build: ad-hoc signed, the release files in dist/, the summary
new_root main
stale_dist
echo old >"$DIST/Cranny-1.2.2.zip"
echo notes >"$DIST/notes.txt"
br
check "builds: exit 0" '[ $RC = 0 ]'
check "...first the languages: validate.py --shipped --release --quiet with /usr/bin/python3 -I (no python3 from PATH)" \
  'logged "run validate --shipped --release --quiet" && logged "env validate isolated=1" && ! ran path-python3 && has "Languages: every shipped language translated, none pending"'
check "...then build.sh, smoke.sh and dist.sh, once each; without --test no other checks, and no xcodebuild" \
  '[ "$(order)" = "validate build smoke dist" ]'
check "...build.sh: Release, both architectures, the version in VERSION, no signing variables" \
  'logged "env build CONFIGURATION=Release" && logged "env build ARCHS=arm64 x86_64" && logged "env build MARKETING_VERSION=$V" && logged "env build SIGN_IDENTITY unset" && logged "env build TEAM_ID unset" && logged "env build NOTARY_PROFILE unset" && logged "env build BUILD_NUMBER unset"'
check "...says what it builds" 'has "Building release $V: ad-hoc (users allow it once in System Settings > Privacy & Security)"'
check "...smoke.sh tests build/Cranny.app; dist.sh packages it as built (REBUILD=0)" \
  'logged "env smoke APP=$APPDIR" && logged "env dist REBUILD=0"'
check "...the old release files of $V are gone before the build; the other files in dist/ stay" \
  'logged "build saw dist: Cranny-1.2.2.zip notes.txt" && [ "$(listing "$DIST")" = "$(sorted $ASSETS Cranny-1.2.2.zip notes.txt)" ] && [ "$(cat "$DIST/notes.txt")" = notes ] && ! stale_kept'
check "...reads the app's version and build with plutil, its architectures with lipo" \
  'logged "tool plutil -extract CFBundleShortVersionString raw -o - $APPDIR/Contents/Info.plist" && logged "tool plutil -extract CFBundleVersion raw -o - $APPDIR/Contents/Info.plist" && logged "tool lipo -archs $APPDIR/Contents/MacOS/Cranny"'
check "...verifies the signature (codesign --verify --deep --strict), reads it with the authorities (codesign -dvv); no stapler check" \
  'logged "tool codesign --verify --deep --strict $APPDIR" && logged "tool codesign -dvv $APPDIR" && ! grep -q "^tool xcrun" "$STUB_LOG"'
check "...the summary: version, build and dist/, then every release file with its size" \
  'has_line "Release $V (build 1): $DIST" && has_line "$(size_line "$DIST" "Cranny-$V.dmg")" && has_line "$(size_line "$DIST" "Cranny-$V.zip")" && has_line "$(size_line "$DIST" "Cranny-$V.sha256")"'
check "...the signing and the architectures" \
  'has_line "Signing: ad-hoc (users allow it once in System Settings > Privacy & Security)" && ! has "team" && has_line "Architectures: arm64 x86_64"'
check "...the sums" \
  'has_line "Cranny-$V.sha256:" && has_line "  $(cd "$DIST" && sha256 "Cranny-$V.zip")" && has_line "  $(cd "$DIST" && sha256 "Cranny-$V.dmg")" && same_files "$DIST" "$DIST"'
check "...and the other files in dist/" 'has_line "$DIST also holds files that are not part of the release: Cranny-1.2.2.zip notes.txt"'
check "...nothing written outside the fake root, nothing but build/ and dist/ in it" \
  '[ -z "$(ls -A "$HOME")" ] && [ "$(listing "$ROOT")" = "$(sorted VERSION build dist scripts)" ]'

new_root 'my project'
br
check "a root path with a space builds" \
  '[ $RC = 0 ] && [ "$(listing "$DIST")" = "$(sorted $ASSETS)" ] && same_files "$DIST" "$DIST" && has_line "Release $V (build 1): $DIST" && ! has "also holds"'

# --- the caller's environment does not change the build
new_root forced
CONFIGURATION=Debug ARCHS=arm64 MARKETING_VERSION=9.9.9 APP=/elsewhere/Cranny.app REBUILD=1 br
check "CONFIGURATION=Debug ARCHS=arm64 MARKETING_VERSION=9.9.9 APP=/elsewhere REBUILD=1 exported: still Release, both archs, VERSION" \
  '[ $RC = 0 ] && logged "env build CONFIGURATION=Release" && logged "env build ARCHS=arm64 x86_64" && logged "env build MARKETING_VERSION=$V" && has_line "Architectures: arm64 x86_64"'
check "...smoke.sh tests build/Cranny.app, dist.sh does not rebuild, the release is $V" \
  'logged "env smoke APP=$APPDIR" && logged "env dist REBUILD=0" && [ "$(listing "$DIST")" = "$(sorted $ASSETS)" ] && has_line "Release $V (build 1): $DIST"'

# --- the languages gate
new_root l10n
stale_dist
STUB_FAIL=validate br
check "untranslated languages stop the release before anything else; dist/ is left alone" \
  '[ $RC = 1 ] && has "a release needs every shipped language translated" && has "or build with --allow-pending." && [ "$(order)" = validate ] && stale_kept'
br --allow-pending
check "--allow-pending: validate.py --shipped --quiet (no --release), then the build" \
  '[ $RC = 0 ] && logged "run validate --shipped --quiet" && logged "env validate isolated=1" && [ "$(order)" = "validate build smoke dist" ] && has "Languages: every shipped language complete and valid (keys pending translation allowed)"'
stale_dist
STUB_FAIL=validate br --allow-pending
check "--allow-pending: invalid languages still stop the build" \
  '[ $RC = 1 ] && has "the shipped languages are not complete or not valid (scripts/lib/l10n/validate.py --shipped)." && [ "$(order)" = validate ] && stale_kept'
STUB_FAIL=validate br --test
check "--test: the languages come first, and failing they stop the other checks" '[ $RC = 1 ] && [ "$(order)" = validate ] && stale_kept'

# --- --test
new_root checks
br --test
check "--test: languages, copy rules, every module + unit tests, name probe, String Catalogs, then the build" \
  '[ $RC = 0 ] && [ "$(order)" = "validate lint-copy check-modules name-probe sync-strings build smoke dist" ]'
check "...lint-copy.py without arguments, with /usr/bin/python3 -I" 'logged "run lint-copy" && logged "env lint-copy isolated=1" && ! ran path-python3'
check "...check-modules.sh with TEST=1 JOBS=3; name-probe.sh and sync-strings.sh with CHECK=1" \
  'logged "env check-modules TEST=1" && logged "env check-modules JOBS=3" && logged "env name-probe CHECK=1" && logged "env sync-strings CHECK=1"'
check "...the build gets none of TEST, JOBS, CHECK" 'logged "env build TEST unset" && logged "env build JOBS unset" && logged "env build CHECK unset"'
check "...each check is named" \
  'has "Copy rules: scripts/lib/lint-copy.py" && has "Every module alone, zero warnings, and the unit tests: scripts/lib/check-modules.sh" && has "Name-collision probe: scripts/lib/name-probe.sh" && has "String Catalogs: scripts/lib/sync-strings.sh"'
JOBS=8 br --test
check "--test with JOBS=8: check-modules.sh gets it" '[ $RC = 0 ] && logged "env check-modules JOBS=8" && logged "env check-modules TEST=1"'
JOBS='' br --test
check "--test with an empty JOBS: 3" '[ $RC = 0 ] && logged "env check-modules JOBS=3"'
ALLOW_WARNINGS=1 br --test
check "--test with ALLOW_WARNINGS=1 exported: check-modules.sh still fails on warnings, as in CI" \
  '[ $RC = 0 ] && logged "env check-modules ALLOW_WARNINGS=0"'
for c in 'lint-copy|copy rules failed.|check-modules' \
  'check-modules|the module check or the unit tests failed.|name-probe' \
  'name-probe|the name-collision probe is out of date.|sync-strings' \
  'sync-strings|the String Catalogs are out of date.|build'; do
  IFS='|' read -r name msg next <<EOF
$c
EOF
  new_root "fail-$name"
  stale_dist
  STUB_FAIL=$name br --test
  stops="$next and the build"
  [ "$next" != build ] || stops="the build"
  check "--test: a failing $name stops it before $stops; dist/ is left alone" \
    '[ $RC = 1 ] && has "error:" && has "$msg" && ran "$name" && ! ran "$next" && ! ran build && stale_kept'
done

# --- signing variables: SIGN_IDENTITY and TEAM_ID both or neither; NOTARY_PROFILE only with them
new_root signvars
M="set both SIGN_IDENTITY and TEAM_ID for Developer ID signing, or neither for an ad-hoc signed release."
SIGN_IDENTITY="$ID" br
check "SIGN_IDENTITY without TEAM_ID is refused before anything runs" '[ $RC = 1 ] && has "$M" && nothing_ran'
TEAM_ID=TEAMID1234 br
check "TEAM_ID without SIGN_IDENTITY is refused before anything runs" '[ $RC = 1 ] && has "$M" && nothing_ran'
SIGN_IDENTITY="$ID" TEAM_ID='' br
check "SIGN_IDENTITY with an empty TEAM_ID is refused" '[ $RC = 1 ] && has "$M" && nothing_ran'
TEAM_ID=TEAMID1234 NOTARY_PROFILE=cranny-notary br
check "TEAM_ID and NOTARY_PROFILE without SIGN_IDENTITY are refused" '[ $RC = 1 ] && has "$M" && nothing_ran'
NOTARY_PROFILE=cranny-notary br
check "NOTARY_PROFILE without Developer ID signing is refused before anything runs" \
  '[ $RC = 1 ] && has "NOTARY_PROFILE needs Developer ID signing: set SIGN_IDENTITY and TEAM_ID too." && nothing_ran'
SIGN_IDENTITY='' TEAM_ID='' NOTARY_PROFILE='' br
check "empty SIGN_IDENTITY, TEAM_ID and NOTARY_PROFILE: an ad-hoc release" \
  '[ $RC = 0 ] && has_line "Signing: ad-hoc (users allow it once in System Settings > Privacy & Security)" && ! grep -q "^tool xcrun" "$STUB_LOG"'

# --- Developer ID
new_root devid
SIGN_IDENTITY="$ID" TEAM_ID=TEAMID1234 br
check "Developer ID: builds; build.sh and dist.sh get SIGN_IDENTITY and TEAM_ID" \
  '[ $RC = 0 ] && logged "env build SIGN_IDENTITY=$ID" && logged "env build TEAM_ID=TEAMID1234" && logged "env dist SIGN_IDENTITY=$ID" && logged "env dist TEAM_ID=TEAMID1234" && logged "env dist NOTARY_PROFILE unset"'
check "...without NOTARY_PROFILE: not notarized, no stapler check" \
  'has "Building release $V: Developer ID ($ID), not notarized (no NOTARY_PROFILE)" && ! grep -q "^tool xcrun" "$STUB_LOG"'
check "...the summary: the identity, the signing authority and the team" \
  'has_line "Signing: Developer ID ($ID), not notarized (no NOTARY_PROFILE)" && has_line "  $ID (team TEAMID1234)"'
SIGN_IDENTITY="$ID" TEAM_ID=TEAMID1234 NOTARY_PROFILE=cranny-notary br
check "NOTARY_PROFILE: dist.sh gets it; the app and the disk image must have stapled tickets" \
  '[ $RC = 0 ] && logged "env dist NOTARY_PROFILE=cranny-notary" && logged "env build NOTARY_PROFILE=cranny-notary" && logged "tool xcrun stapler validate $APPDIR" && logged "tool xcrun stapler validate $DIST/Cranny-$V.dmg" && has_line "Signing: Developer ID ($ID), notarized"'
SIGN_IDENTITY="$ID" TEAM_ID=TEAMID1234 NOTARY_PROFILE=cranny-notary STUB_UNSTAPLED=app br
check "NOTARY_PROFILE: an app without a stapled ticket is refused" 'refused "the app has no stapled notarization ticket."'
SIGN_IDENTITY="$ID" TEAM_ID=TEAMID1234 NOTARY_PROFILE=cranny-notary STUB_UNSTAPLED=dmg br
check "NOTARY_PROFILE: a disk image without a stapled ticket is refused" 'refused "Cranny-$V.dmg has no stapled notarization ticket."'
SIGN_IDENTITY="$ID" TEAM_ID=TEAMID1234 STUB_TEAM=OTHERTEAM9 br
M="the app is signed by team 'OTHERTEAM9', not TEAM_ID=TEAMID1234."
check "Developer ID: an app of another team is refused" 'refused "$M"'
SIGN_IDENTITY="$ID" TEAM_ID=TEAMID1234 STUB_SIGNATURE=adhoc br
M="the app is signed with 'no certificate', not a Developer ID Application certificate."
check "Developer ID: an ad-hoc signed app is refused" 'refused "$M"'
SIGN_IDENTITY="Apple Development: Jane Doe (TEAMID1234)" TEAM_ID=TEAMID1234 br
M="the app is signed with 'Apple Development: Jane Doe (TEAMID1234)', not a Developer ID Application certificate."
check "Developer ID: a development certificate of the right team is refused" 'refused "$M"'

# --- the app's signature
new_root sig
STUB_SIGNATURE=devid br
check "ad-hoc expected, but the app has a Developer ID signature: refused" 'refused "the app should be ad-hoc signed, but codesign says otherwise."'
STUB_FAIL=verify br
check "a signature that does not verify is refused" 'refused "the app'\''s signature does not verify." && has "a sealed resource is missing or invalid"'
STUB_FAIL=dv br
check "a signature codesign cannot read is refused" 'refused "codesign cannot read the app'\''s signature."'

# --- the app's version, build number and architectures
new_root app
STUB_BUILT_VERSION=1.2.4 br
M="the app is version '1.2.4', not $V."
check "an app of another version is refused" 'refused "$M"'
STUB_BUILT_VERSION=none br
check "an app without CFBundleShortVersionString is refused" 'refused "cannot read CFBundleShortVersionString from $APPDIR/Contents/Info.plist."'
BUILD_NUMBER=77 br
check "BUILD_NUMBER: build.sh gets it, the app has it, the summary names it" \
  '[ $RC = 0 ] && logged "env build BUILD_NUMBER=77" && has_line "Release $V (build 77): $DIST"'
BUILD_NUMBER=77 STUB_BUILD_NUMBER=76 br
M="the app is build '76', not BUILD_NUMBER=77."
check "an app of another build than BUILD_NUMBER is refused" 'refused "$M"'
STUB_BUILD_NUMBER=none br
check "an app without CFBundleVersion is refused" 'refused "cannot read CFBundleVersion from $APPDIR/Contents/Info.plist."'
STUB_ARCHS=arm64 br
check "an app without x86_64 is refused" 'refused "the app lacks x86_64 (it has: arm64)."'
STUB_ARCHS=x86_64 br
check "an app without arm64 is refused" 'refused "the app lacks arm64 (it has: x86_64)."'
STUB_ARCHS='arm64e x86_64' br
check "arm64e is not arm64" 'refused "the app lacks arm64 (it has: arm64e x86_64)."'
STUB_ARCHS='x86_64 arm64' br
check "the architectures in lipo's order pass" '[ $RC = 0 ] && has_line "Architectures: x86_64 arm64"'
STUB_FAIL=lipo br
check "a binary lipo cannot read is refused" 'refused "lipo cannot read the app'\''s binary."'
STUB_NOAPP=1 br
check "no build/Cranny.app after the build is refused" 'refused "the build passed, but there is no build/Cranny.app."'

# --- the build steps failing
new_root steps
stale_dist
STUB_FAIL=build br
check "a failing build.sh stops it before the smoke test; the old release files are gone all the same" \
  '[ $RC != 0 ] && [ "$(order)" = "validate build" ] && ! has "Release $V (build" && [ ! -e "$DIST/Cranny-$V.zip" ] && [ ! -e "$DIST/Cranny-$V.sha256" ]'
STUB_FAIL=smoke br
check "a failing smoke test stops it before the packages" '[ $RC != 0 ] && [ "$(order)" = "validate build smoke" ] && ! has "Release $V (build"'
STUB_FAIL=dist br
check "a failing dist.sh fails the build" '[ $RC != 0 ] && [ "$(order)" = "validate build smoke dist" ] && ! has "Release $V (build"'

# --- the release files and their sums
for c in "nozip|dist/ lacks: Cranny-$V.zip." \
  "emptydmg|dist/ lacks: Cranny-$V.dmg." \
  "nosums|dist/ lacks: Cranny-$V.sha256." \
  "emptysums|dist/ lacks: Cranny-$V.sha256." \
  "othernames|Cranny-$V.sha256 sums 'Cranny-0.9.0.dmg Cranny-$V.zip', not 'Cranny-$V.dmg Cranny-$V.zip'." \
  "onename|Cranny-$V.sha256 sums 'Cranny-$V.zip', not 'Cranny-$V.dmg Cranny-$V.zip'." \
  "twice|Cranny-$V.sha256 sums 'Cranny-$V.dmg Cranny-$V.zip Cranny-$V.zip', not 'Cranny-$V.dmg Cranny-$V.zip'."; do
  new_root "files-${c%%|*}"
  M=${c#*|}
  STUB_DIST=${c%%|*} br
  check "release files: STUB_DIST=${c%%|*} is refused ($M)" 'refused "$M"'
done
new_root files-none
stale_dist
STUB_DIST=none br
check "no release files from dist.sh: refused, the old ones of $V do not count" \
  'refused "dist/ lacks: Cranny-$V.dmg Cranny-$V.zip Cranny-$V.sha256." && [ -z "$(listing "$DIST")" ]'
new_root files-mismatch
STUB_DIST=mismatch br
check "sums that do not match the files are refused" 'refused "the files in $DIST do not match Cranny-$V.sha256."'
new_root files-binary
STUB_DIST=binary br
check "sums in binary mode (\"<sum> *<file>\") pass" \
  '[ $RC = 0 ] && has_line "  $(cd "$DIST" && sha256 "Cranny-$V.zip" | sed "s/  / */")"'

# --- --out DIR
new_root outroot
mkdir -p "$DIST"
echo notes >"$DIST/notes.txt"
mkdir -p "$WORK/out"
echo mine >"$WORK/out/mine.txt"
echo old >"$WORK/out/Cranny-$V.zip"
br --out out
check "--out DIR (relative to the current directory): exactly the release files are copied there and verified" \
  '[ $RC = 0 ] && [ "$(listing "$WORK/out")" = "$(sorted $ASSETS mine.txt)" ] && same_files "$DIST" "$WORK/out"'
check "...dist/ keeps them too" '[ "$(listing "$DIST")" = "$(sorted $ASSETS notes.txt)" ] && same_files "$DIST" "$DIST"'
check "...the summary is about DIR: its files and sizes, its sums, its other files" \
  'has_line "Release $V (build 1): $WORK/out" && has_line "$(size_line "$WORK/out" "Cranny-$V.zip")" && has_line "  $(cd "$WORK/out" && sha256 "Cranny-$V.dmg")" && has_line "$WORK/out also holds files that are not part of the release: mine.txt" && ! has "notes.txt"'
check "...and leaves DIR's other files alone" '[ "$(cat "$WORK/out/mine.txt")" = mine ]'
br --test "--out=$WORK/out 2/new"
check "--out=DIR: a new directory (with a space, parents too) gets the release files" \
  '[ $RC = 0 ] && [ "$(listing "$WORK/out 2/new")" = "$(sorted $ASSETS)" ] && same_files "$DIST" "$WORK/out 2/new" && has_line "Release $V (build 1): $WORK/out 2/new" && ! has "also holds"'
br --out "$DIST"
check "--out dist/ itself: nothing to copy, the summary is about dist/" \
  '[ $RC = 0 ] && has_line "Release $V (build 1): $DIST" && has_line "$DIST also holds files that are not part of the release: notes.txt" && [ "$(listing "$DIST")" = "$(sorted $ASSETS notes.txt)" ]'
ln -s "$DIST" "$WORK/distlink"
br --out distlink
check "--out a symlink to dist/: the same directory, nothing to copy" \
  '[ $RC = 0 ] && has_line "Release $V (build 1): $DIST" && [ "$(listing "$DIST")" = "$(sorted $ASSETS notes.txt)" ]'
echo file >"$WORK/afile"
br --out "$WORK/afile"
check "--out naming a file fails" '[ $RC != 0 ] && ! has "Release $V (build" && [ "$(cat "$WORK/afile")" = file ]'
br --out
check "--out without DIR is a usage error" '[ $RC = 2 ] && has "--out: name a directory" && has "scripts/build-release.sh [--test]" && nothing_ran'
br --out ''
check "--out '' is a usage error" '[ $RC = 2 ] && has "--out: name a directory" && nothing_ran'
br --out=
check "--out= is a usage error" '[ $RC = 2 ] && has "--out=" && has "scripts/build-release.sh [--test]" && nothing_ran'

# --- VERSION
for v in 1.2 v1.2.3 01.2.3 1.02.3 1.2.03 1.2.3.4 1.2.3-beta 1.2.x -1.2.3 1234567890.0.0 '1.2.3 4'; do
  new_root badversion "$v"
  M="VERSION holds '$v', not X.Y.Z (no leading zeros, no \"v\", at most 9 digits per number)."
  br
  check "VERSION '$v' is refused before anything runs" '[ $RC = 1 ] && has "$M" && nothing_ran'
done
M="VERSION must hold exactly one line, the version X.Y.Z."
new_root versionlines
printf '%s\n%s\n' "$V" 1.2.4 >"$ROOT/VERSION"
br
check "two version lines are refused before anything runs" '[ $RC = 1 ] && has "$M" && nothing_ran'
: >"$ROOT/VERSION"
br
check "an empty VERSION is refused before anything runs" '[ $RC = 1 ] && has "$M" && nothing_ran'
printf ' \n\t\n' >"$ROOT/VERSION"
br
check "a VERSION of blanks is refused before anything runs" '[ $RC = 1 ] && has "$M" && nothing_ran'
rm "$ROOT/VERSION"
br
check "no VERSION is refused before anything runs" '[ $RC = 1 ] && has "$M" && nothing_ran'
printf '\n  %s \r\n\n' "$V" >"$ROOT/VERSION"
br
check "the version line may have blanks and blank lines around it" \
  '[ $RC = 0 ] && logged "env build MARKETING_VERSION=$V" && has_line "Release $V (build 1): $DIST"'
W=999999999.999999999.999999999
new_root bigversion "$W"
br
check "9-digit numbers build: $W" \
  '[ $RC = 0 ] && logged "env build MARKETING_VERSION=$W" && has_line "Release $W (build 1): $DIST" && [ "$(listing "$DIST")" = "$(sorted "Cranny-$W.dmg" "Cranny-$W.zip" "Cranny-$W.sha256")" ]'

# --- options
new_root options "not a version"
br --help
check "--help prints the usage and runs nothing (VERSION is not read)" \
  '[ $RC = 0 ] && has "scripts/build-release.sh [--test] [--allow-pending] [--out DIR]" && has "--allow-pending  keys pending translation are warnings" && nothing_ran'
br -h
check "-h prints the usage" '[ $RC = 0 ] && has "scripts/build-release.sh [--test] [--allow-pending] [--out DIR]" && nothing_ran'
OUT="$(cd "$WORK" && "$BASH_BIN" "$ROOT/scripts/build-release.sh" --help 2>/dev/null)"
check "...on stdout" 'has "Signing: Developer ID with SIGN_IDENTITY and TEAM_ID"'
br --bogus
check "an unknown option is a usage error" \
  '[ $RC = 2 ] && has "unknown option --bogus" && has "scripts/build-release.sh [--test] [--allow-pending] [--out DIR]" && nothing_ran'
OUT="$(cd "$WORK" && "$BASH_BIN" "$ROOT/scripts/build-release.sh" --bogus 2>/dev/null)"
check "...on stderr only" '[ -z "$OUT" ]'
br "$V"
check "an argument is a usage error" '[ $RC = 2 ] && has "unknown option $V" && nothing_ran'
br --test --allow-pending --bogus
check "an unknown option after good ones is a usage error" '[ $RC = 2 ] && has "unknown option --bogus" && nothing_ran'

echo "# $pass passed, $fail failed"
[ "$fail" = 0 ]
