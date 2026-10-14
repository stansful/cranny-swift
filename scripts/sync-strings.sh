#!/usr/bin/env bash
# Update every CrannyKit String Catalog with the keys the compiler extracted from code
# (what Xcode's editor does after a build, but scriptable/CI-friendly).
#
#   scripts/sync-strings.sh          # build targets that have a catalog, then sync
#   CHECK=1 scripts/sync-strings.sh  # fail if a catalog would change (for CI)
#
# Uses the compiler-produced .stringsdata (exact keys such as "%lld minutes left").
# `xcstringstool extract` exists too, but its lightweight parser turns interpolations
# into "%arg" keys, so we do not use it.
source "$(dirname "$0")/lib.sh"
ensure_xcode
cd "$PACKAGE_DIR"

scratch="$PACKAGE_DIR/.build-strings"
changed=0
for catalog in Sources/*/Resources/Localizable.xcstrings; do
  target="$(basename "$(dirname "$(dirname "$catalog")")")"
  log "$target"
  # The .stringsdata paths below are the swift-build backend's layout: request it explicitly
  # (default on SwiftPM 6.4; Xcode 26's SwiftPM 6.2 defaults to the native backend).
  swift build --build-system swiftbuild --target "$target" --scratch-path "$scratch" >/dev/null 2>&1 \
    || die "build of $target failed (run scripts/check-modules.sh $target)"
  stringsdata=()
  while IFS= read -r f; do stringsdata+=("$f"); done < <(
    find "$scratch/out/Intermediates.noindex" -path "*/$target-t.build/*" -name '*.stringsdata' 2>/dev/null)
  (( ${#stringsdata[@]} )) || die "no .stringsdata for $target (is SwiftPM using the swiftbuild backend?)"
  tmp="$(mktemp -d)"
  cp "$catalog" "$tmp/Localizable.xcstrings"
  xcrun xcstringstool sync "$tmp/Localizable.xcstrings" --stringsdata "${stringsdata[@]}"
  if ! cmp -s "$catalog" "$tmp/Localizable.xcstrings"; then
    changed=1
    if [[ "${CHECK:-0}" == 1 ]]; then
      warn "$catalog is out of date"
    else
      cp "$tmp/Localizable.xcstrings" "$catalog"
      log "  updated $catalog"
    fi
  fi
  rm -rf "$tmp"
done
if [[ "${CHECK:-0}" == 1 && $changed == 1 ]]; then
  die "String Catalogs are out of date; run scripts/sync-strings.sh and commit the result"
fi
log "String Catalogs are in sync"
