# Retro: Autodev v6.1.1 Cascade Retro Follow-ups

**PR:** #45 — feat(v6.1.1): cascade retro plugin-level follow-ups bundle
**Merged:** 2026-05-27
**Branch:** feat/v6.1.1-cascade-retro-followups-2026-05-27
**Design:** docs/plans/2026-05-27-cascade-retro-followups-design.md (on design/cascade-retro-followups-2026-05-27T0442)
**Plan:** docs/plans/2026-05-27-cascade-retro-followups.md (on design/cascade-retro-followups-2026-05-27T0442)
**Related ADRs:** none

## Adversarial-review findings, scored

Design and plan went through 4 adversarial cycles before lock. The design doc records each cycle's summary inline. Cycle-1 surfaced the most signal; cycles 2–4 were verification and bash-bug passes.

| Phase | Finding | Severity | Outcome |
|---|---|---|---|
| design (cycle 1) | File-path targets wrong (SKILL.md insertion sections, table names) — e.g., `verification-before-completion` has Claim Matrix not a "Verification table"; `writing-plans` table is at line 82 not line 28 | Critical | Resolved upfront — cycle 2 verified every target via direct file read before rewriting plan |
| design (cycle 1) | `scope-lock-publish` should be a separate sibling helper matching `scope-lock-{apply,complete,claim,abandon}` pattern, not an inline block | Important | Resolved upfront — design adopted sibling-helper pattern |
| design (cycle 3) | `scope-lock-publish` bash bugs: `@{-1}` wrong after multi-hop checkouts; `--quiet` rejected by git rev-parse; dirty-tree check missing; committed-file guard needed | Critical | Resolved upfront — cycle-3 rewrote script with all guards |
| design (cycle 4) | `--branch` filter on `gh run list` excludes tag-triggered Release runs (headBranch = tag, not `main`) | Critical | Resolved upfront — cycle-4 dropped `--branch` filter from cascade-preflight.sh |
| design (cycle 4) | `gh pr merge --delete-branch` deletes local branch too; Git blocks deleting currently-checked-out branch | Critical | Resolved upfront — cycle-4 added `git checkout "$orig_branch"` before merge |

## Gate misses

| Issue | Gate that missed | Why it slipped | Fix idea |
|---|---|---|---|
| `marketplace.json` version not bumped alongside `plugin.json` and `cursor-plugin/plugin.json` | writing-plans (Task 7) | Plan task listed only `.claude-plugin/plugin.json` and `.cursor-plugin/plugin.json`; `marketplace.json` is a third version file checked by `tests/version-check.sh` but not mentioned in task 7's Files list | Add `marketplace.json` to the version-bump task Files list in the plan template, or update `scripts/bump-version.sh` reference in the plan to make it the canonical bump path |

## Missed skill activations

| Gate | Fired? | Notes |
|---|---|---|
| brainstorming | no | Skipped — changes were concrete follow-ups from an existing retro; no exploratory design needed |
| adversarial-design-review (design) | yes | 4 cycles; caught 5 critical/important findings upfront |
| adversarial-design-review (plan) | yes | Folded into cycle 4 |
| writing-plans | no | Plan was authored inline on the design branch, not via skill invocation |
| alignment-check | yes | |
| scope-lock | yes | |
| subagent-driven-development | no | Execution was single-agent (8 tasks, all markdown + bash); subagent overhead not justified |
| finishing-a-development-branch | no | Skipped — no build artifact, no runtime-launch-validation trigger condition |
| pr-monitoring | yes | Caught version-check CI failure; fixed in one round |
| post-merge-retrospective | yes | This document |

## What worked

- 4-cycle adversarial process caught 5 Critical findings (path errors, bash bugs, workflow-filter mismatch, branch-delete ordering) before any code was written. None became CI failures or code-review comments.
- `pr-monitoring` caught the `marketplace.json` version gap immediately on first CI run; fix was a 1-minute edit + push.
- All 8 tasks executed cleanly in-order with no task collisions or rollbacks.
- `bash -n` syntax checks on both new scripts confirmed clean before commit.

## What didn't

- Task 7's Files list omitted `marketplace.json`; this caused a CI failure on the first push. The plan should enumerate ALL files touched by a version bump, not just the ones the author remembered. The `scripts/bump-version.sh` script handles all three files atomically — the plan should reference it rather than listing files manually.
- `brainstorming` and `writing-plans` were skipped. For a 280-line, 8-task concrete follow-up bundle this was reasonable, but the skill-activation audit flags them as absent. A short note in the plan explaining intentional skips would quiet the audit signal.

## Plugin-level follow-ups

The `marketplace.json` version-bump miss is a one-off attribution error, not a repeating pattern. No new bug class warranted yet. If a second retro shows a version-file miss, add a "version-file completeness" class to the adversarial-design-review plan-phase table.

The `scripts/bump-version.sh` reference should be the canonical path for version bumps in plan tasks — mention it explicitly rather than listing individual files.

## Project guidance updates

| Guidance file | Change | Reason |
|---|---|---|
| `docs/design-guidance.md` | no change | No new cross-design constraint; the version-file miss is plan-authoring hygiene, not a design principle |
