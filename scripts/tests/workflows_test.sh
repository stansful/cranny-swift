#!/usr/bin/env bash
# Static checks that the release pieces agree: release.yml publishes the files release_assets (scripts/lib/version.sh)
# lists, which scripts/build-release.sh and scripts/lib/dist.sh build; the release is tagged v<version> (release_tag,
# through the gate's output), titled "Cranny <version>" and made the latest one (the in-app update check reads
# /releases/latest); the tag's commit is read one way (tag_commit); release.yml runs the whole CI (ci.yml with
# release: true) and ci.yml leaves pushes to main to it; the builds run scripts/build-release.sh; shellcheck covers
# every script; and every scripts/... path a workflow, the Makefile or a script names exists.
#
#   scripts/tests/workflows_test.sh
#
# Prints 'ok <name>' / 'not ok <name>: <why>' and exits non-zero on a failure. Reads the tree, writes nothing.
# The patterns match the workflows' and scripts' own text, $VERSION and the like included.
# shellcheck disable=SC2016
set -u
# SIGPIPE ignored, as on the GitHub runner (every step inherits that from its Node.js), for these tests and the
# scripts they run: a reader that stops early makes its writer fail with "Broken pipe" there instead of dying quietly
trap "" PIPE

HERE="$(cd "$(dirname "$0")" && pwd -P)"
TREE="$(cd "$HERE/../.." && pwd -P)"
RELEASE="$TREE/.github/workflows/release.yml"
CI="$TREE/.github/workflows/ci.yml"
STATE="$TREE/.github/scripts/release-state.sh"
NOTES="$TREE/.github/scripts/release-notes.sh"
BUILD="$TREE/scripts/build-release.sh"
MAKE="$TREE/scripts/make-release.sh"
DIST="$TREE/scripts/lib/dist.sh"

pass=0 fail=0
ok() {
  echo "ok $1"
  pass=$((pass + 1))
}
nok() {
  echo "not ok $1: $2"
  fail=$((fail + 1))
}
# check <name> <why> <command...>: ok when the command succeeds
check() {
  local name="$1" why="$2"
  shift 2
  if "$@"; then ok "$name"; else nok "$name" "$why"; fi
}
has() { grep -qF -- "$1" "$2"; }
# matches <grep arguments>: grep -q that reads all its input; grep -q stops at the first match, and its writer then
# fails with "Broken pipe" (SIGPIPE is ignored)
matches() { grep "$@" >/dev/null; }
# has_line <line> <file>: the file has exactly this line
has_line() { grep -qxF -- "$1" "$2"; }
# count <fixed string> <file>: the number of lines with it
count() { grep -cF -- "$1" "$2"; }
# job <workflow> <job>: the lines of that job (from "  <job>:" to the next job or top-level key)
job() {
  awk -v start="  $2:" '
    $0 == start { on = 1; next }
    on && (/^  [^ #]/ || /^[^ #]/) { exit }
    on' "$1"
}
# jobs <workflow>: the names of its jobs
jobs_of() {
  awk '
    /^jobs:$/ { on = 1; next }
    on && /^[^ #]/ { exit }
    on && /^  [A-Za-z0-9_-]+:$/ { sub(/^  /, ""); sub(/:$/, ""); print }' "$1"
}
# job_has <workflow> <job> <line>: the job has exactly this line
job_has() { job "$1" "$2" | matches -xF -- "$3"; }

# shellcheck source=scripts/lib/version.sh
. "$TREE/scripts/lib/version.sh"

# --- the release files
check "build-release.sh builds the files release_assets lists" "build-release.sh does not take its list from release_assets" \
  has 'assets="$(release_assets "$version" | tr' "$BUILD"
check "release.yml checks the build against release_assets" "the build job compares the output with another list" \
  has 'expected="$(release_assets "$VERSION" | LC_ALL=C sort)"' "$RELEASE"
check "release.yml uploads exactly the release_assets files" "the publish step uploads another list" \
  has 'done < <(release_assets "$VERSION")' "$RELEASE"
assets="$(release_assets 1.2.3 | tr '\n' ' ')"
check "every release has the disk image, the zip and their SHA-256 sums" "release_assets 1.2.3: $assets" \
  test "$assets" = "Cranny-1.2.3.dmg Cranny-1.2.3.zip Cranny-1.2.3.sha256 "
if has 'NAME="Cranny-$VERSION"' "$DIST" && has 'DIST="$ROOT/dist"' "$DIST" &&
  has 'ditto -c -k --norsrc --keepParent "$APP" "$DIST/$NAME.zip"' "$DIST" &&
  has '-ov "$DIST/$NAME.dmg"' "$DIST" &&
  has '(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > "$NAME.sha256")' "$DIST"; then
  ok "scripts/lib/dist.sh writes those three files into dist/, the sums of the dmg and the zip"
else
  nok "scripts/lib/dist.sh writes those three files into dist/" "dist.sh names or sums its files another way"
fi
if has 'sums="Cranny-$version.sha256"' "$BUILD" &&
  has '(cd "$RUNNER_TEMP/out" && shasum -a 256 -c "Cranny-$VERSION.sha256")' "$RELEASE" &&
  has '(cd "$RUNNER_TEMP/release-assets" && sha256sum -c "Cranny-$VERSION.sha256")' "$RELEASE" &&
  [ "$(release_assets 1.2.3 | grep -c '\.sha256$')" = 1 ] && release_assets 1.2.3 | matches -xF Cranny-1.2.3.sha256; then
  ok "build-release.sh and both jobs of release.yml check the sums file release_assets lists"
else
  nok "build-release.sh and release.yml check the sums file release_assets lists" "another sums file name"
fi
check "release.yml's build job copies the files out with --out" "no --out \"\$RUNNER_TEMP/out\"" \
  job_has "$RELEASE" build '        run: scripts/build-release.sh --out "$RUNNER_TEMP/out"'
check "...and hands them to publish as artifact release-<version>" "the artifact names differ" \
  eval 'job_has "$RELEASE" build "          name: release-\${{ env.VERSION }}" && job_has "$RELEASE" publish "          name: release-\${{ env.VERSION }}" && job_has "$RELEASE" build "      VERSION: \${{ needs.gate.outputs.version }}" && job_has "$RELEASE" publish "      VERSION: \${{ needs.gate.outputs.version }}"'

# CI keeps what a release would publish: every kind of release file, from every build job
ci_builds=0
ci_missing=''
for j in $(jobs_of "$CI"); do
  if job "$CI" "$j" | matches -E '^    runs-on: (xcode|macos)'; then
    ci_builds=$((ci_builds + 1))
    for ext in dmg zip sha256; do
      job_has "$CI" "$j" "            dist/*.$ext" || ci_missing="$ci_missing $j:dist/*.$ext"
    done
  fi
done
if [ "$ci_builds" -ge 1 ] && [ -z "$ci_missing" ]; then
  ok "every CI build job ($ci_builds) uploads the .dmg, .zip and .sha256 of dist/"
else
  nok "every CI build job uploads the .dmg, .zip and .sha256 of dist/" "build jobs: $ci_builds; missing:$ci_missing"
fi

# --- the tag, the title, latest
check "release_tag: the tag of release 1.2.3 is v1.2.3" "release_tag 1.2.3: $(release_tag 1.2.3)" test "$(release_tag 1.2.3)" = v1.2.3
if job_has "$RELEASE" gate '      tag: ${{ steps.decide.outputs.tag }}' &&
  job "$RELEASE" gate | matches -xF '            echo "tag=$(release_tag "$version")"' &&
  job_has "$RELEASE" publish '      TAG: ${{ needs.gate.outputs.tag }}' &&
  has '-f tag_name="$TAG" -f target_commitish="$GITHUB_SHA"' "$RELEASE"; then
  ok "the release's tag is release_tag of the version, the gate's tag output, as the publish job's TAG"
else
  nok "the release's tag is release_tag of the version, through the gate's tag output" "release.yml makes the tag another way"
fi
if ! grep -Eq 'v\$\{?(VERSION|version)([^A-Za-z0-9_]|$)|tag_name="\$\{?VERSION' "$RELEASE" "$STATE" "$NOTES" "$BUILD" "$MAKE"; then
  ok "no workflow or release script spells the tag itself (v\$VERSION, tag_name=\"\$VERSION\")"
else
  nok "no workflow or release script spells the tag itself" \
    "$(grep -nE 'v\$\{?(VERSION|version)([^A-Za-z0-9_]|$)|tag_name="\$\{?VERSION' "$RELEASE" "$STATE" "$NOTES" "$BUILD" "$MAKE" | tr '\n' ' ')"
fi
check "release-state.sh asks for the release of release_tag" "release-state.sh reads another tag" \
  eval 'has "TAG=\"\$(release_tag \"\$VERSION\")\"" "$STATE" && has "/repos/\$GITHUB_REPOSITORY/releases/tags/\$TAG\"" "$STATE"'
check "release-notes.sh skips the release's own tag, release_tag of the version" "release-notes.sh skips another tag" \
  has '| highest_tag "$(release_tag "$VERSION")")"' "$NOTES"
check "the release is titled \"Cranny <version>\"" "another release title" \
  has '-f name="Cranny $VERSION"' "$RELEASE"
check "the release is published as the latest one, which the in-app update check reads" "no make_latest=true on publish" \
  has '-F draft=false -f make_latest=true' "$RELEASE"
check "...and publish waits until /releases/latest is that tag" "no check of /releases/latest against \$TAG" \
  eval 'has "latest=\"\$(gh api \"repos/\$GH_REPO/releases/latest\" --jq .tag_name || true)\"" "$RELEASE" && has "if [[ \"\$latest\" != \"\$TAG\" ]]; then" "$RELEASE"'
check "the release notes come from release-notes.sh" "the notes come from somewhere else" \
  eval 'has "bash .github/scripts/release-notes.sh > \"\$RUNNER_TEMP/release-notes.md\"" "$RELEASE" && has "-F body=@\"\$RUNNER_TEMP/release-notes.md\"" "$RELEASE"'
check "...out of the full history and tags (fetch-depth: 0)" "the publish checkout is shallow" \
  job_has "$RELEASE" publish '          fetch-depth: 0'

# `git ls-remote` given a pattern leaves out an annotated tag's peeled line, so it reads the tag object, not the
# commit: an annotated tag release-state.sh accepts as retry would fail the publish job after publishing
if [ "$(count 'git ls-remote --tags origin | tag_commit "$TAG")"' "$RELEASE")" = 2 ] &&
  has 'tag_sha="$(tag_commit "$TAG" <<<"$refs")"' "$STATE" &&
  has 'refs="$(git -C "$ROOT_DIR" ls-remote --tags origin)"' "$STATE" &&
  ! grep -Eq 'ls-remote[^|]*refs/tags' "$RELEASE" "$STATE"; then
  ok "release.yml checks the tag's commit (twice) the way release-state.sh reads it: tag_commit over every tag"
else
  nok "release.yml checks the tag's commit the way release-state.sh reads it" "a tag is read another way (ls-remote with a pattern?)"
fi

# The release list lags behind a draft created a moment ago: the publish step takes the draft's id from the create
# call and never looks the draft up by its tag
if has 'id="$(gh api --method POST "repos/$GH_REPO/releases"' "$RELEASE" && has '-F draft=true --jq .id)"' "$RELEASE" &&
  ! grep -Eq 'gh release (create|upload|edit)' "$RELEASE"; then
  ok "publish works with the id the API returns for the new draft, not a lookup by tag"
else
  nok "publish works with the id the API returns for the new draft" "release.yml creates or finds the draft another way"
fi

# --- the gate and release-state.sh
states="$(sed -nE 's/^ *echo (new|retry|released)$/\1/p' "$STATE" | LC_ALL=C sort | tr '\n' ' ')"
labels="$(job "$RELEASE" gate | sed -nE 's/^ +([a-z]+)\)$/\1/p' | LC_ALL=C sort | tr '\n' ' ')"
check "the gate handles exactly the states release-state.sh prints" "release-state.sh: $states; the gate: $labels" \
  test "$states" = "new released retry "
check "...(the gate's cases)" "the gate: $labels" test "$labels" = "$states"
check "the gate and the publish job both run release-state.sh (a re-run sees fresh state)" "one of them does not" \
  eval 'job "$RELEASE" gate | matches -xF "            state=\"\$(bash .github/scripts/release-state.sh)\"" && job "$RELEASE" publish | matches -xF "          state=\"\$(bash .github/scripts/release-state.sh)\""'
sparse_ok=1
for j in gate publish; do
  for p in /VERSION /scripts/lib/ /.github/scripts/; do
    job_has "$RELEASE" "$j" "            $p" || sparse_ok=''
  done
done
if [ -n "$sparse_ok" ] && has '. "$ROOT_DIR/scripts/lib/version.sh"' "$STATE" && has '. "$ROOT_DIR/scripts/lib/version.sh"' "$NOTES" &&
  [ "$APP_VERSION_FILE" = VERSION ]; then
  ok "the sparse checkouts of gate and publish hold what the scripts read: VERSION, scripts/lib/, .github/scripts/"
else
  nok "the sparse checkouts of gate and publish hold what the scripts read" "a sparse-checkout path is missing"
fi

# --- the release commit
if has 'message="feat: release - version $new"' "$MAKE" && has "-e '^- feat: release - version [0-9]'" "$NOTES" &&
  has 'commit \"feat: release - version X.Y.Z\"' "$RELEASE"; then
  ok "release-notes.sh leaves out the commit make-release.sh makes (\"feat: release - version X.Y.Z\")"
else
  nok "release-notes.sh leaves out the commit make-release.sh makes" "the release commit's subject differs between them"
fi

# --- the workflows and the builds
check "release.yml runs the whole CI (ci.yml) with release: true" "no workflow_call of ci.yml with release: true" \
  eval 'job_has "$RELEASE" quality "    uses: ./.github/workflows/ci.yml" && job_has "$RELEASE" quality "      release: true"'
check "...which ci.yml takes as a boolean workflow_call input" "ci.yml has no boolean input release" \
  eval 'grep -A 4 "^  workflow_call:$" "$CI" | matches -x "      release:" && grep -A 4 "^  workflow_call:$" "$CI" | matches -x "        type: boolean"'
check "the build needs the gate and the CI" "the build job does not need quality" \
  job_has "$RELEASE" build '    needs: [gate, quality]'
check "publish needs the gate, the CI and the build" "the publish job does not need all three" \
  job_has "$RELEASE" publish '    needs: [gate, quality, build]'
check "only publish holds a write token" "contents: write elsewhere, or not on publish" \
  eval '[ "$(count "contents: write" "$RELEASE")" = 1 ] && job_has "$RELEASE" publish "      contents: write" && has_line "permissions: {}" "$RELEASE"'

# A push to main starts release.yml only (which calls ci.yml): no second CI run for the same push
# ci.yml has no push trigger: main's pushes reach it through release.yml, and a branch push next to its pull request
# would run the macOS jobs twice for one commit
if grep -A 2 '^  push:$' "$RELEASE" | matches '^      - main$' && ! matches '^  push:' <"$CI" &&
  matches '^  pull_request:$' <"$CI" && matches '^  workflow_call:$' <"$CI"; then
  ok "a push to main runs release.yml (which calls ci.yml); ci.yml runs for pull requests, by hand and when called"
else
  nok "a push to main runs release.yml only" "release.yml must trigger on main; ci.yml must have no push trigger, and pull_request and workflow_call"
fi
check "the gate publishes only from main" "no refs/heads/main check in the gate" \
  eval 'job "$RELEASE" gate | matches -F "if [[ \"\$GITHUB_REF\" != \"refs/heads/main\" ]]; then"'

# runs <workflow>: its lines that run build-release.sh (not comments, not step names)
runs() { grep -v -e '^ *#' -e '^ *- name: ' -e '^ *name: ' "$1" | grep 'build-release\.sh'; }
check "release.yml builds once, with scripts/build-release.sh --out, which refuses pending translations there" \
  "release.yml runs: $(runs "$RELEASE" | tr '\n' '|')" \
  eval '[ "$(runs "$RELEASE")" = "        run: scripts/build-release.sh --out \"\$RUNNER_TEMP/out\"" ] && ! grep -v "^ *#" "$RELEASE" | matches -- --allow-pending'
ci_ok=1
for j in $(jobs_of "$CI"); do
  if job "$CI" "$j" | matches -E '^    runs-on: (xcode|macos)'; then
    job_has "$CI" "$j" '        run: scripts/build-release.sh --allow-pending' || ci_ok=''
  fi
done
ci_runs="$(runs "$CI" | grep -c .)"
if [ -n "$ci_ok" ] && [ "$ci_runs" = "$ci_builds" ] && ! runs "$CI" | matches -vxF '        run: scripts/build-release.sh --allow-pending'; then
  ok "every CI build job ($ci_builds) runs scripts/build-release.sh --allow-pending, and nothing else runs it"
else
  nok "every CI build job runs scripts/build-release.sh --allow-pending" "build jobs: $ci_builds; ci.yml runs: $(runs "$CI" | tr '\n' '|')"
fi
check "every build-release.sh step passes the run number as BUILD_NUMBER" "a build step without BUILD_NUMBER" \
  eval '[ "$(count "BUILD_NUMBER: \${{ github.run_number }}" "$CI")" = "$ci_runs" ] && [ "$(count "BUILD_NUMBER: \${{ github.run_number }}" "$RELEASE")" = 1 ]'

# Signing: build-release.sh and dist.sh read SIGN_IDENTITY, TEAM_ID, NOTARY_PROFILE and NOTARY_KEYCHAIN; the
# import step sets them from five secrets, all or none
sign_ok=1
for v in SIGN_IDENTITY TEAM_ID NOTARY_PROFILE; do
  has "\${$v:-}" "$BUILD" || sign_ok=''
  job "$RELEASE" build | matches "^            echo \"$v=" || sign_ok=''
done
has '${NOTARY_KEYCHAIN:+--keychain "$NOTARY_KEYCHAIN"}' "$DIST" || sign_ok=''
job "$RELEASE" build | matches '^            echo "NOTARY_KEYCHAIN=' || sign_ok=''
has 'echo "NOTARY_PROFILE=cranny-notary"' "$RELEASE" && has 'xcrun notarytool store-credentials cranny-notary' "$RELEASE" || sign_ok=''
check "the import step sets every signing variable build-release.sh and dist.sh read" "a variable is not set, or the profile names differ" \
  test -n "$sign_ok"
secrets="$(grep -oE 'secrets\.[A-Z0-9_]+' "$RELEASE" | LC_ALL=C sort -u | tr '\n' ' ')"
if [ "$secrets" = "secrets.DEVELOPER_ID_P12_BASE64 secrets.DEVELOPER_ID_P12_PASSWORD secrets.NOTARY_ISSUER_ID secrets.NOTARY_KEY_ID secrets.NOTARY_KEY_P8_BASE64 " ] &&
  has 'for name in P12_BASE64 P12_PASSWORD NOTARY_KEY_P8_BASE64 NOTARY_KEY_ID NOTARY_ISSUER_ID; do' "$RELEASE" &&
  has 'if ((configured != 5)); then' "$RELEASE" && has 'if ((configured == 0)); then' "$RELEASE"; then
  ok "signing is optional: five secrets, all or none"
else
  nok "signing is optional: five secrets, all or none" "secrets: $secrets"
fi

# --- the scripts job
sc_line="$(grep -A 1 -- '--entrypoint shellcheck' "$CI" | tail -n 1)"
check "the CI shellchecks scripts/tests too" "shellcheck runs on: $sc_line" \
  eval 'case " $sc_line " in *" scripts/tests/*.sh "*) true ;; *) false ;; esac'
# shellcheck disable=SC2086 # the globs of the shellcheck line, expanded as the step's shell does
sc_files="$(cd "$TREE" && for f in $sc_line; do [ -f "$f" ] && echo "$f"; done | LC_ALL=C sort -u)"
all_sh="$(cd "$TREE" && find scripts .github/scripts -type f -name '*.sh' | LC_ALL=C sort)"
unchecked="$(printf '%s\n' "$all_sh" | grep -vxF -f <(printf '%s\n' "$sc_files") | tr '\n' ' ')"
check "...and every *.sh in scripts/ and .github/scripts/" "not shellchecked: $unchecked" test -z "$unchecked"
check "the CI runs these tests" "ci.yml does not run scripts/tests/run.sh" \
  grep -q '^        run: scripts/tests/run.sh$' "$CI"

# --- every path named exists
# The scripts/... and .github/... paths the workflows, the Makefile and the scripts (not these tests, which build
# fake trees) name: a path, a directory (scripts/lib/) or a glob that matches at least one file.
sources="$(cd "$TREE" && {
  ls .github/workflows/*.yml Makefile
  find scripts .github/scripts -type f ! -path 'scripts/tests/*' ! -path '*/__pycache__/*'
} | LC_ALL=C sort)"
missing=''
named=0
while IFS= read -r src; do
  while IFS= read -r p; do
    # the String Catalog merge driver's fallback for branches from before the scripts moved to scripts/lib/
    [ "$p" != scripts/merge-xcstrings.py ] || continue
    named=$((named + 1))
    case $p in
    *'*'*)
      # shellcheck disable=SC2086 # a glob on purpose
      [ -n "$(cd "$TREE" && for f in $p; do [ -e "$f" ] && echo "$f"; done)" ] || missing="$missing $src:$p"
      ;;
    *) [ -e "$TREE/$p" ] || missing="$missing $src:$p" ;;
    esac
  done < <(grep -IoE '(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/|[^A-Za-z0-9_./$}-]|^)(scripts|\.github)/[A-Za-z0-9_./*-]*' "$TREE/$src" |
    sed -E 's#^(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/|[^A-Za-z0-9_./$}-])##; s#\.+$##' | LC_ALL=C sort -u)
done <<<"$sources"
if [ "$named" -gt 20 ] && [ -z "$missing" ]; then
  ok "every scripts/... and .github/... path the workflows, the Makefile and the scripts name exists ($named)"
else
  nok "every scripts/... and .github/... path the workflows, the Makefile and the scripts name exists" "named: $named; missing:$missing"
fi
# Paths relative to a script's own directory: "$(dirname "$0")/x" and "$HERE/x"
rel_missing=''
while IFS= read -r src; do
  case $src in *.sh) ;; *) continue ;; esac
  dir="$(dirname "$TREE/$src")"
  while IFS= read -r p; do
    [ -e "$dir/$p" ] || rel_missing="$rel_missing $src:$p"
  done < <(sed -nE 's#.*"\$\(dirname "\$0"\)/([A-Za-z0-9_./-]+)".*#\1#p; s#.*"\$HERE/([A-Za-z0-9_./-]+)".*#\1#p' "$TREE/$src")
done <<<"$sources"
check "every path a script names relative to its own directory exists" "missing:$rel_missing" test -z "$rel_missing"
check "scripts/lib/common.sh's ROOT is the repository root" "common.sh does not go up two directories" \
  has 'ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"' "$TREE/scripts/lib/common.sh"
# The Python helpers find the root by going up from their own file
if command -v python3 >/dev/null 2>&1; then
  # -B: no __pycache__ in the tree
  roots="$(python3 -I -B - "$TREE" 2>&1 <<'PY'
import importlib.util, os, sys
root = os.path.realpath(sys.argv[1])
for rel in ("scripts/lib/lint-copy.py", "scripts/lib/l10n/l10n.py"):
    spec = importlib.util.spec_from_file_location("probe", os.path.join(root, rel))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if os.path.realpath(module.ROOT) != root:
        print(f"{rel}: ROOT {module.ROOT}")
PY
)"
  check "the Python helpers' ROOT is the repository root" "$roots" test -z "$roots"
else
  echo "# skip the Python helpers' ROOT is the repository root: no python3"
fi

# --- release.yml's own checks, run: the step's script under the workflow's shell, with exactly the release files
# step_script <workflow> <step name>: the `run: |` block of that step, unindented
step_script() {
  awk -v name="      - name: $2" '
    $0 == name { on = 1; next }
    on && /^      - / { exit }
    on && /^        run: \|$/ { body = 1; next }
    body && /^          / { print substr($0, 11); next }
    body && /^$/ { print; next }
    body { exit }' "$1"
}
if command -v shasum >/dev/null 2>&1; then
  w="$(mktemp -d "${TMPDIR:-/tmp}/workflows_test.XXXXXX")"
  mkdir -p "$w/tree/scripts/lib" "$w/runner/out"
  cp "$TREE/scripts/lib/version.sh" "$w/tree/scripts/lib/"
  echo 1.2.3 >"$w/tree/VERSION"
  for f in Cranny-1.2.3.dmg Cranny-1.2.3.zip; do echo "$f" >"$w/runner/out/$f"; done
  (cd "$w/runner/out" && shasum -a 256 Cranny-1.2.3.zip Cranny-1.2.3.dmg >Cranny-1.2.3.sha256)
  step_script "$RELEASE" "Check the release files" >"$w/step.sh"
  run_step() { (cd "$w/tree" && RUNNER_TEMP="$w/runner" VERSION=1.2.3 bash --noprofile --norc -euo pipefail "$w/step.sh") >"$w/out.txt" 2>&1; }
  check "release.yml's 'Check the release files' is extracted" "no run: block" matches -F 'release_assets' "$w/step.sh"
  check "...passes with exactly the release files (no dotfiles: an unmatched glob must not fail the step)" \
    "$(run_step; cat "$w/out.txt")" run_step
  touch "$w/runner/out/extra.txt"
  check "...fails with a file more" "it passed" eval '! run_step && matches -F "::error::The build holds" "$w/out.txt"'
  rm "$w/runner/out/extra.txt"
  echo changed >>"$w/runner/out/Cranny-1.2.3.zip"
  check "...fails when the sums do not match" "it passed" eval '! run_step'
  rm -rf "$w"
else
  echo "# skip release.yml's 'Check the release files' run: no shasum"
fi

echo "# $pass passed, $fail failed"
[ "$fail" = 0 ]
