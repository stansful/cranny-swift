#!/usr/bin/env bash
# Build every CrannyKit library target on its own (`swift build --target`), each in
# its own scratch path, so a module that accidentally relies on something it does not
# import/depend on fails here instead of only inside the app build.
#
#   scripts/check-modules.sh                 # all non-test targets, sequential
#   scripts/check-modules.sh CrannyMedia     # just these targets
#   JOBS=4 scripts/check-modules.sh          # build targets in parallel
#   TEST=1 scripts/check-modules.sh          # also run `swift test`
source "$(dirname "$0")/lib.sh"
ensure_xcode   # SwiftPM from Xcode's toolchain (CLT's would work too, but keep one toolchain)

# D13: no offline Metal compilation in v1 (the Metal Toolchain is an optional Xcode component).
if find "$PACKAGE_DIR/Sources" -name '*.metal' -print -quit | grep -q .; then
  die "Metal sources found in CrannyKit/Sources (not allowed in v1, see ARCHITECTURE.md D13)"
fi

cd "$PACKAGE_DIR"
if (($#)); then
  targets=("$@")
else
  targets=()
  while IFS= read -r t; do targets+=("$t"); done < <(
    swift package describe --type json 2>/dev/null |
      /usr/bin/python3 -I -c 'import json,sys; [print(t["name"]) for t in json.load(sys.stdin)["targets"] if t["type"] != "test"]' |
      sort)
fi
(( ${#targets[@]} )) || die "no targets found"

mkdir -p "$BUILD_DIR/logs"
build_one() {
  local t="$1" lower scratch
  lower="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
  scratch="$PACKAGE_DIR/.build-$lower"
  if swift build --target "$t" --scratch-path "$scratch" >"$BUILD_DIR/logs/module-$t.log" 2>&1; then
    printf '  \033[32mok\033[0m    %s\n' "$t"
  else
    printf '  \033[31mFAIL\033[0m  %s  (log: build/logs/module-%s.log)\n' "$t" "$t"
    grep -E 'error:' "$BUILD_DIR/logs/module-$t.log" | head -5 | sed 's/^/        /'
    return 1
  fi
}

log "Building ${#targets[@]} targets: ${targets[*]}"
failed=0
if [[ "${JOBS:-1}" -gt 1 ]]; then
  pids=()
  for t in "${targets[@]}"; do
    build_one "$t" & pids+=($!)
    while (( $(jobs -rp | wc -l) >= JOBS )); do sleep 0.2; done
  done
  for p in "${pids[@]}"; do wait "$p" || failed=1; done
else
  for t in "${targets[@]}"; do build_one "$t" || failed=1; done
fi

if [[ "${TEST:-0}" == 1 ]]; then
  log "swift test"
  swift test --scratch-path "$PACKAGE_DIR/.build-test" || failed=1
fi
(( failed == 0 )) || die "module check failed"
log "All modules build independently"
