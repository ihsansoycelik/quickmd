#!/usr/bin/env bash
# Publishes a GitHub release of QuickMD from the current commit on main.
#
#   ./scripts/release.sh 1.1.0          build, tag v1.1.0, upload QuickMD-1.1.0.zip
#   ./scripts/release.sh 1.1.0 --draft  the same, as a draft release
#
# Before running: move the "Unreleased" notes in CHANGELOG.md under a
# "## [1.1.0] - YYYY-MM-DD" heading and commit. This script then:
#   1. checks the tree is clean, on main and in step with origin/main,
#   2. runs swift test,
#   3. writes MARKETING_VERSION to Packaging/version and commits it,
#   4. builds build/QuickMD.app, zips it with ditto,
#   5. tags vX.Y.Z, pushes main and the tag, and creates the release with
#      the CHANGELOG section as its notes.
# Needs macOS, the Swift toolchain and the GitHub CLI (gh auth login).
set -euo pipefail

VERSION="${1:-}"
DRAFT="${2:-}"
[[ -z "$DRAFT" || "$DRAFT" == "--draft" ]] || { echo "usage: $0 X.Y.Z [--draft]" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 X.Y.Z [--draft]" >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TAG="v$VERSION"

command -v gh >/dev/null || { echo "error: needs the GitHub CLI (brew install gh)" >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "error: release from main" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "error: commit or stash your changes first" >&2; exit 1; }
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "error: main is not in step with origin/main; pull or push first" >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "error: tag $TAG already exists" >&2; exit 1; }

# Release notes: the CHANGELOG section for this version, up to the next "## [".
NOTES="$(awk -v v="$VERSION" '
    $0 ~ "^## \\[" v "\\]" { on = 1; next }
    on && /^## \[/ { exit }
    on { print }
' CHANGELOG.md)"
[[ -n "${NOTES//[[:space:]]/}" ]] || { echo "error: CHANGELOG.md has no \"## [$VERSION]\" section; add one and commit" >&2; exit 1; }

swift test

sed -i '' "s/^MARKETING_VERSION=.*/MARKETING_VERSION=$VERSION/" Packaging/version
if [[ -n "$(git status --porcelain Packaging/version)" ]]; then
    git commit -q -m "Release $VERSION" -- Packaging/version
fi

./scripts/build-app.sh
ZIP="build/QuickMD-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/QuickMD.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

NOTES="$NOTES

---

Not notarized yet: on first launch right-click QuickMD.app and choose Open, or run
\`xattr -dr com.apple.quarantine /Applications/QuickMD.app\`.

SHA-256 of QuickMD-$VERSION.zip: \`$SHA\`"

git tag -a "$TAG" -m "QuickMD $VERSION"
git push -q origin main "$TAG"
gh release create "$TAG" "$ZIP" --title "QuickMD $VERSION" --notes "$NOTES" ${DRAFT:+--draft}
echo "Released $TAG ($ZIP, sha256 $SHA)"
