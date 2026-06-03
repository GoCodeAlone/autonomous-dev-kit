#!/usr/bin/env bash
# tests/adk-path-canonicalization.sh — proves the canonical ADK state-path resolver
# and that all 12 state-writing hooks adopt it. (#70 residual; v6.5.0)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
LIB="$ROOT/hooks/lib-autodev-paths.sh"
failures=0
pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; failures=$((failures+1)); }

# --- Group A: resolver behavior against a REAL temp git + linked worktree ---
if [ -f "$LIB" ]; then
  . "$LIB"
  tmp="$(mktemp -d)"
  # portable git init (avoid `git init <dir>` which needs git>=2.28): mkdir + `git -C`
  mkdir -p "$tmp/main"
  ( cd "$tmp/main" && git init -q && git -c user.email=a@b -c user.name=x commit -q --allow-empty -m init \
      && git worktree add -q ../wt >/dev/null 2>&1 )
  main_root="$(cd "$tmp/main" && pwd -P)"   # pwd -P to match the resolver's physical-path output (C-2)
  # (a) from main checkout -> main root
  [ "$(autodev_repo_root "$tmp/main")" = "$main_root" ] \
    && pass "resolver: main checkout -> main root" || fail "resolver main: got $(autodev_repo_root "$tmp/main")"
  # (b) from linked worktree -> SAME main root (the load-bearing claim)
  [ "$(autodev_repo_root "$tmp/wt")" = "$main_root" ] \
    && pass "resolver: linked worktree -> main root (shared)" || fail "resolver worktree: got $(autodev_repo_root "$tmp/wt")"
  # (c) non-git dir -> cwd fallback (C-1: NOT '/')
  ngt="$(mktemp -d)"; [ "$(autodev_repo_root "$ngt")" = "$ngt" ] \
    && pass "resolver: non-git dir -> cwd fallback" || fail "resolver non-git: got $(autodev_repo_root "$ngt") (want $ngt)"
  # (d) env override wins
  [ "$(AUTODEV_STATE_ROOT=/tmp/override autodev_repo_root "$tmp/main")" = "/tmp/override" ] \
    && pass "resolver: AUTODEV_STATE_ROOT override" || fail "resolver override broken"
  rm -rf "$tmp" "$ngt"
else
  fail "lib missing: $LIB"
fi

# --- Group B: all 11 state-WRITING hooks source the lib + guard the function ---
# (scope-lock-claim is EXCLUDED — its only autodev-state mention is a comment, no runtime state I/O.)
HOOKS="completion-claim-guard pre-compact-snapshot pre-tool-scope-guard pretool-demo-fidelity-guard pretool-pr-review-reminder prompt-strict-interpretation record-activity scope-lock-abandon scope-lock-complete session-start subagent-scope-guard"
for h in $HOOKS; do
  f="$ROOT/hooks/$h"
  if grep -q "lib-autodev-paths.sh" "$f" && grep -q "declare -f autodev_repo_root" "$f"; then
    pass "hook wired: $h"
  else
    fail "hook NOT wired (no lib source + declare -f guard): $h"
  fi
done

# --- Group C: lib-missing degradation — BEHAVIORAL proof (m-1): copy record-activity to a
# sandbox WITHOUT the sibling lib + a NON-git cwd, and assert it (a) doesn't crash AND
# (b) actually writes to the cwd-fallback location ($cwd/.claude/autodev-state/in-progress.jsonl),
# proving the `declare -f` identity-on-cwd fallback fired (not a vacuous exit-0).
cwdfb="$(mktemp -d)"   # non-git dir => resolver (if it existed) AND the fallback both yield $cwdfb
sandbox="$(mktemp -d)"; cp "$ROOT/hooks/record-activity" "$sandbox/record-activity"  # NO lib sibling
payload='{"tool_name":"Skill","tool_input":{"skill":"autodev:degrade-probe"},"cwd":"'"$cwdfb"'"}'
out_rc=0; printf '%s' "$payload" | bash "$sandbox/record-activity" >/dev/null 2>&1 || out_rc=$?
if [ "$out_rc" != "127" ] && [ "$out_rc" != "2" ] \
   && grep -q "degrade-probe" "$cwdfb/.claude/autodev-state/in-progress.jsonl" 2>/dev/null; then
  pass "degradation: record-activity (lib hidden) wrote to cwd fallback, no crash (rc=$out_rc)"
else
  fail "degradation: record-activity did not degrade to cwd fallback (rc=$out_rc; file=$cwdfb/.claude/autodev-state/in-progress.jsonl)"
fi
rm -rf "$cwdfb" "$sandbox"

echo ""; echo "Results: $failures failure(s)"; [ "$failures" -eq 0 ]
