#!/usr/bin/env bash
# Verifies every skill that uses compressed prose advertises the expander skill.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

failures=0
note='Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.'

while IFS= read -r file; do
  case "$file" in
    skills/condensed-pipeline-writing/SKILL.md)
      if grep -Fq "$note" "$file"; then
        printf 'FAIL: compression skill should not require itself: %s\n' "$file" >&2
        failures=$((failures + 1))
      fi
      ;;
    *)
      if ! grep -Fq "$note" "$file"; then
        printf 'FAIL: missing condensed-format note: %s\n' "$file" >&2
        failures=$((failures + 1))
      fi
      ;;
  esac
done < <(find skills -mindepth 2 -maxdepth 2 -name SKILL.md | sort)

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "PASS: condensed-format notes are present where required."
