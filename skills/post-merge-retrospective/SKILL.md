---
name: post-merge-retrospective
description: Use after a PR has merged and CI is green - reads design, plan, adversarial-review reports, code-review threads, and CI history to produce a short retrospective in docs/retros/ that closes the loop on which gates worked and which didn't
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Post-Merge Retrospective

## Overview

Every other skill in this plugin acts on the work in flight. This one acts on completed work. After a PR merges and CI is green, this skill produces a short retrospective: which adversarial-review findings turned out to matter, which gates produced false positives, which skill activations didn't fire when they should have. The output sits in `docs/retros/` and feeds back into the next iteration of the plugin itself.

**Core principle:** the only way the gates get sharper is if completed work is read back against the predictions they made. This skill does the reading.

## When to use this skill

Invoked automatically by `pr-monitoring` when **all** of:

1. The PR is merged.
2. The base-branch CI is green for the merge commit.
3. The PR was created via the autonomous pipeline (i.e., a design + plan + adversarial-review report exist in `docs/plans/` for this branch).

Manual invocation is also supported on any merged PR with the matching artifacts.

If the PR was opened ad-hoc (no design / plan in `docs/plans/`), this skill exits cleanly without writing a retro — there's nothing to compare against.

## Process

1. **Locate the artifacts.** From the merged PR, identify:
   - Design doc: `docs/plans/YYYY-MM-DD-<topic>-design.md`
   - Plan doc: `docs/plans/YYYY-MM-DD-<feature>.md`
   - Adversarial-review reports for design and plan phases (committed alongside)
   - Code-review threads: `gh pr view <N> --json reviews,comments`
   - CI history for the branch: `gh run list --branch <branch> --json conclusion,name,createdAt`
   - Any ADRs cited from the design or plan

2. **Score each adversarial-review finding.**
   For every finding raised in either phase's adversarial-review report, classify it as one of:
   - **Prescient** — the finding called out something that turned out to matter (showed up as a code-review comment, CI failure, follow-up bug fix, or revert).
   - **Resolved upfront** — the finding was addressed during plan revision and prevented an issue downstream (no code-review comment / CI failure traces back to it).
   - **False positive** — the finding flagged something that did NOT cause downstream issues and the design rationale held up.
   - **Inconclusive** — not enough signal to decide either way.

3. **Score each code-review comment.**
   For every code-review comment that requested a change, ask: which gate, if any, *should* have caught this earlier? Map the comment to the most-upstream gate that could have caught it (`brainstorming` self-challenge / `adversarial-design-review` design / `adversarial-design-review` plan / `alignment-check` / `requesting-code-review` / none). Comments mapped to a gate that was supposed to catch them but didn't are **gate misses** — the most actionable retro signal.

4. **Score CI failure history.**
   For each unique CI failure on the branch, ask: was this caught by `verification-before-completion` / `runtime-launch-validation` / something else, or did it slip past every local gate? Slips are gate misses too.

5. **Score skill activations.**
   Read `.claude/autodev-state/in-progress.jsonl` (if present in the repo's `.claude/` directory) and verify the expected pipeline ran. The canonical chain documented in `skills/using-autodev/SKILL.md` is:
   `brainstorming → adversarial-design-review (design) → writing-plans → adversarial-design-review (plan) → alignment-check → subagent-driven-development → finishing-a-development-branch → pr-monitoring → post-merge-retrospective`.
   For each gate that was *expected* to fire and didn't, that's a missed-activation. Use `tests/skill-activation-audit.sh` (this repo) to confirm what fired — note that the audit script reports each skill once even when invoked twice (e.g., adversarial-design-review for both phases), so cross-check phase counts against the JSONL `args=--phase=<design|plan>` entries when both phases are required.

6. **Backfeed project design guidance.**
   Invoke `autodev:project-design-guidance`. If the merged work reveals a
   durable cross-design lesson, update `docs/design-guidance.md` in the same
   commit as the retro. Durable lessons include language/runtime/framework
   direction changes, new product/application modes, deployment/compliance/
   privacy/operations constraints, repeated gate misses that should become a
   design principle, or false assumptions in existing guidance. Do not append
   one-off implementation trivia.

7. **Write the retro.**
   Save to `docs/retros/YYYY-MM-DD-<feature>-retro.md` using the format below. Commit it.

## Retro format

```markdown
# Retro: <Feature Name>

**PR:** #<N> — <title>
**Merged:** YYYY-MM-DD
**Branch:** <branch>
**Design:** docs/plans/YYYY-MM-DD-<topic>-design.md
**Plan:** docs/plans/YYYY-MM-DD-<feature>.md
**Related ADRs:** <decisions/NNNN-...md, ...>

## Adversarial-review findings, scored

| Phase | Finding | Severity | Outcome |
|---|---|---|---|
| design | <one-line summary> | Critical / Important / Minor | Prescient / Resolved upfront / False positive / Inconclusive |
| plan   | ... | ... | ... |

## Gate misses

For each code-review comment or CI failure that *should* have been caught earlier, name the gate that missed it and why. If none — say so.

| Issue | Gate that missed | Why it slipped | Fix idea (optional) |
|---|---|---|---|
| <one-line description> | adversarial-design-review (plan) | <one sentence> | <one sentence> |

If there are zero gate misses, write: "No gate misses this PR. All downstream issues were caught by the gate they were assigned to, or were genuinely novel and not in any gate's bug-class scope."

## Missed skill activations

Pipeline gates expected to fire (per `using-autodev`): list any that didn't. Pull from `tests/skill-activation-audit.sh`.

| Gate | Fired? | Notes |
|---|---|---|
| brainstorming | yes | |
| adversarial-design-review (design) | yes | |
| adversarial-design-review (plan) | no | <why — e.g., manual override; deferred to alignment-check> |
| ... | ... | |

## What worked

2-4 bullets, concrete. "Adversarial review caught the missing rollback path; plan was revised before execution started."

## What didn't

2-4 bullets, concrete. No abstract laments. "Code review found a thread-safety bug in the cache layer; this should have been an `adversarial-design-review --phase=design` finding under failure-modes — the design doc said `cache is in-process` without addressing concurrency."

## Plugin-level follow-ups

If a gate miss recurs across multiple retros, propose a concrete plugin change: a new bug class in `adversarial-design-review`, a new line in `runtime-launch-validation`, a new entry in `tests/skill-cross-refs.sh`. Cite the prior retros.

If no plugin-level changes are warranted, say so.

## Project guidance updates

| Guidance file | Change | Reason |
|---|---|---|
| `docs/design-guidance.md` | <updated / no change> | <durable lesson or "no cross-design lesson"> |
```

## Dispatch

<host: claude-code>
This is short, structured analysis work — one pass over the artifacts. Run inline, not as a subagent. The lead agent has the context already. If the artifact set is large (10+ code-review threads, dozens of CI runs), dispatch a `balanced`-tier general-purpose subagent with the artifact paths inline.
</host>

<host: codex, opencode, cursor>
Run inline. The lead agent has the context already. The retro is a structured artifact, not a long-running task — produce the markdown directly.
</host>

## Why this skill exists

`pr-monitoring` exits when CI is green and reviews are resolved. That's the end of the in-flight pipeline, but it's not the end of the loop. Without `post-merge-retrospective`, the plugin has no organic way to know which gates are actually pulling their weight. With it, every merged PR produces a small piece of evidence that gets compared across PRs over time. That's how the gate set sharpens.

The retro is intentionally short. Long retros don't get read. The format above fits on one screen for a typical PR; the gate-miss table is the only required-non-empty section if there's anything to learn.

## Integration

**Called by:**
- `pr-monitoring` — on its successful exit (CI green + reviews resolved).
- Manual — any merged PR with matching artifacts.

**Calls:**
- `project-design-guidance` — when the retro identifies a durable cross-design
  guidance change.

**Reads:**
- `docs/plans/` (design, plan, adversarial-review reports)
- `decisions/` (ADRs cited from the design / plan)
- `gh pr view`, `gh pr review-comments`, `gh run list`
- `.claude/autodev-state/in-progress.jsonl` (if present)
- `tests/skill-activation-audit.sh` (this repo)
- `docs/design-guidance.md` or equivalent project guidance, if present

**Writes:**
- `docs/retros/YYYY-MM-DD-<feature>-retro.md`
- `docs/design-guidance.md` when the retro identifies a durable cross-design
  guidance change

## Anti-patterns

- **Long, narrative retros.** The format is a table-driven one-pager. If it grows past two screens, the structure is being abused.
- **Validating the work.** This isn't "did we ship the right thing?" — that's the user's call. This is "did the gates do their job?" — that's a process question with binary answers per gate.
- **Skipping the gate-miss table.** "Everything went great" is fine as a statement, but the table format forces you to walk every code-review comment and CI failure. Skipping it means signal is being lost.
- **Acting on a single retro.** Plugin-level follow-ups require pattern across retros. One miss is signal; two is a trend.
- **Failing to backfeed durable guidance.** If the application changes language,
  product mode, deployment model, compliance posture, or another cross-design
  constraint, update project guidance so the next design inherits it.
