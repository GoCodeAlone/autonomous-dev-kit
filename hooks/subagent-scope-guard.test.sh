#!/usr/bin/env bash
# hooks/subagent-scope-guard.test.sh
# Lifecycle test for the subagent-scope-guard SubagentStop hook.
#
# Regression coverage for autonomous-dev-kit#86:
#   (1) a COMMITTED .scope-lock at HEAD (legitimate; written by scope-lock-apply)
#       must NOT trigger a block — the old code inspected HEAD's last commit and
#       false-positived on every subsequent subagent, then instructed `git revert`.
#   (2) an UNCOMMITTED working-tree .scope-lock write (a subagent directly writing
#       a lock) MUST trigger a block — but the message must be NON-destructive: it
#       must NOT instruct the subagent to revert/run git (the #86 hazard), and must
#       tell it to surface to the lead instead.
#   (3) a clean repo (no scope-lock changes) must NOT trigger a block.
#
# Run: bash hooks/subagent-scope-guard.test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname -- "$0")/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/subagent-scope-guard"

export LC_ALL=C LANG=C LC_CTYPE=C
export SUPERPOWERS_HOOKS_DISABLE=  # ensure the guard is active during the test

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'PASS: %s\n' "$*"; }

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not found; subagent-scope-guard test requires jq\n'
    exit 0
  fi
}

# run_hook <cwd>  — feeds a SubagentStop payload (stop_hook_active=false) on stdin.
run_hook() {
  local cwd="$1"
  jq -nc --arg cwd "$cwd" --arg tp "/tmp/fake-transcript-${RANDOM}.jsonl" \
    '{stop_hook_active:false, cwd:$cwd, transcript_path:$tp, tool_name:"Agent"}' \
    | env LC_ALL=C LANG=C LC_CTYPE=C "$HOOK"
}

setup_repo() {
  # Create a temp git repo with one ordinary committed file (clean baseline).
  local d
  d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  printf 'hello\n' > "$d/README.md"
  git -C "$d" add README.md
  git -C "$d" commit -q -m init
  printf '%s' "$d"
}

require_jq

# ── Test 1: committed .scope-lock at HEAD must NOT block (the #86 bug) ──
{
  repo="$(setup_repo)"
  # simulate scope-lock-apply having written + committed the lock
  mkdir -p "$repo/docs/plans"
  printf 'manifest\n' > "$repo/docs/plans/x.plan.md"
  printf 'abcdef0123456789\n' > "$repo/docs/plans/x.plan.md.scope-lock"
  git -C "$repo" add docs/plans/x.plan.md docs/plans/x.plan.md.scope-lock
  git -C "$repo" commit -q -m "lock scope"
  out="$(run_hook "$repo" 2>/dev/null || true)"
  if printf '%s' "$out" | jq -e '.decision=="block"' >/dev/null 2>&1; then
    fail "Test1: committed lock at HEAD falsely blocked (the #86 bug): $(printf '%s' "$out" | jq -r .reason)"
  else
    pass "Test1: committed lock at HEAD does NOT block (regression fixed)"
  fi
  rm -rf "$repo"
}

# ── Test 2: uncommitted working-tree .scope-lock write MUST block, non-destructively ──
{
  repo="$(setup_repo)"
  # a subagent directly wrote a .scope-lock next to an already-tracked plan
  # (the realistic case: the plan dir is tracked, so the new lock shows as a
  # specific untracked file rather than a collapsed untracked dir).
  mkdir -p "$repo/docs/plans"
  printf '## Scope Manifest\n\n(locked content)\n' > "$repo/docs/plans/y.plan.md"
  git -C "$repo" add docs/plans/y.plan.md
  git -C "$repo" commit -q -m "add plan"
  printf 'tampered\n' > "$repo/docs/plans/y.plan.md.scope-lock"
  out="$(run_hook "$repo" 2>/dev/null || true)"
  if ! printf '%s' "$out" | jq -e '.decision=="block"' >/dev/null 2>&1; then
    fail "Test2: uncommitted .scope-lock write did NOT block (should be caught)"
  else
    pass "Test2: uncommitted .scope-lock write is blocked (legitimate catch)"
    reason="$(printf '%s' "$out" | jq -r .reason)"
    # Non-destructive: the OLD "Revert unauthorized" instruction must be GONE
    if printf '%s' "$reason" | grep -qi 'Revert unauthorized'; then
      fail "Test2: block message still instructs 'Revert unauthorized' (the #86 hazard)"
    else
      pass "Test2: block message is non-destructive (no 'Revert unauthorized' instruction)"
    fi
    # And it must tell the subagent to surface to the lead / run no git
    if printf '%s' "$reason" | grep -qi 'Surface this finding to the lead'; then
      pass "Test2: block message directs subagent to surface to the lead"
    else
      fail "Test2: block message does not direct subagent to surface to the lead"
    fi
  fi
  rm -rf "$repo"
}

# ── Test 3: clean repo must NOT block ──
{
  repo="$(setup_repo)"
  out="$(run_hook "$repo" 2>/dev/null || true)"
  if printf '%s' "$out" | jq -e '.decision=="block"' >/dev/null 2>&1; then
    fail "Test3: clean repo falsely blocked"
  else
    pass "Test3: clean repo does NOT block"
  fi
  rm -rf "$repo"
}

if [ "$failures" -gt 0 ]; then
  printf '\n%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf '\nAll subagent-scope-guard tests passed.\n'
