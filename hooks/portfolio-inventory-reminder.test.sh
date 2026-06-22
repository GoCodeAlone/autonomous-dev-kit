#!/usr/bin/env bash
# hooks/portfolio-inventory-reminder.test.sh
# Lifecycle test for the portfolio-inventory-reminder UserPromptSubmit hook.
#
# Mirrors the pr-reminder dedup test in tests/hook-contracts.sh:
#   (1) fresh marker absent → first invocation emits the reminder + creates the
#       marker containing the session_key;
#   (2) second invocation with the same session_key → suppressed (no reminder);
#   (3) simulate pre-compact (run the clear logic) → the marker line for that
#       session is removed → next invocation re-emits.
#
# Run: bash hooks/portfolio-inventory-reminder.test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname -- "$0")/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/portfolio-inventory-reminder"

export LC_ALL=C
export LANG=C
export LC_CTYPE=C

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not found; portfolio-inventory-reminder test requires jq\n'
    exit 0
  fi
}

run_hook() {
  local payload="$1"
  printf '%s' "$payload" | env LC_ALL=C LANG=C LC_CTYPE=C "$HOOK"
}

# build_payload <cwd> <transcript_path>
build_payload() {
  jq -nc --arg cwd "$1" --arg tp "$2" \
    '{prompt:"build a portfolio dashboard feature",cwd:$cwd,transcript_path:$tp}'
}

# simulate_pre_compact_clear <adk_root> <session_key>
# Replicates the exact line-filter-rewrite the pre-compact-snapshot hook applies
# to the portfolio-inventory-seen marker (grep -vxF + atomic tmp-then-mv).
simulate_pre_compact_clear() {
  local adk_root="$1" session_key="$2"
  local marker="${adk_root}/.claude/autodev-state/portfolio-inventory-seen"
  [ -f "$marker" ] || return 0
  local remaining
  remaining="$(grep -vxF "$session_key" "$marker" 2>/dev/null || true)"
  if [ -n "$remaining" ]; then
    printf '%s\n' "$remaining" > "${marker}.tmp" 2>/dev/null \
      && mv "${marker}.tmp" "$marker" \
      || rm -f "${marker}.tmp"
  else
    rm -f "$marker"
  fi
}

test_portfolio_reminder_lifecycle() {
  local tmp transcript session_key payload marker out1 out2 out3 marker_after_first

  tmp="$(mktemp -d)"
  # Don't trap RETURN (portability under set -e in some bash versions); clean up at end.

  transcript="${tmp}/transcripts/sess-portfolio-abc.jsonl"
  mkdir -p "$(dirname "$transcript")"
  : > "$transcript"
  session_key="$(basename "$transcript")"   # sess-portfolio-abc.jsonl
  payload="$(build_payload "$tmp" "$transcript")"
  marker="${tmp}/.claude/autodev-state/portfolio-inventory-seen"

  # (1) Fresh: marker absent → first invocation emits + creates marker with session_key.
  if [ -f "$marker" ]; then
    fail "lifecycle(1): precondition violated — marker already exists at ${marker}"
    rm -rf "$tmp"; return
  fi
  out1="$(run_hook "$payload")"
  if ! printf '%s' "$out1" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit" and (.hookSpecificOutput.additionalContext | type == "string") and (.hookSpecificOutput.additionalContext | length > 0)' >/dev/null 2>&1; then
    fail "lifecycle(1): first invocation must emit valid UserPromptSubmit additionalContext JSON, got: ${out1}"
    rm -rf "$tmp"; return
  fi
  if ! printf '%s' "$out1" | jq -e '.hookSpecificOutput.additionalContext | contains("docs/PORTFOLIO.md") and contains("docs/FOLLOWUPS.md")' >/dev/null 2>&1; then
    fail "lifecycle(1): reminder text must mention docs/PORTFOLIO.md and docs/FOLLOWUPS.md, got: ${out1}"
    rm -rf "$tmp"; return
  fi
  if [ ! -f "$marker" ]; then
    fail "lifecycle(1): marker file must be created after first emit, missing at ${marker}"
    rm -rf "$tmp"; return
  fi
  marker_after_first="$(cat "$marker")"
  if [ "$marker_after_first" != "$session_key" ]; then
    fail "lifecycle(1): marker must contain exactly the session_key, got: [${marker_after_first}] want [${session_key}]"
    rm -rf "$tmp"; return
  fi
  pass "lifecycle(1): fresh marker absent → emits reminder + creates marker with session_key"

  # (2) Second invocation with same session_key → suppressed (no reminder / empty output).
  out2="$(run_hook "$payload")"
  if [ -n "$out2" ]; then
    fail "lifecycle(2): second invocation with same session_key must be suppressed (no output), got: ${out2}"
    rm -rf "$tmp"; return
  fi
  pass "lifecycle(2): second invocation with same session_key → suppressed"

  # (3) Simulate pre-compact clear → marker line removed → next invocation re-emits.
  simulate_pre_compact_clear "$tmp" "$session_key"
  if [ -f "$marker" ]; then
    fail "lifecycle(3): pre-compact clear must remove marker (only our key was present), still exists: $(cat "$marker")"
    rm -rf "$tmp"; return
  fi
  out3="$(run_hook "$payload")"
  if ! printf '%s' "$out3" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit" and (.hookSpecificOutput.additionalContext | length > 0)' >/dev/null 2>&1; then
    fail "lifecycle(3): must re-emit after pre-compact clear, got: ${out3}"
    rm -rf "$tmp"; return
  fi
  pass "lifecycle(3): pre-compact clear removes marker → next invocation re-emits"

  rm -rf "$tmp"
}

test_portfolio_reminder_preserves_other_sessions_on_clear() {
  # When two sessions share the marker, clearing session A must keep session B's line.
  local tmp t_a t_b key_a key_b marker out_a1 out_b1 out_a2
  tmp="$(mktemp -d)"

  t_a="${tmp}/ta.jsonl"; : > "$t_a"; key_a="$(basename "$t_a")"
  t_b="${tmp}/tb.jsonl"; : > "$t_b"; key_b="$(basename "$t_b")"
  marker="${tmp}/.claude/autodev-state/portfolio-inventory-seen"

  out_a1="$(run_hook "$(build_payload "$tmp" "$t_a")")"
  out_b1="$(run_hook "$(build_payload "$tmp" "$t_b")")"
  printf '%s' "$out_a1" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
    || { fail "preserve: session A first emit missing"; rm -rf "$tmp"; return; }
  printf '%s' "$out_b1" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
    || { fail "preserve: session B first emit missing"; rm -rf "$tmp"; return; }

  # Clear session A only.
  simulate_pre_compact_clear "$tmp" "$key_a"
  if ! [ -f "$marker" ]; then
    fail "preserve: clearing A must NOT remove the marker (B still present)"
    rm -rf "$tmp"; return
  fi
  if ! grep -qxF "$key_b" "$marker"; then
    fail "preserve: session B key must survive clearing A; marker=$(cat "$marker")"
    rm -rf "$tmp"; return
  fi
  if grep -qxF "$key_a" "$marker"; then
    fail "preserve: session A key must be removed; marker=$(cat "$marker")"
    rm -rf "$tmp"; return
  fi
  # Session A re-emits after its clear.
  out_a2="$(run_hook "$(build_payload "$tmp" "$t_a")")"
  printf '%s' "$out_a2" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
    || { fail "preserve: session A must re-emit after its clear"; rm -rf "$tmp"; return; }
  pass "preserve: clearing one session keeps the other sessions' keys"

  rm -rf "$tmp"
}

test_portfolio_reminder_no_transcript_emits_every_time() {
  # Degrade: no transcript_path → emit every time (template's documented behavior).
  local tmp out1 out2
  tmp="$(mktemp -d)"
  out1="$(run_hook "$(jq -nc --arg cwd "$tmp" '{prompt:"x",cwd:$cwd}')")"
  out2="$(run_hook "$(jq -nc --arg cwd "$tmp" '{prompt:"x",cwd:$cwd}')")"
  printf '%s' "$out1" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
    || { fail "degrade: first no-transcript call must emit"; rm -rf "$tmp"; return; }
  printf '%s' "$out2" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
    || { fail "degrade: second no-transcript call must still emit (no session_key dedup)"; rm -rf "$tmp"; return; }
  pass "degrade: no transcript_path → emits every time"
  rm -rf "$tmp"
}

require_jq
test_portfolio_reminder_lifecycle
test_portfolio_reminder_preserves_other_sessions_on_clear
test_portfolio_reminder_no_transcript_emits_every_time

if [ "$failures" -ne 0 ]; then
  printf '\n%d portfolio-inventory-reminder test(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll portfolio-inventory-reminder tests passed.\n'
