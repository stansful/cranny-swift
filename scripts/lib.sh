#!/usr/bin/env bash
# Shared helpers for Cranny scripts. Source it; do not execute it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Cranny.xcodeproj"
SCHEME="Cranny"
PACKAGE_DIR="$ROOT/Packages/CrannyKit"
BUILD_DIR="$ROOT/build"
DERIVED_DIR="$BUILD_DIR/DerivedData"
MIN_XCODE_MAJOR=26   # swift-tools-version 6.2, .icon app icons, objectVersion 77

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Use a full Xcode even when `xcode-select -p` points at the Command Line Tools
# (common on dev machines; changing it needs sudo). DEVELOPER_DIR wins if set.
ensure_xcode() {
  if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    local selected
    selected="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$selected" != *.app/Contents/Developer ]]; then
      local candidate
      for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app /Applications/Xcode_*.app /Applications/Xcode*.app; do
        if [[ -x "$candidate/Contents/Developer/usr/bin/xcodebuild" ]]; then
          export DEVELOPER_DIR="$candidate/Contents/Developer"
          break
        fi
      done
      [[ -n "${DEVELOPER_DIR:-}" ]] || die "Xcode not found. Install Xcode $MIN_XCODE_MAJOR+ or set DEVELOPER_DIR."
      log "xcode-select points to '$selected'; using DEVELOPER_DIR=$DEVELOPER_DIR"
    fi
  fi
  local version major
  version="$(xcodebuild -version 2>/dev/null | awk 'NR==1 {print $2}')" || true
  major="${version%%.*}"
  [[ -n "$major" ]] || die "xcodebuild is not usable (DEVELOPER_DIR=${DEVELOPER_DIR:-unset})."
  (( major >= MIN_XCODE_MAJOR )) || die "Xcode $version is too old; need $MIN_XCODE_MAJOR+."
}

# CrannyEffects compiles Metal shaders (Sources/CrannyEffects/Shaders/*.metal → default.metallib), and every
# target above it builds CrannyEffects. The Metal Toolchain is an optional Xcode component (Xcode 26+); stop
# early with the fix instead of failing deep inside the package build. Never downloads anything itself.
# Call after ensure_xcode.
ensure_metal_toolchain() {
  local status
  status="$(xcodebuild -showComponent MetalToolchain 2>/dev/null | awk -F': *' '/^Status/ {print $2; exit}')" || true
  if [[ "$status" == installed ]] && xcrun metal -v >/dev/null 2>&1; then
    return 0
  fi
  # Print the fix with the Xcode this script uses: when ensure_xcode chose it through DEVELOPER_DIR (xcode-select
  # points at the Command Line Tools), a bare `xcodebuild` in the user's shell fails with "requires Xcode".
  local fix="xcodebuild -downloadComponent MetalToolchain" developer_dir
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    printf -v developer_dir '%q' "$DEVELOPER_DIR"
    fix="DEVELOPER_DIR=$developer_dir $fix"
  fi
  die "Metal Toolchain missing — run: $fix
       (CrannyEffects compiles Metal shaders; \`xcodebuild -showComponent MetalToolchain\` reports: ${status:-unknown})"
}

# Pretty-print xcodebuild output when xcbeautify is installed (CI images have it).
xcpretty_filter() {
  if command -v xcbeautify >/dev/null 2>&1 && [[ "${VERBOSE:-0}" != 1 ]]; then
    xcbeautify --quieter
  else
    cat
  fi
}

# Read a key from a built app's Info.plist.
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
