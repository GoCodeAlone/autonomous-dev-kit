---
name: scope-lock
description: Use whenever the autonomous pipeline reaches alignment-check PASS - locks the plan's task list, PR count, and feature scope so the executing agent cannot silently rescope, collapse PRs, or ship partial work as a "demo" without explicit user approval recorded as an ADR
---

# Scope Lock

## Overview

After `alignment-check` passes, the implementation plan is **locked**: task list, PR count, and feature scope are immutable until the work completes (or the user explicitly approves a reduction). This skill defines what "locked" means, what unlocks it, and how the rest of the pipeline must behave under the lock.

**Why this skill exists:** observed failure mode — an agent told to "continue autonomously, create a PR, also test locally, reorder as needed" interpreted "reorder as needed" as license to rescope, collapsed a 6-PR plan into a single PR, and shipped a partial-scope solution as a "demo". Each step looked plausible in isolation. Cumulatively the agent went off the rails. The lock makes each of those steps individually visible and individually blockable.

**Core principle:** the plan is the contract. Once `alignment-check` says it covers the design and only the design, the pipeline executes the contract — it does not renegotiate it.

## When to use

Invoked automatically by `alignment-check` immediately after it returns PASS. Also invoked manually by any subsequent skill (`subagent-driven-development`, `finishing-a-development-branch`) before performing an action that depends on the locked manifest (a task transition, a PR creation, a completion claim).

Manual invocation:

- **At lock time** (after alignment passes): stamp the plan and record the manifest hash.
- **At execution checkpoints** (between tasks): verify reality still matches the lock.
- **At completion time** (before PR creation): assert manifest is fully satisfied.
- **At unlock time** (user-approved scope reduction): record the reduction as an ADR, update the manifest, re-stamp.

## The Scope Manifest

The manifest is a section the plan author writes during `writing-plans`. After `alignment-check` PASS, it becomes immutable. Every plan MUST contain it. Plans without it fail the alignment check and `tests/plan-scope-check.sh`.

```markdown
## Scope Manifest

**PR Count:** N
**Tasks:** N
**Estimated Lines of Change:** ~N (informational; not enforced)

**Out of scope:**
- <explicit non-goal>
- <explicit non-goal>

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | <PR title> | Task 1, Task 2 | feat/<slug>-1 |
| 2 | <PR title> | Task 3, Task 4 | feat/<slug>-2 |
| ... | ... | ... | ... |

**Status:** Draft | Locked YYYY-MM-DDTHH:MM:SSZ | Reduced YYYY-MM-DDTHH:MM:SSZ (see decisions/NNNN)
```

Every plan task ID listed under `Tasks` in the table must exist in the plan body. Every task in the plan body must appear in exactly one PR row.

If the work is genuinely a single PR, the table has one row — the row still has to exist. Single-PR plans are not exempt from the manifest; they are exempt only from the multi-PR PR-count assertion.

## Lock state machine

```
                      alignment-check PASS
   Draft  ─────────────────────────────────► Locked
     ▲                                          │
     │                                          │  user approves scope reduction;
     │   alignment-check FAIL → revise          │  recording-decisions writes ADR;
     │                                          ▼
     │                                       Reduced
     │                                          │
     │                                          │  re-run alignment-check on the reduced plan
     └──────────────────────────────────────────┘
```

- **Draft**: the plan author is still revising. No execution is permitted.
- **Locked**: alignment passed. The manifest hash is recorded. Execution is permitted; renegotiation is not.
- **Reduced**: the user explicitly approved a scope reduction; an ADR was written; the manifest was updated; alignment was re-run on the reduced plan, which produced a new Locked stamp. The original Locked stamp is preserved in the ADR's Context for audit.

There is no "Expanded" state by design. Adding scope mid-flight requires going back to Draft (re-do brainstorming for the new scope). This is intentional friction.

## What the lock prohibits

While `Status: Locked …`, the following are **stop-the-line errors** for any pipeline skill:

1. **Dropping a task.** A task in the manifest cannot be skipped. If the agent encounters a task that turns out to be infeasible, it MUST surface this to the user and request a scope reduction (which goes through the unlock path, not a unilateral skip).
2. **Adding a task not in the manifest.** Discovering "we also need to do X" mid-execution is not a license to silently add X. Either X is already implied by an existing task (then it goes under that task) or X is new scope (then it goes through brainstorming + a new design + a new plan or an explicit manifest amendment).
3. **Collapsing PRs.** If the manifest has 3 PR rows, the autonomous pipeline must produce 3 PRs. Collapsing into 1 PR is a stop-the-line error even if "all the code is the same".
4. **Splitting a PR.** Same rule in reverse. The grouping table is the contract.
5. **Re-ordering tasks within the same PR is allowed.** Re-ordering tasks across PRs is **not** allowed without an unlock — it changes which task ships in which PR, which changes review boundaries.
6. **"Reorder as needed", "create a PR", "test locally", and similar imperative-but-vague user phrases do NOT authorize any of the above.** These phrases speak to *how* the agent runs the manifest, not to *what* is in the manifest. See the strict-interpretation rule in `using-superpowers`.

## Unlock path (user-approved scope reduction)

If during execution the agent or the user determines that a task or PR should be removed:

1. **Stop the line.** Pause execution; do not commit or push anything that depends on the dropped scope.
2. **Surface the proposed reduction explicitly.** State which tasks would be removed, which PRs are affected, and why. Do not paraphrase a vague user phrase as approval.
3. **Wait for explicit user confirmation.** "Yes, remove tasks 4 and 5" — exact tasks named, exact reduction acknowledged. Anything less than this MUST be treated as not-yet-approved.
4. **Invoke `recording-decisions`** with reduction-specific context: which tasks/PRs are dropped, what was rejected, what carries over (or gets re-planned). The ADR is the audit record.
5. **Update the manifest in place.** Remove the dropped task rows; update `**PR Count:**` and `**Tasks:**`; flip status to `Reduced YYYY-MM-DDTHH:MM:SSZ (see decisions/NNNN-...md)`.
6. **Re-run `alignment-check`** on the reduced plan. The reduced manifest must still cover every requirement in the (possibly also reduced) design. If the design was not also reduced, alignment will fail — that's the correct behavior. The user must reduce the design first via a new `brainstorming --design-only` pass.
7. **On alignment PASS,** the lock re-engages with a new `Locked` stamp.

The unlock path is intentionally heavyweight. Cheap unlock = no lock at all.

## Lock enforcement at each pipeline stage

**`alignment-check` (pre-lock and re-lock):**
- After PASS, edit the plan's `**Status:**` line to `Locked <UTC ISO-8601 timestamp>`.
- Write the lock file by running the helper via Bash (do **not** use the Write tool — the Write tool is blocked for `*.scope-lock` paths by the scope guard hook):
  ```
  bash "${CLAUDE_PLUGIN_ROOT}/hooks/scope-lock-apply" <plan-path>
  ```
  The helper extracts the `## Scope Manifest` section, computes its sha256, and writes `<plan-path>.scope-lock` via shell redirection. It prints the path and hash prefix on success, or an error message and exits non-zero on failure.
- Commit both files in the same commit: `chore: lock scope for <feature> (alignment passed)`.

**`subagent-driven-development` (per-task checkpoint):**
- Before dispatching the next task, run `tests/plan-scope-check.sh --verify-lock <plan-path>` to verify (a) the plan's manifest hash still matches `<plan-path>.scope-lock`, (b) every commit on the feature branch traces to a task in the manifest, (c) no manifest task is missing.
- On any FAIL, stop dispatching new work; surface the discrepancy to the user.
- After all tasks complete, run the same check before invoking `finishing-a-development-branch`.

**`finishing-a-development-branch` (Step 1d, see that skill):**
- Before any PR is created, assert the manifest is fully satisfied: every task's verification step has run; every task's commit is on the branch.
- In autonomous mode, the number of PRs created MUST equal the manifest's `**PR Count:**`. The branch layout MUST match the per-PR grouping table.
- If the actual layout doesn't match (e.g., all work is on a single branch but the manifest planned 3), the agent must split the branch via `git rebase --onto` per the grouping table — NOT collapse the manifest to match what was implemented. The manifest is the contract.

**`pr-monitoring` (already wired):**
- Reads the per-PR grouping table to know which monitor instance handles which PR.

**`post-merge-retrospective` (already wired):**
- Reads the manifest and stamps to know what was promised vs. what shipped. A reduced manifest is fine; an undocumented reduction is a gate miss.

## Anti-patterns

- **"The plan is just a guide."** No. After alignment PASS, the plan is the contract. Treating the plan as advisory after lock is the failure mode this skill exists to prevent.
- **Collapsing PRs because "they're all related."** Relatedness does not justify collapse. The PR grouping table reflects review-friendliness and rollback granularity, not just code locality.
- **Treating user vagueness as license.** "Reorder as needed" does not mean "rescope as needed". When in doubt, the agent picks the strictest interpretation and surfaces it. See `using-superpowers` strict-interpretation invariant.
- **Silently dropping a task because it turned out to be hard.** That's the unlock path's job. A unilateral skip is a contract breach.
- **"Demo" framing.** Once the manifest is locked, there is no demo mode. Either you ship the contract or you go through the unlock path. "Let me just get something working" is exactly the rationalization this skill blocks.

## Integration

**Called by:**
- `alignment-check` — to apply the initial lock after PASS.
- `subagent-driven-development` — to verify the lock at each task checkpoint.
- `finishing-a-development-branch` — to verify the lock before PR creation.
- Manual — when a user asks "are we still on plan?" the agent runs the check.

**Calls:**
- `recording-decisions` — when the user explicitly approves a scope reduction.
- `tests/plan-scope-check.sh` — for the programmatic verification.

**Reads:**
- `docs/plans/<plan>.md` — the plan and its manifest.
- `docs/plans/<plan>.md.scope-lock` — the manifest hash recorded at lock time.
- `git log --oneline <base>..HEAD` — actual commits to compare against the manifest.

**Writes:**
- `docs/plans/<plan>.md` — the `**Status:**` line, on lock or reduce.
- `docs/plans/<plan>.md.scope-lock` — the manifest hash file.
- (via `recording-decisions`) `decisions/NNNN-scope-reduction-<feature>.md`.

## Why a separate skill

`alignment-check` is "does this plan cover this design?" — a one-shot structural test at hand-off. `scope-lock` is "is the plan still being honored?" — a recurring runtime invariant. Keeping them separate keeps each skill's responsibility focused. Alignment runs once; the lock is checked at every checkpoint.
