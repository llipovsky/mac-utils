#!/bin/bash
# Bumps the version, builds a signed release and publishes it on GitHub.
# Installed copies pick it up through their update check.
#
#   scripts/release.sh            0.1.0 -> 0.1.1
#   scripts/release.sh minor      0.1.0 -> 0.2.0
#   scripts/release.sh major      0.1.0 -> 1.0.0
#   scripts/release.sh 1.4.2      exact version (may equal VERSION, e.g. for the first release)
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "$ROOT"

command -v gh >/dev/null || die "GitHub CLI (gh) is required: brew install gh"
[[ -z "$(git status --porcelain)" ]] || die "commit or stash your changes first."

CURRENT="$(tr -d '[:space:]' < VERSION)"
IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "${1:-patch}" in
    patch) NEW="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor) NEW="$MAJOR.$((MINOR + 1)).0" ;;
    major) NEW="$((MAJOR + 1)).0.0" ;;
    [0-9]*.[0-9]*.[0-9]*) NEW="$1" ;;
    *) die "usage: scripts/release.sh [patch|minor|major|X.Y.Z]" ;;
esac
git rev-parse "v$NEW" >/dev/null 2>&1 && die "tag v$NEW already exists."

echo "$NEW" > VERSION
trap 'git checkout -- VERSION 2>/dev/null || true' ERR
"$ROOT/scripts/build.sh"
trap - ERR

step "Publishing v$NEW"
git add VERSION signing/designated-requirement.txt
# Nothing to commit when releasing the version already in VERSION (e.g. the first release).
git diff --cached --quiet || git commit -m "Release v$NEW"
git tag "v$NEW"
git push origin HEAD "v$NEW"
gh release create "v$NEW" "build/$APP_NAME.zip" --repo "$GITHUB_REPO" --title "MacUtils $NEW" --generate-notes

echo "Released v$NEW: https://github.com/$GITHUB_REPO/releases/tag/v$NEW"
