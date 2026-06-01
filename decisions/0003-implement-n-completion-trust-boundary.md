# 0003. Implement-N completion is a lead-verified trust boundary, not a hook-blocked invariant

**Status:** Accepted
**Date:** 2026-06-01
**Decision-makers:** autodev maintainers, autonomous pipeline
**Related:** issue #58; `skills/subagent-driven-development/SKILL.md`; `agents/team-conventions.md`; docs/plans/2026-06-01-pipeline-hardening-4issues-design.md

## Context

Across infra-admin v1 + v1.1 autonomous runs, `Implement: N` tasks were flipped to
`completed` by implementers or via a blockedBy-clear *before* the code-reviewer's
quality gate, violating the team-conventions contract ("only code-reviewer flips
Implement-N to completed"). In v1.1 this masked a non-compiling tree (uncommitted
helper) and a CI-failing hash regression — both reported "done"; only the lead's
independent `verification-before-completion` pass caught them.

Issue #58 asked for **plugin/harness enforcement**: reject
`TaskUpdate(status=completed)` on `Implement: *` tasks unless `owner ==
code-reviewer`.

We investigated whether a deterministic plugin hook can enforce this. It cannot:

- The PreToolUse payload for a `TaskUpdate` call carries the *tool input*
  (`taskId`, `status`, `owner`) but **not** the task's current `subject`
  ("Implement: N") nor the identity of the calling subagent. The task store is
  harness state a bash hook cannot read (there is no `TaskList` available to a
  hook).
- Therefore a hook cannot reliably answer the two questions the block requires —
  "is this taskId an Implement task?" and "is the caller the code-reviewer?". The
  only deterministic option, "block all `status=completed`", would break every
  legitimate completion (spec-review, quality-review, and the orchestrator's own).

## Decision

We reject the infeasible hard-block and instead **shift the trust boundary**: a
flipped `Implement: N` is a *claim*, not *evidence*, and is **not trusted as done
until the lead runs `autodev:verification-before-completion`** (build + test from a
clean tree, CI green) before treating the task as complete or proceeding to
`finishing-a-development-branch`.

We encode this in `skills/subagent-driven-development/SKILL.md` (the
"Completion is not trusted until lead-verified" rule) and restate the
implementer/code-reviewer conventions in `agents/team-conventions.md`. We do **not**
add an advisory `TaskUpdate` hook: it cannot block, it cannot identify Implement
tasks, and it would fire on every completion (noise) for no enforcement gain.

## Consequences

The harm #58 names — a premature "done" masking a broken tree — is addressed at the
point it actually bit: the lead's verification gate, which already caught both v1.1
regressions. The convention ("code-reviewer is the sole flipper") remains as
team discipline but is no longer load-bearing for correctness; correctness rests on
lead verification, which does not depend on who flipped the checkbox.

The limitation is documented so the infeasible hard-block is not re-proposed. If a
future harness exposes the task subject **and** the calling subagent identity in
the PreToolUse payload, the deterministic block becomes feasible and this ADR
should be revisited (the convention is then mechanically enforceable). Until then,
"green checkbox ≠ verified" is the operative rule.
