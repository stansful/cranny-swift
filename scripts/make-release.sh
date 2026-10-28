#!/usr/bin/env bash
# Prepares a release: shows the current version (VERSION) and the last release tag, asks for the new version (Enter
# takes the next patch version), checks that it is higher than the current version and every release tag (local
# ones and origin's), writes it into VERSION and commits only that file as "feat: release - version X.Y.Z". It
# never pushes: the release starts when that commit reaches main on GitHub (.github/workflows/release.yml: the CI
# checks, scripts/build-release.sh and the GitHub release vX.Y.Z). No tags here: GitHub creates the tag vX.Y.Z when
# the workflow publishes the release.
#
#   scripts/make-release.sh [X.Y.Z|patch|minor|major] [--yes] [--no-commit]
#
# Runs from any directory; bash 3.2 (macOS) or 5 (Linux), BSD or GNU tools. Needs git only (no Xcode).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/.." && pwd -P)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=scripts/lib/version.sh
source "$HERE/lib/version.sh"

usage() {
  cat <<'EOF'
Prepares a Cranny release: writes the new version into VERSION and commits it as "feat: release - version X.Y.Z".
Release X.Y.Z (tag vX.Y.Z) comes out when that commit reaches main on GitHub (.github/workflows/release.yml).

  scripts/make-release.sh [X.Y.Z|patch|minor|major] [--yes] [--no-commit]

  X.Y.Z         the new version; without it the script shows the current one and asks (Enter: the next patch version)
  patch, minor, major
                the next patch, minor or major version
  -y, --yes     no questions: the next patch version (unless one is given), commit without asking
  --no-commit   only write the version into VERSION, no commit
  -h, --help    this help

A version is X.Y.Z: three numbers without leading zeros and without "v", each at most 9 digits, higher than the
current version and every release tag (local ones and origin's). The script sets no tag: GitHub creates vX.Y.Z when
the release workflow publishes the release.
EOF
}

say() { printf '%s\n' "$*"; }
usage_error() {
  printf '\033[1;31merror:\033[0m %s\n\n' "$*" >&2
  usage >&2
  exit 2
}
yes_answer() {
  case $1 in
  y | Y | yes | Yes | YES | д | Д | да | Да | ДА) return 0 ;;
  *) return 1 ;;
  esac
}
trim() {
  local s="$1"
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}
# bump_kind <word>: prints patch, minor or major for a bump word; fails for anything else
bump_kind() {
  case $1 in
  patch | Patch | PATCH) echo patch ;;
  minor | Minor | MINOR) echo minor ;;
  major | Major | MAJOR) echo major ;;
  *) return 1 ;;
  esac
}

new='' have_new='' yes='' commit=1
while [ $# -gt 0 ]; do
  case $1 in
  -h | --help)
    usage
    exit 0
    ;;
  -y | --yes) yes=1 ;;
  --no-commit) commit= ;;
  -*) usage_error "unknown option $1" ;;
  *)
    [ -z "$have_new" ] || usage_error "two versions given: $new and $1"
    new=$1 have_new=1
    ;;
  esac
  shift
done

# --- the repository
command -v git >/dev/null 2>&1 || die "git is required."
top="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null)" ||
  die "$ROOT_DIR is not a git repository. Run git init, make the first commit and git remote add origin <url> first."
[ "$(cd "$top" && pwd -P)" = "$ROOT_DIR" ] || die "$ROOT_DIR is not the root of its git repository (the root is $top)."
cd "$ROOT_DIR"
git rev-parse -q --verify HEAD >/dev/null || die "the repository has no commits yet: commit the project first."
branch="$(git symbolic-ref -q --short HEAD)" ||
  die "HEAD is not on a branch (detached HEAD): switch to a branch first, e.g. git switch main."
git ls-files --error-unmatch "$APP_VERSION_FILE" >/dev/null 2>&1 || die "$APP_VERSION_FILE is not in git: commit it."

dirty="$(git status --porcelain --untracked-files=no)"
if [ -n "$dirty" ]; then
  printf '\033[1;31merror:\033[0m there are uncommitted changes (working tree or index):\n%s\n' "$dirty" >&2
  printf 'Commit them or set them aside (git stash) and run again: the release commit holds only %s.\n' \
    "$APP_VERSION_FILE" >&2
  exit 1
fi
untracked="$(git ls-files --others --exclude-standard)"
if [ -n "$untracked" ]; then
  warn "files not in git, the release does not get them:"
  printf '%s\n' "$untracked" | sed -n '1,10s/^/  /p' >&2
  [ "$(printf '%s\n' "$untracked" | wc -l | tr -d ' ')" -le 10 ] || printf '  …\n' >&2
fi

has_origin=
git remote get-url origin >/dev/null 2>&1 && has_origin=1

# release.yml releases pushes to main only, whatever origin's default branch is
[ "$branch" = main ] ||
  warn "you are on $branch, and releases come out of main only: this commit is released only once it is merged into main."
if [ -n "$has_origin" ] && git show-ref -q --verify "refs/remotes/origin/$branch"; then
  behind="$(git rev-list --count "HEAD..refs/remotes/origin/$branch")"
  [ "$behind" = 0 ] ||
    warn "$branch is $behind commit(s) behind origin/$branch (as of the last fetch): git pull first."
fi

# --- versions
current="$(app_version_get "$ROOT_DIR")" ||
  die "$APP_VERSION_FILE must hold exactly one line, the version X.Y.Z: fix the file by hand and commit it."
version_valid "$current" ||
  die "$APP_VERSION_FILE holds '$current', not X.Y.Z (no leading zeros, no \"v\"): fix the file by hand and commit it."

# Releases are tagged on GitHub, so a clone often has no tags of its own: origin's count. tags_known is empty when
# origin has them but they could not be read.
tags="$(git tag -l)" tags_known=1
if [ -n "$has_origin" ]; then
  if remote="$(GIT_TERMINAL_PROMPT=0 git ls-remote --tags origin)"; then
    tags="$tags
$remote"
  else
    tags_known=
    warn "cannot read the tags of origin ($(git remote get-url origin)): comparing with the local tags only."
  fi
fi
highest="$(printf '%s\n' "$tags" | highest_tag)"
highest_version=${highest%% *}
last_tag=${highest#* }

say "Current version:  $current ($APP_VERSION_FILE)"
if [ -n "$highest" ]; then
  if [ -n "$tags_known" ]; then
    say "Last release tag: $last_tag"
  else
    say "Last release tag: $last_tag (of the local tags)"
  fi
elif [ -n "$tags_known" ]; then
  say "No release tags yet."
else
  say "Release tags unknown: there are no local ones, and origin's could not be read."
fi
if [ -n "$tags_known" ] && { [ -z "$highest" ] || version_gt "$current" "$highest_version"; }; then
  say "There is no tag $(release_tag "$current") yet: once a commit with this version is on main on GitHub, release $current comes out even without a new version."
fi
base=$current
[ -z "$highest" ] || ! version_gt "$highest_version" "$base" || base=$highest_version
# The bumps of the base that are still versions (above the current version and every tag they always are); Enter and
# --yes take the patch one, else the minor one, else the major one, as the numbers run out of digits
choices='' suggested=''
for kind in patch minor major; do
  v="$(version_bump "$base" "$kind")"
  version_valid "$v" || continue
  choices="$choices${choices:+, }$v ($kind)"
  [ -n "$suggested" ] || suggested=$v
done
[ -n "$suggested" ] ||
  die "there is no version after $base with at most 9 digits per number: nothing left to release."

# check_version <v>: prints why v cannot be the new version, and fails
check_version() {
  local v="$1" t
  if [ -z "$v" ]; then
    echo "no version given"
    return 1
  fi
  if ! version_valid "$v"; then
    case $v in
    v[0-9]* | V[0-9]*) echo "'$v': give the version without \"v\", e.g. ${v#?}" ;;
    *) echo "'$v' is not a version X.Y.Z (three numbers without leading zeros, at most 9 digits each, e.g. $suggested)" ;;
    esac
    return 1
  fi
  t="$(printf '%s\n' "$tags" | tag_of_version "$v")"
  if [ -n "$t" ]; then
    echo "tag $t exists: version $v has been released already"
    return 1
  fi
  if ! version_gt "$v" "$current"; then
    echo "version $v is not higher than the current version $current"
    return 1
  fi
  if [ -n "$highest" ] && ! version_gt "$v" "$highest_version"; then
    echo "version $v is not higher than the last release tag $last_tag"
    return 1
  fi
}
# resolve <answer>: prints the version an answer names: a bump word becomes that bump of the base version
resolve() {
  local kind
  if kind="$(bump_kind "$1")"; then
    version_bump "$base" "$kind"
  else
    printf '%s' "$1"
  fi
}

if [ -n "$have_new" ]; then
  new="$(resolve "$new")"
  reason="$(check_version "$new")" || die "$reason."
  say "New version: $new"
elif [ -n "$yes" ]; then
  new=$suggested
  reason="$(check_version "$new")" || die "$reason."
  say "New version: $new"
else
  say "Next: $choices."
  while :; do
    printf 'New version [%s]: ' "$suggested"
    if ! IFS= read -r answer; then
      echo
      die "no input, nothing changed."
    fi
    answer="$(trim "$answer")"
    [ -n "$answer" ] || answer=$suggested
    answer="$(resolve "$answer")"
    if reason="$(check_version "$answer")"; then
      new=$answer
      break
    fi
    printf '  %s. Enter another version.\n' "$reason" >&2
  done
fi

# --- VERSION and the commit
message="feat: release - version $new"
numstat="$(printf '1\t1\t%s' "$APP_VERSION_FILE")"
restore() { git checkout -q -- "$APP_VERSION_FILE"; }
trap 'restore; printf "\nInterrupted: %s restored.\n" "$APP_VERSION_FILE" >&2; exit 130' INT TERM
# Exactly the version line changes, to exactly the new version
if ! app_version_set "$ROOT_DIR" "$new" || [ "$(app_version_get "$ROOT_DIR")" != "$new" ] ||
  [ "$(git diff --numstat -- "$APP_VERSION_FILE")" != "$numstat" ]; then
  restore
  die "could not write version $new into $APP_VERSION_FILE; the file is restored."
fi
git --no-pager diff -- "$APP_VERSION_FILE"

if [ -z "$commit" ]; then
  trap - INT TERM
  say "$APP_VERSION_FILE: version $new. No commit (--no-commit). Commit this file alone:"
  say "  git commit -m '$message' -- $APP_VERSION_FILE"
  exit 0
fi
if [ -z "$yes" ]; then
  printf 'Commit %s as "%s"? [Y/n] ' "$APP_VERSION_FILE" "$message"
  if ! IFS= read -r answer; then
    echo
    restore
    die "no input; $APP_VERSION_FILE restored."
  fi
  answer="$(trim "$answer")"
  if [ -n "$answer" ] && ! yes_answer "$answer"; then
    restore
    say "Cancelled: $APP_VERSION_FILE restored, no commit."
    exit 1
  fi
fi
parent="$(git rev-parse HEAD)"
if ! git commit -q -m "$message" -- "$APP_VERSION_FILE"; then
  restore
  die "git commit failed; $APP_VERSION_FILE restored."
fi
# git hooks (pre-commit and the like) run on the commit's own index: whatever one stages lands in the commit.
# The release commit is the version line of VERSION with the new version and nothing else, or it is undone.
changed="$(git diff-tree -r --name-only "$parent" HEAD)"
if [ "$changed" != "$APP_VERSION_FILE" ] || [ "$(git diff --numstat "$parent" HEAD)" != "$numstat" ] ||
  [ "$(git show "HEAD:$APP_VERSION_FILE" 2>/dev/null | app_version_parse)" != "$new" ]; then
  git reset -q --soft "$parent"
  git reset -q -- "$APP_VERSION_FILE"
  restore
  trap - INT TERM
  {
    printf '\033[1;31merror:\033[0m a git hook (pre-commit or another) changed the release commit, which must hold only version %s in %s. The commit had:\n' "$new" "$APP_VERSION_FILE"
    printf '%s\n' "$changed" | sed 's/^/  /'
    printf 'The commit is undone and %s restored; whatever the hook changed in the working tree stays there (git status).\n' "$APP_VERSION_FILE"
    printf 'Fix the hook, or commit past the hooks: scripts/make-release.sh %s --no-commit, then\n' "$new"
    printf "  git commit --no-verify -m '%s' -- %s\n" "$message" "$APP_VERSION_FILE"
  } >&2
  exit 1
fi
trap - INT TERM
say "Commit $(git rev-parse --short HEAD): $message"
say "Release $new (tag $(release_tag "$new")) comes out when this commit reaches main on GitHub (.github/workflows/release.yml)."
