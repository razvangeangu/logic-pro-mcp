#!/bin/bash
#
# Scripts/release-stable.sh — guarded stable release tag publisher.
#
# Stable tags trigger .github/workflows/release.yml and require Apple
# Developer ID + notarization secrets. This script prevents the common
# failure mode where a stable tag is pushed before those repo secrets exist.
#
# Usage:
#   Scripts/release-stable.sh v3.4.6
#   DRY_RUN=1 Scripts/release-stable.sh v3.4.6
#
set -euo pipefail

VERSION="${1:-}"
REPO="${GITHUB_REPOSITORY:-MongLong0214/logic-pro-mcp}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"

required_secrets=(
    MACOS_CERT_BASE64
    MACOS_CERT_PASSWORD
    MACOS_SIGNING_IDENTITY
    MACOS_KEYCHAIN_PASSWORD
    APPLE_NOTARY_APPLE_ID
    APPLE_NOTARY_TEAM_ID
    APPLE_NOTARY_APP_PASSWORD
)

usage() {
    echo "Usage: $0 vMAJOR.MINOR.PATCH"
}

run() {
    echo "→ $*"
    if [ "$DRY_RUN" != "1" ]; then
        "$@"
    fi
}

if [ -z "$VERSION" ]; then
    usage
    exit 1
fi

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: stable VERSION '$VERSION' must be strict SemVer, e.g. v3.4.6"
    echo "       Use Scripts/release.sh vX.Y.Z-rcN for ADHOC prereleases."
    exit 1
fi

cd "$REPO_ROOT"

echo ""
echo "  Logic Pro MCP — stable release preflight"
echo "  version: $VERSION"
echo "  repo:    $REPO"
echo "  dry-run: $DRY_RUN"
echo ""

if [ "$(git branch --show-current)" != "main" ]; then
    echo "Error: stable releases must be tagged from the main branch."
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Error: working tree is not clean. Commit or stash first."
    git status --short
    exit 1
fi

run git fetch --quiet origin main --tags

if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "Error: HEAD must match origin/main before publishing a stable tag."
    echo "       Push or pull main first, then rerun this script."
    exit 1
fi

if git rev-parse "refs/tags/$VERSION" >/dev/null 2>&1; then
    echo "Error: tag $VERSION already exists locally."
    exit 1
fi

REMOTE_TAGS=$(git ls-remote --tags origin "$VERSION") || {
    echo "Error: could not verify remote tag availability for $VERSION."
    echo "       Refusing to continue because a duplicate stable tag cannot be fixed safely."
    exit 1
}
if printf '%s\n' "$REMOTE_TAGS" | grep -q "refs/tags/$VERSION"; then
    echo "Error: tag $VERSION already exists on origin."
    exit 1
fi

gh auth status >/dev/null

if gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    echo "Error: GitHub Release $VERSION already exists."
    exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
    echo "DRY_RUN: checking GitHub secret names anyway; no tag will be created."
fi

SECRET_NAMES=$(gh secret list --repo "$REPO" --app actions --json name --jq '.[].name') || {
    echo "Error: could not list GitHub Actions secrets for $REPO."
    exit 1
}

missing=0
for secret in "${required_secrets[@]}"; do
    if ! printf '%s\n' "$SECRET_NAMES" | grep -qx "$secret"; then
        echo "Error: missing GitHub Actions secret: $secret"
        missing=1
    fi
done

if [ "$missing" != "0" ]; then
    echo ""
    echo "Stable tag '$VERSION' was NOT created."
    echo "Configure all notarization secrets first, then rerun this script."
    exit 1
fi

run python3 -m py_compile Scripts/live-e2e-test.py
run swift test --no-parallel
run swift build -c release

run git tag "$VERSION" -m "Release $VERSION"
run git push origin "$VERSION"

echo ""
echo "  Stable tag published: $VERSION"
echo "  GitHub Actions release workflow will build, notarize, publish artifacts,"
echo "  then run install validation on macos-14 and macos-15."
echo ""
