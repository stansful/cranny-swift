#!/usr/bin/env bash
# Builds the release files of the version in VERSION exactly as the release workflow does (.github/workflows/
# release.yml runs this script, and so does every CI build, with --allow-pending): checks that every shipped language
# is translated, builds the universal Release app (scripts/lib/build.sh), smoke-tests it (scripts/lib/smoke.sh) and
# packages it (scripts/lib/dist.sh). The files are release_assets in scripts/lib/version.sh, in dist/:
#   Cranny-X.Y.Z.dmg  Cranny-X.Y.Z.zip  Cranny-X.Y.Z.sha256 (the sums of the other two)
# Fails unless the app is version X.Y.Z with both architectures, its signature verifies (a Developer ID Application
# certificate of TEAM_ID and a stapled ticket, when those are configured), and the sums match. Prints the version,
# the signing, the files with their sizes and the sums.
#
#   scripts/build-release.sh [--test] [--allow-pending] [--out DIR]
#
#   --test           first the checks: copy rules, every module alone + unit tests, name probe, String Catalogs
#   --allow-pending  keys pending translation are warnings, not errors (CI builds; a release never allows them)
#   --out DIR        also copy the release files to DIR (they are always in dist/)
#
# Env: SIGN_IDENTITY, TEAM_ID   Developer ID signing: both, or neither for an ad-hoc signed release
#      NOTARY_PROFILE           notarytool keychain profile: notarize and staple (needs SIGN_IDENTITY); NOTARY_KEYCHAIN
#                               when the profile is in another keychain
#      BUILD_NUMBER             CFBundleVersion (release.yml: the run number; default: the project's)
#      JOBS                     parallel module builds for --test (default 3)
# bash 3.2 (macOS) or 5. Needs Xcode 26+ with its Metal Toolchain (scripts/lib/common.sh); --test also needs Xcode 27
# (the String Catalog check).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/version.sh
source "$HERE/lib/version.sh"

usage() {
  cat <<'EOF'
Builds the release files of the version in VERSION as GitHub Actions does (release.yml runs this script): the
universal Release app, smoke-tested, as Cranny-X.Y.Z.dmg, Cranny-X.Y.Z.zip and their sums Cranny-X.Y.Z.sha256 in dist/.

  scripts/build-release.sh [--test] [--allow-pending] [--out DIR]

  --test           first the checks: copy rules, every module alone + unit tests, name probe, String Catalogs
  --allow-pending  keys pending translation are warnings, not errors (CI builds; a release never allows them)
  --out DIR        also copy the release files to DIR (they are always in dist/)
  -h, --help       this help

Signing: Developer ID with SIGN_IDENTITY and TEAM_ID (both), notarized with NOTARY_PROFILE as well; without them the
release is ad-hoc signed, and users allow it once in System Settings > Privacy & Security.
EOF
}
say() { printf '%s\n' "$*"; }
usage_error() {
  printf '\033[1;31merror:\033[0m %s\n\n' "$*" >&2
  usage >&2
  exit 2
}
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

run_tests='' allow_pending='' out=''
while [ $# -gt 0 ]; do
  case $1 in
  -h | --help)
    usage
    exit 0
    ;;
  --test) run_tests=1 ;;
  --allow-pending) allow_pending=1 ;;
  --out)
    [ $# -ge 2 ] && [ -n "$2" ] || usage_error "--out: name a directory"
    out=$2
    shift
    ;;
  --out=?*) out=${1#--out=} ;;
  *) usage_error "unknown option $1" ;;
  esac
  shift
done

version="$(app_version_get "$ROOT_DIR")" ||
  die "$APP_VERSION_FILE must hold exactly one line, the version X.Y.Z."
version_valid "$version" ||
  die "$APP_VERSION_FILE holds '$version', not X.Y.Z (no leading zeros, no \"v\", at most 9 digits per number)."
assets="$(release_assets "$version" | tr '\n' ' ')"
sums="Cranny-$version.sha256"

# --- signing: Developer ID from the environment, or ad-hoc
if [[ -n "${SIGN_IDENTITY:-}" || -n "${TEAM_ID:-}" ]]; then
  [[ -n "${SIGN_IDENTITY:-}" && -n "${TEAM_ID:-}" ]] ||
    die "set both SIGN_IDENTITY and TEAM_ID for Developer ID signing, or neither for an ad-hoc signed release."
  signing="Developer ID ($SIGN_IDENTITY)"
else
  [[ -z "${NOTARY_PROFILE:-}" ]] || die "NOTARY_PROFILE needs Developer ID signing: set SIGN_IDENTITY and TEAM_ID too."
  signing="ad-hoc (users allow it once in System Settings > Privacy & Security)"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  signing="$signing, notarized"
elif [[ -n "${SIGN_IDENTITY:-}" ]]; then
  signing="$signing, not notarized (no NOTARY_PROFILE)"
fi

# --- checks that need no build first
if [[ -n "$allow_pending" ]]; then
  log "Languages: every shipped language complete and valid (keys pending translation allowed)"
  /usr/bin/python3 -I "$ROOT_DIR/scripts/lib/l10n/validate.py" --shipped --quiet ||
    die "the shipped languages are not complete or not valid (scripts/lib/l10n/validate.py --shipped)."
else
  log "Languages: every shipped language translated, none pending"
  /usr/bin/python3 -I "$ROOT_DIR/scripts/lib/l10n/validate.py" --shipped --release --quiet ||
    die "a release needs every shipped language translated (docs/TRANSLATING.md ▸ New strings), or build with --allow-pending."
fi
if [[ -n "$run_tests" ]]; then
  log "Copy rules: scripts/lib/lint-copy.py"
  /usr/bin/python3 -I "$ROOT_DIR/scripts/lib/lint-copy.py" || die "copy rules failed."
  log "Every module alone, zero warnings, and the unit tests: scripts/lib/check-modules.sh"
  JOBS="${JOBS:-3}" TEST=1 ALLOW_WARNINGS=0 "$ROOT_DIR/scripts/lib/check-modules.sh" || die "the module check or the unit tests failed."
  log "Name-collision probe: scripts/lib/name-probe.sh"
  CHECK=1 "$ROOT_DIR/scripts/lib/name-probe.sh" || die "the name-collision probe is out of date."
  log "String Catalogs: scripts/lib/sync-strings.sh"
  CHECK=1 "$ROOT_DIR/scripts/lib/sync-strings.sh" || die "the String Catalogs are out of date."
fi

# --- the build: always Release, universal and of this version, whatever CONFIGURATION, ARCHS or MARKETING_VERSION say
app="$ROOT_DIR/build/Cranny.app"
dist="$ROOT_DIR/dist"
for f in $assets; do
  rm -f "$dist/$f"
done
log "Building release $version: $signing"
CONFIGURATION=Release ARCHS="arm64 x86_64" MARKETING_VERSION="$version" "$ROOT_DIR/scripts/lib/build.sh"
log "Smoke test: scripts/lib/smoke.sh"
APP="$app" "$ROOT_DIR/scripts/lib/smoke.sh"
log "Packaging: scripts/lib/dist.sh"
REBUILD=0 "$ROOT_DIR/scripts/lib/dist.sh"

# --- what was built
[[ -d "$app" ]] || die "the build passed, but there is no build/Cranny.app."
plist="$app/Contents/Info.plist"
built_version="$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" ||
  die "cannot read CFBundleShortVersionString from $plist."
[[ "$built_version" == "$version" ]] || die "the app is version '$built_version', not $version."
build_number="$(plutil -extract CFBundleVersion raw -o - "$plist")" || die "cannot read CFBundleVersion from $plist."
[[ -z "${BUILD_NUMBER:-}" || "$build_number" == "$BUILD_NUMBER" ]] ||
  die "the app is build '$build_number', not BUILD_NUMBER=$BUILD_NUMBER."
archs="$(lipo -archs "$app/Contents/MacOS/Cranny")" || die "lipo cannot read the app's binary."
for arch in arm64 x86_64; do
  case " $archs " in *" $arch "*) ;; *) die "the app lacks $arch (it has: $archs)." ;; esac
done
codesign --verify --deep --strict "$app" || die "the app's signature does not verify."
# -dvv: the Authority lines (the certificate chain) need verbosity 2
signature="$(codesign -dvv "$app" 2>&1)" || die "codesign cannot read the app's signature."
team="$(sed -n 's/^TeamIdentifier=//p' <<<"$signature")"
authority="$(awk -F= '$1 == "Authority" { print substr($0, 11); exit }' <<<"$signature")"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  [[ "$authority" == "Developer ID Application: "* ]] ||
    die "the app is signed with '${authority:-no certificate}', not a Developer ID Application certificate."
  [[ "$team" == "$TEAM_ID" ]] || die "the app is signed by team '${team:-none}', not TEAM_ID=$TEAM_ID."
else
  grep -qx 'Signature=adhoc' <<<"$signature" || die "the app should be ad-hoc signed, but codesign says otherwise."
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun stapler validate "$app" >/dev/null || die "the app has no stapled notarization ticket."
  xcrun stapler validate "$dist/Cranny-$version.dmg" >/dev/null || die "Cranny-$version.dmg has no stapled notarization ticket."
fi

# Exactly the release files, and the sums file names exactly the other two
missing=''
for f in $assets; do
  [[ -s "$dist/$f" ]] || missing="$missing $f"
done
[[ -z "$missing" ]] || die "dist/ lacks:$missing."
summed="$(awk '{ sub(/^\*/, "", $2); print $2 }' "$dist/$sums" | LC_ALL=C sort | tr '\n' ' ')"
expected="$(release_assets "$version" | grep -vxF "$sums" | LC_ALL=C sort | tr '\n' ' ')"
[[ "$summed" == "$expected" ]] || die "$sums sums '${summed% }', not '${expected% }'."
(cd "$dist" && sha256 -c "$sums" >/dev/null) || die "the files in $dist do not match $sums."

dest=$dist
if [[ -n "$out" ]]; then
  mkdir -p "$out"
  out="$(cd "$out" && pwd)"
  if [[ "$(cd "$out" && pwd -P)" != "$(cd "$dist" && pwd -P)" ]]; then
    for f in $assets; do
      cp "$dist/$f" "$out/$f"
    done
    (cd "$out" && sha256 -c "$sums" >/dev/null) || die "the files in $out do not match $sums."
    dest=$out
  fi
fi

say
say "Release $version (build $build_number): $dest"
for f in $assets; do
  printf '  %11s  %s\n' "$(wc -c <"$dest/$f" | tr -d ' ')" "$f"
done
say
say "Signing: $signing"
[[ -z "${SIGN_IDENTITY:-}" ]] || say "  $authority (team $team)"
say "Architectures: $archs"
say
say "$sums:"
sed 's/^/  /' "$dest/$sums"
other=''
for path in "$dest"/* "$dest"/.[!.]*; do
  [[ -e "$path" ]] || continue
  case " $assets " in *" ${path##*/} "*) continue ;; esac
  other="$other ${path##*/}"
done
[[ -z "$other" ]] || say "$dest also holds files that are not part of the release:$other"
