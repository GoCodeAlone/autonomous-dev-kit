# Session-Owned Lock Claims Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Prevent resumed/fresh sessions from accidentally claiming another session's locked plan unless the recorded objective matches or the user explicitly re-anchors the handoff.

**Architecture:** Extend existing bash hook/session-lock machinery. `pre-tool-scope-guard` records owner metadata and blocks claim mismatches; `session-start` surfaces a resume checkpoint; `scope-lock-claim` accepts `--confirmed`; scope-lock docs explain cross-harness behavior.

**Tech Stack:** Bash, jq, git, shasum/sha256sum, existing hook contract tests.

**Base branch:** main

---

## Scope Manifest

**PR Count:** 1
**Tasks:** 4
**Estimated Lines of Change:** ~260

**Out of scope:**
- Lock servers, leases, or active-process detection.
- Changing Scope Manifest hashing or `.scope-lock` first-hash compatibility.
- Auto-detecting semantic task equivalence across unrelated prompts.

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | fix(scope-lock): require objective match for claims | Task 1, Task 2, Task 3, Task 4 | fix/issue-52-session-ownership |

**Status:** Complete 2026-05-31T18:14:36Z

---

### Task 1: Claim Ownership Regression Tests

**Files:**
- Modify: `tests/hook-contracts.sh`

**Step 1: Write failing tests**

Add transcript fixture helpers and tests:

```bash
write_transcript_with_user() {
  local path="$1" text="$2"
  jq -nc --arg text "$text" '{type:"user",message:{content:$text}}' > "$path"
}

test_scope_lock_claim_blocks_objective_mismatch() {
  # existing row objective A; current transcript objective B; claim blocks.
}

test_scope_lock_claim_allows_matching_objective() {
  # existing row objective A; current transcript objective A; claim writes row.
}

test_scope_lock_claim_confirmed_allows_objective_mismatch() {
  # existing row objective A; current transcript objective B; --confirmed writes row.
}
```

**Step 2: Verify RED**

Run: `tests/hook-contracts.sh`

Expected: the three new tests fail because claims do not inspect objective metadata.

**Step 3: Commit tests**

```bash
git add tests/hook-contracts.sh
git commit -m "test(scope-lock): cover objective-bound claims"
```

### Task 2: Objective-Aware Claim Guard

**Files:**
- Modify: `hooks/pre-tool-scope-guard`
- Modify: `hooks/scope-lock-claim`

**Step 1: Implement**

- Add helpers to extract/normalize/hash the transcript's latest user-visible
  message.
- Record `repo`, `branch`, `objective_sha256`, `objective_excerpt`, and
  `confirmed` in `session-locks.jsonl`.
- Before appending a `scope-lock-claim` row, block when an existing row for the
  plan has a different or missing objective hash and the command lacks
  `--confirmed`.
- Update `scope-lock-claim` usage to accept `--confirmed`.

**Step 2: Verify GREEN**

Run: `tests/hook-contracts.sh`

Expected: all hook contract tests pass.

**Step 3: Regression invariant**

Revert only `hooks/pre-tool-scope-guard` and rerun the three tests.

Expected: mismatch test fails, proving the test catches issue #52.

**Step 4: Commit**

```bash
git add hooks/pre-tool-scope-guard hooks/scope-lock-claim
git commit -m "fix(scope-lock): require objective match for claims"
```

### Task 3: Resume Target Checkpoint

**Files:**
- Modify: `hooks/session-start`
- Modify: `tests/hook-contracts.sh`

**Step 1: Write failing test**

Add a compact/resume test that seeds `session-locks.jsonl`, invokes
`session-start`, and expects `Resume target checkpoint`, repo/branch, current
objective excerpt, and "lock snapshots are not ownership proof" in
`additionalContext`.

Run: `tests/hook-contracts.sh`

Expected: new test fails before `session-start` emits the checkpoint.

**Step 2: Implement**

Add compact/resume checkpoint text using transcript objective + attributed
session locks.

**Step 3: Verify**

Run: `tests/hook-contracts.sh`

Expected: all hook contract tests pass.

**Step 4: Commit**

```bash
git add hooks/session-start tests/hook-contracts.sh
git commit -m "fix(session-start): emit resume target checkpoint"
```

### Task 4: Documentation, Alignment, Full Verification

**Files:**
- Modify: `skills/scope-lock/SKILL.md`
- Modify: `README.md`
- Modify: `RELEASE-NOTES.md`

**Step 1: Update docs**

Document:
- owner metadata in session-lock rows;
- objective-match claim rule;
- `scope-lock-claim --confirmed` for user-directed handoff;
- resume checkpoint behavior.

**Step 2: Verify**

Run:

```bash
tests/hook-contracts.sh
tests/skill-cross-refs.sh
tests/skill-content-grep.sh
tests/plan-scope-check.sh --plan docs/plans/2026-05-31-session-owned-lock-claims.md
```

Expected:
- `All hook contract tests passed.`
- cross refs/content grep exit 0.
- plan scope check exit 0.

**Rollback:** revert PR; extra JSONL fields are ignored by older releases.

**Step 3: Commit**

```bash
git add skills/scope-lock/SKILL.md README.md RELEASE-NOTES.md docs/plans/2026-05-31-session-owned-lock-claims*.md decisions/0002-lock-claims-require-objective-match.md
git commit -m "docs(scope-lock): document session-owned lock claims"
```
