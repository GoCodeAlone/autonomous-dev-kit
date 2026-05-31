# Retro: Session-Owned Lock Claims

**PR:** #53 — fix(scope-lock): require objective match for claims
**Merged:** 2026-05-31
**Branch:** `fix/issue-52-session-ownership`
**Design:** `docs/plans/2026-05-31-session-owned-lock-claims-design.md`
**Plan:** `docs/plans/2026-05-31-session-owned-lock-claims.md`
**Related ADRs:** `decisions/0002-lock-claims-require-objective-match.md`

## Adversarial-review findings, scored

| Phase | Finding | Severity | Outcome |
|---|---|---|---|
| design | First-user-message objective fails sessions that pivot | Important | Resolved upfront — design/ADR/plan changed to latest user-visible objective before implementation. |
| design | Objective excerpts may contain local task details | Minor | False positive — capped repo-local state is acceptable and caused no downstream issue. |
| design | Prompt-only resume checkpoint is simpler | Minor | False positive — prompt-only was the bug class; hook-enforced claim metadata was needed. |
| plan | Regression proof only reverts `pre-tool-scope-guard` | Minor | Prescient — inline review later caught helper/parser edge coverage and added `--confirmed` flag-position coverage. |
| plan | Shared `tests/hook-contracts.sh` write path serializes tasks | Minor | False positive — single-PR sequential execution avoided conflicts. |
| plan | Rollback is a paragraph, not a command | Minor | False positive — revert PR is sufficient; no runtime state migration. |

## Gate Misses

| Issue | Gate that missed | Why it slipped | Fix idea |
|---|---|---|---|
| `scope-lock-claim --confirmed <plan>` helper syntax was accepted by the script but not by the hook parser before inline review | adversarial-design-review (plan) | Plan did not require testing both documented flag positions. | Add option-order checks when a bash helper accepts flags before or after positional args. |
| HTTPS remote normalization would have stored `//github.com/org/repo` | requesting-code-review | Inline review caught it before PR; no external review comment or CI failure. | Consider a shell-helper URL-normalization fixture if more metadata fields are added. |

No CI failures occurred. PR and main-branch checks were green.

## Missed Skill Activations

| Gate | Fired? | Notes |
|---|---|---|
| brainstorming | yes | Autonomous user approval; design doc committed. |
| project-design-guidance | yes | Existing guidance absent; README/cross-LLM canon cited. |
| adversarial-design-review (design) | yes | Inline report committed. |
| writing-plans | yes | Plan with Scope Manifest committed. |
| adversarial-design-review (plan) | yes | Inline report committed. |
| alignment-check | yes | Inline trace + `plan-scope-check` before lock. |
| scope-lock | yes | Plan locked, verified, then completed. |
| test-driven-development | yes | RED/GREEN plus revert/restore proof for claim guard. |
| requesting-code-review | yes | Inline review; subagent unavailable by Codex delegation policy. |
| pr-monitoring | yes | PR #53 monitored; all checks green; no review threads. |
| post-merge-retrospective | yes | This file. |

`tests/skill-activation-audit.sh` could not read a state file in this Codex
worktree, so this table is reconstructed from committed artifacts and command
evidence.

## What Worked

- Design adversarial review caught the objective-source flaw before code.
- TDD regression proof reproduced issue #52: mismatch claim passed before the
  hook fix and failed correctly with the fix removed.
- PR monitoring caught no CI/review follow-ups; CodeQL, skill-content, and
  version checks all passed.
- Release automation created `v6.2.1` and dispatched the marketplace update on
  merge.

## What Didn't

- Plan review did not force option-order tests for `scope-lock-claim`.
- The session audit file was unavailable in this Codex worktree, so activation
  evidence came from artifacts rather than hook telemetry.

## Plugin-Level Follow-Ups

No new plugin-level change is warranted from a single option-order miss. If a
second retro shows bash helper flag-position drift, add a plan-phase
adversarial-review bug class for "helper parser accepts more syntax than hook
recognizer."

## Project Guidance Updates

| Guidance file | Change | Reason |
|---|---|---|
| `docs/design-guidance.md` | no change (file absent) | Durable lesson was captured in ADR 0002 and `skills/scope-lock/SKILL.md`; no broader project guidance shift. |
