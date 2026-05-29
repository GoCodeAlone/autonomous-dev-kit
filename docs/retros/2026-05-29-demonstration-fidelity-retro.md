# Retro: Demonstration Fidelity

**PR:** #50 — feat: demonstration-fidelity skill + advisory hook (v6.2.0)
**Merged:** 2026-05-29
**Branch:** feat/demonstration-fidelity-2026-05-29T1128
**Design:** docs/plans/2026-05-29-demonstration-fidelity-design.md
**Plan:** docs/plans/2026-05-29-demonstration-fidelity.md
**Related ADRs:** none (no manifest amendment; design backports only)

## Adversarial-review findings, scored

| Phase | Finding | Severity | Outcome |
|---|---|---|---|
| design c1 | TDD Iron Law: design claimed RED baseline "captured" before it was run | Critical | Resolved upfront (ran 2 baselines; backported real learnings) |
| design c1 | User-intent drift: filename hook misses dominant inline/cross-language fake demos | Critical | Resolved upfront (skill+VBC row own dominant mode; hook demoted to bonus) |
| design c1 | Hook FP on test fixtures (`example_test.go`) | Important | Resolved upfront (anchored heuristic) |
| design c1 | Dedup lifecycle underspecified | Important | Resolved upfront (session-keyed jsonl + fail-open) |
| design c1 | Discoverability untested | Important | Resolved upfront (symptom-first CSO + behavioral check) — partially Inconclusive (non-CI) |
| design c2 | `test`/`spec` bare-substring over-exclusion eats `latest`/`contest` demos | Important | Prescient (would have shipped a real FN regression) |
| design c2 | RLV "no stub on either end" vs disclosed seam-substitution contradiction | Important | Prescient (reconciled in exact RLV row wording) |
| plan c1 | `session_id` absent from PreToolUse payloads → dedup degenerates cross-session | Critical | Prescient (switched to `transcript_path`; empirically verified) |
| plan c1 | Dedup test not deterministic until session-key fixed | Critical | Resolved upfront |
| plan c1 | fail-open vs `set -euo pipefail` (naive `>>` fails closed) | Important | Prescient (guard made explicit; impl needed it) |
| plan c1 | `examples/testdata/` exclusion edge untested | Important | Resolved upfront (test added) |
| plan c1 | Task 6 GREEN non-gating undermines Iron Law | Important | Resolved upfront (made gating on Task 7) |
| plan c1 | hooks.json exact JSON / merge-into-scope-guard risk | Important | Resolved upfront (exact element specified) |
| code review | RSpec `*_spec.rb` not excluded → spurious fire on Ruby | Important | Prescient (fixed in-PR: added `*_spec.*`) |
| code review | bash 3.2 `set -u` empty-array (unreachable) | Minor | Resolved upfront (`${segs[@]:-}` hardening) |

## Gate misses

| Issue | Gate that missed | Why it slipped | Fix idea |
|---|---|---|---|
| `session_id` not in PreToolUse payload | adversarial-design-review (design) | design wrote dedup keyed on `<session-id>` under assumptions; design-phase review did not attack hook-payload-field availability | When a design adds a hook, the assumptions class should explicitly verify which payload fields the hook *event type* actually provides. Caught one stage later (plan phase) at low cost. |
| RSpec `*_spec.rb` exclusion gap | adversarial-design-review (plan), FP/FN class | plan-phase FP/FN analysis enumerated Go `example_test.go` but not the Ruby `_spec.rb` convention | Enumerate test-naming conventions across major languages when reviewing path-heuristic exclusions. Advisory-only path; caught at code review pre-merge. |

Both misses were caught by a *downstream* gate before merge — no production escape. CI: 7/7 green first try, zero failures, zero gate misses on CI.

## Missed skill activations

| Gate | Fired? | Notes |
|---|---|---|
| brainstorming | yes | one AskUserQuestion handoff (fix shape / hook mode / PR count) |
| project-design-guidance | yes | no `docs/design-guidance.md`; cited canon equivalents |
| adversarial-design-review (design) | yes | 3 cycles (FAIL→FAIL→PASS) |
| writing-plans | yes | Scope Manifest, 1 PR |
| adversarial-design-review (plan) | yes | 2 cycles (FAIL→PASS) |
| alignment-check | yes | zero drift |
| scope-lock | yes | locked 2026-05-29T11:52:19Z; verified intact at merge |
| subagent-driven-development | partial | implemented in main loop (cohesive markdown/bash PR) with TDD RED→GREEN + independent code review, rather than per-task subagent dispatch |
| finishing-a-development-branch | yes | Step 1d scope check + RLV transcript |
| pr-monitoring | adapted | inline CI watch (tiny PR) instead of 60-min background agent |
| post-merge-retrospective | yes | this doc |

## What worked

- Adversarial reviews caught **4 Criticals pre-merge** that would each have shipped a real defect: the premature-TDD claim, the user-intent drift (hook-only solution would have missed the dominant failure mode), the `session_id` payload assumption, and the cross-session dedup degeneration.
- RED baselines **reshaped the invariant**: baseline #2's honest seam-substitution disclosure became the "allowed with disclosure" rule + the "fidelity not language-sameness" nuance — content that would not exist without watching the baseline.
- Dogfooding paid off twice live: the existing `completion-claim-guard` fired on this very session at every phase boundary, and the new `pretool-demo-fidelity-guard`'s 22 contract assertions gave empirical proof of the heuristic (incl. the rev2 regression guard).

## What didn't

- Design-phase adversarial review did not attack hook-**payload-field availability** (`session_id`), leaving a Critical for the plan phase to catch. Cheap here, but it's a hook-specific blind spot.
- Both design and plan under-specified the path-exclusion **test-naming conventions** (RSpec `_spec.rb`), caught at code review. Advisory-only, but a recurring "enumerate conventions" gap.

## Plugin-level follow-ups

Single-occurrence signals — noted as candidates, not yet trends (plugin change needs a pattern across ≥2 retros):

1. **Hook payload-field availability** as an explicit adversarial-design-review (design) assumption sub-check when a design adds a hook (which fields does this *event type* provide?). Watch for recurrence.
2. **`runtime-launch-validation` is absent from the README Skills Library** (noticed during wiring; left out of this PR for scope discipline). Trivial doc follow-up.

No plugin code change made from this single retro.

## Project guidance updates

| Guidance file | Change | Reason |
|---|---|---|
| `docs/design-guidance.md` | no change (file absent) | No durable cross-design lesson (no language/deploy/compliance shift). The harness-agnostic + host-neutral constraints are already canon (README §Cross-LLM, cross-llm-portability design). The `transcript_path`-not-`session_id` lesson is plugin-implementation detail, tracked as follow-up #1, not a user-facing design constraint. |
