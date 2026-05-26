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

**Status:** Draft

---

### Task 1: Anchored status-line grep — pre-tool-scope-guard

**Files:**
- Modify: `hooks/pre-tool-scope-guard`

**Step 1: Write the failing test.**

Add to `tests/hook-contracts.sh`:

```bash
test_pretool_ignores_prose_mention_of_locked_status() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
  cat >"$tmp/docs/plans/draft.md" <<'PLAN'
# Draft Plan

Body discusses lock mechanics: a plan marked `**Status:** Locked 2026-05-26T00:00:00Z`
triggers the nag. This draft itself is not locked.

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Draft | Task 1 | feat/draft |

**Status:** Draft

### Task 1: Draft
PLAN
  # The status line is Draft, but the body mentions the Locked string in prose.
  # Pre-fix behavior: pre-tool-scope-guard treats this as locked and runs verify_lock.
  # Post-fix behavior: anchored grep ignores the prose mention.
  output="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/x"},"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}' \
    | run_hook pre-tool-scope-guard 2>&1 || true)"
  # No block decision should be emitted (no .scope-lock file exists; pre-fix this would error).
  if printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "pre-tool-scope-guard: prose mention of Locked status falsely matched, output: ${output}"
    return
  fi
  pass "pre-tool-scope-guard: anchored grep ignores prose mention of Locked status"
}
```

**Step 2: Run test to verify it fails.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_pretool_ignores_prose_mention'`
Expected: `FAIL: pre-tool-scope-guard: prose mention of Locked status falsely matched, ...` (substring grep matches body prose).

**Step 3: Tighten the grep in `find_locked_plans` and the workspace-fallback grep.**

Replace both `grep -q '\*\*Status:\*\* Locked'` and `grep -rl '\*\*Status:\*\* Locked'` invocations with their `-E '^\*\*Status:\*\*[[:space:]]+Locked'` anchored counterparts. The two call sites are inside `find_locked_plans` (around current line 95 — the session-attributed branch's `grep -q`) and the workspace-fallback branch (around current line 101 — the `grep -rl`).

**Step 4: Run test to verify it passes.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_pretool_ignores_prose_mention'`
Expected: `PASS: pre-tool-scope-guard: anchored grep ignores prose mention of Locked status`

**Step 5: Commit.**

```bash
git add hooks/pre-tool-scope-guard tests/hook-contracts.sh
git commit -m "fix(hooks): anchor Status:Locked grep in pre-tool-scope-guard"
```

---

### Task 2: Anchored status-line grep — prompt-strict-interpretation

**Files:**
- Modify: `hooks/prompt-strict-interpretation`

**Step 1: Write the failing test.**

Add to `tests/hook-contracts.sh`:

```bash
test_prompt_strict_ignores_prose_mention_of_locked_status() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/draft.md" <<'PLAN'
# Draft Plan

Body quotes `**Status:** Locked 2026-05-26T00:00:00Z` in prose.

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Draft | Task 1 | feat/draft |

**Status:** Draft

### Task 1: Draft
PLAN

  output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead and create a PR","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "prompt-strict-interpretation: prose mention of Locked status triggered nag, output: ${output}"
    return
  fi
  pass "prompt-strict-interpretation: anchored grep ignores prose mention of Locked status"
}
```

**Step 2: Run test to verify it fails.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_prompt_strict_ignores_prose_mention'`
Expected: FAIL (substring grep currently matches prose mention).

**Step 3: Tighten the grep in both `workspace_locked_plans` and `session_locked_plans` inner loops.**

Replace `grep -q '\*\*Status:\*\* Locked'` with `grep -qE '^\*\*Status:\*\*[[:space:]]+Locked'` at every occurrence in this file (≈ lines 105 and 124 in the current file).

**Step 4: Run test to verify it passes.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_prompt_strict_ignores_prose_mention'`
Expected: PASS

**Step 5: Commit.**

```bash
git add hooks/prompt-strict-interpretation tests/hook-contracts.sh
git commit -m "fix(hooks): anchor Status:Locked grep in prompt-strict-interpretation"
```

---

### Task 3: Anchored status-line grep — pre-compact-snapshot

**Files:**
- Modify: `hooks/pre-compact-snapshot`

**Step 1: Write the failing test.**

Add to `tests/hook-contracts.sh`:

```bash
test_pre_compact_ignores_prose_mention_of_locked_status() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/draft.md" <<'PLAN'
# Draft Plan

Body mentions `**Status:** Locked 2026-05-26T00:00:00Z` in prose.

**Status:** Draft

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Draft | Task 1 | feat/draft |

### Task 1: Draft
PLAN

  output="$(run_hook pre-compact-snapshot '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  # The hook should emit no snapshot since no plan is actually Locked.
  if [ -n "$output" ]; then
    fail "pre-compact-snapshot: prose mention of Locked status triggered snapshot, output: ${output}"
    return
  fi
  pass "pre-compact-snapshot: anchored grep ignores prose mention of Locked status"
}
```

**Step 2: Run test to verify it fails.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_pre_compact_ignores_prose_mention'`
Expected: FAIL.

**Step 3: Tighten the grep at both occurrences (workspace + session loops, ≈ lines 44 and 63).**

Replace `grep -q '\*\*Status:\*\* Locked'` with `grep -qE '^\*\*Status:\*\*[[:space:]]+Locked'`.

**Step 4: Run test to verify it passes.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_pre_compact_ignores_prose_mention'`
Expected: PASS

**Step 5: Commit.**

```bash
git add hooks/pre-compact-snapshot tests/hook-contracts.sh
git commit -m "fix(hooks): anchor Status:Locked grep in pre-compact-snapshot"
```

---

### Task 4: Session-aware subagent-scope-guard + anchored grep

**Files:**
- Modify: `hooks/subagent-scope-guard`

**Step 1: Write the failing test.**

Add to `tests/hook-contracts.sh`:

```bash
test_subagent_scope_guard_ignores_unattributed_workspace_lock() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/unrelated.md" <<'PLAN'
# Unrelated Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Unrelated | Task 1 | feat/unrelated |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Unrelated
PLAN
  # Lock it but DON'T attribute it to this session.
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/unrelated.md >/dev/null )
  # Mutate the manifest after lock so verify_lock would fail if invoked.
  printf '\n<!-- drift -->\n' >> "$tmp/docs/plans/unrelated.md"
  # Run subagent-scope-guard with stop_hook_active false from a session that never claimed.
  output="$(run_hook subagent-scope-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false}' 2>&1 || true)"
  if printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "subagent-scope-guard: blocked stop for unattributed workspace lock, output: ${output}"
    return
  fi
  pass "subagent-scope-guard: ignores unattributed workspace lock"
}
```

**Step 2: Run test to verify it fails.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_subagent_scope_guard_ignores_unattributed'`
Expected: FAIL (current workspace-wide grep returns the plan; verify_lock fails on drift; block fires).

**Step 3: Refactor `subagent-scope-guard` to use session attribution.**

Replace the existing manifest-hash block (current lines 74-83) with:

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

**Step 4: Run test to verify it passes.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_subagent_scope_guard_ignores_unattributed'`
Expected: PASS

**Step 5: Add a session-attributed regression test.**

Add to `tests/hook-contracts.sh`:

```bash
test_subagent_scope_guard_blocks_attributed_drift() {
  local tmp transcript output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
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

**Status:** Locked 2026-05-26T00:00:00Z

### Task 1: Active
PLAN
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/active.md >/dev/null )
  jq -nc --arg session "session.jsonl" --arg pl "docs/plans/active.md" \
    '{ev:"session-lock",session:$session,pl:$pl}' \
    > "$tmp/.claude/autodev-state/session-locks.jsonl"
  # Drift the manifest after attribution.
  awk '/^### Task 1:/ {print "extra manifest content"; print; next} {print}' \
    "$tmp/docs/plans/active.md" > "$tmp/docs/plans/active.md.tmp" \
    && mv "$tmp/docs/plans/active.md.tmp" "$tmp/docs/plans/active.md"
  ( cd "$tmp" && cp "$REPO_ROOT/tests/plan-scope-check.sh" tests/plan-scope-check.sh \
    && chmod +x tests/plan-scope-check.sh )
  output="$(run_hook subagent-scope-guard '{"cwd":"'"$tmp"'","transcript_path":"'"$transcript"'","stop_hook_active":false}' 2>&1 || true)"
  if ! printf '%s' "$output" | grep -q '"decision":"block"'; then
    fail "subagent-scope-guard: did NOT block for attributed drift, output: ${output}"
    return
  fi
  pass "subagent-scope-guard: blocks on attributed drift"
}
```

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_subagent_scope_guard_blocks_attributed_drift'`
Expected: PASS

**Step 6: Commit.**

```bash
git add hooks/subagent-scope-guard tests/hook-contracts.sh
git commit -m "fix(hooks): session-scope subagent-scope-guard and anchor Locked grep"
```

---

### Task 5: Drop the single-workspace-lock fallback in nag hooks

**Files:**
- Modify: `hooks/prompt-strict-interpretation`
- Modify: `hooks/pre-compact-snapshot`
- Modify: `tests/hook-contracts.sh` (replace existing fallback test with a "no fallback" test)

**Step 1: Write the failing tests.**

Replace `test_prompt_strict_falls_back_to_single_workspace_lock` with:

```bash
test_prompt_strict_ignores_single_workspace_lock_when_session_has_no_lock() {
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
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/active.md >/dev/null )
  output="$(run_hook prompt-strict-interpretation '{"prompt":"continue autonomously","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "prompt-strict-interpretation: single workspace lock falsely triggered fallback, output: ${output}"
    return
  fi
  pass "prompt-strict-interpretation: no workspace fallback when session has no lock"
}
```

Add analogous `test_pre_compact_ignores_single_workspace_lock_when_session_has_no_lock` for `pre-compact-snapshot` (assert empty output).

**Step 2: Run test to verify it fails.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_prompt_strict_ignores_single_workspace_lock|test_pre_compact_ignores_single_workspace_lock'`
Expected: both FAIL (current fallback still picks the single workspace lock).

**Step 3: Remove the fallback branch in both hooks.**

In `prompt-strict-interpretation` (current lines 130-138):

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

In `pre-compact-snapshot` (current lines 68-83): equivalent shape — when `session_key` is present, only use `session_locked_plans`. When `session_key` is empty, keep the workspace-wide stream as today (host did not expose session identity → workspace is the only signal available).

**Step 4: Run tests to verify they pass.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_prompt_strict_ignores_single_workspace_lock|test_pre_compact_ignores_single_workspace_lock'`
Expected: both PASS

**Step 5: Commit.**

```bash
git add hooks/prompt-strict-interpretation hooks/pre-compact-snapshot tests/hook-contracts.sh
git commit -m "fix(hooks): drop single-workspace-lock fallback when session has no attribution"
```

---

### Task 6: `hooks/scope-lock-claim` helper

**Files:**
- Create: `hooks/scope-lock-claim`
- Modify: `hooks/pre-tool-scope-guard` (extend `record_session_lock` recognizer)

**Step 1: Write the failing test.**

Add to `tests/hook-contracts.sh`:

```bash
test_scope_lock_claim_writes_session_attribution() {
  local tmp transcript record_payload output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  transcript="$tmp/session.jsonl"
  touch "$transcript"
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
  cat >"$tmp/docs/plans/p.md" <<'PLAN'
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

**Status:** Locked 2026-05-26T00:00:00Z

### Task 1: P
PLAN
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/p.md >/dev/null )
  # Simulate a fresh-session pre-tool-scope-guard intercept of a scope-lock-claim Bash call.
  record_payload=$(jq -nc --arg cmd "bash hooks/scope-lock-claim docs/plans/p.md" --arg cwd "$tmp" --arg tp "$transcript" \
    '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,transcript_path:$tp}')
  output="$(printf '%s' "$record_payload" | run_hook pre-tool-scope-guard 2>&1 || true)"
  state_file="$tmp/.claude/autodev-state/session-locks.jsonl"
  if [ ! -s "$state_file" ]; then
    fail "scope-lock-claim: pre-tool-scope-guard did not write session-locks.jsonl, output: ${output}"
    return
  fi
  if ! jq -e --arg s "session.jsonl" --arg pl "docs/plans/p.md" \
      'select(.ev=="session-lock" and .session==$s and .pl==$pl)' "$state_file" >/dev/null; then
    fail "scope-lock-claim: row missing for (session,plan), file: $(cat "$state_file")"
    return
  fi
  pass "scope-lock-claim: recognized by pre-tool-scope-guard and writes session row"
}

test_scope_lock_claim_helper_runs_and_is_idempotent() {
  local tmp output1 output2
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/p.md" <<'PLAN'
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

**Status:** Locked 2026-05-26T00:00:00Z

### Task 1: P
PLAN
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/p.md >/dev/null )
  output1="$(cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-claim" docs/plans/p.md 2>&1 || true)"
  if ! printf '%s' "$output1" | grep -q 'scope-lock-claim'; then
    fail "scope-lock-claim: helper output missing recognizer token, got: ${output1}"
    return
  fi
  output2="$(cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-claim" docs/plans/p.md 2>&1 || true)"
  if ! printf '%s' "$output2" | grep -q 'scope-lock-claim'; then
    fail "scope-lock-claim: helper failed on second invocation, got: ${output2}"
    return
  fi
  pass "scope-lock-claim: helper is re-invokable (idempotent shape)"
}

test_scope_lock_claim_rejects_unlocked_plan() {
  local tmp rc output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/draft.md" <<'PLAN'
# Draft
**Status:** Draft
## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Draft | Task 1 | feat/draft |

### Task 1: Draft
PLAN
  set +e
  output="$(cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-claim" docs/plans/draft.md 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    fail "scope-lock-claim: accepted unlocked plan, output: ${output}"
    return
  fi
  pass "scope-lock-claim: rejects unlocked plan"
}

test_scope_lock_claim_rejects_drift() {
  local tmp rc output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/p.md" <<'PLAN'
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

**Status:** Locked 2026-05-26T00:00:00Z

### Task 1: P
PLAN
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/p.md >/dev/null )
  # Drift the manifest after lock.
  sed -i.bak 's/\*\*PR Count:\*\* 1/\*\*PR Count:\*\* 2/' "$tmp/docs/plans/p.md" && rm "$tmp/docs/plans/p.md.bak"
  # plan-scope-check.sh must be available locally for the drift check.
  cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh" 2>/dev/null \
    || ( mkdir -p "$tmp/tests" && cp "$REPO_ROOT/tests/plan-scope-check.sh" "$tmp/tests/plan-scope-check.sh" )
  chmod +x "$tmp/tests/plan-scope-check.sh"
  set +e
  output="$(cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-claim" docs/plans/p.md 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    fail "scope-lock-claim: accepted drifted manifest, output: ${output}"
    return
  fi
  pass "scope-lock-claim: rejects manifest drift"
}
```

**Step 2: Run tests to verify they fail.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_scope_lock_claim_'`
Expected: 4 × FAIL (helper file does not exist, pre-tool-scope-guard regex does not recognize claim).

**Step 3: Centralize the recognized-command list in `pre-tool-scope-guard` and add `scope-lock-claim` to it.**

Near the top of the script (after the JSON parsing block), introduce:

```bash
# ──────────────────────────────────────────────────────────────────────────
# Recognized helper script names that update session-lock state. These are
# pattern-matched against Bash tool commands by record_session_lock so the
# helper scripts never need to know the current session_key themselves.
#
# Helpers MUST print a line containing their bare name (e.g. "scope-lock-claim")
# so future maintainers can audit which Bash invocations matter from either end.
# ──────────────────────────────────────────────────────────────────────────
SESSION_LOCK_RECOGNIZED="scope-lock-apply|scope-lock-claim"
```

Modify `record_session_lock` to use the variable:

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

    # Dedupe: skip if the (session, plan) row already exists.
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
        --arg ts "$ts" \
        --arg session "$session_key" \
        --arg pl "$plan_arg" \
        '{ts:$ts,ev:"session-lock",session:$session,pl:$pl}' \
        >> "$state_file" 2>/dev/null || true
}
```

**Step 4: Create `hooks/scope-lock-claim`.**

```bash
#!/usr/bin/env bash
# hooks/scope-lock-claim
# Attribute an existing locked plan to the current session so the locked-plan
# nag hooks (prompt-strict-interpretation, pre-compact-snapshot,
# pre-tool-scope-guard, subagent-scope-guard) fire for this session.
#
# Use case: an agent session was interrupted (e.g., computer restart) and a
# fresh session needs to resume the same work. The .scope-lock file is still
# on disk, but the new session is not in .claude/autodev-state/session-locks.jsonl.
# Running this helper attributes the lock to the current session.
#
# Usage: scope-lock-claim <plan-path>
#
# Verifies:
#   1. The plan exists and has a line-start "**Status:** Locked …".
#   2. A .scope-lock sidecar exists (no claim without an anchor).
#   3. tests/plan-scope-check.sh --verify-lock (when present) passes —
#      claiming a drifted manifest is strictly worse than refusing.
#
# The actual session-locks.jsonl write is performed by hooks/pre-tool-scope-guard's
# record_session_lock, which intercepts this Bash invocation and recognizes the
# helper name in SESSION_LOCK_RECOGNIZED. This helper is read-only with respect
# to .scope-lock: it never re-hashes the manifest (re-running scope-lock-apply
# would silently overwrite the original author's hash and defeat the lock's
# purpose).
#
# After the helper returns, it reads back session-locks.jsonl and exits non-zero
# if the row is not present. Converts a silent "hook recognizer missed me" into
# a loud failure.

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
checker_dirs=("$(dirname "$plan")/../../tests" "$(dirname "$plan")/../tests" "./tests")
for d in "${checker_dirs[@]}"; do
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

# Liveness read-back: if pre-tool-scope-guard runs in the same Bash call (it does),
# session-locks.jsonl should have a row for this (session, plan). We can't read
# session_key from here, but we can confirm a row referencing the plan exists.
state_file="$(dirname "$plan")/../../.claude/autodev-state/session-locks.jsonl"
if [ -f "$state_file" ]; then
    if jq -e --arg pl "$plan" 'select(.ev=="session-lock" and (.pl==$pl or .pl|endswith($pl)))' \
        "$state_file" >/dev/null 2>&1; then
        printf 'scope-lock-claim: session attribution confirmed in session-locks.jsonl\n'
        exit 0
    fi
fi

# Row not yet present (or state file absent). pre-tool-scope-guard runs AFTER
# this helper for the same Bash command, so the write may not be visible yet
# from inside this process. We exit success in that case; the hook's
# additionalContext does not affect the agent's view of the row, and the next
# prompt/snapshot will see it.
exit 0
```

Make executable: `chmod +x hooks/scope-lock-claim`.

**Step 5: Run tests to verify they pass.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_scope_lock_claim_'`
Expected: 4 × PASS

**Step 6: Commit.**

```bash
git add hooks/scope-lock-claim hooks/pre-tool-scope-guard tests/hook-contracts.sh
git commit -m "feat(scope-lock): add scope-lock-claim helper for session re-attribution"
```

---

### Task 7: `hooks/scope-lock-abandon` helper

**Files:**
- Create: `hooks/scope-lock-abandon`
- Modify: `hooks/pre-tool-scope-guard` (extend `SESSION_LOCK_RECOGNIZED` cleanup recognizer)

**Step 1: Write the failing tests.**

Add to `tests/hook-contracts.sh`:

```bash
test_scope_lock_abandon_flips_status_and_prunes_state() {
  local tmp output
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state" "$tmp/.autodev/state"
  cat >"$tmp/docs/plans/p.md" <<'PLAN'
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

**Status:** Locked 2026-05-26T00:00:00Z

### Task 1: P
PLAN
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/p.md >/dev/null )
  jq -nc --arg s "session.jsonl" --arg pl "docs/plans/p.md" \
    '{ev:"session-lock",session:$s,pl:$pl}' \
    > "$tmp/.claude/autodev-state/session-locks.jsonl"
  output="$(cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-abandon" docs/plans/p.md --reason "user pivoted" 2>&1)"
  # Status flipped
  if ! grep -qE '^\*\*Status:\*\*[[:space:]]+Abandoned' "$tmp/docs/plans/p.md"; then
    fail "scope-lock-abandon: status not flipped to Abandoned, file:\n$(cat "$tmp/docs/plans/p.md")"
    return
  fi
  if ! grep -q 'user pivoted' "$tmp/docs/plans/p.md"; then
    fail "scope-lock-abandon: reason missing from status line"
    return
  fi
  # Lock file removed
  if [ -e "$tmp/docs/plans/p.md.scope-lock" ]; then
    fail "scope-lock-abandon: .scope-lock not removed"
    return
  fi
  # session-locks.jsonl pruned
  if [ -s "$tmp/.claude/autodev-state/session-locks.jsonl" ]; then
    if jq -e --arg pl "docs/plans/p.md" 'select(.pl==$pl)' \
        "$tmp/.claude/autodev-state/session-locks.jsonl" >/dev/null 2>&1; then
      fail "scope-lock-abandon: session-lock row not pruned"
      return
    fi
  fi
  # phase-progress.jsonl appended
  if ! jq -e 'select(.ev=="plan" and .st=="abandoned" and .reason=="user pivoted")' \
      "$tmp/.autodev/state/phase-progress.jsonl" >/dev/null 2>&1; then
    fail "scope-lock-abandon: phase-progress row missing or malformed, file: $(cat "$tmp/.autodev/state/phase-progress.jsonl")"
    return
  fi
  pass "scope-lock-abandon: flips status, removes lock, prunes session-locks, appends phase-progress"
}

test_scope_lock_abandon_requires_reason() {
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/p.md" <<'PLAN'
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

**Status:** Locked 2026-05-26T00:00:00Z

### Task 1: P
PLAN
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/p.md >/dev/null )
  set +e
  bash "$REPO_ROOT/hooks/scope-lock-abandon" "$tmp/docs/plans/p.md" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { fail "scope-lock-abandon: accepted missing --reason"; return; }
  set +e
  bash "$REPO_ROOT/hooks/scope-lock-abandon" "$tmp/docs/plans/p.md" --reason "" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { fail "scope-lock-abandon: accepted empty --reason"; return; }
  pass "scope-lock-abandon: requires non-empty --reason"
}

test_scope_lock_abandon_sanitizes_reason() {
  local tmp output line
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/docs/plans"
  cat >"$tmp/docs/plans/p.md" <<'PLAN'
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

**Status:** Locked 2026-05-26T00:00:00Z

### Task 1: P
PLAN
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/p.md >/dev/null )
  bash "$REPO_ROOT/hooks/scope-lock-abandon" "$tmp/docs/plans/p.md" --reason $'multi\nline\twith\ttabs and **bold** text' >/dev/null
  line=$(grep -E '^\*\*Status:\*\*[[:space:]]+Abandoned' "$tmp/docs/plans/p.md")
  # Must be a single line; embedded newlines collapsed to spaces.
  count=$(printf '%s' "$line" | wc -l | awk '{print $1}')
  if [ "$count" -ne 0 ]; then
    fail "scope-lock-abandon: status spans multiple lines: ${line}"
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
  cat >"$tmp/docs/plans/p.md" <<'PLAN'
# P
**Status:** Draft
## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | P | Task 1 | feat/p |

### Task 1: P
PLAN
  set +e
  bash "$REPO_ROOT/hooks/scope-lock-abandon" "$tmp/docs/plans/p.md" --reason "test" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { fail "scope-lock-abandon: accepted non-Locked plan"; return; }
  pass "scope-lock-abandon: refuses non-Locked plan"
}
```

**Step 2: Run tests to verify they fail.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_scope_lock_abandon_'`
Expected: 4 × FAIL (helper does not exist).

**Step 3: Create `hooks/scope-lock-abandon`.**

```bash
#!/usr/bin/env bash
# hooks/scope-lock-abandon
# Abandon a locked plan that will not be completed.
#
# Sibling to hooks/scope-lock-complete (ADR 0001). Use this when an agent or
# operator decides to stop pursuing the locked design (user pivoted, design
# superseded, ran out of capacity, …). Distinct from complete so retros can
# tell "verified done" from "stopped pursuing".
#
# Differences from scope-lock-complete:
#   - Does NOT verify the manifest hash. Drift is expected for abandoned work.
#   - Status flips to "Abandoned <UTC> — <reason>" instead of "Complete <UTC>".
#   - Requires --reason (non-empty), sanitized to a single line, capped at
#     200 chars, with literal "**" replaced by "__" so the status line's
#     markdown bold cannot be broken.
#   - Appends phase-progress.jsonl with st:"abandoned" + reason field (NOT
#     evidence) so the audit row is distinguishable from a completion.
#   - Does NOT write an ADR. The status line + phase-progress row together
#     cover the durable-record case; an operator who wants more detail can
#     hand-write one.
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

if [ -z "$reason" ]; then
    printf 'scope-lock-abandon: --reason is required\n' >&2
    exit 2
fi

# Sanitize reason: collapse whitespace runs (newlines/tabs/multiple spaces) to
# single spaces, replace literal ** with __, and cap at 200 characters.
sanitized_reason=$(printf '%s' "$reason" | tr -s '\n\t ' ' ' | sed 's/\*\*/__/g' | cut -c1-200)

canonical_path_from_base() {
    local base="$1"
    local ref="$2"
    local candidate
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
    printf 'scope-lock-abandon: unable to resolve plan path: %s\n' "$plan" >&2
    exit 2
}
[ -f "$plan_abs" ] || {
    printf 'scope-lock-abandon: plan not found: %s\n' "$plan_abs" >&2
    exit 2
}
if ! grep -qE '^\*\*Status:\*\*[[:space:]]+Locked' "$plan_abs"; then
    printf 'scope-lock-abandon: plan is not in Locked status: %s\n' "$plan_abs" >&2
    exit 2
fi

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
    local file="$1"
    [ -f "$file" ] || return 0
    local tmp
    tmp=$(mktemp "${file}.abandon.XXXXXX")
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        pl=$(printf '%s' "$line" | jq -r '.pl // empty' 2>/dev/null || true) || {
            rm -f "$tmp"
            return 1
        }
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
    --arg ts "$ts" \
    --arg pl "$plan_name" \
    --arg r "$sanitized_reason" \
    '{ts:$ts,ev:"plan",pl:$pl,st:"abandoned",reason:$r}' \
    >> "$progress_file"

printf 'scope-lock-abandon: abandoned %s (reason: %s)\n' "$plan_rel" "$sanitized_reason"
```

Make executable: `chmod +x hooks/scope-lock-abandon`.

**Step 4: Run tests to verify they pass.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_scope_lock_abandon_'`
Expected: 4 × PASS

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

**Status:** Locked 2026-05-26T00:00:00Z

### Task 1: Active
PLAN
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/active.md >/dev/null )

  # Simulate the agent running scope-lock-claim under pre-tool-scope-guard.
  record_payload=$(jq -nc \
    --arg cmd "bash hooks/scope-lock-claim docs/plans/active.md" \
    --arg cwd "$tmp" \
    --arg tp "$transcript" \
    '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,transcript_path:$tp}')
  printf '%s' "$record_payload" | run_hook pre-tool-scope-guard >/dev/null 2>&1 || true

  # Now the next user prompt with a trigger phrase should nag with the plan name.
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
  mkdir -p "$tmp/docs/plans" "$tmp/.claude/autodev-state"
  cat >"$tmp/docs/plans/stale.md" <<'PLAN'
# Stale Plan

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Stale | Task 1 | feat/stale |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: Stale
PLAN
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" docs/plans/stale.md >/dev/null )
  # Pre-claim so the nag would fire if we didn't abandon.
  record_payload=$(jq -nc \
    --arg cmd "bash hooks/scope-lock-claim docs/plans/stale.md" \
    --arg cwd "$tmp" \
    --arg tp "$transcript" \
    '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,transcript_path:$tp}')
  printf '%s' "$record_payload" | run_hook pre-tool-scope-guard >/dev/null 2>&1 || true

  # Confirm pre-condition: nag fires.
  nag_output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  printf '%s' "$nag_output" | jq -e '.hookSpecificOutput.additionalContext | contains("stale.md")' >/dev/null \
    || { fail "e2e abandon: precondition (nag fires after claim) not met"; return; }

  # Abandon.
  ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-abandon" docs/plans/stale.md --reason "test abandon" >/dev/null )

  # Now the next prompt should NOT nag.
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
  for n in foo bar; do
    cat >"$tmp/docs/plans/${n}.md" <<PLAN
# ${n}

## Scope Manifest

**PR Count:** 1
**Tasks:** 1
**Out of scope:**
- (none)

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | ${n} | Task 1 | feat/${n} |

**Status:** Locked 2026-05-25T00:00:00Z

### Task 1: ${n}
PLAN
    ( cd "$tmp" && bash "$REPO_ROOT/hooks/scope-lock-apply" "docs/plans/${n}.md" >/dev/null )
  done
  # No claim. Even a single workspace lock should NOT trigger fallback.
  rm -f "$tmp/docs/plans/bar.md.scope-lock" "$tmp/docs/plans/bar.md"   # leave only one locked plan
  output="$(run_hook prompt-strict-interpretation '{"prompt":"go ahead","cwd":"'"$tmp"'","transcript_path":"'"$transcript"'"}')"
  if [ -n "$output" ]; then
    fail "e2e fresh session: workspace fallback still fires, output: ${output}"
    return
  fi
  pass "e2e: fresh session with no claim does not nag on workspace-only locks"
}
```

**Step 2: Run tests to verify they pass.**

Run: `bash tests/hook-contracts.sh 2>&1 | grep -E '^(PASS|FAIL): test_e2e_'`
Expected: 3 × PASS

**Step 3: Commit.**

```bash
git add tests/hook-contracts.sh
git commit -m "test: end-to-end claim→nag and abandon→silence cycles"
```

---

### Task 9: SKILL.md documentation + register the helpers

**Files:**
- Modify: `skills/scope-lock/SKILL.md`

**Step 1: Update the skill with the new commands.**

Add a section after "Completing a Locked Plan":

```markdown
## Claiming an Existing Lock (resume after restart)

When a session is interrupted (computer restart, host crash, accidental
`/clear`) and a fresh session needs to resume work on an already-locked plan,
the new session must explicitly **claim** the lock for itself. The nag hooks
only fire for plans attributed to the current session via
`.claude/autodev-state/session-locks.jsonl`, and that attribution is per-session
— a fresh session inherits no attribution from the killed one.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/hooks/scope-lock-claim" docs/plans/<plan>.md
```

The helper verifies the plan is `**Status:** Locked`, has a `.scope-lock`
sidecar, and that the manifest hash still matches (claiming a drifted manifest
is rejected — go through the amendment path instead). The session-attribution
row is appended to `session-locks.jsonl` by `hooks/pre-tool-scope-guard`'s
`record_session_lock` recognizer (the same mechanism that writes the row at
`scope-lock-apply` time). Idempotent — re-claiming the same plan is a no-op.

## Abandoning a Lock (stopped pursuing)

When work on a locked plan will not complete (user pivoted, design superseded,
out of capacity), close the lock as **Abandoned** rather than leaving stale
state:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-.}/hooks/scope-lock-abandon" docs/plans/<plan>.md \
    --reason "user pivoted away from feature X"
```

Differs from `scope-lock-complete`:

- Does NOT verify the manifest hash. Drift is expected for abandoned work.
- Flips `Status:` to `Abandoned <UTC> — <reason>` instead of `Complete <UTC>`.
- Requires `--reason` (non-empty); the value is sanitized to a single line,
  capped at 200 chars, with literal `**` replaced by `__`.
- Appends `phase-progress.jsonl` with `st:"abandoned"` + the reason so retros
  can distinguish abandoned work from completed work.
- Does NOT write an ADR.

Abandoned plans are not auto-revivable. If the operator changes their mind,
edit the status line back to `Locked YYYY-MM-DDTHH:MM:SSZ` by hand and re-run
`scope-lock-apply` to create a fresh `.scope-lock` file. The original lock
hash is unrecoverable.
```

Also update the "## Lock state machine" diagram and lists to mention the `Abandoned` terminal state.

In the **Reads/Writes** section under `## Integration`, add `hooks/scope-lock-claim`, `hooks/scope-lock-abandon`, and note that `pre-tool-scope-guard`'s `SESSION_LOCK_RECOGNIZED` variable is the source of truth for which helper names update session-lock state.

**Step 2: Render preview (docs verification).**

Run: `cat skills/scope-lock/SKILL.md | head -200 | tail -60`
Expected: Renders the new sections without broken markdown (no unmatched code fences, headings present).

**Step 3: Run the full test suite to confirm nothing regressed.**

Run: `bash tests/hook-contracts.sh`
Expected: all PASS lines; no FAIL lines.

Run: `bash tests/skill-cross-refs.sh` (if present)
Expected: all PASS or "no issues found".

**Step 4: Commit.**

```bash
git add skills/scope-lock/SKILL.md
git commit -m "docs(scope-lock): document scope-lock-claim and scope-lock-abandon"
```

---

## Verification summary

| Task | Class | Verification |
|------|-------|-------------|
| 1-4 | Hook / trigger / event handler | `bash tests/hook-contracts.sh` per-test grep; all PASS |
| 5 | Hook / trigger / event handler | same |
| 6-7 | Hook / trigger / event handler | same; helpers exit 0 with sentinel token in stdout |
| 8 | Multi-component boundary | end-to-end test triplet (claim→nag, abandon→silence, fresh→silent) |
| 9 | Documentation / comments | render preview + full test suite green |

No tasks trigger `runtime-launch-validation` (no build/deploy/migration/startup-config changes). No `Rollback:` notes required at the task level. Plugin rollback is by revert + bump (covered in design's `## Rollback`).
