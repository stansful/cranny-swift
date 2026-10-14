#!/usr/bin/env bash
# Release build of Cranny.app (universal arm64 + x86_64) -> build/Cranny.app
#
#   scripts/build.sh                 # ad-hoc signed ("Sign to Run Locally"), no Apple account needed
#   ARCHS=arm64 scripts/build.sh     # single-arch (faster)
#   CONFIGURATION=Debug scripts/build.sh
#   SIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID1234)" TEAM_ID=TEAMID1234 scripts/build.sh
source "$(dirname "$0")/lib.sh"
ensure_xcode

CONFIGURATION="${CONFIGURATION:-Release}"
ARCHS="${ARCHS:-arm64 x86_64}"
LOG="$BUILD_DIR/logs/build-$CONFIGURATION.log"
mkdir -p "$BUILD_DIR/logs"

overrides=(ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO)
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # Distribution signing (maintainers only). Secure timestamp is required for notarization.
  overrides+=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="${TEAM_ID:?TEAM_ID is required with SIGN_IDENTITY}"
              OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
fi
MARKETING_VERSION="${MARKETING_VERSION:-$(tr -d "[:space:]" < "$ROOT/VERSION")}"
overrides+=(MARKETING_VERSION="$MARKETING_VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && overrides+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")

log "Building $SCHEME ($CONFIGURATION, $ARCHS) with $(xcodebuild -version | head -1)"
# 'generic/platform=macOS' (= "Any Mac") is what makes xcodebuild honour ARCHS; with the
# implicit "My Mac" run destination it silently builds only the host architecture.
set +e
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DIR" \
  "${overrides[@]}" 2>&1 | tee "$LOG" | xcpretty_filter
status=${PIPESTATUS[0]}
set -e
(( status == 0 )) || die "xcodebuild failed ($status); full log: $LOG"

PRODUCT="$DERIVED_DIR/Build/Products/$CONFIGURATION/Cranny.app"
rm -rf "$BUILD_DIR/Cranny.app" "$BUILD_DIR/Cranny.app.dSYM"
ditto "$PRODUCT" "$BUILD_DIR/Cranny.app"
[[ -d "$PRODUCT.dSYM" ]] && ditto "$PRODUCT.dSYM" "$BUILD_DIR/Cranny.app.dSYM"

APP="$BUILD_DIR/Cranny.app"
codesign --verify --deep --strict "$APP" || die "code signature verification failed"
log "Built $APP"
log "  version $(plist_value "$APP" CFBundleShortVersionString) ($(plist_value "$APP" CFBundleVersion))"
log "  $(lipo -archs "$APP/Contents/MacOS/Cranny" | sed 's/^/archs: /')"
log "  $(codesign -dv "$APP" 2>&1 | grep -E '^(Signature|TeamIdentifier|CodeDirectory)' | tr '\n' ' ')"
