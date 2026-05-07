#!/usr/bin/env bash
# bump-version.sh — Update the version string across all plugin manifests.
#
# Usage:
#   scripts/bump-version.sh <new-version>
#   scripts/bump-version.sh <old-version> <new-version>
#
# When called with one argument the script detects the current version from
# .claude-plugin/plugin.json and replaces it everywhere.
# When called with two arguments the first is the version to replace (useful
# when the files are already inconsistent).
#
# Version files managed by this script:
#   .claude-plugin/plugin.json
#   .claude-plugin/marketplace.json
#   .cursor-plugin/plugin.json

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VERSION_FILES=(
  ".claude-plugin/plugin.json"
  ".claude-plugin/marketplace.json"
  ".cursor-plugin/plugin.json"
)

usage() {
  echo "Usage: $0 <new-version>" >&2
  echo "       $0 <old-version> <new-version>" >&2
  exit 1
}

if [[ $# -eq 1 ]]; then
  NEW_VERSION="$1"
  # Detect the current version from the primary file
  PRIMARY="${REPO_ROOT}/${VERSION_FILES[0]}"
  OLD_VERSION=$(grep '"version"' "$PRIMARY" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
  if [[ -z "$OLD_VERSION" ]]; then
    echo "ERROR: Could not detect current version from $PRIMARY" >&2
    exit 1
  fi
elif [[ $# -eq 2 ]]; then
  OLD_VERSION="$1"
  NEW_VERSION="$2"
else
  usage
fi

# Validate version looks like semver (N.N.N)
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: Version '$NEW_VERSION' does not look like semver (e.g. 5.7.0)" >&2
  exit 1
fi

echo "Bumping version: $OLD_VERSION → $NEW_VERSION"

for rel_path in "${VERSION_FILES[@]}"; do
  abs_path="${REPO_ROOT}/${rel_path}"
  if [[ ! -f "$abs_path" ]]; then
    echo "WARNING: $rel_path not found, skipping" >&2
    continue
  fi
  sed -i.bak "s/\"version\": \"${OLD_VERSION}\"/\"version\": \"${NEW_VERSION}\"/" "$abs_path" && rm -f "${abs_path}.bak"
  echo "  Updated $rel_path"
done

echo "Done. Remember to:"
echo "  1. Update RELEASE-NOTES.md with a new ## v${NEW_VERSION} section."
echo "  2. Commit the changes: git commit -am \"chore: bump version to ${NEW_VERSION}\""
echo "  3. Tag the release:     git tag v${NEW_VERSION}"
