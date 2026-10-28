#!/usr/bin/env bash
# Update every CrannyKit String Catalog with the keys the compiler extracted from code
# (what Xcode's editor does after a build, but scriptable/CI-friendly).
#
#   scripts/lib/sync-strings.sh                  # build targets that have a catalog, then sync
#   scripts/lib/sync-strings.sh CrannyTimer      # just these targets (parallel work on one module)
#   CHECK=1 scripts/lib/sync-strings.sh [Target…]   # fail if a catalog would change (for CI)
#
# Uses the compiler-produced .stringsdata (exact keys such as "%lld minutes left").
# `xcstringstool extract` exists too, but its lightweight parser turns interpolations
# into "%arg" keys, so we do not use it.
# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/common.sh"
ensure_xcode
ensure_metal_toolchain   # CrannyEffects compiles Metal shaders
cd "$PACKAGE_DIR" || exit

scratch="$PACKAGE_DIR/.build-strings"
changed=0
catalogs=()
if (($#)); then
  for t in "$@"; do
    [[ -f "Sources/$t/Resources/Localizable.xcstrings" ]] || die "no String Catalog for target $t"
    catalogs+=("Sources/$t/Resources/Localizable.xcstrings")
  done
else
  catalogs=(Sources/*/Resources/Localizable.xcstrings)
fi
for catalog in "${catalogs[@]}"; do
  target="$(basename "$(dirname "$(dirname "$catalog")")")"
  log "$target"
  # The .stringsdata paths below are the swift-build backend's layout: request it explicitly
  # (default on SwiftPM 6.4; Xcode 26's SwiftPM 6.2 defaults to the native backend).
  swift build --build-system swiftbuild --target "$target" --scratch-path "$scratch" >/dev/null 2>&1 \
    || die "build of $target failed (run scripts/lib/check-modules.sh $target)"
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
  die "String Catalogs are out of date; run scripts/lib/sync-strings.sh and commit the result"
fi
log "String Catalogs are in sync"
