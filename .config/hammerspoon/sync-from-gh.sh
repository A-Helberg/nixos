#!/bin/bash
# Sync the GitHub upstream's default branch back to forgejo.
# Usage: sync-from-gh.sh <forgejo-repo-url>   e.g. https://git.coded.page/andre/teamready
set -euo pipefail

# Hammerspoon launches us outside a login shell, so nix tools aren't on PATH.
PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

REPO_URL="${1:?usage: sync-from-gh.sh <forgejo-repo-url>}"
REPO_URL="${REPO_URL%/}" REPO_URL="${REPO_URL%.git}"
[[ "$REPO_URL" =~ ^https://git\.coded\.page/([^/]+)/([^/]+)$ ]] ||
  { echo "unrecognised forgejo repo URL: $REPO_URL" >&2; exit 1; }
OWNER="${BASH_REMATCH[1]}" REPO="${BASH_REMATCH[2]}"

# The GitHub upstream is whatever the forgejo repo's website field points at.
WEBSITE=$(curl -fsS "https://git.coded.page/api/v1/repos/$OWNER/$REPO" | jq -r '.website // ""')
WEBSITE="${WEBSITE%/}" WEBSITE="${WEBSITE%.git}"
[[ "$WEBSITE" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]] ||
  { echo "forgejo repo $OWNER/$REPO has no GitHub URL in its website field (got: '$WEBSITE')" >&2; exit 1; }
GH_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"

DEFAULT=$(gh repo view "$GH_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
[[ -n "$DEFAULT" ]] || { echo "cannot determine default branch of $GH_REPO" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git clone --quiet --bare --single-branch --branch "$DEFAULT" \
  "git@github.com:$GH_REPO.git" "$TMP"

# Fast-forward only: if forgejo has diverged, this fails and the alert says so.
git -C "$TMP" push --quiet "ssh://forgejo@git.coded.page:2222/$OWNER/$REPO.git" \
  "refs/heads/$DEFAULT:refs/heads/$DEFAULT"

echo "pushed $DEFAULT ($GH_REPO -> $OWNER/$REPO)"
