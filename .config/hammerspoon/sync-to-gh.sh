#!/bin/bash
# Sync a forgejo PR to GitHub: push the branch and open a matching PR.
# Usage: sync-to-gh.sh <forgejo-pr-url>   e.g. https://git.coded.page/andre/teamready/pulls/20
# Prints the GitHub PR URL as its last line of output.
set -euo pipefail

# Hammerspoon launches us outside a login shell, so nix tools aren't on PATH.
PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

PR_URL="${1:?usage: sync-to-gh.sh <forgejo-pr-url>}"
[[ "$PR_URL" =~ ^https://git\.coded\.page/([^/]+)/([^/]+)/pulls/([0-9]+)$ ]] ||
  { echo "unrecognised forgejo PR URL: $PR_URL" >&2; exit 1; }
OWNER="${BASH_REMATCH[1]}" REPO="${BASH_REMATCH[2]}" NUM="${BASH_REMATCH[3]}"

PR_JSON=$(curl -fsS "https://git.coded.page/api/v1/repos/$OWNER/$REPO/pulls/$NUM")
TITLE=$(jq -r '.title' <<<"$PR_JSON")
HEAD_REF=$(jq -r '.head.ref' <<<"$PR_JSON")
BASE_REF=$(jq -r '.base.ref' <<<"$PR_JSON")

# The GitHub upstream is whatever the forgejo repo's website field points at.
WEBSITE=$(curl -fsS "https://git.coded.page/api/v1/repos/$OWNER/$REPO" | jq -r '.website // ""')
WEBSITE="${WEBSITE%/}" WEBSITE="${WEBSITE%.git}"
[[ "$WEBSITE" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]] ||
  { echo "forgejo repo $OWNER/$REPO has no GitHub URL in its website field (got: '$WEBSITE')" >&2; exit 1; }
GH_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
gh repo view "$GH_REPO" --json name >/dev/null ||
  { echo "cannot reach $GH_REPO on GitHub" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git clone --quiet --bare "https://git.coded.page/$OWNER/$REPO.git" "$TMP"

# Forgejo is the source of truth: the head branch mirrors it exactly. The base
# is only pushed so the PR has something to target; if GitHub's copy has
# diverged we leave it alone rather than force it.
git -C "$TMP" push --quiet "git@github.com:$GH_REPO.git" "$BASE_REF" || true
git -C "$TMP" push --quiet --force "git@github.com:$GH_REPO.git" "$HEAD_REF"

EXISTING=$(gh pr list --repo "$GH_REPO" --head "$HEAD_REF" --state open --json url -q '.[0].url // empty')
if [[ -n "$EXISTING" ]]; then
  echo "$EXISTING"
else
  gh pr create --repo "$GH_REPO" --head "$HEAD_REF" --base "$BASE_REF" \
    --title "$TITLE" --body ""
fi
