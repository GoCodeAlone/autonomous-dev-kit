#!/usr/bin/env bash
# tests/plan-scope-check-contracts.sh — direct contracts for plan-scope-check.sh.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/tests/plan-scope-check.sh"
APPLY="$REPO_ROOT/hooks/scope-lock-apply"
failures=0

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

test_relative_plan_paths_resolve_from_caller_cwd() {
  local tmp ws out status
  tmp="$(mktemp -d)"
  ws="$tmp/workspace"
  mkdir -p "$ws/docs/plans"
  (
    cd "$ws" &&
      git init -q &&
      git checkout -q -b feat/p &&
      git -c user.email=a@b -c user.name=x commit -q --allow-empty -m init
  )
  cat >"$ws/docs/plans/p.md" <<'PLAN'
# P

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | P | Task 1 | feat/p |

**Status:** Locked 2026-06-23T00:00:00Z

### Task 1: P
PLAN
  bash "$APPLY" "$ws/docs/plans/p.md" >/dev/null

  set +e
  out="$(
    cd "$ws" &&
      bash "$CHECKER" \
        --plan docs/plans/p.md \
        --verify-lock docs/plans/p.md \
        --against-branch docs/plans/p.md
  )"
  status=$?
  set -e

  if [ "$status" = "0" ] && printf '%s' "$out" | grep -q 'PASS: scope-manifest checks succeeded'; then
    pass "plan-scope-check: relative plan paths resolve from caller cwd"
  else
    fail "plan-scope-check: expected caller-relative paths to pass, status=${status}, output=${out}"
  fi
  rm -rf "$tmp"
}

test_relative_plan_paths_resolve_from_caller_cwd

echo ""
echo "Results: $failures failure(s)"
[ "$failures" -eq 0 ]
