#!/usr/bin/env bash
# version-check.sh — Validate that all plugin manifests declare the same version.
#
# Optionally validates against the latest git tag when --check-tag is passed.
#
# Usage:
#   tests/version-check.sh              # consistency check only
#   tests/version-check.sh --check-tag  # also verify versions match latest git tag
#
# Exit codes:
#   0  All version files are consistent (and match the git tag if --check-tag).
#   1  One or more version files disagree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CHECK_TAG=false
if [[ "${1:-}" == "--check-tag" ]]; then
  CHECK_TAG=true
fi

VERSION_FILES=(
  ".claude-plugin/plugin.json"
  ".claude-plugin/marketplace.json"
  ".cursor-plugin/plugin.json"
)

extract_version() {
  grep '"version"' "$1" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/'
}

ERRORS=0
FIRST_VERSION=""
FIRST_FILE=""

for rel_path in "${VERSION_FILES[@]}"; do
  abs_path="${REPO_ROOT}/${rel_path}"
  if [[ ! -f "$abs_path" ]]; then
    echo "ERROR: $rel_path not found" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi
  ver=$(extract_version "$abs_path")
  if [[ -z "$ver" ]]; then
    echo "ERROR: Could not read version from $rel_path" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi
  if [[ -z "$FIRST_VERSION" ]]; then
    FIRST_VERSION="$ver"
    FIRST_FILE="$rel_path"
  elif [[ "$ver" != "$FIRST_VERSION" ]]; then
    echo "ERROR: Version mismatch: $rel_path has '$ver' but $FIRST_FILE has '$FIRST_VERSION'" >&2
    ERRORS=$((ERRORS + 1))
  fi
done

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo "FAIL: Version files are inconsistent. Run scripts/bump-version.sh <new-version> to fix." >&2
  exit 1
fi

echo "OK: All version files agree on version $FIRST_VERSION"

if [[ "$CHECK_TAG" == true ]]; then
  # Get the latest semver tag (strip the leading 'v')
  LATEST_TAG=$(git -C "$REPO_ROOT" tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
  if [[ -z "$LATEST_TAG" ]]; then
    echo "WARNING: No semver git tags found; skipping tag check." >&2
  else
    TAG_VERSION="${LATEST_TAG#v}"
    if [[ "$FIRST_VERSION" != "$TAG_VERSION" ]]; then
      echo "ERROR: Plugin version '$FIRST_VERSION' does not match latest git tag '$LATEST_TAG'." >&2
      echo "       Run: scripts/bump-version.sh ${TAG_VERSION}" >&2
      exit 1
    fi
    echo "OK: Plugin version $FIRST_VERSION matches latest git tag $LATEST_TAG"
  fi
fi
