#!/usr/bin/env bash
# tests/no-machine-paths.sh — forbid operator-home absolute paths in committed artifacts.
# Catches a real leak (/Users/<realuser>/x) but IGNORES <placeholder> segments and ellipsis,
# so artifacts that DOCUMENT the pattern (this feature's own docs) pass. Lines containing the
# sentinel `path-hygiene-allow` are skipped. Scans docs/, decisions/, and skills/ (all committed
# artifact dirs — the skill-rule's "enforced by this script" claim must hold for skills/ too).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
pattern='(/Users/|/home/)[A-Za-z0-9][A-Za-z0-9._-]*'
hits=0
while IFS= read -r f; do
  while IFS=: read -r line content; do
    case "$content" in (*path-hygiene-allow*) continue ;; esac
    printf 'LEAK: %s:%s: %s\n' "${f#$ROOT/}" "$line" "$content" >&2
    hits=$((hits+1))
  done < <(grep -nE "$pattern" "$f" 2>/dev/null || true)
done < <(find "$ROOT/docs" "$ROOT/decisions" "$ROOT/skills" "$ROOT/agents" -type f \( -name '*.md' -o -name '*.txt' \) 2>/dev/null)
if [ "$hits" -eq 0 ]; then echo "PASS: no operator-home machine paths in committed artifacts."; else
  echo "FAIL: $hits machine-path leak(s) in committed artifacts." >&2; fi
[ "$hits" -eq 0 ]
