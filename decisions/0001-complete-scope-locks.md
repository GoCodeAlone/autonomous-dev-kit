# 0001. Complete scope locks explicitly

**Status:** Accepted
**Date:** 2026-05-26
**Decision-makers:** Jon Langevin, Codex
**Related:** `hooks/scope-lock-complete`, `skills/scope-lock/SKILL.md`, `tests/hook-contracts.sh`

## Context

Scope locks prevent autonomous agents from silently changing a plan after
alignment. The previous lifecycle had a creation path but no completion path,
so old locked plans continued to trigger prompt, stop, and pre-compact
reminders in later unrelated sessions.

## Decision

We will complete locks explicitly with `hooks/scope-lock-complete`. The helper
verifies the lock when possible, changes the plan status to `Complete`, removes
the `.scope-lock` file, prunes session reminder traces, and records compact
completion evidence.

**Alternatives considered and rejected:**

- **Ignore old locks through active-context only** — hook state is repo-local
  and must not depend on one workspace-specific state file.
- **Teach every hook to infer completion from PR history** — too expensive and
  ambiguous; completion needs an explicit operator/agent action.

## Consequences

**Positive:**

- Completed designs no longer nag unrelated sessions.
- Lock cleanup has one testable command instead of manual state edits.

**Negative:**

- Agents must remember one more lifecycle command before claiming a full
  locked design is complete.

**Reversibility:** Low cost. Revert the helper and tests; existing completed
plans remain ordinary markdown with no live lock file.
