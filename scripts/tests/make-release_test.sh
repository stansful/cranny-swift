#!/usr/bin/env bash
# Tests of scripts/make-release.sh: throwaway repositories, each a clone of its own local bare "origin", in a temp
# dir (TMPDIR), with the script, scripts/lib/common.sh, scripts/lib/version.sh and a VERSION file. The script runs
# from a directory outside the repository, under $TEST_BASH (default: bash from PATH, /bin/bash 3.2 on macOS). git
# reads only this test's config (HOME is the temp dir). Needs git and mkfifo; no Xcode, no network, no python3.
#
#   scripts/tests/make-release_test.sh          KEEP=1 keeps the temp dir
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
if ! WORK="$(mktemp -d "${TMPDIR:-/tmp}/make-release-test.XXXXXX")" || ! WORK="$(cd "$WORK" && pwd -P)"; then
  echo "not ok no temp dir in ${TMPDIR:-/tmp}"
  exit 1
fi
if [ -z "${KEEP:-}" ]; then trap 'rm -rf "$WORK"' EXIT; else echo "# work dir: $WORK"; fi

export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
# git never finds a repository above the temp dir (a TMPDIR inside some checkout)
GIT_CEILING_DIRECTORIES="$(dirname "$WORK")"
export GIT_CEILING_DIRECTORIES
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p "$HOME"
git config --global init.defaultBranch main
# whatever temp files the script or git make land here, an absolute path whatever the caller's TMPDIR
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
# check <name> <condition (eval'd)>: on failure prints the script's output
check() {
  if eval "$2"; then ok "$1"; else nok "$1" "rc=$RC; condition: $2; output:
$OUT"; fi
}
NL='
'
ESC="$(printf '\033')"
# has <text>: the output (colours stripped) contains text; line <text>: one of its lines is exactly text
has() { case $OUT in *"$1"*) return 0 ;; esac; return 1; }
line() { case "$NL$OUT$NL" in *"$NL$1$NL"*) return 0 ;; esac; return 1; }
# warned <text>: a "warning: " line of the output contains text
warned() { printf '%s\n' "$OUT" | grep '^warning: ' | grep -F -- "$1" >/dev/null; }
# nocolour: stdin without the terminal colour codes
nocolour() { sed "s/${ESC}\[[0-9;]*m//g"; }
hex() { od -An -tx1 | tr -d ' \n'; }

echo "# scripts/make-release.sh under $("$BASH_BIN" -c 'echo "bash $BASH_VERSION"'), $(git --version)"

# --- the template: origin.git with main (VERSION 0.1.0, the script and its libs) and the tag v0.1.0 on its first
# commit, as GitHub makes it (lightweight)
TPL="$WORK/tpl"
mkdir -p "$TPL/seed/scripts/lib"
cp "$TREE/scripts/make-release.sh" "$TPL/seed/scripts/"
cp "$TREE/scripts/lib/common.sh" "$TREE/scripts/lib/version.sh" "$TPL/seed/scripts/lib/"
echo 0.1.0 >"$TPL/seed/VERSION"
echo readme >"$TPL/seed/README"
printf 'build/\n' >"$TPL/seed/.gitignore"
(
  set -e
  cd "$TPL/seed"
  git init -q .
  git symbolic-ref HEAD refs/heads/main
  git add -A
  git commit -q -m init
  git tag v0.1.0
  echo more >>README
  git commit -q -am 'Fix something'
  git init -q --bare "$TPL/origin.git"
  git -C "$TPL/origin.git" symbolic-ref HEAD refs/heads/main
  git push -q "$TPL/origin.git" main v0.1.0
) || {
  echo "not ok the test fixture could not be built"
  exit 1
}

# new_case <name>: CASE/origin.git (a copy of the template's) and its clone REPO; a name used twice stops the tests
# (the clone would fail and the case would run in the earlier case's repository)
new_case() {
  CASE="$WORK/$1"
  if [ -e "$CASE" ]; then
    echo "not ok the test case name '$1' is used twice"
    exit 1
  fi
  mkdir -p "$CASE"
  cp -R "$TPL/origin.git" "$CASE/origin.git"
  git clone -q "$CASE/origin.git" "$CASE/repo"
  REPO="$CASE/repo"
}
# mr <stdin (printf %b)> [args...]: make-release.sh of REPO, run from WORK; sets RAW (stdout and stderr), OUT (RAW
# without colours) and RC
mr() {
  local input="$1"
  shift
  RAW="$(cd "$WORK" && printf '%b' "$input" 2>/dev/null | "$BASH_BIN" "$REPO/scripts/make-release.sh" "$@" 2>&1)"
  RC=$?
  OUT="$(printf '%s\n' "$RAW" | nocolour)"
}
# run_in <dir> <script> [args...]: <script> (a path as given, relative to <dir> or absolute) run from <dir> with no
# input; sets RAW, OUT and RC like mr
run_in() {
  local dir="$1"
  shift
  RAW="$(cd "$dir" && "$BASH_BIN" "$@" 2>&1 </dev/null)"
  RC=$?
  OUT="$(printf '%s\n' "$RAW" | nocolour)"
}
# streams [args...]: make-release.sh of REPO with no input, run from WORK; sets STDOUT and STDERR (raw) and RC
streams() {
  STDERR="$(cd "$WORK" && "$BASH_BIN" "$REPO/scripts/make-release.sh" "$@" 2>&1 >"$WORK/stdout" </dev/null)"
  RC=$?
  STDOUT="$(cat "$WORK/stdout")"
  OUT="stdout:
$STDOUT
stderr:
$STDERR"
}
# interrupt <signal> <prompt> [args...]: make-release.sh of REPO in the background, from WORK, its stdin a FIFO
# that stays open and gets nothing; once <prompt> is in its output, AT_PROMPT is the content of VERSION (blanks
# dropped) and the script gets <signal>; sets OUT and RC. set -m gives the job a process group of its own: without
# job control a background job starts with SIGINT ignored, and a signal ignored at start cannot be trapped.
interrupt() {
  local sig="$1" prompt="$2" fifo="$CASE/stdin" out="$CASE/out" pid i=0
  shift 2
  rm -f "$fifo" "$out"
  AT_PROMPT=''
  if ! mkfifo "$fifo"; then
    RC=255 OUT="mkfifo $fifo failed"
    return
  fi
  : >"$out"
  # read and write: the open does not wait for a reader, and the script never sees the end of its input
  exec 3<>"$fifo"
  set -m
  (cd "$WORK" && exec "$BASH_BIN" "$REPO/scripts/make-release.sh" "$@" <"$fifo" >"$out" 2>&1 3>&-) &
  pid=$!
  set +m
  while [ "$i" -lt 300 ] && kill -0 "$pid" 2>/dev/null; do
    case $(cat "$out") in *"$prompt"*) break ;; esac
    sleep 0.1
    i=$((i + 1))
  done
  AT_PROMPT="$(tr -d ' \t\r\n' <"$REPO/VERSION")"
  kill "-$sig" "$pid" 2>/dev/null
  # a signal that does not stop it (it hangs at the prompt) must not hang the tests
  i=0
  while [ "$i" -lt 100 ] && kill -0 "$pid" 2>/dev/null; do
    sleep 0.1
    i=$((i + 1))
  done
  kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  wait "$pid"
  RC=$?
  exec 3>&-
  OUT="$(nocolour <"$out")"
}
g() { git -C "$REPO" "$@"; }
count() { g rev-list --count HEAD; }
message() { g log -1 --format=%B; }
origin_ref() { git -C "$CASE/origin.git" rev-parse -q --verify "refs/heads/$1"; }
all_tags() { { g tag -l && git -C "$CASE/origin.git" tag -l; } | LC_ALL=C sort | tr '\n' ' '; }
clean() { [ -z "$(g status --porcelain)" ]; }
# version_is <v>: VERSION in the working tree is "<v>" and a newline, byte for byte
version_is() { [ "$(hex <"$REPO/VERSION")" = "$(printf '%s\n' "$1" | hex)" ]; }
# release_commit <old> <new>: HEAD is the release commit of <new>: its whole message is "feat: release - version <new>",
# and against HEAD^ it changes VERSION from <old> (blanks around it aside) to "<new>" and a newline, and nothing
# else (no other line, file or mode)
release_commit() {
  [ "$(message)" = "feat: release - version $2" ] &&
    [ "$(g diff --numstat HEAD^ HEAD)" = "$(printf '1\t1\tVERSION')" ] &&
    [ -z "$(g diff --summary HEAD^ HEAD)" ] &&
    [ "$(g show HEAD^:VERSION | tr -d ' \t\r\n')" = "$1" ] &&
    [ "$(g show HEAD:VERSION | hex)" = "$(printf '%s\n' "$2" | hex)" ]
}
# commit_version <content (printf %b)>: VERSION holds that, committed
commit_version() {
  printf '%b' "$1" >"$REPO/VERSION"
  g commit -q -am "VERSION: $1"
}
NOT_A_VERSION="is not a version X.Y.Z (three numbers without leading zeros, at most 9 digits each, e.g."

# --- Enter takes the suggestion, the next patch version
new_case enter
before=$(count) head=$(g rev-parse HEAD) origin=$(origin_ref main) tags=$(all_tags)
mr '\n\n'
check "prints the current version" 'line "Current version:  0.1.0 (VERSION)"'
check "prints the last release tag" 'line "Last release tag: v0.1.0"'
check "...and no 'no tag yet' note for a released version" '! has "There is no tag"'
check "prints the next patch, minor and major versions" 'line "Next: 0.1.1 (patch), 0.2.0 (minor), 1.0.0 (major)."'
check "suggests the next patch version" 'has "New version [0.1.1]: "'
check "shows the diff of VERSION" 'line "-0.1.0" && line "+0.1.1"'
check "asks to commit" 'has "Commit VERSION as \"feat: release - version 0.1.1\"? [Y/n] "'
check "Enter takes 0.1.1, Enter commits (run from outside the repository)" '[ $RC = 0 ] && version_is 0.1.1'
check "...exactly one new commit, on the old HEAD" '[ "$(count)" = $((before + 1)) ] && [ "$(g rev-parse HEAD^)" = "$head" ]'
check "...'feat: release - version 0.1.1', only the version line of VERSION" 'release_commit 0.1.0 0.1.1 && clean'
check "...prints the commit" 'has "Commit $(g rev-parse --short HEAD): feat: release - version 0.1.1"'
check "...and the release it makes, tag v0.1.1" 'line "Release 0.1.1 (tag v0.1.1) comes out when this commit reaches main on GitHub (.github/workflows/release.yml)."'
check "...never pushes, never tags: origin and the tags untouched" '[ "$(origin_ref main)" = "$origin" ] && [ "$(all_tags)" = "$tags" ] && ! has "git push"'
check "...no warnings on main, in sync with origin" '! has "warning:"'

new_case 'with space'
mr '' --yes
check "a repository path with a space works" '[ $RC = 0 ] && release_commit 0.1.0 0.1.1 && clean'

# --- bump words at the prompt
for c in 'patch|0.1.1' 'Patch|0.1.1' 'minor|0.2.0' 'MINOR|0.2.0' 'major|1.0.0' 'Major|1.0.0' '  patch  |0.1.1' \
  '\tmajor\t|1.0.0' '0.3.0|0.3.0'; do
  w=${c%|*} want=${c#*|}
  new_case "prompt-$want-$(printf '%s' "$w" | hex)"
  mr "$w\n\n"
  check "prompt: '$w' is $want" '[ $RC = 0 ] && version_is "$want" && release_commit 0.1.0 "$want" && clean'
done

# --- bump words and versions as the argument
new_case words
before=$(count)
for c in 'patch|0.1.1' 'minor|0.2.0' 'major|1.0.0' 'Patch|0.1.1' 'MINOR|0.2.0' 'Major|1.0.0' '0.3.0|0.3.0' \
  '999999999.999999999.999999999|999999999.999999999.999999999'; do
  w=${c%|*} want=${c#*|}
  mr '' "$w" --no-commit
  check "argument '$w' is $want" '[ $RC = 0 ] && line "New version: $want" && version_is "$want" && [ "$(count)" = "$before" ] && [ "$(g status --porcelain)" = " M VERSION" ]'
  g checkout -q -- VERSION
done
mr '' minor --yes
check "argument minor --yes commits 0.2.0 without a question" '[ $RC = 0 ] && ! has "[Y/n]" && ! has "New version [" && release_commit 0.1.0 0.2.0 && clean'
new_case positional
mr '\n' 0.2.0
check "a version argument: no version prompt, only the commit question, Enter commits" '[ $RC = 0 ] && ! has "New version [" && line "New version: 0.2.0" && has "[Y/n] " && release_commit 0.1.0 0.2.0 && clean'

# --- the prompt asks again after a refused version
new_case reask
before=$(count)
mr '0.0.9\n0.1.0\nv0.1.0\n1.2\nv0.2.0\nV0.2.0\n01.2.3\n1.02.3\n0.2.0-rc1\n1.2.3.4\n1000000000.0.0\n0.1.1000000000\nbump\nпатч\n \t 0.3.0 \t \ny\n'
check "prompt: a lower version is refused" 'has "  version 0.0.9 is not higher than the current version 0.1.0. Enter another version."'
check "prompt: an already tagged version is refused" 'has "  tag v0.1.0 exists: version 0.1.0 has been released already. Enter another version."'
for w in v0.1.0 v0.2.0 V0.2.0; do
  want="  '$w': give the version without \"v\", e.g. ${w#?}. Enter another version."
  check "prompt: '$w' gets the hint to drop the v" 'has "$want"'
done
for w in 1.2 01.2.3 1.02.3 0.2.0-rc1 1.2.3.4 1000000000.0.0 0.1.1000000000 bump патч; do
  want="  '$w' $NOT_A_VERSION 0.1.1). Enter another version."
  check "prompt: '$w' is not a version" 'has "$want"'
done
check "prompt: asked once per answer, 15 times" '[ "$(printf "%s\n" "$OUT" | grep -o "New version \[0\.1\.1\]: " | wc -l | tr -d " ")" = 15 ]'
check "prompt: then 0.3.0 (blanks trimmed) is committed" '[ $RC = 0 ] && version_is 0.3.0 && [ "$(count)" = $((before + 1)) ] && release_commit 0.1.0 0.3.0 && clean'

# --- end of input at the prompt
new_case eof
before=$(count)
mr 'abc\n'
check "end of input at the prompt changes nothing" '[ $RC = 1 ] && line "error: no input, nothing changed." && version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'
mr ''
check "no input at all changes nothing" '[ $RC = 1 ] && line "error: no input, nothing changed." && version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'

# --- refused versions given as the argument
new_case refuse
before=$(count)
for c in "0.0.9|version 0.0.9 is not higher than the current version 0.1.0" \
  "0.1.0|tag v0.1.0 exists: version 0.1.0 has been released already" \
  "v0.2.0|'v0.2.0': give the version without \"v\", e.g. 0.2.0" \
  "V0.2.0|'V0.2.0': give the version without \"v\", e.g. 0.2.0" \
  "1.2|'1.2' $NOT_A_VERSION 0.1.1)" "1.2.3.4|'1.2.3.4' $NOT_A_VERSION 0.1.1)" \
  "01.2.3|'01.2.3' $NOT_A_VERSION 0.1.1)" "1.02.3|'1.02.3' $NOT_A_VERSION 0.1.1)" \
  "1.2.03|'1.2.03' $NOT_A_VERSION 0.1.1)" "0.2.0-rc1|'0.2.0-rc1' $NOT_A_VERSION 0.1.1)" \
  " 0.2.0|' 0.2.0' $NOT_A_VERSION 0.1.1)" "0.2.0 |'0.2.0 ' $NOT_A_VERSION 0.1.1)" \
  "bump|'bump' $NOT_A_VERSION 0.1.1)" "1000000000.0.0|'1000000000.0.0' $NOT_A_VERSION 0.1.1)" \
  "0.1000000000.0|'0.1000000000.0' $NOT_A_VERSION 0.1.1)" "0.2.1000000000|'0.2.1000000000' $NOT_A_VERSION 0.1.1)" \
  "|no version given"; do
  v=${c%%|*} want=${c#*|}
  mr '' --yes "$v"
  check "argument '$v' is refused: $want" '[ $RC = 1 ] && line "error: $want." && version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'
done
mr '\n\n' 0.0.9
check "a refused argument does not fall back to the prompt" '[ $RC = 1 ] && ! has "New version [" && version_is 0.1.0 && [ "$(count)" = "$before" ]'
streams --yes 0.0.9
check "errors go to stderr, as a red 'error:'" '[ $RC = 1 ] && case $STDERR in *"${ESC}[1;31merror:${ESC}[0m version 0.0.9 is not higher"*) true ;; *) false ;; esac && case $STDOUT in *error*) false ;; *) true ;; esac'

# --- tags: local and origin's, vX.Y.Z and X.Y.Z, lightweight and annotated; other tags do not count
new_case tags
g tag v0.5.0
git clone -q "$CASE/origin.git" "$CASE/other"
git -C "$CASE/other" tag 0.7.0
git -C "$CASE/other" tag -a v0.8.0 -m 'Cranny 0.8.0'
git -C "$CASE/other" tag -a 0.4.0 -m 'old style'
for t in v10.0.0-rc1 release-20.0.0 V20.0.0 v9.9 nightly; do git -C "$CASE/other" tag "$t"; done
git -C "$CASE/other" push -q origin --tags
before=$(count) origin=$(origin_ref main) tags=$(all_tags)
for c in 'v0.5.0|0.5.0|a local tag' '0.7.0|0.7.0|a plain tag only on origin' \
  'v0.8.0|0.8.0|an annotated tag only on origin' '0.4.0|0.4.0|an annotated plain tag only on origin'; do
  t=${c%%|*} v=${c#*|} what=${c##*|}
  v=${v%%|*}
  mr '' --yes "$v"
  check "$what is refused: $t" '[ $RC = 1 ] && line "error: tag $t exists: version $v has been released already."'
done
mr '' --yes 0.6.0
check "a version below the highest tag is refused" '[ $RC = 1 ] && line "error: version 0.6.0 is not higher than the last release tag v0.8.0."'
check "...nothing changed" 'version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'
mr ''
check "the last tag and the suggestions come from all release tags" 'line "Last release tag: v0.8.0" && line "Next: 0.8.1 (patch), 0.9.0 (minor), 1.0.0 (major)." && has "New version [0.8.1]: " && [ $RC = 1 ]'
check "...a current version below the tags gets no 'no tag yet' note" '! has "There is no tag"'
mr '' patch --no-commit
check "a bump word bumps the highest tag, not the current version" '[ $RC = 0 ] && version_is 0.8.1'
g checkout -q -- VERSION
mr '' 20.0.0 --no-commit
check "tags other than vX.Y.Z and X.Y.Z do not count (V20.0.0, release-20.0.0, v10.0.0-rc1)" '[ $RC = 0 ] && version_is 20.0.0'
g checkout -q -- VERSION
mr '' --yes
check "--yes takes the suggested 0.8.1 and commits without a question" '[ $RC = 0 ] && ! has "[Y/n]" && release_commit 0.1.0 0.8.1 && [ "$(count)" = $((before + 1)) ] && clean'
check "--yes neither pushes nor tags" '[ "$(origin_ref main)" = "$origin" ] && [ "$(all_tags)" = "$tags" ]'

new_case numeric
git clone -q "$CASE/origin.git" "$CASE/other"
git -C "$CASE/other" tag v0.9.0
git -C "$CASE/other" tag v0.10.0
git -C "$CASE/other" push -q origin v0.9.0 v0.10.0
mr ''
check "tags compare as numbers: v0.10.0 is above v0.9.0" 'line "Last release tag: v0.10.0" && has "New version [0.10.1]: "'
mr '' --yes 0.9.5
check "...0.9.5 is not higher than v0.10.0" '[ $RC = 1 ] && line "error: version 0.9.5 is not higher than the last release tag v0.10.0."'

# --- origin's tags cannot be read: a warning, then the local tags only
new_case badorigin
git clone -q "$CASE/origin.git" "$CASE/other"
git -C "$CASE/other" tag v0.7.0
git -C "$CASE/other" push -q origin v0.7.0
g remote set-url origin "$CASE/missing.git"
mr '' -y
check "unreadable origin tags: a warning, the local tags only, the commit is made" '[ $RC = 0 ] && line "warning: cannot read the tags of origin ($CASE/missing.git): comparing with the local tags only." && line "Last release tag: v0.1.0 (of the local tags)" && release_commit 0.1.0 0.1.1'
check "...no claim that a version has no tag yet" '! has "There is no tag"'

new_case notags-offline
g tag -d v0.1.0 >/dev/null
g remote set-url origin "$CASE/missing.git"
unknown="Release tags unknown: there are no local ones, and origin's could not be read."
mr '0.2.0\n' --no-commit
check "unreadable origin and no local tags: a warning, no claims about tags or an unreleased version" \
  '[ $RC = 0 ] && warned "cannot read the tags of origin" && line "$unknown" && ! has "No release tags yet" && ! has "There is no tag"'

# --- no release tags at all
new_case notags
g tag -d v0.1.0 >/dev/null
git -C "$CASE/origin.git" tag -d v0.1.0 >/dev/null
mr ''
check "no tags: says so, and that the current version has no release yet" 'line "No release tags yet." && line "There is no tag v0.1.0 yet: once a commit with this version is on main on GitHub, release 0.1.0 comes out even without a new version." && has "New version [0.1.1]: "'
mr '' 0.1.0 --yes
check "no tags: the current version itself is still refused" '[ $RC = 1 ] && line "error: version 0.1.0 is not higher than the current version 0.1.0."'
git -C "$CASE/origin.git" tag 0.1.0 main~1
mr ''
check "a plain tag X.Y.Z on origin counts as the release of X.Y.Z" 'line "Last release tag: 0.1.0" && ! has "There is no tag"'

new_case ahead
commit_version '0.3.0\n'
mr ''
check "a version above every tag: says it has no release yet, suggests its next patch version" 'line "There is no tag v0.3.0 yet: once a commit with this version is on main on GitHub, release 0.3.0 comes out even without a new version." && line "Next: 0.3.1 (patch), 0.4.0 (minor), 1.0.0 (major)." && has "New version [0.3.1]: "'

# --- what VERSION holds
new_case badversion
for v in x v0.3.0 V0.3.0 1.2 01.2.3 0.3.0-rc1 0.1000000000.0 0.3.0.1 '0. 3.0'; do
  commit_version "$v\n"
  cp "$REPO/VERSION" "$WORK/before"
  before=$(count)
  want="error: VERSION holds '$v', not X.Y.Z (no leading zeros, no \"v\"): fix the file by hand and commit it."
  mr '' --yes 0.4.0
  check "VERSION '$v' is refused" '[ $RC = 1 ] && line "$want" && cmp -s "$REPO/VERSION" "$WORK/before" && [ "$(count)" = "$before" ] && clean'
done
for c in '|empty' '\n \t\n|blank only' '0.3.0\n0.4.0\n|two versions' '0.3.0\n0.3.0\n|one version twice' \
  '0.3.0\n# next: 0.4.0\n|a version and a comment'; do
  commit_version "${c%|*}"
  cp "$REPO/VERSION" "$WORK/before"
  before=$(count)
  mr '' --yes 0.4.0
  check "VERSION that is ${c#*|} is refused" '[ $RC = 1 ] && line "error: VERSION must hold exactly one line, the version X.Y.Z: fix the file by hand and commit it." && cmp -s "$REPO/VERSION" "$WORK/before" && [ "$(count)" = "$before" ] && clean'
done
for c in '0.3.0|no final newline' '0.3.0\r\n|CRLF' '  0.3.0\t\n|blanks around the version'; do
  new_case "version-$(printf '%s' "${c#*|}" | tr ' ' -)"
  commit_version "${c%|*}"
  mr '' --yes
  check "VERSION with ${c#*|}: 0.3.0, released as 0.3.1 alone on its line" '[ $RC = 0 ] && line "Current version:  0.3.0 (VERSION)" && release_commit 0.3.0 0.3.1 && version_is 0.3.1 && clean'
done
# VERSION is "exactly one non-blank line" (scripts/lib/version.sh): blank lines around it are fine for every reader
new_case version-blank-lines
commit_version '\n0.3.0\n\n'
cp "$REPO/VERSION" "$WORK/before"
before=$(count)
mr '' --yes
check "VERSION with blank lines around the version: released as 0.3.1, or refused for its format up front" \
  '{ [ $RC = 0 ] && [ "$(count)" = $((before + 1)) ] && [ "$(message)" = "feat: release - version 0.3.1" ] && [ "$(g diff --name-only HEAD^ HEAD)" = VERSION ] && [ "$(g show HEAD:VERSION | tr -d " \t\r\n")" = 0.3.1 ] && clean; } || { [ $RC = 1 ] && has "VERSION must hold exactly one line" && cmp -s "$REPO/VERSION" "$WORK/before" && [ "$(count)" = "$before" ] && clean; }'
new_case version-mode
chmod +x "$REPO/VERSION"
g commit -q -am 'VERSION: executable'
mr '' --yes
check "VERSION keeps its file mode" '[ $RC = 0 ] && release_commit 0.1.0 0.1.1 && [ -x "$REPO/VERSION" ] && clean'
new_case version-readonly
chmod 444 "$REPO/VERSION"
if [ -w "$REPO/VERSION" ]; then
  ok "a read-only VERSION: could not write, nothing changed # skip: running as root, every file is writable"
else
  before=$(count)
  mr '' --yes
  check "a read-only VERSION: could not write, nothing changed" '[ $RC = 1 ] && line "error: could not write version 0.1.1 into VERSION; the file is restored." && version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'
fi
chmod 644 "$REPO/VERSION"

# --- the digits: at most 9 per number
new_case digits
commit_version '0.999999999.0\n'
head=$(g rev-parse HEAD)
mr '\n\n'
check "prompt: only the bumps with at most 9 digits are offered, Enter takes the patch one" \
  'line "Next: 0.999999999.1 (patch), 1.0.0 (major)." && has "New version [0.999999999.1]: " && ! has "0.1000000000.0" && [ $RC = 0 ] && release_commit 0.999999999.0 0.999999999.1'
g reset -q --hard "$head"
mr '0.1000000000.0\nminor\n1.0.0\nn\n'
want="'0.1000000000.0' $NOT_A_VERSION 0.999999999.1). Enter another version."
check "prompt: 0.1000000000.0, typed or as minor, is refused" '[ $RC = 1 ] && [ "$(printf "%s\n" "$OUT" | grep -cF -- "$want")" = 2 ] && version_is 0.999999999.0 && clean'
mr '' major --yes
check "...while major, 1.0.0, is released" '[ $RC = 0 ] && release_commit 0.999999999.0 1.0.0'
g reset -q --hard "$head"
commit_version '0.1.999999999\n'
mr '\n\n'
check "the patch number out of digits: Enter takes the minor version" \
  'line "Next: 0.2.0 (minor), 1.0.0 (major)." && has "New version [0.2.0]: " && [ $RC = 0 ] && release_commit 0.1.999999999 0.2.0'
g reset -q --hard "$head"
commit_version '0.999999999.999999999\n'
mr '' --yes
check "...and --yes the major one when the minor number is out of digits too" \
  'line "New version: 1.0.0" && [ $RC = 0 ] && release_commit 0.999999999.999999999 1.0.0'
g reset -q --hard "$head"
commit_version '999999999.999999999.999999999\n'
before=$(count)
mr '' --yes
check "after 999999999.999999999.999999999 nothing is left: refused, nothing changed" \
  '[ $RC = 1 ] && line "error: there is no version after 999999999.999999999.999999999 with at most 9 digits per number: nothing left to release." && version_is 999999999.999999999.999999999 && [ "$(count)" = "$before" ] && clean'
new_case digits-patch
commit_version '999999999.999999999.5\n'
head=$(g rev-parse HEAD)
mr '' 999999999.999999999.6 --yes
check "minor and major out of digits: a higher patch version given as the argument is released" \
  '[ $RC = 0 ] && release_commit 999999999.999999999.5 999999999.999999999.6 && clean'
g reset -q --hard "$head"
mr '' patch --yes
check "minor and major out of digits: patch is released" '[ $RC = 0 ] && release_commit 999999999.999999999.5 999999999.999999999.6 && clean'

# --- a dirty tree
new_case dirty
before=$(count)
echo change >>"$REPO/README"
mr '' --yes 0.2.0
check "a modified file is refused" '[ $RC = 1 ] && line "error: there are uncommitted changes (working tree or index):" && line " M README" && line "Commit them or set them aside (git stash) and run again: the release commit holds only VERSION." && version_is 0.1.0 && [ "$(count)" = "$before" ]'
check "...and stays modified" '[ "$(g status --porcelain)" = " M README" ]'
g checkout -q -- README
echo 0.5.0 >"$REPO/VERSION"
mr '' --yes 0.2.0
check "a modified VERSION is refused and left as it is" '[ $RC = 1 ] && line " M VERSION" && version_is 0.5.0 && [ "$(count)" = "$before" ]'
g checkout -q -- VERSION
echo new >"$REPO/newfile"
g add newfile
mr '' --yes 0.2.0
check "a staged file is refused" '[ $RC = 1 ] && line "A  newfile" && version_is 0.1.0 && [ "$(count)" = "$before" ] && [ "$(g status --porcelain)" = "A  newfile" ]'
g reset -q
rm "$REPO/README"
mr '' --yes 0.2.0
check "a deleted file is refused" '[ $RC = 1 ] && line " D README" && version_is 0.1.0 && [ "$(count)" = "$before" ]'
g checkout -q -- README
mkdir -p "$REPO/build"
echo log >"$REPO/build/build.log"
mr '' --yes 0.2.0
check "an untracked file is only a warning, and stays out of the commit" '[ $RC = 0 ] && line "warning: files not in git, the release does not get them:" && line "  newfile" && release_commit 0.1.0 0.2.0 && [ "$(g status --porcelain)" = "?? newfile" ]'
check "...ignored files are not listed" '! has "build.log"'
new_case untracked
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do echo x >"$REPO/f$i"; done
mr '' --yes 0.2.0
check "more than 10 untracked files: the first 10 and …" '[ $RC = 0 ] && line "  f10" && ! has "f11" && line "  …" && release_commit 0.1.0 0.2.0'
new_case untracked10
for i in 01 02 03 04 05 06 07 08 09 10; do echo x >"$REPO/f$i"; done
mr '' --yes 0.2.0
check "exactly 10 untracked files: all of them, no …" '[ $RC = 0 ] && line "  f01" && line "  f10" && ! has "…" && release_commit 0.1.0 0.2.0'

# --- git hooks: they run on the commit's own index, so what a pre-commit hook stages lands in the commit
# hook <commands>: REPO's pre-commit hook
hook() {
  printf '#!/bin/sh\n%s\n' "$1" >"$REPO/.git/hooks/pre-commit"
  chmod +x "$REPO/.git/hooks/pre-commit"
}
no_verify="  git commit --no-verify -m 'feat: release - version 0.2.0' -- VERSION"
new_case hooknew
hook 'echo x >>other && git add other'
head=$(g rev-parse HEAD) origin=$(origin_ref main)
mr '' 0.2.0 --yes
check "a hook that stages a new file: the release commit is undone" '[ $RC = 1 ] && line "error: a git hook (pre-commit or another) changed the release commit, which must hold only version 0.2.0 in VERSION. The commit had:" && [ "$(g rev-parse HEAD)" = "$head" ] && [ "$(origin_ref main)" = "$origin" ]'
check "...it names the files the commit had and how to commit past the hook" 'line "  VERSION" && line "  other" && line "Fix the hook, or commit past the hooks: scripts/make-release.sh 0.2.0 --no-commit, then" && line "$no_verify"'
check "...VERSION is back in the tree and the index, the hook's file is left untracked" 'version_is 0.1.0 && [ "$(g status --porcelain)" = "?? other" ]'
new_case hooktracked
hook 'echo x >>README && git add README'
head=$(g rev-parse HEAD)
mr '' 0.2.0 --yes
check "a hook that stages a tracked file: the commit is undone, the hook's change is left unstaged" '[ $RC = 1 ] && line "  README" && [ "$(g rev-parse HEAD)" = "$head" ] && version_is 0.1.0 && [ "$(g status --porcelain)" = " M README" ]'
new_case hookversion
hook "sed 's/0.2.0/9.9.9/' VERSION >.git/v && cat .git/v >VERSION && git add VERSION"
head=$(g rev-parse HEAD)
mr '' 0.2.0 --yes
check "a hook that rewrites the version in VERSION: the commit is undone" '[ $RC = 1 ] && has "changed the release commit" && [ "$(g rev-parse HEAD)" = "$head" ] && version_is 0.1.0 && clean'
new_case hookline
hook "echo '# formatted' >>VERSION && git add VERSION"
head=$(g rev-parse HEAD)
mr '' 0.2.0 --yes
check "a hook that adds another line to VERSION: the commit is undone" '[ $RC = 1 ] && has "changed the release commit" && line "  VERSION" && [ "$(g rev-parse HEAD)" = "$head" ] && version_is 0.1.0 && clean'
new_case hookfail
hook 'exit 1'
head=$(g rev-parse HEAD)
mr '' 0.2.0 --yes
check "a failing hook: no commit, VERSION is back" '[ $RC = 1 ] && line "error: git commit failed; VERSION restored." && [ "$(g rev-parse HEAD)" = "$head" ] && version_is 0.1.0 && clean'
new_case hookok
hook 'git add VERSION'
before=$(count)
mr '' 0.2.0 --yes
check "a hook that stages only VERSION (a formatter) keeps the release commit" '[ $RC = 0 ] && [ "$(count)" = $((before + 1)) ] && release_commit 0.1.0 0.2.0 && clean'

# --- no push, ever
new_case nopush
origin=$(origin_ref main) tags=$(all_tags)
mr '\nд\n'
check "the commit stays local: no push question, origin and tags untouched" '[ $RC = 0 ] && release_commit 0.1.0 0.1.1 && [ "$(origin_ref main)" = "$origin" ] && [ "$(all_tags)" = "$tags" ] && ! has "push"'
mr '' 0.3.0 --push
check "--push is not an option" '[ $RC = 2 ] && line "error: unknown option --push"'

# --- the confirmation
new_case decline
before=$(count)
for a in n no N nope нет; do
  mr "0.2.0\n$a\n"
  check "answer '$a' cancels and restores VERSION" '[ $RC = 1 ] && has "Cancelled: VERSION restored, no commit." && version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'
done
mr '0.2.0\n'
check "end of input at the confirmation restores VERSION" '[ $RC = 1 ] && line "error: no input; VERSION restored." && version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'
for a in y Yes YES ' Y ' да Д; do
  new_case "accept-$(printf '%s' "$a" | hex)"
  mr "0.2.0\n$a\n"
  check "answer '$a' commits" '[ $RC = 0 ] && release_commit 0.1.0 0.2.0 && clean'
done

# --- interrupted: Ctrl-C (INT) or TERM at the confirmation puts VERSION back
# A shell started with SIGINT ignored (a background job of a shell without job control, nohup) passes that on to
# everything it runs, set -m or not: then no SIGINT reaches the script, and the INT cases are skipped
set -m
"$BASH_BIN" -c 'trap "exit 7" INT; kill -INT $$; exit 0' &
probe=$!
set +m
wait "$probe"
int_reaches=$?
confirm='Commit VERSION as "feat: release - version 0.2.0"? [Y/n] '
if [ "$int_reaches" = 7 ]; then
  new_case interrupt-int
  before=$(count)
  interrupt INT "$confirm" 0.2.0
  check "INT at the confirmation: VERSION had the new version when it came" '[ "$AT_PROMPT" = 0.2.0 ]'
  check "...VERSION restored, no commit, exit 130" '[ $RC = 130 ] && line "Interrupted: VERSION restored." && version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'
  new_case interrupt-prompt
  before=$(count)
  interrupt INT 'New version [0.1.1]: '
  check "INT at the version prompt: nothing changed" '[ $RC != 0 ] && has "New version [0.1.1]: " && version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'
else
  for t in "INT at the confirmation: VERSION restored, no commit, exit 130" "INT at the version prompt: nothing changed"; do
    ok "$t # skip: this shell was started with SIGINT ignored"
  done
fi
new_case interrupt-term
before=$(count)
interrupt TERM "$confirm" 0.2.0
check "TERM at the confirmation: VERSION restored, no commit" '[ "$AT_PROMPT" = 0.2.0 ] && [ $RC = 130 ] && line "Interrupted: VERSION restored." && version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'

# --- --no-commit and the options
new_case nocommit
before=$(count)
mr '' 0.2.0 --no-commit
check "--no-commit writes VERSION and commits nothing" '[ $RC = 0 ] && version_is 0.2.0 && [ "$(count)" = "$before" ] && [ "$(g status --porcelain)" = " M VERSION" ] && line "VERSION: version 0.2.0. No commit (--no-commit). Commit this file alone:"'
check "...the change is the version line only" '[ "$(g diff --numstat)" = "$(printf "1\t1\tVERSION")" ]'
commit_cmd="  git commit -m 'feat: release - version 0.2.0' -- VERSION"
check "...shows the diff and the commit command" 'line "-0.1.0" && line "+0.2.0" && line "$commit_cmd"'
g checkout -q -- VERSION
mr '\n' --no-commit
check "--no-commit at the prompt: Enter writes 0.1.1, no confirmation" '[ $RC = 0 ] && version_is 0.1.1 && ! has "[Y/n]" && [ "$(count)" = "$before" ]'
g checkout -q -- VERSION
mr '' --yes --no-commit
check "--yes --no-commit writes the suggested 0.1.1, no question, no commit" '[ $RC = 0 ] && version_is 0.1.1 && ! has "[Y/n]" && ! has "New version [" && [ "$(count)" = "$before" ]'
g checkout -q -- VERSION
mr '' --bogus
check "an unknown option is a usage error" '[ $RC = 2 ] && line "error: unknown option --bogus" && has "scripts/make-release.sh [X.Y.Z|patch|minor|major] [--yes] [--no-commit]" && ! has "Current version"'
mr '' -x 0.2.0
check "an unknown short option is a usage error" '[ $RC = 2 ] && line "error: unknown option -x" && version_is 0.1.0'
streams --bogus
check "...the usage error and the usage go to stderr" '[ $RC = 2 ] && [ -z "$STDOUT" ] && case $STDERR in *"unknown option --bogus"*"scripts/make-release.sh [X.Y.Z"*) true ;; *) false ;; esac'
mr '' 0.2.0 0.3.0
check "two versions are a usage error" '[ $RC = 2 ] && line "error: two versions given: 0.2.0 and 0.3.0" && version_is 0.1.0'
mr '' patch 0.3.0
check "a bump word and a version are two versions" '[ $RC = 2 ] && line "error: two versions given: patch and 0.3.0"'
mr '' --help
check "--help prints the usage" '[ $RC = 0 ] && line "  scripts/make-release.sh [X.Y.Z|patch|minor|major] [--yes] [--no-commit]" && ! has "Current version"'
mr '' -h
check "-h prints the usage" '[ $RC = 0 ] && line "  --no-commit   only write the version into VERSION, no commit"'
mr '' 0.2.0 --yes --help
check "--help after a version and --yes only prints the usage" '[ $RC = 0 ] && has "scripts/make-release.sh [X.Y.Z|patch|minor|major]" && ! has "New version"'
streams --help
check "...the usage goes to stdout" '[ $RC = 0 ] && [ -z "$STDERR" ] && case $STDOUT in *"scripts/make-release.sh [X.Y.Z"*) true ;; *) false ;; esac'
check "...options change nothing" 'version_is 0.1.0 && [ "$(count)" = "$before" ] && clean'

# --- branches
new_case branch
g checkout -q -b feature
origin=$(origin_ref main)
mr '' 0.2.0 --yes
check "another branch: a warning, then the commit on that branch" '[ $RC = 0 ] && line "warning: you are on feature, and releases come out of main only: this commit is released only once it is merged into main." && [ "$(g symbolic-ref --short HEAD)" = feature ] && release_commit 0.1.0 0.2.0 && [ "$(origin_ref main)" = "$origin" ]'
new_case detached
g checkout -q --detach
head=$(g rev-parse HEAD)
mr '' 0.2.0 --yes
check "a detached HEAD is refused" '[ $RC = 1 ] && line "error: HEAD is not on a branch (detached HEAD): switch to a branch first, e.g. git switch main." && version_is 0.1.0 && [ "$(g rev-parse HEAD)" = "$head" ] && clean'
new_case behind
git clone -q "$CASE/origin.git" "$CASE/other"
echo other >>"$CASE/other/README"
git -C "$CASE/other" commit -q -am 'Fix other'
git -C "$CASE/other" push -q origin main
g fetch -q origin
origin=$(origin_ref main)
mr '' 0.2.0 --yes
check "a branch behind origin: a warning to pull first, the commit is still made locally" '[ $RC = 0 ] && line "warning: main is 1 commit(s) behind origin/main (as of the last fetch): git pull first." && [ "$(origin_ref main)" = "$origin" ] && release_commit 0.1.0 0.2.0'
new_case ahead-of-origin
echo local >>"$REPO/README"
g commit -q -am 'Local work'
mr '' 0.2.0 --yes
check "a branch only ahead of origin: no warning" '[ $RC = 0 ] && ! has "warning:" && release_commit 0.1.0 0.2.0'

# --- no origin; the default branch
new_case noorigin
g remote remove origin
before=$(count)
mr '' --yes
check "without origin: no warning, the local tags count, the commit is made" '[ $RC = 0 ] && ! has "warning:" && line "Last release tag: v0.1.0" && release_commit 0.1.0 0.1.1 && [ "$(count)" = $((before + 1)) ]'
g branch -q -m main dev
mr '' --yes
check "on dev without origin: a warning, the commit is made" '[ $RC = 0 ] && line "warning: you are on dev, and releases come out of main only: this commit is released only once it is merged into main." && release_commit 0.1.1 0.1.2'
# release.yml releases from main only: a release commit on master (and no main anywhere) never comes out
new_case master
g remote remove origin
g branch -q -m main master
mr '' --yes
check "on master with no main anywhere: a warning that releases come out of main" '[ $RC = 0 ] && warned "main" && release_commit 0.1.0 0.1.1'
# origin's default branch does not matter: release.yml releases pushes to main
new_case origin-head
g push -q origin main:develop
git -C "$CASE/origin.git" symbolic-ref HEAD refs/heads/develop
g remote set-head origin -a >/dev/null
mr '' --yes
check "on main while origin's HEAD is develop: no warning" '[ $RC = 0 ] && ! has "warning:" && release_commit 0.1.0 0.1.1'
g checkout -q -b develop origin/develop
mr '' --yes
check "on origin's default branch develop: the warning that releases come out of main" '[ $RC = 0 ] && line "warning: you are on develop, and releases come out of main only: this commit is released only once it is merged into main."'

# --- run from another directory
new_case elsewhere
git clone -q "$CASE/origin.git" "$CASE/other"
other_head=$(git -C "$CASE/other" rev-parse HEAD)
run_in "$CASE/other" "$REPO/scripts/make-release.sh" --yes
check "run from inside another repository: the commit lands in the script's repository only" '[ $RC = 0 ] && release_commit 0.1.0 0.1.1 && [ "$(git -C "$CASE/other" rev-parse HEAD)" = "$other_head" ] && [ -z "$(git -C "$CASE/other" status --porcelain)" ] && [ "$(git -C "$CASE/other" cat-file -p HEAD:VERSION)" = 0.1.0 ]'
run_in "$REPO/scripts" ./make-release.sh --yes
check "run from scripts/ as ./make-release.sh" '[ $RC = 0 ] && release_commit 0.1.1 0.1.2 && clean'
run_in "$REPO/scripts/lib" ../make-release.sh --yes
check "run from scripts/lib as ../make-release.sh" '[ $RC = 0 ] && release_commit 0.1.2 0.1.3 && clean'

# --- not a repository, no commits, VERSION not in git, not the root
REPO="$WORK/plain"
mkdir -p "$REPO/scripts/lib"
cp "$TREE/scripts/make-release.sh" "$REPO/scripts/"
cp "$TREE/scripts/lib/common.sh" "$TREE/scripts/lib/version.sh" "$REPO/scripts/lib/"
echo 0.1.0 >"$REPO/VERSION"
mr '' 0.2.0 --yes
check "outside a git repository it is refused" '[ $RC = 1 ] && line "error: $REPO is not a git repository. Run git init, make the first commit and git remote add origin <url> first." && version_is 0.1.0'
mr '' --help
check "...--help works there too" '[ $RC = 0 ] && has "scripts/make-release.sh [X.Y.Z|patch|minor|major]"'
git init -q "$REPO"
mr '' 0.2.0 --yes
check "a repository without commits is refused" '[ $RC = 1 ] && line "error: the repository has no commits yet: commit the project first." && version_is 0.1.0'
g add scripts
g commit -q -m scripts
mr '' 0.2.0 --yes
check "a VERSION that is not in git is refused" '[ $RC = 1 ] && line "error: VERSION is not in git: commit it." && version_is 0.1.0 && [ "$(count)" = 1 ]'
printf 'VERSION\n' >"$REPO/.gitignore"
g add .gitignore
g commit -q -m ignore
mr '' 0.2.0 --yes
check "an ignored VERSION is not in git either" '[ $RC = 1 ] && line "error: VERSION is not in git: commit it." && version_is 0.1.0 && [ "$(count)" = 2 ]'

REPO="$WORK/outer/sub"
mkdir -p "$REPO/scripts/lib"
cp "$TREE/scripts/make-release.sh" "$REPO/scripts/"
cp "$TREE/scripts/lib/common.sh" "$TREE/scripts/lib/version.sh" "$REPO/scripts/lib/"
echo 0.1.0 >"$REPO/VERSION"
git init -q "$WORK/outer"
git -C "$WORK/outer" add -A
git -C "$WORK/outer" commit -q -m init
mr '' 0.2.0 --yes
check "a script in a subdirectory of a repository is refused" '[ $RC = 1 ] && line "error: $REPO is not the root of its git repository (the root is $WORK/outer)." && version_is 0.1.0 && [ "$(git -C "$WORK/outer" rev-list --count HEAD)" = 1 ]'

echo "# $pass passed, $fail failed"
[ "$fail" = 0 ]
