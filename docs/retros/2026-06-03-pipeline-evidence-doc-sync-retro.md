# Retro: Pipeline Evidence + Doc-Sync Hardening

**PR:** #73 — Pipeline evidence + doc-sync hardening (#69 #70 #71 #72) → v6.4.0
**Merged:** 2026-06-03
**Branch:** feat/pipeline-evidence-doc-sync
**Design:** docs/plans/2026-06-03-pipeline-evidence-doc-sync-design.md
**Plan:** docs/plans/2026-06-03-pipeline-evidence-doc-sync.md
**Committed adversarial reports (dogfood of #69):** docs/plans/2026-06-03-pipeline-evidence-doc-sync-design-review.md · -plan-review.md
**Related ADRs:** none (no new non-trivial trade-off beyond what the design captured)

## Adversarial-review findings, scored

Scored directly from the committed review reports — the first end-to-end exercise of #69's new convention.

| Phase | Finding | Severity | Outcome |
|---|---|---|---|
| design | D1 — invented `-adversarial-<phase>.md` name diverged from existing `-design-review.md`/`-plan-review.md` convention; "never written" premise overstated (2 files already existed) | Critical | Prescient — adopting the existing name was the right call; the whole feature reframed from "new artifact" to "systematize ad-hoc practice" |
| design | D2 — retro fix would leave the format template (`:99`) + Reads bullet still pointing at the kit-local script | Critical | Prescient — became the 3-edit-site requirement in Task 4; verified by the regression test's negative assertion |
| design | D3 — dogfood framing misleading (skill edits don't take effect until their task lands) | Important | Resolved upfront — design + Task 5 noted manual emulation; no downstream confusion |
| design | D4 — phase attribution conflated `ev:"skill"` vs `ev:"agent"` records | Important | Resolved upfront — clarified to key off `ev:"skill"` args |
| design | D5 — `Resolution` field per-cycle-mutable with no consumer (YAGNI) | Important | Resolved upfront — reframed optional/end-state + wired retro consumer |
| design | D6 — Step 1e judgment gate could silently self-pass (the user's "trap") | Important | Resolved upfront — narrowed trigger + PR-body accountability token |
| design (cycle 2) | N1 — stem-derivation ambiguous for plan files → could break D1↔D2 path contract | Critical | Prescient — deterministic two-case rule + worked examples; later test-guarded |
| design (cycle 2) | N2 — Step 1e absent from finishing's Autonomous Mode list → never fires autonomously | Important | Prescient — the single highest-value catch; without it the gate was dead-on-arrival in autonomous runs |
| design (cycle 2) | N3 — PR-body token had no wired retro consumer (aspirational) | Important | Resolved upfront — wired to retro Step 5 missed-activation row |
| plan | P1 — two test assertions pre-green (matched ambient "committed"/"in-progress.jsonl" prose) → weak RED | Important | Prescient — code review independently re-derived the precision need (M1); tightened both |
| plan | P2 — `skill-cross-refs.sh` run locally but not wired into CI | Important | Resolved upfront — wired into `skill-content-check.yml` for free |
| code | I1 — finding-ID numbering ambiguous (sequential-all vs per-severity) | Important | Resolved upfront — clarifying parenthetical added |
| code | M1 — D1↔D2 test assertion OR-branch too broad | Minor | Resolved upfront — narrowed to the specific load-bearing phrase + revert-restore proven |

## Gate misses

No gate misses this PR. Every code-review finding (I1, M1) was a refinement of contracts the design/plan adversarial passes had already established, not a class they missed; both were caught before merge. CI was green on the first push (CodeQL, skill-content-check, version-check, Analyze ×3) — no CI failure slipped any local gate. The plan-phase reviewer's P1 (weak RED assertions) and the code reviewer's M1 (broad OR) converged on the same test-precision issue from two angles — a healthy redundancy, not a miss.

## Missed skill activations

Full canonical chain fired (verified from session memory + the partial activation log; see the dogfood note below for why the log is partial):

| Gate | Fired? | Notes |
|---|---|---|
| brainstorming | yes | logged in `in-progress.jsonl` |
| adversarial-design-review (design) | yes | 3 cycles → PASS; committed report exists |
| writing-plans | yes | |
| adversarial-design-review (plan) | yes | PASS; committed report exists |
| alignment-check | yes | PASS (1 drift item resolved) |
| scope-lock | yes | Locked + `.scope-lock` sha256 6cb6ebd9… |
| subagent-driven-development | yes | 1 implementer (sequential; tasks share files) |
| requesting-code-review (adversarial) | yes | APPROVE, 0 Critical |
| finishing-a-development-branch | yes | Step 1d PASS; Step 1e dogfooded (`Doc-reconciliation: clean`) |
| pr-monitoring | yes | bash poll-loop (sanctioned pattern), not a subagent |
| post-merge-retrospective | yes | this document |

## What worked

- **The phantom-dependency catch (design D1) reframed the whole feature.** The reviewer found 2 pre-existing `-design-review.md` files, disproving the "report is never written" premise. The fix became "systematize the ad-hoc practice under the existing name" instead of "invent a new artifact" — smaller, precedent-aligned, less bloat. This is the design-phase adversarial review doing exactly its job.
- **Cycle-2 N2 (Step 1e missing from the Autonomous Mode list) was the highest-value catch.** A doc-reconciliation gate that exists in the skill body but not the autonomous control-flow list would have been dead on arrival in every autonomous run — the precise "trap" the user warned about. Caught before a line of code.
- **#69 dogfooded end-to-end.** Both committed review reports rode the squash-merge to `main`; this retro scored findings by reading them — no transcript reconstruction. The feature proved itself on its own pipeline.
- **Bloat discipline held.** Net +~85 skill lines across 3 files, no new skill, no scanner — the user's explicit constraint. The two largest skills (writing-skills 740, TDD 522) were untouched.

## What didn't

- **#70's dogfood was only partial — and surfaced a residual the design under-weighted.** `record-activity` writes `<cwd>/.claude/autodev-state/in-progress.jsonl`, but the pipeline executed in a git worktree that was removed on cleanup, and the lead's session-cwd log captured only a fraction of the chain. So the retro's activation table leaned on session memory, not purely the log — the exact reconstruction #70 set out to eliminate. The fix is real (no more "script does not exist"), but **worktree-based execution + cwd-scoping fragments the very log the retro now depends on.** Assumption A2 ("Skill-invoked gates are what the retro needs") held; the unspoken assumption "the log lives where the retro looks" did not.
- **No `docs/design-guidance.md` exists**, so durable lessons keep landing in retros + memory rather than a single inherited guidance file. Recurring across many retros now.

## Plugin-level follow-ups

1. **Activation-log location robustness (new, from #70's partial dogfood).** The retro reads `<repo>/.claude/autodev-state/in-progress.jsonl`, but `record-activity` writes to the hook payload's `.cwd`, which for worktree-based pipelines is often the session cwd or a since-removed worktree. Candidate fixes: have `record-activity` also/instead anchor to the git common-dir (`git rev-parse --git-common-dir`) so worktrees share one log; or have the retro union the logs from the repo root + any sibling worktrees. **File as a follow-up issue** — this is the natural #70 successor, not a regression of it. One occurrence so far (this retro); watch for a second before hard-committing to a design.
2. **`docs/design-guidance.md` bootstrap (recurring).** Multiple retros (this one, and prior 6.3.x retros) have noted the absence of a canonical guidance file. Consider seeding one with the durable principles that keep recurring (anti-bloat for skills; phantom-dependency / circular-logic class; "the log must live where the consumer reads it"). Not urgent; flagged as a trend.

## Project guidance updates

| Guidance file | Change | Reason |
|---|---|---|
| `docs/design-guidance.md` | no change (absent) | The durable lesson ("an evidence artifact is only useful if it lives where its consumer reads it — verify location, not just existence") is captured here + in memory; no guidance file exists to update. Bootstrapping one is follow-up #2 above, not in this PR's scope. |
