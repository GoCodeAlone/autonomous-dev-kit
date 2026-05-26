#!/usr/bin/env bash
# tests/hook-contracts.sh — regression tests for hook JSON contracts.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

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
  printf '%s' "$payload" | "hooks/${hook}"
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
test_pretool_pr_review_json
test_posttool_pr_created_json
test_pre_compact_snapshot_json
test_completion_continuation_block
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
