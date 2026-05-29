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

# emit_locked_fixture <plan-abs-path> <name>
#   Writes a minimal-but-valid locked plan to <plan-abs-path>, then runs
#   hooks/scope-lock-apply against it from the repo root. The plan body is
#   produced with printf (not a heredoc) so this file does not itself contain
#   column-0 occurrences of "## Scope Manifest" or "**Status:** Locked" that
#   would trip the project's own plan-scope-check.sh / nag hooks when run
#   against this repo.
emit_locked_fixture() {
  local path="$1" name="$2"
  printf '# %s Plan\n\n%s\n\n**PR Count:** 1\n**Tasks:** 1\n**Out of scope:**\n- (none)\n\n**PR Grouping:**\n\n| PR # | Title | Tasks | Branch |\n|------|-------|-------|--------|\n| 1 | %s | Task 1 | feat/%s |\n\n%s\n\n### Task 1: %s\n' \
    "$name" "## Scope Manifest" "$name" "$name" "**Status:** Locked 2026-05-26T00:00:00Z" "$name" > "$path"
  bash "$REPO_ROOT/hooks/scope-lock-apply" "$path" >/dev/null
}

# emit_draft_fixture <plan-abs-path> <name>
#   Same shape but Status is Draft; the body literally quotes the locked status
#   string in prose so we can regression-test the anchored-grep fix.
emit_draft_fixture() {
  local path="$1" name="$2"
  printf '# %s Plan\n\n%s\n\n**PR Count:** 1\n**Tasks:** 1\n**Out of scope:**\n- (none)\n\n**PR Grouping:**\n\n| PR # | Title | Tasks | Branch |\n|------|-------|-------|--------|\n| 1 | %s | Task 1 | feat/%s |\n\n**Status:** Draft\n\nProse mention: %s 2026-05-26T00:00:00Z\n\n### Task 1: %s\n' \
    "$name" "## Scope Manifest" "$name" "$name" "**Status:** Locked" "$name"  > "$path"
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

test_session_start_time_dedup_suppresses_rapid_refires() {
  # Regression for v6.1.5: Codex was observed firing SessionStart 9+ times
  # in rapid succession near session limits. Session-id-based dedup misses
  # this when session_id rotates or source is a value we don't anticipate.
  # Time-based dedup (default 5s window) must catch ALL rapid re-fires
  # regardless of payload shape -- different session_id, different source.
  local tmp out1 out2 out3 out4
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  # Fire 1: fresh state, emits.
  out1="$(run_hook session-start '{"source":"startup","cwd":"'"$tmp"'","session_id":"sA"}')"
  if [ -z "$out1" ]; then
    fail "session-start: first fire must emit, got empty"
    return
  fi
  # Fire 2: same session+source within window -> suppressed by session-id dedup OR time dedup.
  out2="$(run_hook session-start '{"source":"startup","cwd":"'"$tmp"'","session_id":"sA"}')"
  if [ -n "$out2" ]; then
    fail "session-start: same-session re-fire within window must be suppressed, got: ${out2}"
    return
  fi
  # Fire 3: rotated session_id, same window -> session-id dedup wouldn't catch this;
  # time dedup must.
  out3="$(run_hook session-start '{"source":"startup","cwd":"'"$tmp"'","session_id":"sB"}')"
  if [ -n "$out3" ]; then
    fail "session-start: rotated-session_id re-fire within window must be suppressed (time dedup), got: ${out3}"
    return
  fi
  # Fire 4: different source (compact, normally NOT deduped), same window.
  # Time dedup must still suppress to prevent the 9-in-rapid-succession bug.
  out4="$(run_hook session-start '{"source":"compact","cwd":"'"$tmp"'","session_id":"sC"}')"
  if [ -n "$out4" ]; then
    fail "session-start: compact re-fire within window must be suppressed (time dedup), got: ${out4}"
    return
  fi
  pass "session-start: time-based dedup suppresses rapid re-fires across session_id/source rotations"
}

test_session_start_json() {
  # Use isolated tmpdir cwd so the hook's per-cwd state dir
  # (.claude/autodev-state) doesn't leak across tests -- the time-based
  # dedup added in v6.1.5 would otherwise suppress emissions in tests
  # that share the same cwd within the 5-second window.
  local tmp output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  output="$(run_hook session-start '{"source":"startup","cwd":"'"$tmp"'"}')"
  assert_hook_context_json "session-start" "SessionStart" "$output"
}

test_pre_tool_scope_guard_does_not_block_force_push_inside_quoted_string() {
  # Destructive-command regexes must use the quote-stripped form of the
  # tool_input.command so that a documentation example inside a quoted
  # heredoc body doesn't trigger a false-positive force-push block.
  # Regression for the session-time block of PR #47 creation: the PR body
  # quoted `git push --force origin main` verbatim and the hook matched it.
  local tmp stdout_file stderr_file status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  stdout_file="$tmp/out"
  stderr_file="$tmp/err"
  payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title hi --body \"Example to avoid: git push --force origin main\""},"cwd":"'"$tmp"'"}'
  set +e
  printf '%s' "$payload" | hooks/pre-tool-scope-guard >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  if [ "$status" != "0" ]; then
    fail "pre-tool-scope-guard: must not block force-push mention inside quoted string, exit ${status} stdout: $(cat "$stdout_file") stderr: $(cat "$stderr_file")"
    return
  fi
  if grep -q '"decision":"block"' "$stdout_file"; then
    fail "pre-tool-scope-guard: blocked force-push mention inside quoted string (false positive). stdout: $(cat "$stdout_file")"
    return
  fi
  pass "pre-tool-scope-guard: does not block force-push mentions inside quoted strings"
}

test_pre_tool_scope_guard_block_exits_zero_with_stderr_reason() {
  # When pre-tool-scope-guard blocks a Bash command, it must:
  #   (1) exit 0  -- both Claude Code and Codex ignore stdout JSON on exit 2
  #   (2) emit {"decision":"block","reason":"..."} on stdout (Claude Code path)
  #   (3) mirror the reason on stderr (Codex path / any host that reads stderr)
  # Regression for Codex error: "PreToolUse hook exited with code 2 but did
  # not write a blocking reason to stderr."
  local tmp stdout_file stderr_file status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  stdout_file="$tmp/out"
  stderr_file="$tmp/err"
  # force-push trigger: always blocked, no setup required
  set +e
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"},"cwd":"'"$tmp"'"}' \
    | hooks/pre-tool-scope-guard >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  if [ "$status" != "0" ]; then
    fail "pre-tool-scope-guard: block must exit 0, got ${status}. stderr: $(cat "$stderr_file")"
    return
  fi
  if ! grep -q '"decision":"block"' "$stdout_file"; then
    fail "pre-tool-scope-guard: block must emit JSON on stdout, got: $(cat "$stdout_file")"
    return
  fi
  if ! grep -qi 'force push' "$stderr_file"; then
    fail "pre-tool-scope-guard: block must mirror reason to stderr, got: $(cat "$stderr_file")"
    return
  fi
  pass "pre-tool-scope-guard: block emits exit 0 + stdout JSON + stderr text (Codex compat)"
}

test_subagent_scope_guard_block_exits_zero_with_stderr_reason() {
  # Same contract for the SubagentStop hook.
  local tmp transcript stdout_file stderr_file status
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state" "$tmp/tests"
  cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  emit_locked_fixture "$tmp/docs/plans/active.md" "active"
  jq -nc --arg s "session.jsonl" --arg pl "docs/plans/active.md" \
    '{ev:"session-lock",session:$s,pl:$pl}' \
    > "$tmp/.claude/autodev-state/session-locks.jsonl"
  # Force drift so verify-lock fails and block() fires.
  awk '/^\*\*Tasks:\*\* 1/ {print; print "**Drift:** yes"; next} {print}' \
    "$tmp/docs/plans/active.md" > "$tmp/docs/plans/active.md.tmp" \
    && mv "$tmp/docs/plans/active.md.tmp" "$tmp/docs/plans/active.md"
  stdout_file="$tmp/out"
  stderr_file="$tmp/err"
  set +e
  printf '%s' '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false}' \
    | hooks/subagent-scope-guard >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  if [ "$status" != "0" ]; then
    fail "subagent-scope-guard: block must exit 0, got ${status}. stderr: $(cat "$stderr_file")"
    return
  fi
  if ! grep -q '"decision":"block"' "$stdout_file"; then
    fail "subagent-scope-guard: block must emit JSON on stdout, got: $(cat "$stdout_file")"
    return
  fi
  if ! grep -qi 'manifest' "$stderr_file"; then
    fail "subagent-scope-guard: block must mirror reason to stderr, got: $(cat "$stderr_file")"
    return
  fi
  pass "subagent-scope-guard: block emits exit 0 + stdout JSON + stderr text (Codex compat)"
}

test_wrapper_suppresses_unavailable_c_utf8_locale_noise() {
  local tmp stdout_file stderr_file stderr_text stdout_text cwd_dir
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  stdout_file="$tmp/stdout.json"
  stderr_file="$tmp/stderr.txt"
  # Use isolated cwd so v6.1.5's time-based session-start dedup doesn't
  # suppress this emission when other tests just ran in REPO_ROOT.
  cwd_dir="$tmp/cwd"
  mkdir -p "$cwd_dir"

  run_hook_wrapper session-start '{"source":"startup","cwd":"'"$cwd_dir"'"}' "$stdout_file" "$stderr_file"
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

test_pretool_ignores_prose_mention_of_locked_status() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state" "$tmp/tests"
  cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  emit_draft_fixture "$tmp/docs/plans/draft.md" "draft"
  output="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/x"},"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}' \
    | run_hook pre-tool-scope-guard 2>&1 || true)"
  if printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "pre-tool-scope-guard: prose mention of Locked status falsely matched, output: ${output}"
    return
  fi
  pass "pre-tool-scope-guard: anchored grep ignores prose mention of Locked status"
}

test_prompt_strict_ignores_prose_mention_of_locked_status() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  emit_draft_fixture "$tmp/docs/plans/draft.md" "draft"
  output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead and create a PR","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "prompt-strict-interpretation: prose mention of Locked status triggered nag, output: ${output}"
    return
  fi
  pass "prompt-strict-interpretation: anchored grep ignores prose mention of Locked status"
}

test_pre_compact_ignores_prose_mention_of_locked_status() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  emit_draft_fixture "$tmp/docs/plans/draft.md" "draft"
  output="$(run_hook pre-compact-snapshot '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "pre-compact-snapshot: prose mention of Locked status triggered snapshot, output: ${output}"
    return
  fi
  pass "pre-compact-snapshot: anchored grep ignores prose mention of Locked status"
}

test_completion_ignores_prose_mention_of_locked_status() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  emit_draft_fixture "$tmp/docs/plans/draft.md" "draft"
  output="$(run_hook completion-claim-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false,"last_assistant_message":"Task complete."}' 2>&1 || true)"
  if printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "completion-claim-guard: prose mention of Locked status falsely matched, output: ${output}"
    return
  fi
  pass "completion-claim-guard: anchored grep ignores prose mention of Locked status"
}

test_subagent_scope_guard_ignores_unattributed_workspace_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  emit_locked_fixture "$tmp/docs/plans/unrelated.md" "unrelated"
  # Drift the manifest so verify-lock would fail if invoked.
  awk '/^\*\*Tasks:\*\* 1/ {print; print "**Drift:** yes"; next} {print}' \
    "$tmp/docs/plans/unrelated.md" > "$tmp/docs/plans/unrelated.md.tmp" \
    && mv "$tmp/docs/plans/unrelated.md.tmp" "$tmp/docs/plans/unrelated.md"
  output="$(run_hook subagent-scope-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false}' 2>&1 || true)"
  if printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "subagent-scope-guard: blocked stop for unattributed workspace lock, output: ${output}"
    return
  fi
  pass "subagent-scope-guard: ignores unattributed workspace lock"
}

test_subagent_scope_guard_blocks_attributed_drift() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state" "$tmp/tests"
  cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  emit_locked_fixture "$tmp/docs/plans/active.md" "active"
  jq -nc --arg s "session.jsonl" --arg pl "docs/plans/active.md" \
    '{ev:"session-lock",session:$s,pl:$pl}' \
    > "$tmp/.claude/autodev-state/session-locks.jsonl"
  # Drift inside the manifest section so verify-lock fails.
  awk '/^\*\*Tasks:\*\* 1/ {print; print "**Drift:** yes"; next} {print}' \
    "$tmp/docs/plans/active.md" > "$tmp/docs/plans/active.md.tmp" \
    && mv "$tmp/docs/plans/active.md.tmp" "$tmp/docs/plans/active.md"
  output="$(run_hook subagent-scope-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false}' 2>&1 || true)"
  if ! printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "subagent-scope-guard: did NOT block for attributed drift, output: ${output}"
    return
  fi
  pass "subagent-scope-guard: blocks on attributed drift"
}

test_prompt_strict_ignores_single_workspace_lock_when_session_has_no_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  emit_locked_fixture "$tmp/docs/plans/active.md" "active"
  output="$(run_hook prompt-strict-interpretation '{"prompt":"continue autonomously","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "prompt-strict-interpretation: single workspace lock falsely triggered fallback, output: ${output}"
    return
  fi
  pass "prompt-strict-interpretation: no workspace fallback when session has no lock"
}

test_pre_compact_ignores_single_workspace_lock_when_session_has_no_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  emit_locked_fixture "$tmp/docs/plans/active.md" "active"
  output="$(run_hook pre-compact-snapshot '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "pre-compact-snapshot: single workspace lock falsely triggered fallback, output: ${output}"
    return
  fi
  pass "pre-compact-snapshot: no workspace fallback when session has no lock"
}

test_completion_ignores_single_workspace_lock_when_session_has_no_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  emit_locked_fixture "$tmp/docs/plans/active.md" "active"
  output="$(run_hook completion-claim-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false,"last_assistant_message":"Task complete."}' 2>&1 || true)"
  if printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "completion-claim-guard: single workspace lock falsely triggered fallback, output: ${output}"
    return
  fi
  pass "completion-claim-guard: no workspace fallback when session has no lock"
}

test_scope_lock_claim_writes_session_attribution() {
  local tmp transcript record_payload state_file
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
  emit_locked_fixture "$tmp/docs/plans/p.md" "p"
  record_payload=$(jq -nc \
    --arg cmd "bash hooks/scope-lock-claim docs/plans/p.md" \
    --arg cwd "$tmp" --arg tp "$transcript" \
    '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,transcript_path:$tp}')
  run_hook pre-tool-scope-guard "$record_payload" >/dev/null 2>&1 || true
  state_file="$tmp/.claude/autodev-state/session-locks.jsonl"
  if [ ! -s "$state_file" ]; then
    fail "scope-lock-claim: pre-tool-scope-guard did not write session-locks.jsonl"
    return
  fi
  if ! jq -e --arg s "session.jsonl" --arg pl "docs/plans/p.md" \
      'select(.ev=="session-lock" and .session==$s and .pl==$pl)' "$state_file" >/dev/null; then
    fail "scope-lock-claim: row missing for (session,plan), file: $(cat "$state_file")"
    return
  fi
  pass "scope-lock-claim: recognized by pre-tool-scope-guard and writes session row"
}

test_scope_lock_claim_writes_are_idempotent() {
  local tmp transcript record_payload rowcount
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
  emit_locked_fixture "$tmp/docs/plans/p.md" "p"
  record_payload=$(jq -nc \
    --arg cmd "bash hooks/scope-lock-claim docs/plans/p.md" \
    --arg cwd "$tmp" --arg tp "$transcript" \
    '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,transcript_path:$tp}')
  for _ in 1 2 3; do
    run_hook pre-tool-scope-guard "$record_payload" >/dev/null 2>&1 || true
  done
  rowcount=$(wc -l < "$tmp/.claude/autodev-state/session-locks.jsonl" | awk '{print $1}')
  if [ "$rowcount" -ne 1 ]; then
    fail "scope-lock-claim: expected 1 row after 3 invocations, got: $rowcount"
    return
  fi
  pass "scope-lock-claim: dedupe keeps session-locks.jsonl at one row per (session, plan)"
}

test_scope_lock_claim_rejects_unlocked_plan() {
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  emit_draft_fixture "$tmp/docs/plans/draft.md" "draft"
  set +e
  bash "$REPO_ROOT/hooks/scope-lock-claim" "$tmp/docs/plans/draft.md" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { fail "scope-lock-claim: accepted unlocked plan"; return; }
  pass "scope-lock-claim: rejects unlocked plan"
}

test_scope_lock_claim_rejects_drift() {
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/tests"
  cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  emit_locked_fixture "$tmp/docs/plans/p.md" "p"
  awk '/^\*\*PR Count:\*\* 1/{print "**PR Count:** 2"; next} {print}' \
    "$tmp/docs/plans/p.md" > "$tmp/docs/plans/p.md.tmp" \
    && mv "$tmp/docs/plans/p.md.tmp" "$tmp/docs/plans/p.md"
  set +e
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-claim" "docs/plans/p.md" >/dev/null 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { fail "scope-lock-claim: accepted drifted manifest"; return; }
  pass "scope-lock-claim: rejects manifest drift"
}

test_scope_lock_abandon_flips_status_and_prunes_state() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state" "$tmp/.autodev/state"
  emit_locked_fixture "$tmp/docs/plans/p.md" "p"
  jq -nc --arg s "session.jsonl" --arg pl "docs/plans/p.md" \
    '{ev:"session-lock",session:$s,pl:$pl}' \
    > "$tmp/.claude/autodev-state/session-locks.jsonl"
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-abandon" "docs/plans/p.md" --reason "user pivoted" >/dev/null )
  if ! grep -qE '^\*\*Status:\*\*[[:space:]]+Abandoned' "$tmp/docs/plans/p.md"; then
    fail "scope-lock-abandon: status not flipped to Abandoned"
    return
  fi
  if ! grep -q 'user pivoted' "$tmp/docs/plans/p.md"; then
    fail "scope-lock-abandon: reason missing from status line"
    return
  fi
  if [ -e "$tmp/docs/plans/p.md.scope-lock" ]; then
    fail "scope-lock-abandon: .scope-lock not removed"
    return
  fi
  if [ -s "$tmp/.claude/autodev-state/session-locks.jsonl" ] \
     && jq -e --arg pl "docs/plans/p.md" 'select(.pl==$pl)' \
        "$tmp/.claude/autodev-state/session-locks.jsonl" >/dev/null 2>&1; then
    fail "scope-lock-abandon: session-lock row not pruned"
    return
  fi
  if ! jq -e 'select(.ev=="plan" and .st=="abandoned" and .reason=="user pivoted")' \
      "$tmp/.autodev/state/phase-progress.jsonl" >/dev/null 2>&1; then
    fail "scope-lock-abandon: phase-progress row missing or malformed"
    return
  fi
  pass "scope-lock-abandon: flips status, removes lock, prunes session-locks, appends phase-progress"
}

test_scope_lock_abandon_requires_reason() {
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  emit_locked_fixture "$tmp/docs/plans/p.md" "p"
  set +e
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-abandon" "docs/plans/p.md" >/dev/null 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { fail "scope-lock-abandon: accepted missing --reason"; return; }
  set +e
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-abandon" "docs/plans/p.md" --reason "" >/dev/null 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { fail "scope-lock-abandon: accepted empty --reason"; return; }
  pass "scope-lock-abandon: requires non-empty --reason"
}

test_scope_lock_abandon_sanitizes_reason() {
  local tmp line
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/.autodev/state"
  emit_locked_fixture "$tmp/docs/plans/p.md" "p"
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-abandon" "docs/plans/p.md" \
      --reason $'multi\nline\twith\ttabs and **bold** text' >/dev/null )
  line=$(grep -E '^\*\*Status:\*\*[[:space:]]+Abandoned' "$tmp/docs/plans/p.md")
  if [ "$(printf '%s' "$line" | wc -l | awk '{print $1}')" -ne 0 ]; then
    fail "scope-lock-abandon: status spans multiple lines: ${line}"
    return
  fi
  if printf '%s' "$line" | grep -q '\*\*bold\*\*'; then
    fail "scope-lock-abandon: did not neutralize ** in reason: ${line}"
    return
  fi
  pass "scope-lock-abandon: sanitizes multi-line reason and neutralizes **"
}

test_scope_lock_abandon_refuses_unlocked() {
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  emit_draft_fixture "$tmp/docs/plans/draft.md" "draft"
  set +e
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-abandon" "docs/plans/draft.md" --reason "test" >/dev/null 2>&1 )
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { fail "scope-lock-abandon: accepted non-Locked plan"; return; }
  pass "scope-lock-abandon: refuses non-Locked plan"
}

test_e2e_claim_then_nag_includes_plan() {
  local tmp transcript record_payload nag_output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
  emit_locked_fixture "$tmp/docs/plans/active.md" "active"
  record_payload=$(jq -nc \
    --arg cmd "bash hooks/scope-lock-claim docs/plans/active.md" \
    --arg cwd "$tmp" --arg tp "$transcript" \
    '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,transcript_path:$tp}')
  run_hook pre-tool-scope-guard "$record_payload" >/dev/null 2>&1 || true
  nag_output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead and create a PR","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if ! printf '%s' "$nag_output" | jq -e '.hookSpecificOutput.additionalContext | contains("active.md")' >/dev/null; then
    fail "e2e claim→nag: nag did not include claimed plan, output: ${nag_output}"
    return
  fi
  pass "e2e: claim → next prompt nag references the claimed plan"
}

test_e2e_abandon_then_no_nag() {
  local tmp transcript record_payload nag_output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state" "$tmp/.autodev/state"
  emit_locked_fixture "$tmp/docs/plans/stale.md" "stale"
  record_payload=$(jq -nc \
    --arg cmd "bash hooks/scope-lock-claim docs/plans/stale.md" \
    --arg cwd "$tmp" --arg tp "$transcript" \
    '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,transcript_path:$tp}')
  run_hook pre-tool-scope-guard "$record_payload" >/dev/null 2>&1 || true
  nag_output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  printf '%s' "$nag_output" | jq -e '.hookSpecificOutput.additionalContext | contains("stale.md")' >/dev/null \
    || { fail "e2e abandon: precondition (nag after claim) not met"; return; }
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-abandon" "docs/plans/stale.md" --reason "test abandon" >/dev/null )
  nag_output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$nag_output" ]; then
    fail "e2e abandon: nag still fires after abandon, output: ${nag_output}"
    return
  fi
  pass "e2e: abandon → next prompt is silent"
}

test_e2e_fresh_session_no_claim_no_nag() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/fresh.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
  emit_locked_fixture "$tmp/docs/plans/foo.md" "foo"
  output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "e2e fresh session: workspace fallback still fires, output: ${output}"
    return
  fi
  pass "e2e: fresh session with no claim does not nag on workspace-only locks"
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

# ── pretool-demo-fidelity-guard (advisory, never blocks) ─────────────────────
demo_fidelity_payload() {
  # $1 = file_path, $2 = transcript_path, $3 = cwd
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s","transcript_path":"%s"}' \
    "$1" "$3" "$2"
}

test_demo_fidelity_fires_and_never_blocks() {
  local tmp transcript output
  tmp="$(mktemp -d)"; transcript="${tmp}/sessionA.jsonl"; : > "$transcript"
  output="$(run_hook pretool-demo-fidelity-guard "$(demo_fidelity_payload "examples/foo-demo.py" "$transcript" "$tmp")")"
  assert_hook_context_json "demo-fidelity:fires" "PreToolUse" "$output"
  if printf '%s' "$output" | grep -q 'demonstration-fidelity'; then
    pass "demo-fidelity: reminder references the skill"
  else
    fail "demo-fidelity: reminder must reference demonstration-fidelity: ${output}"
  fi
  if printf '%s' "$output" | jq -e 'has("decision")' >/dev/null 2>&1; then
    fail "demo-fidelity: advisory hook must never emit decision/block: ${output}"
  else
    pass "demo-fidelity: never blocks (no decision key)"
  fi
  rm -rf "$tmp"
}

test_demo_fidelity_fires_on_legit_demos() {
  local tmp transcript output p
  tmp="$(mktemp -d)"
  # Capitalized + names containing test/spec as substrings (NOT segments) must still fire.
  for p in "examples/latest-feature-demo.py" "examples/attestation-demo.go" "examples/Showcase.go" "demo_runner.go" "quickstart.md"; do
    transcript="${tmp}/$(printf '%s' "$p" | tr '/.' '__').jsonl"; : > "$transcript"
    output="$(run_hook pretool-demo-fidelity-guard "$(demo_fidelity_payload "$p" "$transcript" "$tmp")")"
    if printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then
      pass "demo-fidelity: fires on ${p}"
    else
      fail "demo-fidelity: must fire on legit demo ${p}: ${output}"
    fi
  done
  rm -rf "$tmp"
}

test_demo_fidelity_silent_on_excluded_and_nondemo() {
  local tmp transcript output p
  tmp="$(mktemp -d)"; transcript="${tmp}/s.jsonl"; : > "$transcript"
  for p in "pkg/example_test.go" "testdata/example.json" "examples/testdata/demo.py" "internal/server.go" "config/sample_config.yaml" "vendor/example/demo.go" "app/spec/example_helper.rb"; do
    output="$(run_hook pretool-demo-fidelity-guard "$(demo_fidelity_payload "$p" "$transcript" "$tmp")")"
    if [ -z "$output" ]; then
      pass "demo-fidelity: silent on ${p}"
    else
      fail "demo-fidelity: must be silent on ${p}: ${output}"
    fi
  done
  rm -rf "$tmp"
}

test_demo_fidelity_silent_on_non_write_tool() {
  local tmp transcript output
  tmp="$(mktemp -d)"; transcript="${tmp}/s.jsonl"; : > "$transcript"
  output="$(printf '{"tool_name":"Bash","tool_input":{"command":"echo hi > examples/foo-demo.py"},"cwd":"%s","transcript_path":"%s"}' "$tmp" "$transcript" | env LC_ALL=C LANG=C LC_CTYPE=C hooks/pretool-demo-fidelity-guard || true)"
  if [ -z "$output" ]; then pass "demo-fidelity: silent on non-Write tool"; else fail "demo-fidelity: must ignore non-Write tools: ${output}"; fi
  rm -rf "$tmp"
}

test_demo_fidelity_respects_disable_env() {
  local tmp transcript output
  tmp="$(mktemp -d)"; transcript="${tmp}/s.jsonl"; : > "$transcript"
  output="$(printf '{"tool_name":"Write","tool_input":{"file_path":"examples/foo-demo.py"},"cwd":"%s","transcript_path":"%s"}' "$tmp" "$transcript" | env SUPERPOWERS_HOOKS_DISABLE=1 LC_ALL=C LANG=C LC_CTYPE=C hooks/pretool-demo-fidelity-guard || true)"
  if [ -z "$output" ]; then pass "demo-fidelity: respects SUPERPOWERS_HOOKS_DISABLE"; else fail "demo-fidelity: must be silent when disabled: ${output}"; fi
  rm -rf "$tmp"
}

test_demo_fidelity_handles_malformed_stdin() {
  local output
  output="$(printf '%s' 'not json {{{' | env LC_ALL=C LANG=C LC_CTYPE=C hooks/pretool-demo-fidelity-guard || true)"
  if [ -z "$output" ]; then pass "demo-fidelity: silent + no crash on malformed stdin"; else fail "demo-fidelity: malformed stdin must not emit: ${output}"; fi
  output="$(printf '%s' '' | env LC_ALL=C LANG=C LC_CTYPE=C hooks/pretool-demo-fidelity-guard || true)"
  if [ -z "$output" ]; then pass "demo-fidelity: silent on empty stdin"; else fail "demo-fidelity: empty stdin must not emit: ${output}"; fi
}

test_demo_fidelity_dedups_within_session() {
  local tmp transcript out1 out2
  tmp="$(mktemp -d)"; transcript="${tmp}/sessionDedup.jsonl"; : > "$transcript"
  out1="$(run_hook pretool-demo-fidelity-guard "$(demo_fidelity_payload "examples/foo-demo.py" "$transcript" "$tmp")")"
  out2="$(run_hook pretool-demo-fidelity-guard "$(demo_fidelity_payload "examples/foo-demo.py" "$transcript" "$tmp")")"
  if printf '%s' "$out1" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then
    pass "demo-fidelity: first write fires"
  else
    fail "demo-fidelity: first write must fire: ${out1}"
  fi
  if [ -z "$out2" ]; then
    pass "demo-fidelity: dedups second write of same path in same session"
  else
    fail "demo-fidelity: second write of same path must be suppressed: ${out2}"
  fi
  rm -rf "$tmp"
}

test_demo_fidelity_fail_open_when_state_unwritable() {
  local tmp transcript output
  tmp="$(mktemp -d)"; transcript="${tmp}/s.jsonl"; : > "$transcript"
  # Make .claude a regular file so mkdir -p .claude/autodev-state cannot succeed.
  printf '' > "${tmp}/.claude"
  output="$(run_hook pretool-demo-fidelity-guard "$(demo_fidelity_payload "examples/foo-demo.py" "$transcript" "$tmp")")"
  if printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then
    pass "demo-fidelity: fail-open — fires when dedup state is unwritable"
  else
    fail "demo-fidelity: must fire (fail-open) when state unwritable: ${output}"
  fi
  rm -rf "$tmp"
}

require_jq
test_session_start_json
test_session_start_time_dedup_suppresses_rapid_refires
test_wrapper_suppresses_unavailable_c_utf8_locale_noise
test_prompt_strict_json
test_prompt_strict_no_output_without_trigger
test_prompt_strict_ignores_ambiguous_workspace_locks_when_session_has_no_lock
test_prompt_strict_ignores_single_workspace_lock_when_session_has_no_lock
test_prompt_strict_uses_session_locked_plan_only
test_prompt_strict_ignores_prose_mention_of_locked_status
test_pretool_pr_review_json
test_posttool_pr_created_json
test_pre_compact_snapshot_json
test_wrapper_suppresses_pre_compact_locale_noise
test_pre_compact_snapshot_only_locked_plans
test_pre_compact_ignores_prose_mention_of_locked_status
test_pre_compact_ignores_single_workspace_lock_when_session_has_no_lock
test_scope_lock_complete_marks_complete_and_prunes_state
test_scope_lock_complete_requires_lock_file
test_scope_lock_complete_rejects_bad_lock_without_project_checker
test_scope_lock_complete_preflights_progress_write
test_scope_lock_complete_rejects_progress_directory
test_completion_continuation_block
test_completion_continuation_block_keeps_heading_separator_when_flattened
test_pretool_records_session_lock_for_scope_lock_apply
test_pretool_ignores_prose_mention_of_locked_status
test_completion_ignores_ambiguous_workspace_locks_when_session_has_no_lock
test_completion_ignores_single_workspace_lock_when_session_has_no_lock
test_completion_uses_session_locked_plan_only
test_completion_allows_hard_blocker
test_completion_ignores_prose_mention_of_locked_status
test_pretool_allows_locked_plan_text_edit
test_subagent_allows_non_manifest_plan_backport
test_subagent_scope_guard_ignores_unattributed_workspace_lock
test_subagent_scope_guard_blocks_attributed_drift
test_pre_tool_scope_guard_does_not_block_force_push_inside_quoted_string
test_pre_tool_scope_guard_block_exits_zero_with_stderr_reason
test_subagent_scope_guard_block_exits_zero_with_stderr_reason
test_scope_lock_claim_writes_session_attribution
test_scope_lock_claim_writes_are_idempotent
test_scope_lock_claim_rejects_unlocked_plan
test_scope_lock_claim_rejects_drift
test_scope_lock_abandon_flips_status_and_prunes_state
test_scope_lock_abandon_requires_reason
test_scope_lock_abandon_sanitizes_reason
test_scope_lock_abandon_refuses_unlocked
test_e2e_claim_then_nag_includes_plan
test_e2e_abandon_then_no_nag
test_e2e_fresh_session_no_claim_no_nag
test_record_activity_compact_state
test_skill_activation_audit_reads_compact_state
test_demo_fidelity_fires_and_never_blocks
test_demo_fidelity_fires_on_legit_demos
test_demo_fidelity_silent_on_excluded_and_nondemo
test_demo_fidelity_silent_on_non_write_tool
test_demo_fidelity_respects_disable_env
test_demo_fidelity_handles_malformed_stdin
test_demo_fidelity_dedups_within_session
test_demo_fidelity_fail_open_when_state_unwritable

if [ "$failures" -ne 0 ]; then
  printf '\n%d hook contract test(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll hook contract tests passed.\n'
