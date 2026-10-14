#!/usr/bin/env bash
# Debug build (host arch) + launch.
#
#   scripts/run.sh                      # build, quit the old dev instance, open the new one
#   scripts/run.sh --no-build           # just relaunch
#   scripts/run.sh -- --some-app-arg    # pass arguments to the app
#   XOJIT=1 scripts/run.sh              # keep Xcode-style Debug (XOJIT previews => hardened runtime OFF)
#   DEV_SIGN_IDENTITY="Cranny Dev" scripts/run.sh   # sign with a stable identity so TCC grants survive rebuilds
#
# Launches through LaunchServices (`open`) so macOS attributes TCC prompts
# (Camera, Calendars, Accessibility, Automation...) to Cranny itself rather than to
# the terminal that spawned it.
source "$(dirname "$0")/lib.sh"

build=1
app_args=()
while (($#)); do
  case "$1" in
    --no-build) build=0 ;;
    --) shift; app_args=("$@"); break ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

APP="$DERIVED_DIR/Build/Products/Debug/Cranny.app"
if (( build )); then
  ensure_xcode
  ensure_metal_toolchain
  overrides=()
  # With ad-hoc signing, Xcode prints "Disabling hardened runtime with ad-hoc codesigning"
  # for Debug builds while ENABLE_XOJIT_PREVIEWS=YES (the Debug default). Turn it off for CLI
  # runs so the dev build behaves like Release (library validation, hardened-runtime
  # resource entitlements for camera/mic/calendars/Apple Events).
  [[ "${XOJIT:-0}" == 1 ]] || overrides+=(ENABLE_XOJIT_PREVIEWS=NO)
  # Stable code identity keeps TCC grants (Accessibility, Camera, Calendars) across rebuilds:
  #   DEV_SIGN_IDENTITY="Cranny Dev" scripts/run.sh   (a self-signed Code Signing certificate in your login keychain)
  [[ -z "${DEV_SIGN_IDENTITY:-}" ]] || overrides+=(CODE_SIGN_IDENTITY="$DEV_SIGN_IDENTITY")
  log "Building Debug"
  mkdir -p "$BUILD_DIR/logs"
  set +e
  xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$DERIVED_DIR" \
    ${overrides[@]+"${overrides[@]}"} 2>&1 | tee "$BUILD_DIR/logs/build-Debug.log" | xcpretty_filter
  status=${PIPESTATUS[0]}
  set -e
  (( status == 0 )) || die "xcodebuild failed; see $BUILD_DIR/logs/build-Debug.log"
fi
[[ -d "$APP" ]] || die "$APP not found; run without --no-build first"

# Quit only *this* build's instance (other Cranny copies, e.g. in /Applications, are left alone).
if pgrep -f "$APP/Contents/MacOS/Cranny" >/dev/null; then
  log "Quitting running dev instance"
  pkill -f "$APP/Contents/MacOS/Cranny" || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$APP/Contents/MacOS/Cranny" >/dev/null || break; sleep 0.3; done
fi

log "Launching $APP"
open -n "$APP" --args ${app_args[@]+"${app_args[@]}"}
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if pid="$(pgrep -f "$APP/Contents/MacOS/Cranny" | head -1)" && [[ -n "$pid" ]]; then
    log "Running (pid $pid). Logs: log stream --level debug --predicate 'process == \"Cranny\"'"
    exit 0
  fi
  sleep 0.5
done
die "Cranny did not start; check ~/Library/Logs/DiagnosticReports/Cranny-*.ips"
