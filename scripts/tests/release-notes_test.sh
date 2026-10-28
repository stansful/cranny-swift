#!/usr/bin/env bash
# Tests of .github/scripts/release-notes.sh: throwaway repositories in a temp dir (TMPDIR) holding only what the
# script reads (.github/scripts/release-notes.sh, scripts/lib/version.sh, VERSION), with release tags (vX.Y.Z and
# X.Y.Z), a side branch and a merge. Runs the script under $TEST_BASH (default: bash from PATH). The notes are the
# body of GitHub release "Cranny X.Y.Z": only "- <commit subject>" lines.
#
#   scripts/tests/release-notes_test.sh          KEEP=1 keeps the temp dir
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
if ! WORK="$(mktemp -d "${TMPDIR:-/tmp}/release-notes-test.XXXXXX")" || ! WORK="$(cd "$WORK" && pwd -P)"; then
  echo "not ok no temp dir in ${TMPDIR:-/tmp}"
  exit 1
fi
if [ -z "${KEEP:-}" ]; then trap 'rm -rf "$WORK"' EXIT; else echo "# work dir: $WORK"; fi

export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
GIT_CEILING_DIRECTORIES="$(dirname "$WORK")"
export GIT_CEILING_DIRECTORIES
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GH_REPO GITHUB_REPOSITORY GITHUB_SHA VERSION
mkdir -p "$HOME"

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
  if eval "$2"; then ok "$1"; else nok "$1" "rc=$RC; condition: $2; output:
$OUT"; fi
}
# notes <line...>: the output is exactly these lines
notes() { [ "$OUT" = "$(printf '%s\n' "$@")" ]; }

echo "# .github/scripts/release-notes.sh under $("$BASH_BIN" -c 'echo "bash $BASH_VERSION"'), $(git --version)"

# Every commit one second after the one before, so `git log` lists them in a fixed order
tick=1700000000
c() {
  tick=$((tick + 1))
  GIT_AUTHOR_DATE="@$tick +0000" GIT_COMMITTER_DATE="@$tick +0000" git -C "$REPO" commit -q --allow-empty "$@"
}
# new_repo <dir>: a repository with the scripts and VERSION 0.2.0, first commit 'feat: first'
new_repo() {
  REPO="$1"
  mkdir -p "$REPO/scripts/lib" "$REPO/.github/scripts"
  cp "$TREE/scripts/lib/version.sh" "$REPO/scripts/lib/"
  cp "$TREE/.github/scripts/release-notes.sh" "$REPO/.github/scripts/"
  printf '0.2.0\n' >"$REPO/VERSION"
  git -c init.defaultBranch=main init -q "$REPO"
  git -C "$REPO" symbolic-ref HEAD refs/heads/main
  git -C "$REPO" add -A
  c -m 'feat: first'
}
# rn [VAR=value...]: release-notes.sh of REPO, run from WORK; sets OUT (stdout and stderr) and RC
rn() {
  OUT="$(cd "$WORK" && env "$@" "$BASH_BIN" "$REPO/.github/scripts/release-notes.sh" 2>&1)"
  RC=$?
}

# 0.0.9 (plain, annotated) - fix: second (v0.1.0) - [side: side work (v0.1.5)] - Release: version 0.2.0 -
# topic merge (feat: topic, Release: version numbers in the docs) - fix: third
new_repo "$WORK/main"
git -C "$REPO" tag -a 0.0.9 -m annotated
c -m 'fix: second'
git -C "$REPO" tag v0.1.0
git -C "$REPO" checkout -q -b side
c -m 'side work'
git -C "$REPO" tag v0.1.5
git -C "$REPO" checkout -q main
c -m 'Release: version 0.2.0'
git -C "$REPO" checkout -q -b topic
c -m 'feat: topic'
c -m 'Release: version numbers in the docs'
git -C "$REPO" checkout -q main
tick=$((tick + 1))
GIT_AUTHOR_DATE="@$tick +0000" GIT_COMMITTER_DATE="@$tick +0000" git -C "$REPO" merge -q --no-ff -m 'Merge branch topic' topic
c -m 'fix: third' -m 'A body line that is not a subject.'

rn
check "the commits since the previous release tag in the history (v0.1.0, not the side branch's v0.1.5), newest first" \
  '[ $RC = 0 ] && notes "- fix: third" "- Release: version numbers in the docs" "- feat: topic"'
check "...only '- <subject>' lines: no header, no merges, no release commits, no bodies" \
  '[ -z "$(printf "%s\n" "$OUT" | grep -v "^- ")" ] && ! printf "%s\n" "$OUT" | grep -q -e Merge -e "version 0.2.0" -e "body line"'
git -C "$REPO" tag v0.2.0
rn
check "this release's own tag v0.2.0 on GITHUB_SHA (a retry) is not the previous one" \
  '[ $RC = 0 ] && notes "- fix: third" "- Release: version numbers in the docs" "- feat: topic"'
git -C "$REPO" tag -d v0.2.0 >/dev/null
git -C "$REPO" tag -a v0.2.0 -m annotated
rn
check "...an annotated one neither" '[ $RC = 0 ] && notes "- fix: third" "- Release: version numbers in the docs" "- feat: topic"'
rn VERSION=0.2.1
check "...but it is the previous release of the next version (VERSION=0.2.1)" '[ $RC = 0 ] && notes "- Release 0.2.1"'
git -C "$REPO" tag -d v0.2.0 >/dev/null
rn GITHUB_SHA=v0.1.0 VERSION=0.1.0
check "GITHUB_SHA and VERSION: the history up to that commit, since the plain tag 0.0.9 (its own v0.1.0 skipped)" \
  '[ $RC = 0 ] && notes "- fix: second"'
rn GITHUB_SHA="$(git -C "$REPO" rev-parse side)" VERSION=0.1.5
check "GITHUB_SHA on the side branch: since v0.1.0 there" '[ $RC = 0 ] && notes "- side work"'
printf '0.3.0\n' >"$REPO/VERSION"
rn
check "the version comes from the VERSION file: 0.3.0, still since v0.1.0" \
  '[ $RC = 0 ] && notes "- fix: third" "- Release: version numbers in the docs" "- feat: topic"'
git -C "$REPO" tag v0.2.0
rn
check "...and v0.2.0 is then the previous release: '- Release 0.3.0'" '[ $RC = 0 ] && notes "- Release 0.3.0"'
printf '\n  0.2.0 \t\r\n\n' >"$REPO/VERSION"
rn
check "the VERSION file's line is read without the blanks around it (0.2.0, so v0.2.0 is its own tag)" \
  '[ $RC = 0 ] && notes "- fix: third" "- Release: version numbers in the docs" "- feat: topic"'
git -C "$REPO" tag -d v0.2.0 >/dev/null

new_repo "$WORK/first"
c -m 'fix: a'
rn
check "no release tag yet: every commit" '[ $RC = 0 ] && notes "- fix: a" "- feat: first"'
git -C "$REPO" tag not-a-release
git -C "$REPO" tag v0.1
git -C "$REPO" tag 0.1.0-rc1
git -C "$REPO" tag V0.1.0
rn
check "...tags that are not releases (not-a-release, v0.1, 0.1.0-rc1, V0.1.0) do not count" '[ $RC = 0 ] && notes "- fix: a" "- feat: first"'
git -C "$REPO" tag 0.1.0
rn
check "a plain tag X.Y.Z on GITHUB_SHA itself, nothing since: '- Release X.Y.Z'" '[ $RC = 0 ] && notes "- Release 0.2.0"'
c -m 'Release: version 0.2.0'
rn
check "only a release commit since the last tag: '- Release X.Y.Z'" '[ $RC = 0 ] && notes "- Release 0.2.0"'
rn VERSION=0.2.1
check "...with the version of VERSION" '[ $RC = 0 ] && notes "- Release 0.2.1"'
c -m 'Release: version 0.1.1'
c -m 'Release: version'
rn
check "every 'Release: version <digits>' commit is left out, not one that only starts like it" '[ $RC = 0 ] && notes "- Release: version"'
for v in v0.2.0 0.2 0.2.0.0 02.0.0 0.2.0-rc1 1000000000.0.0 "0.2.0 "; do
  rn VERSION="$v"
  check "a malformed VERSION '$v' is refused" '[ $RC = 1 ] && [ "$OUT" = "release-notes: '"'"'$v'"'"' is not X.Y.Z" ]'
done
printf '0.2.0\n0.2.0\n' >"$REPO/VERSION"
rn
check "a VERSION file with two lines is refused" '[ $RC = 1 ] && [ "$OUT" = "release-notes: '"''"' is not X.Y.Z" ]'
rn VERSION=0.2.0
check "...unless VERSION is given" '[ $RC = 0 ] && notes "- Release: version"'
printf 'v0.2.0\n' >"$REPO/VERSION"
rn
check "a VERSION file with v0.2.0 is refused" '[ $RC = 1 ] && [ "$OUT" = "release-notes: '"'"'v0.2.0'"'"' is not X.Y.Z" ]'
rm -f "$REPO/VERSION"
rn
check "a missing VERSION file is refused" '[ $RC = 1 ] && case $OUT in *"release-notes: '"''"' is not X.Y.Z") true ;; *) false ;; esac'

# Versions compare as numbers across both tag forms: 0.1.9 (plain) is below v0.1.10
new_repo "$WORK/numeric"
git -C "$REPO" tag 0.1.9
c -m 'fix: x'
git -C "$REPO" tag v0.1.10
c -m 'fix: y'
rn
check "the previous release is the highest tag as numbers (v0.1.10 above the plain 0.1.9)" '[ $RC = 0 ] && notes "- fix: y"'
git -C "$REPO" tag 0.1.11 'HEAD~2'
rn
check "...the highest version, not the nearest tag: a plain 0.1.11 on an older commit than v0.1.10" \
  '[ $RC = 0 ] && notes "- fix: y" "- fix: x"'

echo "# $pass passed, $fail failed"
[ "$fail" = 0 ]
