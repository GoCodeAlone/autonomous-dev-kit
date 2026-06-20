#!/usr/bin/env bash
# tests/no-machine-paths.sh — forbid operator-home paths and live secret literals in committed artifacts.
# Catches a real leak (/Users/<realuser>/x) but IGNORES <placeholder> segments and ellipsis,
# so artifacts that DOCUMENT the pattern (this feature's own docs) pass. Lines containing the
# sentinel `path-hygiene-allow` are skipped. Scans docs/, decisions/, skills/, and agents/.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
pattern='(/Users/|/home/)[A-Za-z0-9][A-Za-z0-9._-]*'
secret_pattern='(gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{20,}|[A-Za-z_][A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|COOKIE|KEY)=[^<[:space:]$][^[:space:]]{8,})'
hits=0
while IFS= read -r f; do
  while IFS=: read -r line content; do
    case "$content" in (*path-hygiene-allow*) continue ;; esac
    printf 'LEAK: %s:%s: %s\n' "${f#$ROOT/}" "$line" "$content" >&2
    hits=$((hits+1))
  done < <(grep -nE "$pattern" "$f" 2>/dev/null || true)
  while IFS=: read -r line content; do
    case "$content" in (*path-hygiene-allow*) continue ;; esac
    case "$content" in (*'<redacted>'*|*'${{ secrets.'*|*'...'*) continue ;; esac
    printf 'SECRET: %s:%s: %s\n' "${f#$ROOT/}" "$line" "$content" >&2
    hits=$((hits+1))
  done < <(grep -nE "$secret_pattern" "$f" 2>/dev/null || true)
done < <(find "$ROOT/docs" "$ROOT/decisions" "$ROOT/skills" "$ROOT/agents" -type f \( -name '*.md' -o -name '*.txt' \) 2>/dev/null)
if [ "$hits" -eq 0 ]; then echo "PASS: no operator-home machine paths or live secret literals in committed artifacts."; else
  echo "FAIL: $hits artifact hygiene leak(s) in committed artifacts." >&2; fi
[ "$hits" -eq 0 ]
