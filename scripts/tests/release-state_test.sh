#!/usr/bin/env bash
# Tests of .github/scripts/release-state.sh: a throwaway clone of a local bare "origin" with tags in a temp dir
# (TMPDIR), holding only what the script reads (.github/scripts/release-state.sh, scripts/lib/version.sh, VERSION),
# and a curl stub (first on PATH) in place of the GitHub API: no network. Runs the script under $TEST_BASH (default:
# bash from PATH).
#
#   scripts/tests/release-state_test.sh          KEEP=1 keeps the temp dir
#
# Prints 'ok <name>' / 'not ok <name>: <why>' and exits non-zero on a failure.
# The conditions of check() are eval'd when it runs: single quotes on purpose, and the variables they read are
# set outside them.
# shellcheck disable=SC2016,SC2034
set -u
# SIGPIPE ignored, as on the GitHub runner (every step inherits that from its Node.js), for these tests and the
# scripts they run: a reader that stops early makes its writer fail with "Broken pipe" there instead of dying quietly
trap "" PIPE

HERE="$(cd "$(dirname "$0")" && pwd -P)"
TREE="$(cd "$HERE/../.." && pwd -P)"
BASH_BIN="${TEST_BASH:-bash}"
# no temp dir stops here: an empty WORK would make the current directory (the checkout) the work dir, and the
# EXIT trap would delete it
if ! WORK="$(mktemp -d "${TMPDIR:-/tmp}/release-state-test.XXXXXX")" || ! WORK="$(cd "$WORK" && pwd -P)"; then
  echo "not ok no temp dir in ${TMPDIR:-/tmp}"
  exit 1
fi
if [ -z "${KEEP:-}" ]; then trap 'rm -rf "$WORK"' EXIT; else echo "# work dir: $WORK"; fi

export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
GIT_CEILING_DIRECTORIES="$(dirname "$WORK")"
export GIT_CEILING_DIRECTORIES
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GH_TOKEN GITHUB_API_URL VERSION STUB_STATUS STUB_FAIL
mkdir -p "$HOME"
# release-state.sh's temp file lands here, an absolute path whatever the caller's TMPDIR (the script runs in REPO):
# the test checks that none is left behind
mkdir -p "$WORK/tmp"
export TMPDIR="$WORK/tmp"

pass=0 fail=0
ok() {
  echo "ok $1"
  pass=$((pass + 1))
}
nok() {
  echo "not ok $1: $2"
  fail=$((fail + 1))
}
check() {
  if eval "$2"; then ok "$1"; else nok "$1" "rc=$RC; condition: $2; stdout: $OUT; stderr: $ERR"; fi
}
has_err() { case $ERR in *"$1"*) return 0 ;; esac; return 1; }
logged() { grep -qxF -- "$1" "$WORK/curl.log" 2>/dev/null; }
# asked <tag>: the one API request was the published release of that tag
asked() { logged "https://api.github.com/repos/owner/repo/releases/tags/$1"; }
tmp_empty() { [ -z "$(ls -A "$WORK/tmp")" ]; }

echo "# .github/scripts/release-state.sh under $("$BASH_BIN" -c 'echo "bash $BASH_VERSION"'), $(git --version)"

# The GitHub API: a published release exists when $WORK/releases/<tag> does
mkdir -p "$WORK/bin" "$WORK/releases"
cat >"$WORK/bin/curl" <<'EOF'
#!/bin/sh
# curl stub: logs its arguments one per line, writes a body to its -o file and prints the HTTP status of the URL
# (its last argument): STUB_STATUS when set, else 200 when $STUB_RELEASES/<tag> exists, else 404. STUB_FAIL=1 fails
# like a refused connection (status 000, exit 7). An -o that is not a regular file fails the way curl 8.5
# (ubuntu-24.04) fails on a retry, when it cannot truncate it: exit 23, no status.
for a; do printf '%s\n' "$a"; done >"$STUB_LOG"
out='' prev=''
for a; do
  if [ "$prev" = -o ]; then out=$a; fi
  prev=$a url=$a
done
if [ -n "${STUB_FAIL:-}" ]; then printf 000; exit 7; fi
if [ -n "$out" ]; then
  if [ -e "$out" ] && [ ! -f "$out" ]; then exit 23; fi
  printf '{}' >"$out"
fi
if [ -n "${STUB_STATUS:-}" ]; then printf '%s' "$STUB_STATUS"
elif [ -e "$STUB_RELEASES/${url##*/}" ]; then printf 200
else printf 404
fi
EOF
chmod +x "$WORK/bin/curl"
export STUB_LOG="$WORK/curl.log" STUB_RELEASES="$WORK/releases"

# origin: A (plain tag 0.1.0) - B (annotated tag v0.2.0) - C (tag not-a-release); VERSION 0.3.0
SEED="$WORK/seed"
mkdir -p "$SEED/scripts/lib" "$SEED/.github/scripts"
cp "$TREE/scripts/lib/version.sh" "$SEED/scripts/lib/"
cp "$TREE/.github/scripts/release-state.sh" "$SEED/.github/scripts/"
printf '0.3.0\n' >"$SEED/VERSION"
(
  set -e
  cd "$SEED"
  git -c init.defaultBranch=main init -q .
  git symbolic-ref HEAD refs/heads/main
  git add -A
  git commit -q -m A
  git tag 0.1.0
  git commit -q --allow-empty -m B
  git tag -a v0.2.0 -m annotated
  git commit -q --allow-empty -m C
  git tag not-a-release
  git -c init.defaultBranch=main init -q --bare "$WORK/origin.git"
  git push -q "$WORK/origin.git" main --tags
  git clone -q "$WORK/origin.git" "$WORK/repo"
  [ -f "$WORK/repo/.github/scripts/release-state.sh" ]
) || {
  echo "not ok the test fixture could not be built"
  exit 1
}
REPO="$WORK/repo"
A=$(git -C "$REPO" rev-parse 0.1.0) B=$(git -C "$REPO" rev-parse 'v0.2.0^{commit}') C=$(git -C "$REPO" rev-parse HEAD)

# rs <GITHUB_SHA> [VAR=value...]: release-state.sh, run in REPO as release.yml runs it; sets OUT, ERR, RC
rs() {
  local sha="$1"
  shift
  rm -f "$WORK/curl.log"
  OUT="$(cd "$REPO" && env PATH="$WORK/bin:$PATH" GITHUB_REPOSITORY=owner/repo GITHUB_SHA="$sha" "$@" \
    "$BASH_BIN" .github/scripts/release-state.sh 2>"$WORK/err")"
  RC=$?
  ERR="$(cat "$WORK/err")"
}
# tag_origin <tag> <commit> [annotated]: puts the tag on origin only (the clone does not fetch it)
tag_origin() {
  if [ -n "${3:-}" ]; then
    git -C "$WORK/origin.git" tag -f -a "$1" -m annotated "$2" >/dev/null
  else
    git -C "$WORK/origin.git" tag -f "$1" "$2" >/dev/null
  fi
}
untag_origin() { git -C "$WORK/origin.git" tag -d "$1" >/dev/null; }
# version_file <content>: REPO's VERSION holds exactly that (printf format)
version_file() {
  # shellcheck disable=SC2059 # the content is a format on purpose: \n, \t, \r
  printf "$1" >"$REPO/VERSION"
}

# --- new, and the request it makes
rs "$C"
check "new: no release and no tag of VERSION's 0.3.0" '[ $RC = 0 ] && [ "$OUT" = new ] && [ -z "$ERR" ]'
check "...asks the API for the published release of tag v0.3.0, without a token" \
  'asked v0.3.0 && logged "Accept: application/vnd.github+json" && ! grep -q Authorization "$WORK/curl.log"'
check "...never for the plain tag 0.3.0: the release tag is vX.Y.Z (release_tag)" \
  '! grep -q "/releases/tags/0\.3\.0$" "$WORK/curl.log" && [ "$(grep -c /releases/tags/ "$WORK/curl.log")" = 1 ]'
check "...the answer goes to a temp file, not /dev/null (curl 8.5 cannot retry into it), and the file is removed" \
  'grep -q "^$WORK/tmp/" "$WORK/curl.log" && ! logged /dev/null && tmp_empty'
rs "$C" GH_TOKEN=secret-token GITHUB_API_URL=https://ghe.example.invalid/api/v3
check "...with GH_TOKEN as a bearer token and GITHUB_API_URL" \
  '[ "$OUT" = new ] && logged "Authorization: Bearer secret-token" && logged "https://ghe.example.invalid/api/v3/repos/owner/repo/releases/tags/v0.3.0"'
rs "$C" GH_TOKEN=
check "...an empty GH_TOKEN sends no Authorization header" '[ "$OUT" = new ] && ! grep -q Authorization "$WORK/curl.log"'
rs "$C" VERSION=0.4.0
check "VERSION overrides the VERSION file" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.4.0'
OUT="$(cd "$WORK" && env PATH="$WORK/bin:$PATH" GITHUB_REPOSITORY=owner/repo GITHUB_SHA="$C" \
  "$BASH_BIN" "$REPO/.github/scripts/release-state.sh" 2>"$WORK/err")"
RC=$? ERR="$(cat "$WORK/err")"
check "...run from another directory it reads its own checkout" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.3.0'

# --- retry, released, a tag elsewhere
tag_origin v0.3.0 "$C"
rs "$C"
check "retry: the tag v0.3.0 is on GITHUB_SHA, no release" '[ $RC = 0 ] && [ "$OUT" = retry ] && [ -z "$ERR" ]'
tag_origin v0.3.0 "$C" annotated
rs "$C"
check "retry: an annotated tag is followed to its commit" '[ $RC = 0 ] && [ "$OUT" = retry ]'
tag_origin v0.3.0 "$A"
rs "$C"
check "a tag v0.3.0 on another commit without a release is refused" \
  '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error::Tag v0.3.0 points at $A, not $C, and has no release. Delete the tag or bump the version (scripts/make-release.sh)."'
tag_origin v0.3.0 "$A" annotated
rs "$C"
check "...an annotated one too, named by its commit, not the tag object" '[ $RC = 1 ] && has_err "::error::Tag v0.3.0 points at $A, not $C"'
touch "$WORK/releases/v0.3.0"
rs "$C"
check "released: a published release, wherever its tag is" '[ $RC = 0 ] && [ "$OUT" = released ] && [ -z "$ERR" ]'
untag_origin v0.3.0
rs "$C"
check "released: a published release whose tag is gone is still released" '[ $RC = 0 ] && [ "$OUT" = released ]'
rm -f "$WORK/releases/v0.3.0"
touch "$WORK/releases/0.3.0"
rs "$C"
check "a release found only under the plain tag 0.3.0 is not asked for: new" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.3.0'
rm -f "$WORK/releases/0.3.0"
touch "$WORK/releases/v0.1.0"
rs "$C" VERSION=0.1.0
check "released: an old version with a published release is released, not refused" '[ $RC = 0 ] && [ "$OUT" = released ]'
rm -f "$WORK/releases/v0.1.0"

# --- the version against the other release tags (vX.Y.Z and X.Y.Z)
rs "$C" VERSION=0.2.0
check "the version of an existing tag v0.2.0 on another commit, without a release, is refused" \
  '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error::Tag v0.2.0 points at $B, not $C, and has no release."'
rs "$B" VERSION=0.2.0
check "...on GITHUB_SHA it is the tag of this release: retry (the annotated tag followed to its commit)" \
  '[ $RC = 0 ] && [ "$OUT" = retry ]'
tag_origin 0.2.0 "$B"
rs "$B" VERSION=0.2.0
check "...but not with a plain tag 0.2.0 beside it: X.Y.Z counts as release X.Y.Z" \
  '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error file=VERSION::Version 0.2.0 is not higher than the existing tag 0.2.0. Bump it with scripts/make-release.sh."'
untag_origin 0.2.0
tag_origin 0.3.0 "$C"
rs "$C"
check "a plain tag 0.3.0 of the version itself is refused, even on GITHUB_SHA" \
  '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error file=VERSION::Version 0.3.0 is not higher than the existing tag 0.3.0. Bump it with scripts/make-release.sh."'
tag_origin v0.3.0 "$C"
rs "$C"
check "...and with the release tag v0.3.0 next to it" '[ $RC = 1 ] && has_err "Version 0.3.0 is not higher than the existing tag 0.3.0."'
untag_origin v0.3.0
untag_origin 0.3.0
rs "$C" VERSION=0.1.5
check "a version below an existing tag is refused" \
  '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error file=VERSION::Version 0.1.5 is not higher than the existing tag v0.2.0."'
tag_origin 0.9.0 "$A"
rs "$C"
check "a plain tag only on origin counts (0.3.0 below 0.9.0)" '[ $RC = 1 ] && has_err "Version 0.3.0 is not higher than the existing tag 0.9.0."'
untag_origin 0.9.0
tag_origin v0.9.0 "$A"
rs "$C"
check "a v tag only on origin counts (0.3.0 below v0.9.0)" '[ $RC = 1 ] && has_err "Version 0.3.0 is not higher than the existing tag v0.9.0."'
untag_origin v0.9.0
tag_origin v0.10.0 "$A" annotated
rs "$C" VERSION=0.9.0
check "versions compare as numbers (0.9.0 below the annotated v0.10.0)" '[ $RC = 1 ] && has_err "Version 0.9.0 is not higher than the existing tag v0.10.0."'
rs "$C" VERSION=0.11.0
check "...and 0.11.0 above it is new" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.11.0'
untag_origin v0.10.0
tag_origin 0.999999999.0 "$A"
rs "$C" VERSION=0.999999998.0
check "nine-digit numbers compare too (0.999999998.0 below 0.999999999.0)" '[ $RC = 1 ] && has_err "Version 0.999999998.0 is not higher than the existing tag 0.999999999.0."'
rs "$C" VERSION=1.0.0
check "...and 1.0.0 above it is new" '[ $RC = 0 ] && [ "$OUT" = new ]'
untag_origin 0.999999999.0
for t in v0.9 0.9.0-rc1 V9.0.0 vv9.0.0 09.0.0 release-9.0.0; do tag_origin "$t" "$A"; done
rs "$C"
check "tags that are not releases (v0.9, 0.9.0-rc1, V9.0.0, vv9.0.0, 09.0.0, release-9.0.0) do not count" \
  '[ $RC = 0 ] && [ "$OUT" = new ] && [ -z "$ERR" ]'
for t in v0.9 0.9.0-rc1 V9.0.0 vv9.0.0 09.0.0 release-9.0.0; do untag_origin "$t"; done

# --- the version itself
for v in v0.3.0 0.3 0.3.0.0 00.3.0 0.03.0 0.3.00 0.3.0-rc1 -1.0.0 0.3.x 1000000000.0.0 0.1000000000.0 "0.3.0 " " 0.3.0" ""; do
  rs "$C" VERSION="$v"
  # an empty VERSION falls back to the VERSION file, like an unset one
  if [ -z "$v" ]; then
    check "an empty VERSION reads the VERSION file" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.3.0'
  else
    check "version '$v' (not X.Y.Z, or a number of more than 9 digits) is refused before any API call" \
      '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error file=VERSION::Version \"$v\" must be X.Y.Z (no leading zeros, no \"v\", at most 9 digits per number)" && [ ! -e "$WORK/curl.log" ]'
  fi
done
rs "$C" VERSION=999999999.999999999.999999999
check "9 digits per number is fine (999999999.999999999.999999999)" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v999999999.999999999.999999999'
rs "$C" VERSION=0.1000.0
check "minor and patch are not limited to 3 digits (0.1000.0)" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.1000.0'
rs "$C" VERSION=0.3.1000
check "...0.3.1000 neither" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.3.1000'

version_file '\n  0.3.0 \t\r\n\n'
rs "$C"
check "the VERSION file's one line is read without the blanks and blank lines around it" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.3.0'
version_file '0.3.0'
rs "$C"
check "...and without a final newline" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.3.0'
version_file 'v0.3.0\n'
rs "$C"
check "a VERSION file with v0.3.0 is refused" \
  '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error file=VERSION::Version \"v0.3.0\" must be X.Y.Z" && [ ! -e "$WORK/curl.log" ]'
version_file '0.3.0 beta\n'
rs "$C"
check "a VERSION line with more than the version is refused" '[ $RC = 1 ] && has_err "Version \"0.3.0 beta\" must be X.Y.Z"'
version_file '0.3.0\n0.3.0\n'
rs "$C"
check "a VERSION file with two lines is refused" \
  '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error file=VERSION::VERSION must hold exactly one line, the version X.Y.Z." && [ ! -e "$WORK/curl.log" ]'
version_file '\n \n'
rs "$C"
check "a blank VERSION file is refused" '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "VERSION must hold exactly one line, the version X.Y.Z."'
rs "$C" VERSION=0.4.0
check "...unless VERSION is given" '[ $RC = 0 ] && [ "$OUT" = new ] && asked v0.4.0'
rm -f "$REPO/VERSION"
rs "$C"
check "a missing VERSION file is refused" '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error file=VERSION::VERSION must hold exactly one line, the version X.Y.Z." && [ ! -e "$WORK/curl.log" ]'
git -C "$REPO" checkout -q -- VERSION

# --- the API and origin
rs "$C" STUB_STATUS=500
check "an API error is refused" \
  '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error::The GitHub API answered HTTP 500 for release v0.3.0." && tmp_empty'
rs "$C" STUB_STATUS=403
check "a rate-limited API (403) is refused, not taken for 'no release'" '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "HTTP 403 for release v0.3.0"'
rs "$C" STUB_STATUS=401
check "a refused token (401) is refused" '[ $RC = 1 ] && has_err "HTTP 401"'
rs "$C" STUB_STATUS=301
check "a redirect (301) is not a release" '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "HTTP 301"'
rs "$C" STUB_FAIL=1
check "no answer from the API is refused" '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "HTTP 000" && tmp_empty'
git -C "$REPO" remote set-url origin "$WORK/missing.git"
rs "$C"
check "unreadable origin tags are refused" '[ $RC = 1 ] && [ -z "$OUT" ] && has_err "::error::Cannot read the tags of origin (git ls-remote)."'
touch "$WORK/releases/v0.3.0"
rs "$C"
check "...but a published release needs no tags: released" '[ $RC = 0 ] && [ "$OUT" = released ]'
rm -f "$WORK/releases/v0.3.0"
git -C "$REPO" remote set-url origin "$WORK/origin.git"
rs "$C" GITHUB_REPOSITORY=
check "GITHUB_REPOSITORY is required" '[ $RC != 0 ] && [ -z "$OUT" ] && [ ! -e "$WORK/curl.log" ]'
rs ""
check "GITHUB_SHA is required" '[ $RC != 0 ] && [ -z "$OUT" ] && [ ! -e "$WORK/curl.log" ]'

# --- tag_commit (scripts/lib/version.sh) on real `git ls-remote --tags` output: release-state.sh and the tag checks
# of release.yml's publish job read the tag's commit with it
# tc <tag>: tag_commit under BASH_BIN, fed origin's `git ls-remote --tags`; sets OUT, RC
tc() {
  OUT="$(git -C "$REPO" ls-remote --tags origin | "$BASH_BIN" -c '. "$1/scripts/lib/version.sh" && tag_commit "$2"' tc "$REPO" "$1")"
  RC=$?
  ERR=
}
B_TAG=$(git -C "$REPO" rev-parse v0.2.0)
tc 0.1.0
check "tag_commit: a lightweight tag's commit" '[ $RC = 0 ] && [ "$OUT" = "$A" ]'
tc v0.2.0
check "tag_commit: an annotated tag is followed to its commit, not the tag object" '[ $RC = 0 ] && [ "$OUT" = "$B" ] && [ "$B" != "$B_TAG" ]'
tag_origin v0.3.0 "$C" annotated
tc v0.3.0
check "tag_commit: an annotated release tag made by hand on GITHUB_SHA is GITHUB_SHA" '[ $RC = 0 ] && [ "$OUT" = "$C" ]'
tc 0.3.0
check "tag_commit: the plain 0.3.0 is another tag than v0.3.0" '[ $RC = 0 ] && [ -z "$OUT" ]'
tc v0.1.0
check "tag_commit: ...and v0.1.0 another tag than the plain 0.1.0" '[ $RC = 0 ] && [ -z "$OUT" ]'
tc v0.3
check "tag_commit: a prefix of a tag is not the tag" '[ $RC = 0 ] && [ -z "$OUT" ]'
untag_origin v0.3.0
tc v0.3.0
check "tag_commit: nothing for a tag that is not there" '[ $RC = 0 ] && [ -z "$OUT" ]'

echo "# $pass passed, $fail failed"
[ "$fail" = 0 ]
