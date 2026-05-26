#!/usr/bin/env bash
# tests/hook-contracts.sh — regression tests for hook JSON contracts.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
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
    printf 'SKIP: jq not found; hook contract tests require jq\n'
    exit 0
  fi
}

run_hook() {
  local hook="$1"
  local payload="$2"
  printf '%s' "$payload" | env LC_ALL=C LANG=C LC_CTYPE=C "hooks/${hook}"
}

run_hook_wrapper() {
  local hook="$1"
  local payload="$2"
  local stdout_file="$3"
  local stderr_file="$4"
  env LC_ALL=C.UTF-8 LANG=C.UTF-8 LC_CTYPE=C.UTF-8 \
    hooks/run-hook.cmd "$hook" >"$stdout_file" 2>"$stderr_file" <<<"$payload"
}

assert_hook_context_json() {
  local name="$1"
  local event="$2"
  local output="$3"

  if ! printf '%s' "$output" | jq -e . >/dev/null 2>&1; then
    fail "${name}: output is not valid JSON: ${output}"
    return
  fi
  if ! printf '%s' "$output" | jq -e --arg event "$event" '
      .hookSpecificOutput.hookEventName == $event and
      (.hookSpecificOutput.additionalContext | type == "string") and
      (.hookSpecificOutput.additionalContext | length > 0) and
      has("additional_context") | not
    ' >/dev/null; then
    fail "${name}: output does not match host-neutral additionalContext schema: ${output}"
    return
  fi
  pass "${name}: emits valid ${event} additionalContext JSON"
}

test_session_start_json() {
  local output
  output="$(run_hook session-start '{"source":"startup","cwd":"'"$REPO_ROOT"'"}')"
  assert_hook_context_json "session-start" "SessionStart" "$output"
}

test_wrapper_suppresses_unavailable_c_utf8_locale_noise() {
  local tmp stdout_file stderr_file stderr_text stdout_text
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  stdout_file="$tmp/stdout.json"
  stderr_file="$tmp/stderr.txt"

  run_hook_wrapper session-start '{"source":"startup","cwd":"'"$REPO_ROOT"'"}' "$stdout_file" "$stderr_file"
  stdout_text="$(cat "$stdout_file")"
  stderr_text="$(cat "$stderr_file")"

  if [ -n "$stderr_text" ]; then
    fail "run-hook.cmd: expected no stderr for unsupported C.UTF-8 locale, got: ${stderr_text}"
    return
  fi
  assert_hook_context_json "run-hook.cmd session-start" "SessionStart" "$stdout_text"
}

test_prompt_strict_json() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN

  local output
  output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead and create a PR","cwd":"'"$tmp"'"}')"
  assert_hook_context_json "prompt-strict-interpretation" "UserPromptSubmit" "$output"
}

test_prompt_strict_no_output_without_trigger() {
  local output
  output="$(run_hook prompt-strict-interpretation '{"prompt":"please inspect the file","cwd":"'"$REPO_ROOT"'"}')"
  if [ -n "$output" ]; then
    fail "prompt-strict-interpretation: expected no output without trigger, got: ${output}"
    return
  fi
  pass "prompt-strict-interpretation: no output without trigger"
}

test_prompt_strict_ignores_ambiguous_workspace_locks_when_session_has_no_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  for name in one two; do
    cat >"$tmp/docs/plans/${name}.md" <<PLAN
# ${name} Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | ${name} | Task 1 | feat/${name} |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: ${name}
PLAN
    bash hooks/scope-lock-apply "$tmp/docs/plans/${name}.md" >/dev/null
  done

  output="$(run_hook prompt-strict-interpretation '{"prompt":"continue autonomously","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "prompt-strict-interpretation: expected ambiguous workspace locks to be ignored for session, got: ${output}"
    return
  fi
  pass "prompt-strict-interpretation: ignores ambiguous workspace locks when session has no lock"
}

test_prompt_strict_falls_back_to_single_workspace_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/active.md" <<'PLAN'
# Active Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Active | Task 1 | feat/active |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Active
PLAN
  bash hooks/scope-lock-apply "$tmp/docs/plans/active.md" >/dev/null

  output="$(run_hook prompt-strict-interpretation '{"prompt":"continue autonomously","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if ! printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("active.md")' >/dev/null; then
    fail "prompt-strict-interpretation: expected single workspace lock fallback, got: ${output}"
    return
  fi
  pass "prompt-strict-interpretation: falls back to single workspace lock"
}

test_prompt_strict_uses_session_locked_plan_only() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
  for name in aa-unrelated zz-active; do
    cat >"$tmp/docs/plans/${name}.md" <<PLAN
# ${name} Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | ${name} | Task 1 | feat/${name} |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: ${name}
PLAN
    bash hooks/scope-lock-apply "$tmp/docs/plans/${name}.md" >/dev/null
  done
  jq -nc --arg session "session.jsonl" --arg pl "docs/plans/zz-active.md" \
    '{ev:"session-lock",session:$session,pl:$pl}' \
    > "$tmp/.claude/autodev-state/session-locks.jsonl"

  output="$(run_hook prompt-strict-interpretation '{"prompt":"continue autonomously","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if ! printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("zz-active.md") and (contains("aa-unrelated.md") | not)' >/dev/null; then
    fail "prompt-strict-interpretation: expected only session locked plan reminder, got: ${output}"
    return
  fi
  pass "prompt-strict-interpretation: uses only session locked plan"
}

test_pretool_pr_review_json() {
  local output
  output="$(run_hook pretool-pr-review-reminder '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test --body test"},"cwd":"'"$REPO_ROOT"'"}')"
  assert_hook_context_json "pretool-pr-review-reminder" "PreToolUse" "$output"
}

test_posttool_pr_created_json() {
  local output
  output="$(run_hook posttool-pr-created '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test --body test"},"tool_response":"https://github.com/owner/repo/pull/123","cwd":"'"$REPO_ROOT"'"}')"
  assert_hook_context_json "posttool-pr-created" "PostToolUse" "$output"
}

test_pre_compact_snapshot_json() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  bash hooks/scope-lock-apply "$tmp/docs/plans/example.md" >/dev/null

  local output
  output="$(run_hook pre-compact-snapshot '{"cwd":"'"$tmp"'"}')"
  assert_hook_context_json "pre-compact-snapshot" "PreCompact" "$output"

  local state_file="$tmp/.claude/autodev-state/in-progress.jsonl"
  if ! jq -e 'select(.ev == "lock" and .pl == "example.md" and (.h | type == "string"))' "$state_file" >/dev/null; then
    fail "pre-compact-snapshot: expected compact lock state row in ${state_file}"
    return
  fi
  pass "pre-compact-snapshot: writes compact lock state row"
}

test_wrapper_suppresses_pre_compact_locale_noise() {
  local tmp stdout_file stderr_file stderr_text stdout_text
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  stdout_file="$tmp/stdout.json"
  stderr_file="$tmp/stderr.txt"
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  bash hooks/scope-lock-apply "$tmp/docs/plans/example.md" >/dev/null

  run_hook_wrapper pre-compact-snapshot '{"cwd":"'"$tmp"'"}' "$stdout_file" "$stderr_file"
  stdout_text="$(cat "$stdout_file")"
  stderr_text="$(cat "$stderr_file")"

  if [ -n "$stderr_text" ]; then
    fail "run-hook.cmd pre-compact-snapshot: expected no stderr for unsupported C.UTF-8 locale, got: ${stderr_text}"
    return
  fi
  assert_hook_context_json "run-hook.cmd pre-compact-snapshot" "PreCompact" "$stdout_text"
}

test_pre_compact_snapshot_only_locked_plans() {
  local tmp output state_file
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  for name in locked draft; do
    status="Draft"
    [ "$name" = "locked" ] && status="Locked 2026-05-25T00:00:00Z"
    cat >"$tmp/docs/plans/${name}.md" <<PLAN
# ${name} Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | ${name} | Task 1 | feat/${name} |

**Status:** ${status}

### Task 1: ${name}
PLAN
  done
  bash hooks/scope-lock-apply "$tmp/docs/plans/locked.md" >/dev/null

  output="$(run_hook pre-compact-snapshot '{"cwd":"'"$tmp"'"}')"
  if ! printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("locked.md") and (contains("draft.md") | not)' >/dev/null; then
    fail "pre-compact-snapshot: expected only locked plans in snapshot, got: ${output}"
    return
  fi

  state_file="$tmp/.claude/autodev-state/in-progress.jsonl"
  if jq -e 'select(.pl == "draft.md")' "$state_file" >/dev/null; then
    fail "pre-compact-snapshot: expected no draft plan row in ${state_file}"
    return
  fi
  pass "pre-compact-snapshot: snapshots only locked plans"
}

test_scope_lock_complete_marks_complete_and_prunes_state() {
  local tmp transcript state_file compact_output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/tests" "$tmp/.claude/autodev-state" "$tmp/.autodev/state"
  cp tests/plan-scope-check.sh "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  bash hooks/scope-lock-apply "$tmp/docs/plans/example.md" >/dev/null
  jq -nc --arg session "session.jsonl" --arg pl "docs/plans/example.md" \
    '{ev:"session-lock",session:$session,pl:$pl}' \
    > "$tmp/.claude/autodev-state/session-locks.jsonl"
  jq -nc --arg session "other.jsonl" --arg pl "./docs/plans/example.md" \
    '{ev:"session-lock",session:$session,pl:$pl}' \
    >> "$tmp/.claude/autodev-state/session-locks.jsonl"
  jq -nc '{ev:"lock",pl:"example.md",st:"Locked 2026-05-25T00:00:00Z",h:"abc"}' \
    > "$tmp/.claude/autodev-state/in-progress.jsonl"

  hooks/scope-lock-complete "$tmp/docs/plans/example.md" --evidence "tests pass" >/dev/null

  if ! grep -q '\*\*Status:\*\* Complete ' "$tmp/docs/plans/example.md"; then
    fail "scope-lock-complete: expected plan status to be Complete"
    return
  fi
  if [ -e "$tmp/docs/plans/example.md.scope-lock" ]; then
    fail "scope-lock-complete: expected scope-lock file to be removed"
    return
  fi
  state_file="$tmp/.claude/autodev-state/session-locks.jsonl"
  if [ -s "$state_file" ] && jq -e 'select(.pl == "docs/plans/example.md")' "$state_file" >/dev/null; then
    fail "scope-lock-complete: expected session lock trace to be pruned"
    return
  fi
  if [ -s "$state_file" ] && jq -e 'select(.pl == "./docs/plans/example.md")' "$state_file" >/dev/null; then
    fail "scope-lock-complete: expected equivalent relative session lock trace to be pruned"
    return
  fi
  state_file="$tmp/.claude/autodev-state/in-progress.jsonl"
  if [ -s "$state_file" ] && jq -e 'select(.pl == "example.md")' "$state_file" >/dev/null; then
    fail "scope-lock-complete: expected compact lock snapshot to be pruned"
    return
  fi
  state_file="$tmp/.autodev/state/phase-progress.jsonl"
  if ! jq -e 'select(.ev == "plan" and .pl == "example.md" and .st == "complete" and .e == "tests pass")' "$state_file" >/dev/null; then
    fail "scope-lock-complete: expected phase-progress completion evidence row"
    return
  fi
  compact_output="$(run_hook pre-compact-snapshot '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$compact_output" ]; then
    fail "scope-lock-complete: expected completed plan to produce no pre-compact lock snapshot, got: ${compact_output}"
    return
  fi
  pass "scope-lock-complete: marks complete and prunes lock traces"
}

test_scope_lock_complete_requires_lock_file() {
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cp tests/plan-scope-check.sh "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN

  set +e
  output="$(hooks/scope-lock-complete "$tmp/docs/plans/example.md" --evidence "tests pass" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ] || ! printf '%s' "$output" | grep -q 'lock file missing'; then
    fail "scope-lock-complete: expected missing lock file failure, got status ${status}: ${output}"
    return
  fi
  pass "scope-lock-complete: requires lock file"
}

test_scope_lock_complete_rejects_bad_lock_without_project_checker() {
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  printf 'bogus\n' > "$tmp/docs/plans/example.md.scope-lock"

  set +e
  output="$(cd "$tmp" && "$REPO_ROOT/hooks/scope-lock-complete" docs/plans/example.md --evidence "tests pass" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ] || ! printf '%s' "$output" | grep -q 'manifest hash mismatch'; then
    fail "scope-lock-complete: expected bad lock failure without project checker, got status ${status}: ${output}"
    return
  fi
  if ! grep -q '\*\*Status:\*\* Locked' "$tmp/docs/plans/example.md" || [ ! -f "$tmp/docs/plans/example.md.scope-lock" ]; then
    fail "scope-lock-complete: bad lock failure mutated plan or removed lock"
    return
  fi
  pass "scope-lock-complete: rejects bad lock without project checker"
}

test_scope_lock_complete_preflights_progress_write() {
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  bash hooks/scope-lock-apply "$tmp/docs/plans/example.md" >/dev/null
  : > "$tmp/.autodev"

  set +e
  output="$(cd "$tmp" && "$REPO_ROOT/hooks/scope-lock-complete" docs/plans/example.md --evidence "tests pass" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    fail "scope-lock-complete: expected progress write preflight failure"
    return
  fi
  if ! grep -q '\*\*Status:\*\* Locked' "$tmp/docs/plans/example.md" || [ ! -f "$tmp/docs/plans/example.md.scope-lock" ]; then
    fail "scope-lock-complete: progress write failure mutated plan or removed lock: ${output}"
    return
  fi
  pass "scope-lock-complete: preflights progress write before mutation"
}

test_scope_lock_complete_rejects_progress_directory() {
  local tmp output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/.autodev/state/phase-progress.jsonl"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  bash hooks/scope-lock-apply "$tmp/docs/plans/example.md" >/dev/null

  set +e
  output="$(cd "$tmp" && "$REPO_ROOT/hooks/scope-lock-complete" docs/plans/example.md --evidence "tests pass" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ] || ! printf '%s' "$output" | grep -q 'expected regular file'; then
    fail "scope-lock-complete: expected progress directory failure, got status ${status}: ${output}"
    return
  fi
  if ! grep -q '\*\*Status:\*\* Locked' "$tmp/docs/plans/example.md" || [ ! -f "$tmp/docs/plans/example.md.scope-lock" ]; then
    fail "scope-lock-complete: progress directory failure mutated plan or removed lock"
    return
  fi
  pass "scope-lock-complete: rejects progress directory before mutation"
}

test_completion_continuation_block() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  cp tests/plan-scope-check.sh "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  bash hooks/scope-lock-apply "$tmp/docs/plans/example.md" >/dev/null

  local output
  output="$(run_hook completion-claim-guard '{"cwd":"'"$tmp"'","stop_hook_active":false,"last_assistant_message":"Task 1 complete."}')"
  if ! printf '%s' "$output" | jq -e '
      .decision == "block" and
      (.reason | contains("phase/task completion")) and
      (.reason | contains("phase-progress.jsonl"))
    ' >/dev/null; then
    fail "completion-claim-guard: expected phase-continuation block JSON, got: ${output}"
    return
  fi
  pass "completion-claim-guard: blocks phase completion and requests progress log"
}

test_completion_continuation_block_keeps_heading_separator_when_flattened() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  cp tests/plan-scope-check.sh "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  bash hooks/scope-lock-apply "$tmp/docs/plans/example.md" >/dev/null

  local output flat_reason
  output="$(run_hook completion-claim-guard '{"cwd":"'"$tmp"'","stop_hook_active":false,"last_assistant_message":"Task 1 complete."}')"
  flat_reason="$(printf '%s' "$output" | jq -r '.reason' | tr -d '\r\n')"

  if ! printf '%s' "$flat_reason" | grep -q 'example.md Before stopping'; then
    fail "completion-claim-guard: expected flattened checkpoint to keep separator before 'Before stopping', got: ${flat_reason}"
    return
  fi
  pass "completion-claim-guard: flattened checkpoint keeps heading separator"
}

test_pretool_records_session_lock_for_scope_lock_apply() {
  local tmp transcript output state_file
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"

  output="$(run_hook pre-tool-scope-guard '{"tool_name":"Bash","tool_input":{"command":"bash hooks/scope-lock-apply docs/plans/active.md"},"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "pre-tool-scope-guard: expected scope-lock recording to pass silently, got: ${output}"
    return
  fi

  state_file="$tmp/.claude/autodev-state/session-locks.jsonl"
  if ! jq -e 'select(.ev == "session-lock" and .session == "session.jsonl" and .pl == "docs/plans/active.md")' "$state_file" >/dev/null; then
    fail "pre-tool-scope-guard: expected session lock row in ${state_file}"
    return
  fi
  pass "pre-tool-scope-guard: records scope-lock plan for current session"
}

test_completion_ignores_ambiguous_workspace_locks_when_session_has_no_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  for name in one two; do
    cat >"$tmp/docs/plans/${name}.md" <<PLAN
# ${name} Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | ${name} | Task 1 | feat/${name} |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: ${name}
PLAN
  done
  cp tests/plan-scope-check.sh "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  bash hooks/scope-lock-apply "$tmp/docs/plans/one.md" >/dev/null
  bash hooks/scope-lock-apply "$tmp/docs/plans/two.md" >/dev/null

  output="$(run_hook completion-claim-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false,"last_assistant_message":"Task complete."}')"
  if [ -n "$output" ]; then
    fail "completion-claim-guard: expected ambiguous workspace locks to be ignored for session, got: ${output}"
    return
  fi
  pass "completion-claim-guard: ignores ambiguous workspace locks when session has no lock"
}

test_completion_falls_back_to_single_workspace_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cat >"$tmp/docs/plans/active.md" <<'PLAN'
# Active Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Active | Task 1 | feat/active |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Active
PLAN
  cp tests/plan-scope-check.sh "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  bash hooks/scope-lock-apply "$tmp/docs/plans/active.md" >/dev/null

  output="$(run_hook completion-claim-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false,"last_assistant_message":"Task complete."}')"
  if ! printf '%s' "$output" | grep -q 'Completion checkpoint'; then
    fail "completion-claim-guard: expected single workspace lock fallback to block completion, got: ${output}"
    return
  fi
  pass "completion-claim-guard: falls back to single workspace lock"
}

test_completion_uses_session_locked_plan_only() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  for name in active unrelated; do
    cat >"$tmp/docs/plans/${name}.md" <<PLAN
# ${name} Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | ${name} | Task 1 | feat/${name} |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: ${name}
PLAN
  done
  cp tests/plan-scope-check.sh "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  bash hooks/scope-lock-apply "$tmp/docs/plans/active.md" >/dev/null
  bash hooks/scope-lock-apply "$tmp/docs/plans/unrelated.md" >/dev/null

  run_hook pre-tool-scope-guard '{"tool_name":"Bash","tool_input":{"command":"bash hooks/scope-lock-apply docs/plans/active.md"},"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}' >/dev/null
  output="$(run_hook completion-claim-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false,"last_assistant_message":"Task complete."}')"

  if ! printf '%s' "$output" | jq -e '.decision == "block" and (.reason | contains("active.md")) and (.reason | contains("unrelated.md") | not)' >/dev/null; then
    fail "completion-claim-guard: expected only the session locked plan to block, got: ${output}"
    return
  fi
  pass "completion-claim-guard: uses only session locked plans"
}

test_completion_allows_hard_blocker() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  cp tests/plan-scope-check.sh "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  bash hooks/scope-lock-apply "$tmp/docs/plans/example.md" >/dev/null

  local output
  output="$(run_hook completion-claim-guard '{"cwd":"'"$tmp"'","stop_hook_active":false,"last_assistant_message":"Blocked: need human approval before deploy to production."}')"
  if [ -n "$output" ]; then
    fail "completion-claim-guard: expected no output for hard blocker, got: ${output}"
    return
  fi
  pass "completion-claim-guard: allows hard blocker stop"
}

test_pretool_allows_locked_plan_text_edit() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  local output
  output="$(run_hook pre-tool-scope-guard '{"tool_name":"Edit","tool_input":{"file_path":"'"$tmp"'/docs/plans/example.md"},"cwd":"'"$tmp"'"}')"
  if [ -n "$output" ]; then
    fail "pre-tool-scope-guard: expected locked plan text edit to pass, got: ${output}"
    return
  fi
  pass "pre-tool-scope-guard: allows locked plan/design text edits"
}

test_subagent_allows_non_manifest_plan_backport() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cp tests/plan-scope-check.sh "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  cat >"$tmp/docs/plans/example.md" <<'PLAN'
# Example Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Example | Task 1 | feat/example |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Example
PLAN
  bash hooks/scope-lock-apply "$tmp/docs/plans/example.md" >/dev/null
  git -C "$tmp" init -q
  git -C "$tmp" config user.email test@example.com
  git -C "$tmp" config user.name "Hook Test"
  git -C "$tmp" add docs tests
  git -C "$tmp" commit -q -m initial
  printf '\n### Backport 2026-05-25: note\n\nCause: test\nChange: no manifest change\n' >>"$tmp/docs/plans/example.md"

  local output
  output="$(run_hook subagent-scope-guard '{"cwd":"'"$tmp"'","stop_hook_active":false}')"
  if [ -n "$output" ]; then
    fail "subagent-scope-guard: expected non-manifest plan backport to pass, got: ${output}"
    return
  fi
  pass "subagent-scope-guard: allows non-manifest locked plan backports"
}

test_record_activity_compact_state() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  run_hook record-activity '{"tool_name":"Skill","tool_input":{"skill":"autodev:brainstorming","args":"design compact state"},"cwd":"'"$tmp"'"}' >/dev/null
  run_hook record-activity '{"tool_name":"Agent","tool_input":{"subagent_type":"reviewer","description":"check implementation","run_in_background":true},"cwd":"'"$tmp"'"}' >/dev/null
  run_hook record-activity '{"tool_name":"TaskUpdate","tool_input":{"task_id":"T1","title":"phase complete","subagent_type":"builder"},"cwd":"'"$tmp"'"}' >/dev/null

  local state_file="$tmp/.claude/autodev-state/in-progress.jsonl"
  if ! jq -s -e '
      . as $rows |
      ($rows | any(.ev == "skill" and .sk == "autodev:brainstorming" and (has("tool") | not) and (has("detail") | not))) and
      ($rows | any(.ev == "agent" and .ag == "reviewer" and .bg == true and (has("tool") | not) and (has("detail") | not))) and
      ($rows | any(.ev == "task" and .tt == "TaskUpdate" and .ag == "builder" and .id == "T1" and (has("tool") | not) and (has("detail") | not)))
    ' "$state_file" >/dev/null; then
    fail "record-activity: expected compact skill/agent/task JSONL rows"
    return
  fi
  pass "record-activity: writes compact skill/agent/task state rows"
}

test_skill_activation_audit_reads_compact_state() {
  local tmp state_file output status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  state_file="$tmp/in-progress.jsonl"
  cat >"$state_file" <<'JSONL'
{"ts":"2026-05-25T00:00:00Z","ev":"skill","sk":"autodev:brainstorming"}
{"ts":"2026-05-25T00:00:01Z","ev":"agent","ag":"reviewer","bg":true}
JSONL

  set +e
  output="$(./tests/skill-activation-audit.sh "$state_file" 2>&1)"
  status=$?
  set -e

  if [ "$status" -ne 2 ]; then
    fail "skill-activation-audit: expected pipeline-gap exit 2 for partial compact pipeline, got ${status}: ${output}"
    return
  fi
  if ! printf '%s' "$output" | grep -q 'brainstorming'; then
    fail "skill-activation-audit: compact skill row not reported: ${output}"
    return
  fi
  if ! printf '%s' "$output" | grep -q 'reviewer'; then
    fail "skill-activation-audit: compact agent row not reported: ${output}"
    return
  fi
  pass "skill-activation-audit: reads compact state rows"
}

require_jq
test_session_start_json
test_wrapper_suppresses_unavailable_c_utf8_locale_noise
test_prompt_strict_json
test_prompt_strict_no_output_without_trigger
test_prompt_strict_ignores_ambiguous_workspace_locks_when_session_has_no_lock
test_prompt_strict_falls_back_to_single_workspace_lock
test_prompt_strict_uses_session_locked_plan_only
test_pretool_pr_review_json
test_posttool_pr_created_json
test_pre_compact_snapshot_json
test_wrapper_suppresses_pre_compact_locale_noise
test_pre_compact_snapshot_only_locked_plans
test_scope_lock_complete_marks_complete_and_prunes_state
test_scope_lock_complete_requires_lock_file
test_scope_lock_complete_rejects_bad_lock_without_project_checker
test_scope_lock_complete_preflights_progress_write
test_scope_lock_complete_rejects_progress_directory
test_completion_continuation_block
test_completion_continuation_block_keeps_heading_separator_when_flattened
test_pretool_records_session_lock_for_scope_lock_apply
test_completion_ignores_ambiguous_workspace_locks_when_session_has_no_lock
test_completion_falls_back_to_single_workspace_lock
test_completion_uses_session_locked_plan_only
test_completion_allows_hard_blocker
test_pretool_allows_locked_plan_text_edit
test_subagent_allows_non_manifest_plan_backport
test_record_activity_compact_state
test_skill_activation_audit_reads_compact_state

if [ "$failures" -ne 0 ]; then
  printf '\n%d hook contract test(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll hook contract tests passed.\n'
