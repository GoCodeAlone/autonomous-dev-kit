# Retro: Existence / Runtime-Validity Bug-Class

**PR:** #56 — feat: add Existence/runtime-validity bug-class to adversarial-design-review (#55)
**Merged:** 2026-05-31
**Branch:** feat/existence-runtime-validity-bugclass-55
**Design:** docs/plans/2026-05-31-existence-runtime-validity-bugclass-design.md
**Plan:** docs/plans/2026-05-31-existence-runtime-validity-bugclass.md
**Related ADRs:** none (design cited no ADR; existing ADRs 0001/0002 govern scope-lock, not this skill)
**Released:** v6.2.2 (Latest)

## Adversarial-review findings, scored

| Phase | Finding | Severity | Outcome |
|---|---|---|---|
| design c1 | Row fires false-positive on create-not-mutate designs (nothing to `ls`/dry-run for an artifact the design *creates*) | Important | Resolved upfront — row scoped part (a) to "edits but did not create" + explicit `Clean` escape hatch |
| design c1 | ADR 0001 (scope-lock) cited as guidance canon — inapplicable to a checklist edit | Important | Resolved upfront — citation removed |
| design c1 | `skill-content-check` claimed as structural validation; it only lints host tokens | Minor | Resolved upfront — claim qualified |
| design c1 | Row shown as blockquote-with-`—`, risks malformed table on copy | Minor | Resolved upfront — shown in exact pipe-delimited form |
| design c1 | Plan-phase dispatch must embed design-phase table for inheritance to hold | Minor | Resolved upfront — noted as pre-existing property of all 11 design-phase classes (no new gap) |
| design c2 | Part (b) parenthetical reads awkwardly (altitude stumble) | Minor | Resolved upfront — reordered to lead with the concrete `wfctl help` check |
| plan | "19 class rows + 2 header-ish" annotation factually wrong (0 header rows match) | Minor | Resolved upfront — corrected to "19 (11 design + 8 plan); assert 20" |
| plan | Insertion point ambiguous between Files section and Step 2 body | Minor | Resolved upfront — aligned both to "before the blank line" |
| plan | Tag-uniqueness pre-check absent from verification summary table | Minor | Resolved upfront — added to summary |

## Gate misses

No gate misses this PR. Every downstream check was clean: the two-stage code review (spec + quality) returned APPROVED with zero findings, and all 7 CI checks passed on the first run with zero failures. Every adversarial finding was raised at the design or plan gate and resolved before any code/content commit — which is exactly the gates doing their job. The single highest-risk item in this change class (the new row text mentions `wfctl`/`gh`/`ls`/`workflow-registry` — could it trip `skill-content-grep.sh`'s forbidden-token lint?) was explicitly verified clean at the plan gate before execution.

| Issue | Gate that missed | Why it slipped | Fix idea |
|---|---|---|---|
| (none) | — | — | — |

## Missed skill activations

| Gate | Fired? | Notes |
|---|---|---|
| brainstorming | yes | |
| adversarial-design-review (design) | yes | 2 cycles (c1 FAIL → c2 PASS) |
| writing-plans | yes | |
| adversarial-design-review (plan) | yes | PASS first cycle (3 Minor applied) |
| alignment-check | yes | programmatic `plan-scope-check` + verbatim row match, zero drift |
| scope-lock | yes | locked 2026-05-31T22:07:47Z, sha256 f765fa18… |
| subagent-driven-development | yes | 3 sequential tasks; lead executed deterministic edits, delegated the review gate |
| finishing-a-development-branch | yes | Step 1d scope completeness PASS (3 tasks → 3 commits, PR count 1=1) |
| pr-monitoring | yes | background bash poll-loop (per learned feedback — not a monitor subagent); settled ~60s, 7/7 green |
| post-merge-retrospective | yes | this doc |

## What worked

- **The adversarial design gate earned its keep on a trivial-looking change.** A one-row doc edit still surfaced a real Important finding (false-positive on create-not-mutate designs) that would have made the new bug-class itself noisy. Caught before any code.
- **Dogfooding-adjacent:** the bug-class being added (existence/runtime-validity) is the same discipline the plan gate applied to itself — Task 1 Step 1 verified `SKILL.md:101` (the inheritance line the whole approach depends on) *exists* before relying on it; Task 3 ran the *same* `version-check.sh` the release workflow runs (consumer-real check). The PR practiced what it preaches.
- **Bash poll-loop for CI** ([[feedback_ci_wait_use_bash_poll_loop]]) cost ~0 tokens and re-invoked the lead exactly once on settle — no monitor-subagent spam.
- **Release path was fully reactive:** merge → `release-tag.yml` auto-tagged v6.2.2 → marketplace dispatch. Only manual step was creating the visible GH Release (tag-only is the repo's release-tag.yml behavior).

## What didn't

- **Minor design-doc hygiene drift:** the guidance-canon citation was copy-pasted from the precedent design (`session-owned-lock-claims`) including an ADR reference that didn't apply here. Caught at design c1, but it's a recurring copy-paste smell when reusing a recent design as a template. Watch for it; not yet a trend.
- **Nothing else.** The change was small and the gates converged fast (design 2 cycles, plan 1 cycle, code review 0 findings).

## Plugin-level follow-ups

No plugin-level change warranted. This PR *is* the plugin change. Note the new `Existence / runtime-validity` row was not yet active for this PR's own adversarial reviews (it merged into the skill at the end); future autonomous runs inherit it. If a *second* retro later shows the guidance-canon copy-paste smell recurring, consider a `tests/skill-cross-refs.sh`-style check that flags an ADR citation in a design's guidance section that the design body never references — but one instance is not yet a trend.

## Project guidance updates

| Guidance file | Change | Reason |
|---|---|---|
| `docs/design-guidance.md` | no change (file absent) | No durable cross-design lesson; this is a self-contained checklist addition. |
