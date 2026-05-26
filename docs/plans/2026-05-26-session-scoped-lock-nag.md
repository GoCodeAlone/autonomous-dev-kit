# Session-scoped lock nag + claim/abandon Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Restrict the locked-plan nag (UserPromptSubmit, PreCompact, PreToolUse, SubagentStop) to plans attributed to the current session, fix the latent substring-grep false-positive, and add `scope-lock-claim` + `scope-lock-abandon` helpers so agents can recover lost session attribution and clean up never-completed locks.

**Architecture:** Bash-only changes inside the autodev plugin distribution. Four nag hooks switch from `grep -q '\*\*Status:\*\* Locked'` (substring) to anchored line-start regex. The workspace-wide fallback that fires when `session_key` is present but session-locks.jsonl has no attribution is removed; the fallback when no `session_key` is provided at all (host doesn't expose it) is kept. Two new helpers (`scope-lock-claim`, `scope-lock-abandon`) mirror `scope-lock-complete`'s shape. `pre-tool-scope-guard`'s `record_session_lock` recognizes both apply and claim by centralizing the helper-name list, and prunes session-locks for abandon.

**Tech Stack:** Bash, jq, awk, sha256sum/shasum (existing toolchain). No new dependencies.

**Base branch:** main

---

## Scope Manifest

**PR Count:** 1
**Tasks:** 9
**Estimated Lines of Change:** ~600 (informational)

**Out of scope:**
- Changes to the Scope Manifest format or `tests/plan-scope-check.sh` extraction logic.
- A multi-session lock or shared-lock semantics — claim is per-session and additive.
- Auto-detection of stale locks (timestamp heuristics, branch presence). Stale-vs-active is operator judgment.
- Re-locking an Abandoned plan automatically. Once abandoned the operator re-runs alignment-check.
- Changes to `scope-lock-complete` (the happy-path helper from ADR 0001).

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | feat(scope-lock): session-scoped nag + claim/abandon helpers | Task 1, Task 2, Task 3, Task 4, Task 5, Task 6, Task 7, Task 8, Task 9 | feat/session-scoped-lock-nag-2026-05-26 |

**Status:** Complete 2026-05-26T22:05:58Z

---

## Test fixture helper (shared by every test below)

To keep `tests/plan-scope-check.sh`'s manifest parser from re-entering on every fixture heredoc, ALL fixture plans emit through a single printf helper that hides the heading from column 0 in this markdown file. Add this helper near the top of the new test block in `tests/hook-contracts.sh`:

```bash
# emit_locked_fixture <plan-abs-path> <name>
#   Writes a minimal-but-valid locked plan to <plan-abs-path>, then runs
#   hooks/scope-lock-apply against it from the repo root. The plan body is
#   produced with printf (not a heredoc) so this plan document's own
#   tests/plan-scope-check.sh parser does not double-count fixture PR rows.
emit_locked_fixture() {
  local path="$1" name="$2"
  printf '# %s Plan\n\n%s\n\n**PR Count:** 1\n**Tasks:** 1\n**Out of scope:**\n- (none)\n\n**PR Grouping:**\n\n| PR # | Title | Tasks | Branch |\n|------|-------|-------|--------|\n| 1 | %s | Task 1 | feat/%s |\n\n**Status:** Locked 2026-05-26T00:00:00Z\n\n### Task 1: %s\n' \
    "$name" "## Scope Manifest" "$name" "$name" "$name" > "$path"
  ( cd "$(dirname "$(dirname "$path")")/.." \
    && bash "$REPO_ROOT/hooks/scope-lock-apply" "${path#"$PWD"/}" >/dev/null 2>&1 \
    || bash "$REPO_ROOT/hooks/scope-lock-apply" "$path" >/dev/null )
}

# emit_draft_fixture <plan-abs-path> <name>
#   Same shape but Status is Draft; used for prose-mention regression tests.
emit_draft_fixture() {
  local path="$1" name="$2"
  printf '# %s Plan\n\n%s\n\n**PR Count:** 1\n**Tasks:** 1\n**Out of scope:**\n- (none)\n\n**PR Grouping:**\n\n| PR # | Title | Tasks | Branch |\n|------|-------|-------|--------|\n| 1 | %s | Task 1 | feat/%s |\n\n**Status:** Draft\n\nProse mention: %s 2026-05-26T00:00:00Z\n\n### Task 1: %s\n' \
    "$name" "## Scope Manifest" "$name" "$name" "**Status:** Locked" "$name"  > "$path"
}
```

Every test below uses these two helpers — no per-test heredoc.

---

### Task 1: Anchored status-line grep — pre-tool-scope-guard

**Files:**
- Modify: `hooks/pre-tool-scope-guard`
- Modify: `tests/hook-contracts.sh` (add `emit_locked_fixture` + `emit_draft_fixture` helpers + test below)

**Step 1: Write the failing test.**

```bash
test_pretool_ignores_prose_mention_of_locked_status() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
  emit_draft_fixture "$tmp/docs/plans/draft.md" "draft"
  output="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/x"},"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}' \
    | run_hook pre-tool-scope-guard 2>&1 || true)"
  if printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "pre-tool-scope-guard: prose mention of Locked status falsely matched, output: ${output}"
    return
  fi
  pass "pre-tool-scope-guard: anchored grep ignores prose mention of Locked status"
}
```

**Step 2: Run test to verify it fails.** `bash tests/hook-contracts.sh 2>&1 | grep test_pretool_ignores_prose_mention` → expect FAIL.

**Step 3: Tighten the grep.** In `hooks/pre-tool-scope-guard`, replace both `grep -q '\*\*Status:\*\* Locked'` (in the session-attributed branch's inner loop) and `grep -rl '\*\*Status:\*\* Locked'` (workspace-fallback) with their anchored counterparts:

```bash
grep -qE '^\*\*Status:\*\*[[:space:]]+Locked' "$resolved"     # session-attributed loop
grep -rlE '^\*\*Status:\*\*[[:space:]]+Locked' "$plans_dir"   # workspace fallback
```

**Step 4: Re-run test.** Expect PASS.

**Step 5: Commit.**

```bash
git add hooks/pre-tool-scope-guard tests/hook-contracts.sh
git commit -m "fix(hooks): anchor Status:Locked grep in pre-tool-scope-guard"
```

---

### Task 2: Anchored status-line grep — prompt-strict-interpretation

**Files:**
- Modify: `hooks/prompt-strict-interpretation`
- Modify: `tests/hook-contracts.sh`

**Step 1: Write the failing test.**

```bash
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
```

**Step 2: Run.** Expect FAIL.

**Step 3: Tighten the grep at both occurrences inside `workspace_locked_plans` and `session_locked_plans` (≈ lines 105, 124).** Replace `grep -q '\*\*Status:\*\* Locked'` with `grep -qE '^\*\*Status:\*\*[[:space:]]+Locked'`.

**Step 4: Re-run.** Expect PASS.

**Step 5: Commit.**

```bash
git add hooks/prompt-strict-interpretation tests/hook-contracts.sh
git commit -m "fix(hooks): anchor Status:Locked grep in prompt-strict-interpretation"
```

---

### Task 3: Anchored status-line grep — pre-compact-snapshot

**Files:**
- Modify: `hooks/pre-compact-snapshot`
- Modify: `tests/hook-contracts.sh`

**Step 1: Write the failing test** (same shape as Task 2, using `pre-compact-snapshot` and asserting empty output).

```bash
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
```

**Step 2-4:** Same as Task 2; locations to patch in `hooks/pre-compact-snapshot` are ≈ lines 44 and 63.

**Step 5: Commit.**

```bash
git add hooks/pre-compact-snapshot tests/hook-contracts.sh
git commit -m "fix(hooks): anchor Status:Locked grep in pre-compact-snapshot"
```

---

### Task 4: Session-aware subagent-scope-guard + anchored grep

**Files:**
- Modify: `hooks/subagent-scope-guard`
- Modify: `tests/hook-contracts.sh`

**Step 1: Write the failing tests.**

```bash
test_subagent_scope_guard_ignores_unattributed_workspace_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  emit_locked_fixture "$tmp/docs/plans/unrelated.md" "unrelated"
  # Drift the manifest so verify-lock would fail if invoked.
  printf '\n<!-- drift -->\n' >> "$tmp/docs/plans/unrelated.md"
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
  emit_locked_fixture "$tmp/docs/plans/active.md" "active"
  jq -nc --arg s "session.jsonl" --arg pl "docs/plans/active.md" \
    '{ev:"session-lock",session:$s,pl:$pl}' \
    > "$tmp/.claude/autodev-state/session-locks.jsonl"
  cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh"
  chmod +x "$tmp/tests/plan-scope-check.sh"
  # Drift inside the manifest section so verify-lock fails.
  awk '/^\*\*Tasks:\*\*/ {print; print "**Drift:** yes"; next} {print}' \
    "$tmp/docs/plans/active.md" > "$tmp/docs/plans/active.md.tmp" \
    && mv "$tmp/docs/plans/active.md.tmp" "$tmp/docs/plans/active.md"
  output="$(run_hook subagent-scope-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false}' 2>&1 || true)"
  if ! printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "subagent-scope-guard: did NOT block for attributed drift, output: ${output}"
    return
  fi
  pass "subagent-scope-guard: blocks on attributed drift"
}
```

**Step 2: Run.** Expect both FAIL.

**Step 3: Refactor `hooks/subagent-scope-guard`.** Extract `transcript_path` + `session_key` from `hook_input` near the top (mirror the pattern already used by `prompt-strict-interpretation`). Replace the existing locked-plans discovery block (current lines 74-83) with:

```bash
transcript_path=$(printf '%s' "$hook_input" | jq -r '.transcript_path // empty' 2>/dev/null || true)
session_key=""
[ -n "$transcript_path" ] && session_key=$(basename "$transcript_path")

find_session_locked_plans() {
    local state_file="${cwd_dir}/.claude/autodev-state/session-locks.jsonl"
    [ -f "$state_file" ] || return 0
    jq -r --arg session "$session_key" \
        'select(.ev == "session-lock" and .session == $session) | .pl // empty' \
        "$state_file" 2>/dev/null \
        | awk 'NF && !seen[$0]++' \
        | while IFS= read -r plan; do
            [ -n "$plan" ] || continue
            case "$plan" in
                /*) resolved="$plan" ;;
                *) resolved="${cwd_dir}/${plan}" ;;
            esac
            [ -f "$resolved" ] || continue
            grep -qE '^\*\*Status:\*\*[[:space:]]+Locked' "$resolved" 2>/dev/null || continue
            printf '%s\n' "$resolved"
        done
}

find_workspace_locked_plans() {
    grep -rlE '^\*\*Status:\*\*[[:space:]]+Locked' "${cwd_dir}/docs/plans" 2>/dev/null \
        | grep '\.md$' | grep -v '\.scope-lock' || true
}

checker="${cwd_dir}/tests/plan-scope-check.sh"
if [ -x "$checker" ] && [ -d "${cwd_dir}/docs/plans" ]; then
    if [ -n "$session_key" ]; then
        locked_plans=$(find_session_locked_plans)
    else
        locked_plans=$(find_workspace_locked_plans)
    fi
    while IFS= read -r plan; do
        [ -z "$plan" ] && continue
        if ! bash "$checker" --verify-lock "$plan" >/dev/null 2>&1; then
            violations="${violations}  • Locked Scope Manifest hash mismatch: ${plan#${cwd_dir}/}\n"
        fi
    done <<< "$locked_plans"
fi
```

**Step 4: Run tests.** Expect both PASS.

**Step 5: Commit.**

```bash
git add hooks/subagent-scope-guard tests/hook-contracts.sh
git commit -m "fix(hooks): session-scope subagent-scope-guard and anchor Locked grep"
```

---

### Task 5: Drop the single-workspace-lock fallback in nag hooks

**Files:**
- Modify: `hooks/prompt-strict-interpretation`
- Modify: `hooks/pre-compact-snapshot`
- Modify: `tests/hook-contracts.sh` — replace `test_prompt_strict_falls_back_to_single_workspace_lock` (currently asserts the fallback) with a "no fallback" assertion, and add the analogous test for `pre-compact-snapshot`.

**Step 1: Edit the existing test to flip its assertion.**

```bash
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
```

Delete the original `test_prompt_strict_falls_back_to_single_workspace_lock` function.

**Step 2: Run.** Expect both new tests FAIL.

**Step 3: Remove the fallback branch in both hooks.** In `prompt-strict-interpretation` (current lines 130-138) and `pre-compact-snapshot` (current lines 68-83), the logic is the same shape:

```bash
# OLD
if [ -n "$session_key" ]; then
    session_plans=$(session_locked_plans)
    if [ -n "$session_plans" ]; then
        locked_plan=$(printf '%s\n' "$session_plans" | head -1)
    else
        workspace_plans=$(workspace_locked_plans)
        if [ "$(printf '%s\n' "$workspace_plans" | awk 'NF {count++} END {print count+0}')" -eq 1 ]; then
            locked_plan=$(printf '%s\n' "$workspace_plans" | head -1)
        fi
    fi
else
    locked_plan=$(workspace_locked_plans | head -1 || true)
fi

# NEW
if [ -n "$session_key" ]; then
    session_plans=$(session_locked_plans)
    [ -n "$session_plans" ] && locked_plan=$(printf '%s\n' "$session_plans" | head -1)
else
    locked_plan=$(workspace_locked_plans | head -1 || true)
fi
```

For `pre-compact-snapshot`, do the equivalent inside `locked_plan_stream`: when `session_key` is set, only stream session_locked_plans; do NOT stream workspace_locked_plans even if exactly one exists.

**Step 4: Re-run.** Expect both PASS plus the rest of the file still green.

**Step 5: Commit.**

```bash
git add hooks/prompt-strict-interpretation hooks/pre-compact-snapshot tests/hook-contracts.sh
git commit -m "fix(hooks): drop single-workspace-lock fallback when session has no attribution"
```

---

### Task 6: `hooks/scope-lock-claim` helper

**Files:**
- Create: `hooks/scope-lock-claim` (chmod +x)
- Modify: `hooks/pre-tool-scope-guard` (centralize recognized-command list; extend regex to `scope-lock-claim`; dedupe writes)
- Modify: `tests/hook-contracts.sh`

**Step 1: Write the failing tests.**

```bash
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
  printf '%s' "$record_payload" | run_hook pre-tool-scope-guard >/dev/null 2>&1 || true
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
    printf '%s' "$record_payload" | run_hook pre-tool-scope-guard >/dev/null 2>&1 || true
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
  # Drift inside the manifest section.
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
```

**Step 2: Run.** Expect 4 × FAIL (helper missing, recognizer regex doesn't match `scope-lock-claim`).

**Step 3: Centralize the recognized-command list and add `scope-lock-claim`.** Near the top of `hooks/pre-tool-scope-guard` (after the JSON parsing block), add:

```bash
# ──────────────────────────────────────────────────────────────────────────
# Recognized helper script names that update session-lock state. Pattern-
# matched against Bash tool commands by record_session_lock so each helper
# script never needs to know the current session_key itself.
#
# Helpers MUST emit their bare name on stdout so a future maintainer can
# audit which Bash invocations matter from either end.
# ──────────────────────────────────────────────────────────────────────────
SESSION_LOCK_RECOGNIZED='scope-lock-apply|scope-lock-claim'
```

Rewrite `record_session_lock` to use the variable AND dedupe writes:

```bash
record_session_lock() {
    local cmd="$1"
    [ -n "$session_key" ] || return 0
    printf '%s' "$cmd" | grep -qE "(${SESSION_LOCK_RECOGNIZED})" || return 0

    local plan_arg=""
    plan_arg=$(printf '%s' "$cmd" \
        | sed -nE "s/.*(${SESSION_LOCK_RECOGNIZED})[[:space:]]+\"?([^\" ;]+)\"?.*/\2/p" \
        | head -1 || true)
    [ -n "$plan_arg" ] || return 0

    local state_dir="${cwd_dir}/.claude/autodev-state"
    mkdir -p "$state_dir" 2>/dev/null || return 0
    local state_file="${state_dir}/session-locks.jsonl"

    if [ -f "$state_file" ]; then
        if jq -e --arg s "$session_key" --arg pl "$plan_arg" \
            'select(.ev=="session-lock" and .session==$s and .pl==$pl)' \
            "$state_file" >/dev/null 2>&1; then
            return 0
        fi
    fi

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -nc \
        --arg ts "$ts" --arg session "$session_key" --arg pl "$plan_arg" \
        '{ts:$ts,ev:"session-lock",session:$session,pl:$pl}' \
        >> "$state_file" 2>/dev/null || true
}
```

**Step 4: Create `hooks/scope-lock-claim`.**

```bash
#!/usr/bin/env bash
# hooks/scope-lock-claim
# Attribute an existing locked plan to the current session so the locked-plan
# nag hooks fire for this session.
#
# Use case: an agent session was interrupted (e.g., computer restart) and a
# fresh session needs to resume the same work. The .scope-lock file is still
# on disk, but the new session is not in session-locks.jsonl. Running this
# helper attributes the lock to the current session.
#
# Usage: scope-lock-claim <plan-path>
#
# Verifies:
#   1. The plan is in "**Status:** Locked …" (line-start match).
#   2. A .scope-lock sidecar exists (no claim without an anchor).
#   3. tests/plan-scope-check.sh --verify-lock passes when present —
#      claiming a drifted manifest is strictly worse than refusing.
#
# The actual session-locks.jsonl write is performed by pre-tool-scope-guard's
# record_session_lock recognizer (SESSION_LOCK_RECOGNIZED matches this script's
# bare name). This helper is read-only with respect to .scope-lock — re-running
# scope-lock-apply would silently overwrite the original author's hash, which
# defeats the lock.

set -euo pipefail

plan="${1:-}"

if [ -z "$plan" ]; then
    printf 'Usage: scope-lock-claim <plan-path>\n' >&2
    exit 3
fi
if [ ! -f "$plan" ]; then
    printf 'Error: plan file not found: %s\n' "$plan" >&2
    exit 1
fi
if ! grep -qE '^\*\*Status:\*\*[[:space:]]+Locked' "$plan"; then
    printf 'Error: plan is not in Locked status: %s\n' "$plan" >&2
    exit 1
fi
lock_file="${plan}.scope-lock"
if [ ! -f "$lock_file" ]; then
    printf 'Error: no .scope-lock sidecar for %s — nothing to claim\n' "$plan" >&2
    exit 1
fi

# Drift check (only when the checker is available; absence is not a failure).
for d in "$(dirname "$plan")/../../tests" "$(dirname "$plan")/../tests" "./tests"; do
    candidate="${d}/plan-scope-check.sh"
    if [ -x "$candidate" ]; then
        if ! bash "$candidate" --verify-lock "$plan" >/dev/null 2>&1; then
            printf 'Error: manifest drift detected for %s — refusing claim (run scope-lock amendment path)\n' "$plan" >&2
            exit 1
        fi
        break
    fi
done

# Sentinel token for pre-tool-scope-guard's record_session_lock recognizer.
printf 'scope-lock-claim: attributing %s to current session\n' "$plan"
exit 0
```

`chmod +x hooks/scope-lock-claim`.

**Step 5: Re-run all four tests.** Expect 4 × PASS.

**Step 6: Commit.**

```bash
git add hooks/scope-lock-claim hooks/pre-tool-scope-guard tests/hook-contracts.sh
git commit -m "feat(scope-lock): add scope-lock-claim helper for session re-attribution"
```

---

### Task 7: `hooks/scope-lock-abandon` helper

**Files:**
- Create: `hooks/scope-lock-abandon` (chmod +x)
- Modify: `tests/hook-contracts.sh`

**Step 1: Write the failing tests.**

```bash
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
    fail "scope-lock-abandon: status spans multiple lines"
    return
  fi
  if printf '%s' "$line" | grep -q '\*\*bold\*\*'; then
    fail "scope-lock-abandon: did not neutralize ** in reason"
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
```

**Step 2: Run.** Expect 4 × FAIL.

**Step 3: Create `hooks/scope-lock-abandon`.**

```bash
#!/usr/bin/env bash
# hooks/scope-lock-abandon
# Abandon a locked plan that will not be completed.
#
# Sibling to hooks/scope-lock-complete (ADR 0001). Distinct from complete:
#   - Does NOT verify the manifest hash.
#   - Status flips to "Abandoned <UTC> — <reason>".
#   - Requires --reason (non-empty); sanitized to single line, capped at 200
#     chars, with literal "**" replaced by "__".
#   - Appends phase-progress.jsonl with st:"abandoned" + reason field.
#   - Does NOT write an ADR.
#
# Usage:
#   scope-lock-abandon <plan-path> --reason "<reason>"

set -euo pipefail

[ "${SUPERPOWERS_HOOKS_DISABLE:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || {
    printf 'scope-lock-abandon: jq is required for state cleanup\n' >&2
    exit 2
}

plan="${1:-}"
[ -n "$plan" ] || {
    printf 'scope-lock-abandon: missing plan path\n' >&2
    exit 2
}
shift || true

reason=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --reason)
            shift
            reason="${1:-}"
            if [ -z "$reason" ] || [ "${reason#--}" != "$reason" ]; then
                printf 'scope-lock-abandon: --reason requires a non-empty value\n' >&2
                exit 2
            fi
            ;;
        *)
            printf 'scope-lock-abandon: unknown argument: %s\n' "$1" >&2
            exit 2
            ;;
    esac
    shift || true
done

[ -n "$reason" ] || { printf 'scope-lock-abandon: --reason is required\n' >&2; exit 2; }

sanitized_reason=$(printf '%s' "$reason" | tr -s '\n\t ' ' ' | sed 's/\*\*/__/g' | cut -c1-200)

canonical_path_from_base() {
    local base="$1" ref="$2" candidate
    case "$ref" in
        /*) candidate="$ref" ;;
        */*) candidate="${base}/${ref}" ;;
        *) candidate="${base}/docs/plans/${ref}" ;;
    esac
    local dir
    dir=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "$dir" "$(basename "$candidate")"
}

plan_abs=$(canonical_path_from_base "$PWD" "$plan") || {
    printf 'scope-lock-abandon: unable to resolve plan path: %s\n' "$plan" >&2; exit 2; }
[ -f "$plan_abs" ] || { printf 'scope-lock-abandon: plan not found: %s\n' "$plan_abs" >&2; exit 2; }
grep -qE '^\*\*Status:\*\*[[:space:]]+Locked' "$plan_abs" || {
    printf 'scope-lock-abandon: plan is not in Locked status: %s\n' "$plan_abs" >&2; exit 2; }

plan_dir=$(cd "$(dirname "$plan_abs")" && pwd)
repo_root=$(cd "${plan_dir}/../.." && pwd)
plan_name=$(basename "$plan_abs")
plan_rel="docs/plans/${plan_name}"
lock_file="${plan_abs}.scope-lock"

session_locks_file="${repo_root}/.claude/autodev-state/session-locks.jsonl"
in_progress_file="${repo_root}/.claude/autodev-state/in-progress.jsonl"
progress_dir="${repo_root}/.autodev/state"
progress_file="${progress_dir}/phase-progress.jsonl"

ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
plan_tmp=$(mktemp "${plan_abs}.abandon.XXXXXX")
trap 'rm -f "$plan_tmp"' EXIT

awk -v ts="$ts" -v r="$sanitized_reason" '
    !done && /^\*\*Status:\*\*[[:space:]]+Locked/ {
        print "**Status:** Abandoned " ts " — " r
        done = 1
        next
    }
    { print }
' "$plan_abs" > "$plan_tmp"

prune_jsonl() {
    local file="$1" tmp
    [ -f "$file" ] || return 0
    tmp=$(mktemp "${file}.abandon.XXXXXX")
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        pl=$(printf '%s' "$line" | jq -r '.pl // empty' 2>/dev/null || true) || { rm -f "$tmp"; return 1; }
        if [ -n "$pl" ]; then
            resolved=$(canonical_path_from_base "$repo_root" "$pl" 2>/dev/null || true)
            [ "$resolved" = "$plan_abs" ] && continue
        fi
        printf '%s\n' "$line" >> "$tmp"
    done < "$file"
    mv "$tmp" "$file"
}

mkdir -p "$progress_dir"
mv "$plan_tmp" "$plan_abs"
trap - EXIT
rm -f "$lock_file"
prune_jsonl "$session_locks_file" || true
prune_jsonl "$in_progress_file" || true
jq -nc \
    --arg ts "$ts" --arg pl "$plan_name" --arg r "$sanitized_reason" \
    '{ts:$ts,ev:"plan",pl:$pl,st:"abandoned",reason:$r}' \
    >> "$progress_file"

printf 'scope-lock-abandon: abandoned %s (reason: %s)\n' "$plan_rel" "$sanitized_reason"
```

`chmod +x hooks/scope-lock-abandon`.

**Step 4: Re-run all four tests.** Expect 4 × PASS.

**Step 5: Commit.**

```bash
git add hooks/scope-lock-abandon tests/hook-contracts.sh
git commit -m "feat(scope-lock): add scope-lock-abandon helper for stopping work without completion"
```

---

### Task 8: End-to-end claim → nag and abandon → silence tests

**Files:**
- Modify: `tests/hook-contracts.sh`

**Step 1: Write the tests.**

```bash
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
  printf '%s' "$record_payload" | run_hook pre-tool-scope-guard >/dev/null 2>&1 || true
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
  printf '%s' "$record_payload" | run_hook pre-tool-scope-guard >/dev/null 2>&1 || true
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
  # No claim, no session-locks row. Single workspace lock — pre-fix would fall back.
  output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "e2e fresh session: workspace fallback still fires, output: ${output}"
    return
  fi
  pass "e2e: fresh session with no claim does not nag on workspace-only locks"
}
```

**Step 2: Run.** Expect 3 × PASS (depends on Tasks 1-7 already merged into the running file).

**Step 3: Commit.**

```bash
git add tests/hook-contracts.sh
git commit -m "test: end-to-end claim→nag and abandon→silence cycles"
```

---

### Task 9: SKILL.md documentation + final test pass

**Files:**
- Modify: `skills/scope-lock/SKILL.md`

**Step 1: Update the skill** by adding two sections after `## Completing a Locked Plan`:

```markdown
## Claiming an Existing Lock (resume after restart)

When a session is interrupted (computer restart, host crash, accidental
`/clear`) and a fresh session needs to resume work on an already-locked plan,
the new session must explicitly **claim** the lock for itself. The nag hooks
only fire for plans attributed to the current session via
`.claude/autodev-state/session-locks.jsonl`; that attribution is per-session
and does not survive across sessions.

`​`​`bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/hooks/scope-lock-claim" docs/plans/<plan>.md
`​`​`

The helper verifies the plan is Locked, has a `.scope-lock` sidecar, and that
the manifest hash still matches (drift is rejected — use the amendment path).
The session-attribution row is appended to `session-locks.jsonl` by
`hooks/pre-tool-scope-guard`'s `record_session_lock` recognizer — the same
mechanism that writes the row at `scope-lock-apply` time. Idempotent.

## Abandoning a Lock (stopped pursuing)

When work on a locked plan will not complete (user pivoted, design superseded,
out of capacity), close the lock as Abandoned rather than leaving stale state:

`​`​`bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/hooks/scope-lock-abandon" docs/plans/<plan>.md \
    --reason "user pivoted away from feature X"
`​`​`

Differs from `scope-lock-complete`:

- Does NOT verify the manifest hash. Drift is expected.
- Flips `Status:` to `Abandoned <UTC> — <reason>`.
- Requires `--reason` (non-empty); sanitized to single line, capped at 200
  chars, with `**` replaced by `__`.
- Appends `phase-progress.jsonl` with `st:"abandoned"` + reason.
- Does NOT write an ADR.

Abandoned plans are not auto-revivable. To restart abandoned work, edit the
status line back to Locked by hand and re-run `scope-lock-apply`; the original
lock hash is unrecoverable.
```

(Replace `​` with nothing — the zero-width joiners above prevent the rendered
plan-doc parser from confusing nested fences with this plan's own fences.)

Update the `## Lock state machine` diagram to add an `Abandoned` terminal state alongside `Complete`. In `## Integration` → **Reads/Writes**, add `hooks/scope-lock-claim`, `hooks/scope-lock-abandon`, and note that `pre-tool-scope-guard`'s `SESSION_LOCK_RECOGNIZED` variable is the source of truth for which helper names update session-lock state.

**Step 2: Sanity-check the SKILL.md additions.**

Run: `grep -q '^## Claiming an Existing Lock' skills/scope-lock/SKILL.md && grep -q '^## Abandoning a Lock' skills/scope-lock/SKILL.md && echo OK`
Expected: `OK`

**Step 3: Run the full test suite.**

Run: `bash tests/hook-contracts.sh 2>&1 | tee /tmp/hook-contracts.out; grep -c '^FAIL:' /tmp/hook-contracts.out`
Expected: PASS lines for every test (existing + new), 0 FAIL.

Run: `bash tests/plan-scope-check.sh --plan docs/plans/2026-05-26-session-scoped-lock-nag.md`
Expected: exit 0, no output (or only PASS lines).

**Step 4: Commit.**

```bash
git add skills/scope-lock/SKILL.md
git commit -m "docs(scope-lock): document scope-lock-claim and scope-lock-abandon"
```

---

## Verification summary

| Task | Class | Verification |
|------|-------|-------------|
| 1-5 | Hook / trigger / event handler | per-test grep against `bash tests/hook-contracts.sh`; all PASS |
| 6-7 | Hook / trigger / event handler | same; helper exits 0 with sentinel token in stdout |
| 8 | Multi-component boundary | end-to-end triplet (claim→nag, abandon→silence, fresh→silent) |
| 9 | Documentation / comments | grep anchor + full suite green |

No tasks trigger `runtime-launch-validation` (no build/deploy/migration/startup-config changes). No per-task rollback notes required. Plugin rollback is by revert + bump (design `## Rollback`).
