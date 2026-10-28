#!/usr/bin/env bash
# Package build/Cranny.app as dist/Cranny-<version>.zip and .dmg (+ SHA-256 sums).
#
#   scripts/lib/dist.sh                 # uses existing build/Cranny.app, or builds it first
#   REBUILD=1 scripts/lib/dist.sh
#
# Maintainers with an Apple Developer ID can produce a notarized release:
#   xcrun notarytool store-credentials cranny-notary --apple-id you@example.com --team-id TEAMID1234
#   SIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID1234)" TEAM_ID=TEAMID1234 \
#   NOTARY_PROFILE=cranny-notary REBUILD=1 scripts/lib/dist.sh
# Without those variables the app stays ad-hoc signed: users must allow it once in
# System Settings > Privacy & Security ("Open Anyway"), or run
#   xattr -dr com.apple.quarantine /Applications/Cranny.app
# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/common.sh"

APP="$BUILD_DIR/Cranny.app"
if [[ "${REBUILD:-0}" == 1 || ! -d "$APP" ]]; then
  "$ROOT/scripts/lib/build.sh"
fi
ensure_xcode

VERSION="$(plist_value "$APP" CFBundleShortVersionString)"
DIST="$ROOT/dist"
NAME="Cranny-$VERSION"
mkdir -p "$DIST"
rm -f "$DIST/$NAME.zip" "$DIST/$NAME.dmg"

notarize() { # $1 = file to submit
  log "Notarizing $(basename "$1") (profile $NOTARY_PROFILE)"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" ${NOTARY_KEYCHAIN:+--keychain "$NOTARY_KEYCHAIN"} --wait
}

# 1) Notarize + staple the app itself first (when configured), so both archives carry the ticket.
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ "$(codesign -dv "$APP" 2>&1 | grep -c 'TeamIdentifier=not set')" == 0 ]] \
    || die "app is ad-hoc signed; rebuild with SIGN_IDENTITY/TEAM_ID before notarizing"
  ditto -c -k --norsrc --keepParent "$APP" "$DIST/notarize-upload.zip"
  notarize "$DIST/notarize-upload.zip"
  rm -f "$DIST/notarize-upload.zip"
  xcrun stapler staple "$APP"
fi

# 2) ZIP. ditto keeps symlinks and signatures intact (plain `zip` can break bundles);
#    --norsrc drops local xattrs (com.apple.provenance...) so no __MACOSX/._ clutter.
log "Creating $NAME.zip"
ditto -c -k --norsrc --keepParent "$APP" "$DIST/$NAME.zip"

# 3) DMG with an /Applications shortcut.
log "Creating $NAME.dmg"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/cranny-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Cranny.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Cranny $VERSION" -srcfolder "$STAGE" -fs APFS -format UDZO -ov "$DIST/$NAME.dmg" >/dev/null
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DIST/$NAME.dmg"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notarize "$DIST/$NAME.dmg"
    xcrun stapler staple "$DIST/$NAME.dmg"
  fi
fi
hdiutil verify "$DIST/$NAME.dmg" >/dev/null

(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > "$NAME.sha256")
log "Artifacts in $DIST:"
# shellcheck disable=SC2012 # a listing for people
ls -lh "$DIST" | sed 1d >&2
