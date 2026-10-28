#!/usr/bin/env bash
# Tests of scripts/lib/version.sh: every function runs in a fresh $TEST_BASH (default: bash from PATH, /bin/bash 3.2
# on macOS) under `set -euo pipefail`, as the scripts that source it run. Files go to a temp dir (TMPDIR); the
# repository is only read (version.sh, a copy of VERSION, and scripts/lib/dist.sh for the names of the release files).
#
#   scripts/tests/version_test.sh          KEEP=1 keeps the temp dir
#
# Prints 'ok <name>' / 'not ok <name>: <why>' and exits non-zero on a failure. Names and failures show strings
# quoted as bash does (printf %q): $'1.2.3\r' is 1.2.3 and a carriage return.
# The conditions of check() are eval'd when it runs: single quotes on purpose, and the variables they read are
# set outside them.
# shellcheck disable=SC2016,SC2034
set -u
# SIGPIPE ignored, as on the GitHub runner (every step inherits that from its Node.js), for these tests and the
# scripts they run: a reader that stops early makes its writer fail with "Broken pipe" there instead of dying quietly
trap "" PIPE

HERE="$(cd "$(dirname "$0")" && pwd -P)"
TREE="$(cd "$HERE/../.." && pwd -P)"
LIB="$TREE/scripts/lib/version.sh"
BASH_BIN="${TEST_BASH:-bash}"
# no temp dir stops here: an empty WORK would make the current directory (the checkout) the work dir, and the
# EXIT trap would delete it
if ! WORK="$(mktemp -d "${TMPDIR:-/tmp}/version-test.XXXXXX")" || ! WORK="$(cd "$WORK" && pwd -P)"; then
  echo "not ok no temp dir in ${TMPDIR:-/tmp}"
  exit 1
fi
if [ -z "${KEEP:-}" ]; then trap 'rm -rf "$WORK"' EXIT; else echo "# work dir: $WORK"; fi
# temp files of the functions land here: the test checks that none is left behind
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
  if eval "$2"; then ok "$1"; else nok "$1" "rc=$RC; condition: $2; stdout: $(q "$OUT"); stderr: $(q "$ERR")"; fi
}
# fn <stdin (printf %b)> <function> [args...]: the function in a fresh BASH_BIN that sourced version.sh under
# set -euo pipefail; sets OUT, ERR, RC. stderr comes through the command substitution, which waits for every
# process holding it: a process substitution's late error lands in this ERR, not in a later one's
fn() {
  local input="$1"
  shift
  ERR="$(printf '%b' "$input" | "$BASH_BIN" -c 'set -euo pipefail; . "$0"; "$@"' "$LIB" "$@" 2>&1 >"$WORK/out")"
  RC=$?
  OUT="$(cat "$WORK/out")"
}
# is <name> <rc> <stdout>: the last fn exited with rc and printed exactly stdout, and nothing on stderr
is() {
  if [ "$RC" = "$2" ] && [ "$OUT" = "$3" ] && [ -z "$ERR" ]; then
    ok "$1"
  else
    nok "$1" "want rc=$2 stdout $(q "$3"); got rc=$RC stdout $(q "$OUT") stderr $(q "$ERR")"
  fi
}
lines() { printf '%s\n' "$@"; }
q() { printf '%q' "$1"; }
# ls -l and ls -i, of plain names: the portable way to the mode and the inode (stat differs on BSD and GNU)
# shellcheck disable=SC2012
mode() { ls -l "$1" | cut -c1-10; }
# shellcheck disable=SC2012
inode() { ls -i "$1" | awk '{ print $1 }'; }
# <n> lines "1.0.1" ... "1.0.<n>" after a first line, no newline at the end: over a pipe buffer (64 KiB) of
# release_tags output for n = 8000
many_after() { printf '%s' "$1"; awk -v n="$2" 'BEGIN { for (i = 1; i <= n; i++) printf "\n1.0.%d", i }'; }

echo "# scripts/lib/version.sh under $("$BASH_BIN" -c 'echo "bash $BASH_VERSION"')"

# --- version_valid: X.Y.Z, no leading zeros, at most 9 digits per number
for v in 0.0.0 1.2.3 3.7.0 10.20.30 2100.0.0 999999999.999999999.999999999 100000000.0.0 0.100000000.0 \
  0.0.100000000 123456789.987654321.0; do
  fn '' version_valid "$v"
  is "version_valid: '$v' is a version" 0 ''
done
for v in 1000000000.0.0 0.1000000000.0 0.0.1000000000 9999999999.9.9 99999999999999999999.0.0; do
  fn '' version_valid "$v"
  is "version_valid: '$v' has a number over 9 digits" 1 ''
done
for v in 01.2.3 1.02.3 1.2.03 00.0.0 0.00.0 0.0.00 000000001.0.0 0.0.000000000; do
  fn '' version_valid "$v"
  is "version_valid: '$v' has a leading zero" 1 ''
done
for v in v1.2.3 V1.2.3 vv1.2.3 v0.0.0 'v 1.2.3'; do
  fn '' version_valid "$v"
  is "version_valid: $(q "$v") has a v: that is the tag, not the version" 1 ''
done
for v in '' ' ' ' 1.2.3' '1.2.3 ' $'\t1.2.3' $'1.2.3\t' $'1.2.3\r' $'1.2.3\n' $'\n1.2.3' $'1.2.3\n4.5.6' '1. 2.3' \
  '1.2 .3'; do
  fn '' version_valid "$v"
  is "version_valid: $(q "$v") is not a version (blanks)" 1 ''
done
for v in 1 1.2 1.2.3.4 1.2.3-rc1 1.2.3+b a.b.c 1..3 .1.2 1.2. -1.2.3 1,2,3 1.2.x 0x1.2.3; do
  fn '' version_valid "$v"
  is "version_valid: '$v' is not a version" 1 ''
done

# --- version_cmp, version_gt
for c in "1.2.3 1.2.3 0" "1.2.3 1.2.4 -1" "1.2.4 1.2.3 1" "1.2.10 1.2.9 1" "1.2.9 1.2.10 -1" "1.10.0 1.9.999 1" \
  "2.0.0 10.0.0 -1" "0.0.0 0.0.1 -1" "1.0.0 0.999.999 1" "0.1.0 0.0.9 1" "3.7.0 3.6.0 1" "3.7.0 3.7.0 0" \
  "999999999.999999999.999999999 999999999.999999999.999999998 1" \
  "100000000.0.0 99999999.999999999.999999999 1" "0.0.99999999 0.0.100000000 -1" \
  "0.123456789.0 0.987654321.0 -1" "999999999.0.0 999999999.0.0 0" "0.0.999999999 0.1.0 -1"; do
  read -r a b want <<<"$c"
  fn '' version_cmp "$a" "$b"
  is "version_cmp $a $b = $want" 0 "$want"
done
fn '' version_gt 1.2.10 1.2.9
is "version_gt: 1.2.10 > 1.2.9 (numbers, not strings)" 0 ''
fn '' version_gt 10.0.0 9.99.999
is "version_gt: 10.0.0 > 9.99.999" 0 ''
fn '' version_gt 999999999.0.0 99999999.999999999.999999999
is "version_gt: 999999999.0.0 > 99999999.999999999.999999999" 0 ''
fn '' version_gt 1.2.3 1.2.3
is "version_gt: 1.2.3 is not > 1.2.3" 1 ''
fn '' version_gt 1.2.3 1.3.0
is "version_gt: 1.2.3 is not > 1.3.0" 1 ''

# --- version_bump
for c in "1.2.3 patch 1.2.4" "1.2.3 minor 1.3.0" "1.2.3 major 2.0.0" "0.1.0 minor 0.2.0" "0.0.0 patch 0.0.1" \
  "0.1.9 patch 0.1.10" "9.99.999 minor 9.100.0" "3.7.0 major 4.0.0" "3.7.0 minor 3.8.0" "3.7.0 patch 3.7.1" \
  "1.2.999999998 patch 1.2.999999999" "999999998.5.5 major 999999999.0.0"; do
  read -r a b want <<<"$c"
  fn '' version_bump "$a" "$b"
  is "version_bump $a $b = $want" 0 "$want"
done
# past 999999999 the result is printed, and version_valid refuses it
for c in "1.2.999999999 patch 1.2.1000000000" "0.999999999.7 minor 0.1000000000.0" \
  "999999999.1.2 major 1000000000.0.0"; do
  read -r a b want <<<"$c"
  fn '' version_bump "$a" "$b"
  is "version_bump $a $b = $want (10 digits)" 0 "$want"
  fn '' version_valid "$want"
  is "...and version_valid refuses $want" 1 ''
done
for k in bogus '' Patch MINOR патч; do
  fn '' version_bump 1.2.3 "$k"
  is "version_bump: '$k' is not a bump" 1 ''
done

# --- release_tag: the tag of release X.Y.Z is vX.Y.Z
for v in 1.2.3 0.0.0 10.20.30 999999999.999999999.999999999; do
  fn '' release_tag "$v"
  is "release_tag $v = v$v" 0 "v$v"
done
fn '' eval 'release_tag 4.5.6 | release_tags'
is "release_tag: release_tags reads its tag back as version 4.5.6" 0 '4.5.6 v4.5.6'
fn '' eval 'release_tag 4.5.6 | tag_of_version 4.5.6'
is "release_tag: tag_of_version finds its tag" 0 v4.5.6

# --- app_version_parse: exactly one line that is not blank, printed without the blanks around it
fn '1.2.3\n' app_version_parse
is "app_version_parse: the one line" 0 1.2.3
fn '1.2.3' app_version_parse
is "app_version_parse: a last line without a newline" 0 1.2.3
fn '\n\n1.2.3\n\n\n' app_version_parse
is "app_version_parse: blank lines before and after" 0 1.2.3
fn ' \t 1.2.3 \t\n' app_version_parse
is "app_version_parse: spaces and tabs around the version" 0 1.2.3
fn '1.2.3\r\n' app_version_parse
is "app_version_parse: a CRLF line" 0 1.2.3
fn '\r\n \t\r\n\t1.2.3 \r\n\r\n' app_version_parse
is "app_version_parse: CRLF, blank lines of spaces, tabs and CRs around the version" 0 1.2.3
fn '1.2.3\r' app_version_parse
is "app_version_parse: a CR and no newline at the end" 0 1.2.3
fn 'x\n' app_version_parse
is "app_version_parse: the value is not checked" 0 x
fn 'v1.2.3\n' app_version_parse
is "app_version_parse: a v is kept (version_valid refuses it)" 0 v1.2.3
fn '1.2. 3\n' app_version_parse
is "app_version_parse: blanks inside the line are kept (version_valid refuses it)" 0 '1.2. 3'
fn '' app_version_parse
is "app_version_parse: an empty file fails, printing nothing" 1 ''
fn '\n\n' app_version_parse
is "app_version_parse: only newlines fail" 1 ''
fn ' \t\n\r\n  \n' app_version_parse
is "app_version_parse: only blank lines fail" 1 ''
fn '1.2.3\n1.2.3\n' app_version_parse
is "app_version_parse: two version lines fail, printing nothing, even with one value" 1 ''
fn '1.2.3\n\n1.2.4\n' app_version_parse
is "app_version_parse: two different version lines fail" 1 ''
fn '# the version\n1.2.3\n' app_version_parse
is "app_version_parse: any second line that is not blank fails (no comments)" 1 ''

# --- app_version_get: app_version_parse of <root>/VERSION
ROOT="$WORK/a root"
F="$ROOT/VERSION"
mkdir -p "$ROOT"
printf '\n 3.7.0\r\n\n' >"$F"
fn '' app_version_get "$ROOT"
is "app_version_get: reads <root>/VERSION (a root with a space)" 0 3.7.0
printf '3.7.1' >"$F"
fn '' app_version_get "$ROOT"
is "app_version_get: a file without a trailing newline" 0 3.7.1
: >"$F"
fn '' app_version_get "$ROOT"
is "app_version_get: an empty file fails" 1 ''
fn '' app_version_get "$WORK/missing"
check "app_version_get: a missing file fails, printing nothing on stdout" '[ $RC != 0 ] && [ -z "$OUT" ]'
# a copy: the functions never run against the repository
mkdir -p "$WORK/tree"
tree_rc=1
if cp "$TREE/VERSION" "$WORK/tree/VERSION"; then
  fn '' app_version_get "$WORK/tree"
  tree_version=$OUT tree_rc=$RC
  fn '' version_valid "$tree_version"
fi
check "app_version_get: this repository's VERSION has one line, a valid X.Y.Z" '[ "$tree_rc" = 0 ] && [ $RC = 0 ]'

# --- app_version_set: the version line becomes "X.Y.Z", in place; nothing changes on a failure
printf '1.2.3\n' >"$F"
chmod 640 "$F"
before_mode=$(mode "$F") before_inode=$(inode "$F")
fn '' app_version_set "$ROOT" 1.3.0
is "app_version_set: writes 1.3.0, printing nothing" 0 ''
check "...the file is exactly '1.3.0' and a newline" '[ "$(od -An -c "$F" | tr -d " ")" = "1.3.0\\n" ]'
check "...the file keeps its mode and inode" '[ "$(mode "$F")" = "$before_mode" ] && [ "$(inode "$F")" = "$before_inode" ]'
check "...no temp file is left in TMPDIR" '[ -z "$(ls -A "$WORK/tmp")" ]'
fn '' app_version_get "$ROOT"
is "...app_version_get reads it back" 0 1.3.0

# Only the version line changes: blank lines stay, so the release commit is that one line (make-release.sh)
for c in 'blank lines, blanks and CRLF|\r\n  1.2.3 \t\r\n\n|\r\n10.0.0\n\n' 'no trailing newline|1.2.3|10.0.0\n' \
  'a CR|1.2.3\r|10.0.0\n' 'a blank line after it|1.2.3\n\n|10.0.0\n\n'; do
  name=${c%%|*} rest=${c#*|}
  printf '%b' "${rest%%|*}" >"$F"
  want=${rest#*|}
  fn '' app_version_set "$ROOT" 10.0.0
  check "app_version_set: a file with $name becomes '$want' (as od -c spells it)" \
    '[ $RC = 0 ] && [ -z "$OUT$ERR" ] && [ "$(od -An -c "$F" | tr -d " ")" = "$want" ]'
done
check "...the file still keeps its mode and inode" '[ "$(mode "$F")" = "$before_mode" ] && [ "$(inode "$F")" = "$before_inode" ]'

printf '1.3.0\n' >"$WORK/before"
for v in 1.2 v3.9.0 V3.9.0 03.9.0 3.09.0 3.9.00 3.9.0-rc1 '' ' 3.9.0' '3.9.0 ' $'3.9.0\r' $'3.9.0\n4.0.0' \
  1000000000.0.0 0.0.1000000000 x; do
  cat "$WORK/before" >"$F"
  fn '' app_version_set "$ROOT" "$v"
  check "app_version_set: $(q "$v") is refused and the file is unchanged" \
    '[ $RC = 1 ] && [ -z "$OUT" ] && cmp -s "$F" "$WORK/before"'
done

for c in 'that is empty|' 'of blank lines|\n \t\r\n\n' 'with two version lines|1.2.3\n1.2.3\n' \
  'with a second line|1.2.3\n# 1.2.4\n'; do
  printf '%b' "${c#*|}" >"$F"
  cp "$F" "$WORK/before"
  fn '' app_version_set "$ROOT" 2.0.0
  check "app_version_set: a file ${c%%|*} fails and is unchanged" \
    '[ $RC = 1 ] && [ -z "$OUT" ] && cmp -s "$F" "$WORK/before"'
done
check "...no temp file is left in TMPDIR" '[ -z "$(ls -A "$WORK/tmp")" ]'

if [ "$(id -u)" = 0 ]; then
  echo "# skip app_version_set on a read-only file: root writes it anyway"
else
  printf '1.2.3\n' >"$F"
  cp "$F" "$WORK/before"
  chmod 444 "$F"
  fn '' app_version_set "$ROOT" 2.0.0
  check "app_version_set: a read-only file fails and is unchanged" '[ $RC != 0 ] && cmp -s "$F" "$WORK/before"'
  chmod 640 "$F"
fi

# its directory exists, so the file could be created
mkdir -p "$WORK/missing"
fn '' app_version_set "$WORK/missing" 2.0.0
check "app_version_set: a missing file fails and is not created" '[ $RC != 0 ] && [ ! -e "$WORK/missing/VERSION" ]'

# --- release_assets: the files of release X.Y.Z, in upload order
fn '' release_assets 3.7.0
is "release_assets 3.7.0: the disk image, the zip and their sums" 0 \
  "$(lines Cranny-3.7.0.dmg Cranny-3.7.0.zip Cranny-3.7.0.sha256)"
fn '' release_assets 999999999.0.10
is "release_assets 999999999.0.10" 0 \
  "$(lines Cranny-999999999.0.10.dmg Cranny-999999999.0.10.zip Cranny-999999999.0.10.sha256)"
# scripts/lib/dist.sh names the files "$NAME.<ext>" with NAME="Cranny-$VERSION", and sums the others into
# "$NAME.sha256"
DIST_SH="$TREE/scripts/lib/dist.sh"
dist_prefix="$(sed -n 's/^NAME="\(.*\)\$VERSION"$/\1/p' "$DIST_SH")"
dist_files="$(grep -o '\$NAME\.[A-Za-z0-9]*' "$DIST_SH" | sed "s/^.NAME/${dist_prefix}1.2.3/" | LC_ALL=C sort -u |
  tr '\n' ' ')"
dist_summed="$(grep 'shasum .*> *"\$NAME\.sha256"' "$DIST_SH" | sed 's/>.*//' | grep -o '\$NAME\.[A-Za-z0-9]*' |
  sed "s/^.NAME/${dist_prefix}1.2.3/" | LC_ALL=C sort -u | tr '\n' ' ')"
lib_files="$("$BASH_BIN" -c '. "$0"; release_assets 1.2.3' "$LIB" | LC_ALL=C sort | tr '\n' ' ')"
lib_summed="$("$BASH_BIN" -c '. "$0"; release_assets 1.2.3' "$LIB" | grep -v '\.sha256$' | LC_ALL=C sort |
  tr '\n' ' ')"
if [ -n "$dist_prefix" ] && [ "$lib_files" = "$dist_files" ] && [ "$lib_summed" = "$dist_summed" ]; then
  ok "release_assets = the files scripts/lib/dist.sh writes, the .sha256 summing the others ($lib_files)"
else
  nok "release_assets = the files of scripts/lib/dist.sh" \
    "version.sh '$lib_files' summing '$lib_summed'; dist.sh '$dist_files' summing '$dist_summed'"
fi

# --- release_tags: tag names or `git ls-remote --tags` lines -> "<X.Y.Z> <tag>", once per tag
TAGS='v0.1.0\n0.2.0\nnot-a-release\nv1.2\n\nv01.0.0\nV0.5.0\nvv0.6.0\nv0.3.0-rc1\nv1000000000.0.0\n'
TAGS="${TAGS}aaaa\trefs/tags/v0.3.0\nbbbb\trefs/tags/0.4.0\ncccc\trefs/tags/0.4.0^{}\n"
TAGS="${TAGS}ffff\trefs/tags/v0.7.0\n9999\trefs/tags/v0.7.0^{}\n"
TAGS="${TAGS}dddd\trefs/heads/v0.9.0\nv0.1.0\neeee\trefs/tags/v0.10.0"
fn "$TAGS" release_tags
is "release_tags: vX.Y.Z and X.Y.Z tags, from names and ls-remote lines (annotated ones once), nothing else" 0 \
  "$(lines '0.1.0 v0.1.0' '0.2.0 0.2.0' '0.3.0 v0.3.0' '0.4.0 0.4.0' '0.7.0 v0.7.0' '0.10.0 v0.10.0')"
fn 'v0.8.0\n0.8.0\nv0.8.0\n' release_tags
is "release_tags: v0.8.0 and 0.8.0 are two tags of one version" 0 "$(lines '0.8.0 v0.8.0' '0.8.0 0.8.0')"
fn 'aaaa refs/tags/v1.0.0\n' release_tags
is "release_tags: a space instead of a tab" 0 '1.0.0 v1.0.0'
fn 'aaaa\trefs/tags/v1000000000.0.0\nbbbb\trefs/tags/v999999999.0.0\n' release_tags
is "release_tags: no tag with a number over 9 digits" 0 '999999999.0.0 v999999999.0.0'
fn '' release_tags
is "release_tags: no input, no tags" 0 ''

# --- highest_tag [skip]
fn "$TAGS" highest_tag
is "highest_tag: the highest version (0.10.0 > 0.7.0)" 0 '0.10.0 v0.10.0'
fn "$TAGS" highest_tag v0.10.0
is "highest_tag v0.10.0 (release_tag 0.10.0): the highest other tag" 0 '0.7.0 v0.7.0'
fn "$TAGS" highest_tag 0.10.0
is "highest_tag 0.10.0: skip names a tag, not a version (no tag 0.10.0)" 0 '0.10.0 v0.10.0'
fn 'v0.9.0\nv0.10.0\n0.11.0\nv1.0.0-rc1\n' highest_tag
is "highest_tag: a plain X.Y.Z tag can be the highest" 0 '0.11.0 0.11.0'
fn 'v0.9.0\n0.11.0\nv0.11.0\n' highest_tag v0.11.0
is "highest_tag v0.11.0 skips only the tag v0.11.0, not 0.11.0" 0 '0.11.0 0.11.0'
fn 'v1.0.0\n1.0.0\n' highest_tag
is "highest_tag: of two tags of the highest version, the first" 0 '1.0.0 v1.0.0'
fn 'v99999999.9.9\nv999999999.0.0\nv1000000000.0.0\nv9.999999999.999999999\n' highest_tag
is "highest_tag: 9-digit numbers compare as numbers, 10-digit ones are no tags" 0 '999999999.0.0 v999999999.0.0'
fn 'nope\nv1.2\n' highest_tag
is "highest_tag: nothing without release tags" 0 ''
fn 'v1.0.0\n' highest_tag v1.0.0
is "highest_tag: nothing when the only tag is skipped" 0 ''
fn '' highest_tag
is "highest_tag: nothing for no input" 0 ''
fn "$(many_after v9.0.0 8000)" highest_tag
is "highest_tag: reads to the end, past a pipe buffer of tags after the highest" 0 '9.0.0 v9.0.0'

# --- tag_of_version
fn "$TAGS" tag_of_version 0.3.0
is "tag_of_version 0.3.0: the tag v0.3.0" 0 v0.3.0
fn "$TAGS" tag_of_version 0.4.0
is "tag_of_version 0.4.0: the plain tag 0.4.0" 0 0.4.0
fn 'v0.8.0\n0.8.0\n' tag_of_version 0.8.0
is "tag_of_version: the first tag of the version (v0.8.0 first)" 0 v0.8.0
fn '0.8.0\nv0.8.0\n' tag_of_version 0.8.0
is "tag_of_version: the first tag of the version (0.8.0 first)" 0 0.8.0
fn "$TAGS" tag_of_version 0.9.0
is "tag_of_version: nothing for a version without a tag (a branch named v0.9.0 is not one)" 0 ''
fn "$TAGS" tag_of_version v0.3.0
is "tag_of_version: takes a version, not a tag" 0 ''
fn "$TAGS" tag_of_version 1.2
is "tag_of_version: nothing for a non-version" 0 ''
fn '' tag_of_version 0.1.0
is "tag_of_version: nothing for no input" 0 ''
# Over 64 KiB (a pipe buffer) of release_tags output after the match: a tag_of_version that stops reading there
# leaves release_tags writing into a closed pipe every time, not only when it loses a race (the CI's Broken pipe)
fn "$(many_after v0.4.0 8000)" tag_of_version 0.4.0
is "tag_of_version: reads release_tags to the end, past a pipe buffer of tags after the match" 0 v0.4.0
# The control: SIGPIPE is ignored here, so a reader that does stop early gets that Broken pipe; without it the two
# tests above prove nothing. The tags come from a file: release_tags, which dies there, would leave fn's printf of
# the input writing into a closed pipe too
many_after v0.4.0 8000 >"$WORK/big-tags"
export BIG_TAGS="$WORK/big-tags"
fn '' eval 'read -r first < <(release_tags <"$BIG_TAGS"); echo "$first"'
check "SIGPIPE is ignored, as on the runner: a reader of release_tags that stops early gets 'Broken pipe'" \
  '[ "$OUT" = "0.4.0 v0.4.0" ] && case $ERR in *"Broken pipe"*) true ;; *) false ;; esac'

# --- tag_commit <tag>: the commit of refs/tags/<tag> in `git ls-remote --tags` lines
REFS='1111\trefs/tags/v0.1.0\n2222\trefs/tags/v0.2.0\n3333\trefs/tags/v0.2.0^{}\n'
REFS="${REFS}4444\trefs/tags/v10.1.0\n5555\trefs/tags/v0.1.0.1\n6666\trefs/tags/v0x1y0\n7777\trefs/heads/v0.5.0\n"
REFS="${REFS}8888\trefs/tags/0.6.0\n"
fn "$REFS" tag_commit v0.1.0
is "tag_commit: a lightweight tag's own line" 0 1111
fn "$REFS" tag_commit v0.2.0
is "tag_commit: an annotated tag's peeled line, not the tag object" 0 3333
fn 'cccc\trefs/tags/v0.4.0^{}\naaaa\trefs/tags/v0.4.0\n' tag_commit v0.4.0
is "tag_commit: the peeled line wins wherever it is" 0 cccc
fn "$REFS" tag_commit 0.6.0
is "tag_commit: a plain X.Y.Z tag" 0 8888
fn "$REFS" tag_commit 0.2.0
is "tag_commit: 0.2.0 is not v0.2.0" 0 ''
fn "$REFS" tag_commit v0.6.0
is "tag_commit: v0.6.0 is not 0.6.0" 0 ''
fn "$REFS" tag_commit v0.5.0
is "tag_commit: only refs/tags/<tag> counts, not a branch" 0 ''
fn '6666\trefs/tags/v0x1y0\n5555\trefs/tags/v0.1.0.1\n' tag_commit v0.1.0
is "tag_commit: no longer names, no dots as wildcards" 0 ''
fn "$REFS" tag_commit v0.1.0.1
is "tag_commit: a longer tag name is its own tag" 0 5555
fn 'aaaa\trefs/tags/v1.0.0\nbbbb\trefs/tags/v1.0.0^{}\n' tag_commit v1.0
is "tag_commit: a prefix of a tag is no tag" 0 ''
fn '' tag_commit v0.1.0
is "tag_commit: nothing for no input" 0 ''

echo "# $pass passed, $fail failed"
[ "$fail" = 0 ]
