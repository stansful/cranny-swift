# shellcheck shell=bash
# Release versions and release files, shared by scripts/make-release.sh, scripts/build-release.sh,
# .github/scripts/*.sh and .github/workflows/release.yml (sourced, not run).
#
# A version is X.Y.Z: three decimal numbers without leading zeros (0 itself is fine), each at most 9 digits (the
# in-app update check reads them as Int, bash arithmetic as 64-bit). It lives in VERSION, alone on its one line;
# scripts/lib/build.sh makes it the app's CFBundleShortVersionString. The release's tag is vX.Y.Z and its files are
# named after the version. Tags X.Y.Z count as version X.Y.Z too.
# bash 3.2 (macOS) and 5 (Linux), BSD or GNU tools; no sort -V, which BSD sort lacks.

VERSION_RE='^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$'

# The file with the version, relative to the repository root
APP_VERSION_FILE=VERSION

# version_valid <s>: whether s is X.Y.Z
version_valid() {
  [[ $1 =~ $VERSION_RE ]]
}

# version_cmp <a> <b>: prints -1, 0 or 1 for a < b, a = b, a > b (both valid). Without leading zeros the longer
# number is the larger one, and numbers of one length compare as strings.
version_cmp() {
  local a="$1." b="$2." x y
  while [ -n "$a" ]; do
    x=${a%%.*} y=${b%%.*}
    a=${a#*.} b=${b#*.}
    [ "$x" = "$y" ] && continue
    if [ ${#x} -gt ${#y} ] || { [ ${#x} -eq ${#y} ] && [[ $x > $y ]]; }; then
      echo 1
    else
      echo -1
    fi
    return 0
  done
  echo 0
}

# version_gt <a> <b>: whether a > b
version_gt() {
  [ "$(version_cmp "$1" "$2")" = 1 ]
}

# version_bump <X.Y.Z> <patch|minor|major>: prints X.Y.(Z+1), X.(Y+1).0 or (X+1).0.0; the result may be too long
# for version_valid (999999999 + 1)
version_bump() {
  local x y z
  x=${1%%.*} z=${1##*.} y=${1#*.}
  y=${y%.*}
  case $2 in
  patch) echo "$x.$y.$((z + 1))" ;;
  minor) echo "$x.$((y + 1)).0" ;;
  major) echo "$((x + 1)).0.0" ;;
  *) return 1 ;;
  esac
}

# release_tag <X.Y.Z>: prints the tag of release X.Y.Z
release_tag() {
  echo "v$1"
}

# app_version_parse: reads VERSION on stdin and prints its version line without the blanks around it; fails,
# printing nothing, unless exactly one line is not blank. The value is not checked: see version_valid.
app_version_parse() {
  awk '
    /[^ \t\r]/ { n++; v = $0; gsub(/^[ \t\r]+|[ \t\r]+$/, "", v) }
    END { if (n != 1) exit 1; print v }'
}

# app_version_get <root>: app_version_parse of <root>/VERSION
app_version_get() {
  app_version_parse <"$1/$APP_VERSION_FILE"
}

# app_version_set <root> <X.Y.Z>: replaces the version line of <root>/VERSION with "X.Y.Z" (blank lines stay, the
# last line ends in a newline), in place (the file keeps its inode and mode); fails, changing nothing, unless the
# version is valid and the file has exactly one version line
app_version_set() {
  local file="$1/$APP_VERSION_FILE" tmp
  version_valid "$2" || return 1
  app_version_parse <"$file" >/dev/null || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/app-version.XXXXXX")" || return 1
  if awk -v v="$2" '/[^ \t\r]/ { print v; next } { print }' "$file" >"$tmp" && cat "$tmp" >"$file"; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# release_assets <X.Y.Z>: prints the names of the files release X.Y.Z publishes, one per line, in upload order:
# the disk image, the zip, and the SHA-256 sums of both (scripts/lib/dist.sh writes all three into dist/)
release_assets() {
  echo "Cranny-$1.dmg"
  echo "Cranny-$1.zip"
  echo "Cranny-$1.sha256"
}

# release_tags: reads tag names, or the lines of `git ls-remote --tags` (refs/tags/<tag>, <tag>^{}), on stdin
# and prints "<X.Y.Z> <tag>" for every release tag (vX.Y.Z or X.Y.Z), once per tag
release_tags() {
  local line ref v seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    ref=${line##*[[:space:]]}
    ref=${ref#refs/tags/}
    ref=${ref%'^{}'}
    v=${ref#v}
    version_valid "$v" || continue
    case $seen in *" $ref "*) continue ;; esac
    seen="$seen$ref "
    echo "$v $ref"
  done
}

# highest_tag [skip]: reads what release_tags reads and prints "<X.Y.Z> <tag>" of the highest release tag other
# than the tag named skip; nothing when there is none
highest_tag() {
  local skip="${1:-}" v t best='' best_tag=''
  while read -r v t; do
    [ "$t" = "$skip" ] && continue
    if [ -z "$best" ] || version_gt "$v" "$best"; then
      best=$v best_tag=$t
    fi
  done < <(release_tags)
  [ -z "$best" ] || echo "$best $best_tag"
}

# tag_of_version <X.Y.Z>: reads what release_tags reads and prints the first tag of that version (vX.Y.Z or
# X.Y.Z); nothing when there is none. It reads release_tags to the end: a reader that stops early leaves
# release_tags writing into a closed pipe, which is "echo: write error: Broken pipe" where SIGPIPE is ignored (the
# GitHub runner)
tag_of_version() {
  local v t found=''
  while read -r v t; do
    if [ -z "$found" ] && [ "$v" = "$1" ]; then
      found=$t
    fi
  done < <(release_tags)
  [ -z "$found" ] || echo "$found"
}

# tag_commit <tag>: reads the lines of `git ls-remote --tags <remote>` (every tag: given a pattern, ls-remote leaves
# out an annotated tag's peeled line) on stdin and prints the commit refs/tags/<tag> is on: the peeled "<tag>^{}"
# line of an annotated tag, else the tag's own line; nothing when there is no such tag
tag_commit() {
  awk -v ref="refs/tags/$1" '
    $2 == ref { sha = $1 }
    $2 == ref "^{}" { peeled = $1 }
    END { if (peeled != "") print peeled; else if (sha != "") print sha }'
}
