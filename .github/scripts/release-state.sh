#!/usr/bin/env bash
# Prints the release state of the version in VERSION (or $VERSION) for the commit $GITHUB_SHA; the release's tag is
# vX.Y.Z (release_tag in scripts/lib/version.sh):
#   new      - no tag and no release yet
#   retry    - the tag is already on $GITHUB_SHA but has no published release
#              (an earlier run died after GitHub created the tag, or the release was deleted)
#   released - a published release exists
# Exits 1, with an annotation, for every state a release must not be built from: a version that is not X.Y.Z, one
# that is not higher than every other release tag (vX.Y.Z or X.Y.Z), a tag on another commit with no release.
# release.yml's gate and its publish job both run it, so a re-run of a failed job sees the current tags and
# releases, not the ones from the first attempt.
#
# Env: GITHUB_REPOSITORY, GITHUB_SHA, GH_TOKEN (optional), GITHUB_API_URL (default https://api.github.com),
#      VERSION (default: the VERSION file). Tags come from `git ls-remote --tags origin` in this checkout.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$HERE/../.." && pwd -P)"
# shellcheck source=scripts/lib/version.sh
. "$ROOT_DIR/scripts/lib/version.sh"

: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}"
if [ -z "${VERSION:-}" ]; then
  VERSION="$(app_version_get "$ROOT_DIR")" || {
    echo "::error file=$APP_VERSION_FILE::$APP_VERSION_FILE must hold exactly one line, the version X.Y.Z." >&2
    exit 1
  }
fi

if ! version_valid "$VERSION"; then
  echo "::error file=$APP_VERSION_FILE::Version \"$VERSION\" must be X.Y.Z (no leading zeros, no \"v\", at most 9 digits per number): it names the release, its tag and its files. Set it with scripts/make-release.sh." >&2
  exit 1
fi
TAG="$(release_tag "$VERSION")"

# GET /releases/tags/{tag} only returns published releases, never drafts. The body goes to a temp file, not
# /dev/null: before a retry curl 8.5 (ubuntu-24.04) truncates its output, which fails on /dev/null (exit 23, no
# retry, no status), so one 5xx or 429 would fail the gate.
body="$(mktemp "${TMPDIR:-/tmp}/release-state.XXXXXX")"
status="$(curl -sS --retry 3 --max-time 30 -o "$body" -w '%{http_code}' \
  -H "Accept: application/vnd.github+json" \
  ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} \
  "${GITHUB_API_URL:-https://api.github.com}/repos/$GITHUB_REPOSITORY/releases/tags/$TAG")" || true
rm -f "$body"
case $status in
200)
  echo released
  exit 0
  ;;
404) ;;
*)
  echo "::error::The GitHub API answered HTTP ${status:-000} for release $TAG." >&2
  exit 1
  ;;
esac

refs="$(git -C "$ROOT_DIR" ls-remote --tags origin)" || {
  echo "::error::Cannot read the tags of origin (git ls-remote)." >&2
  exit 1
}
# The commit of the tag, an annotated one followed to it
tag_sha="$(tag_commit "$TAG" <<<"$refs")"
highest="$(printf '%s\n' "$refs" | highest_tag "$TAG")"

# /releases/latest, which the in-app update check polls, would be a lower version than an existing one.
if [ -n "$highest" ] && ! version_gt "$VERSION" "${highest%% *}"; then
  echo "::error file=$APP_VERSION_FILE::Version $VERSION is not higher than the existing tag ${highest#* }. Bump it with scripts/make-release.sh." >&2
  exit 1
fi

if [ -z "$tag_sha" ]; then
  echo new
elif [ "$tag_sha" = "$GITHUB_SHA" ]; then
  echo retry
else
  echo "::error::Tag $TAG points at $tag_sha, not $GITHUB_SHA, and has no release. Delete the tag or bump the version (scripts/make-release.sh)." >&2
  exit 1
fi
