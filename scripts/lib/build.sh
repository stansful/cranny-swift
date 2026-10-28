#!/usr/bin/env bash
# Release build of Cranny.app (universal arm64 + x86_64) -> build/Cranny.app
#
#   scripts/lib/build.sh                 # ad-hoc signed ("Sign to Run Locally"), no Apple account needed
#   ARCHS=arm64 scripts/lib/build.sh     # single-arch (faster)
#   CONFIGURATION=Debug scripts/lib/build.sh
#   SIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID1234)" TEAM_ID=TEAMID1234 scripts/lib/build.sh
# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/common.sh"
ensure_xcode
ensure_metal_toolchain   # CrannyEffects compiles Metal shaders

CONFIGURATION="${CONFIGURATION:-Release}"
ARCHS="${ARCHS:-arm64 x86_64}"
LOG="$BUILD_DIR/logs/build-$CONFIGURATION.log"
mkdir -p "$BUILD_DIR/logs"

overrides=(ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO)
if [[ "$CONFIGURATION" == Release ]]; then
  # Strip like an archive does: no local symbols or debug-map stabs (they hold the builder's absolute
  # paths) in the shipped binaries; the dSYM next to the app keeps everything for symbolication.
  # Xcode strips before signing; the bridge dylib keeps its exported `_cranny_bridge_main` (non-global style).
  overrides+=(DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES)
fi
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # Distribution signing (maintainers only). Secure timestamp is required for notarization.
  overrides+=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="${TEAM_ID:?TEAM_ID is required with SIGN_IDENTITY}"
              OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
fi
MARKETING_VERSION="${MARKETING_VERSION:-$(tr -d "[:space:]" < "$ROOT/VERSION")}"
overrides+=(MARKETING_VERSION="$MARKETING_VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && overrides+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")

PRODUCT="$DERIVED_DIR/Build/Products/$CONFIGURATION/Cranny.app"

run_xcodebuild() {
  # 'generic/platform=macOS' (= "Any Mac") is what makes xcodebuild honour ARCHS; with the
  # implicit "My Mac" run destination it silently builds only the host architecture.
  set +e
  xcodebuild build \
    -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DIR" \
    "${overrides[@]}" 2>&1 | tee "$LOG" | xcpretty_filter
  local status=${PIPESTATUS[0]}
  set -e
  (( status == 0 )) || die "xcodebuild failed ($status); full log: $LOG"
}

log "Building $SCHEME ($CONFIGURATION, $ARCHS) with $(xcodebuild -version | head -1)"
run_xcodebuild
# An incremental build that only changed package resources (String Catalogs) can copy new
# .lproj files into the app without re-signing it ("a sealed resource is missing or invalid").
# Rebuild the app product once from scratch in that case.
if ! codesign --verify --deep --strict "$PRODUCT" 2>/dev/null; then
  log "Stale signature on the incremental product; rebuilding Cranny.app"
  rm -rf "$PRODUCT"
  run_xcodebuild
fi

rm -rf "$BUILD_DIR/Cranny.app" "$BUILD_DIR/Cranny.app.dSYM"
ditto "$PRODUCT" "$BUILD_DIR/Cranny.app"
[[ -d "$PRODUCT.dSYM" ]] && ditto "$PRODUCT.dSYM" "$BUILD_DIR/Cranny.app.dSYM"

APP="$BUILD_DIR/Cranny.app"
codesign --verify --deep --strict "$APP" || die "code signature verification failed"
if [[ "$CONFIGURATION" == Release ]]; then
  # Shipped binaries must not carry debug-map stabs (absolute paths of the build machine). An incremental
  # build over products made before stripping was enabled can keep an old copy: start clean then.
  for binary in "$APP/Contents/MacOS/Cranny" "$APP"/Contents/Frameworks/*.dylib; do
    stabs="$(nm -ap "$binary" 2>/dev/null | grep -cE ' (SO|OSO) ' || true)"
    [[ "$stabs" == 0 ]] || die "$binary is not stripped (stale build products?); run \`make clean\` and build again"
  done
fi
log "Built $APP"
log "  version $(plist_value "$APP" CFBundleShortVersionString) ($(plist_value "$APP" CFBundleVersion))"
log "  $(lipo -archs "$APP/Contents/MacOS/Cranny" | sed 's/^/archs: /')"
log "  $(codesign -dv "$APP" 2>&1 | grep -E '^(Signature|TeamIdentifier|CodeDirectory)' | tr '\n' ' ')"
