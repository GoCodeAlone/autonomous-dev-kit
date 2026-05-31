# Existence / Runtime-Validity Bug-Class Design

**Status:** Approved (autonomous — user pre-authorized full-pipeline execution)
**Date:** 2026-05-31
**Issue:** https://github.com/GoCodeAlone/autonomous-dev-kit/issues/55

## Problem

`adversarial-design-review` scans a fixed checklist of bug-classes. Two recent
retros independently hit the same gap the checklist does not cover: **the review
verifies the intended content/shape of an artifact but never verifies the
artifact actually EXISTS or RUNS as the design assumes.**

Evidence (2-retro trend, both *gate-asserted-shape, reality-differed*):

1. **wfctl smart CI generation** (`docs/retros/2026-05-30-wfctl-secrets-wizard-and-smart-ci-retro.md`):
   generated CI steps were shape-valid but **non-functional at runtime** —
   emitted `wfctl ci run --phase migrate` (no such phase) and a `... || true`
   plan-guard that gated nothing. Caught late (real-repo regen + code review),
   not at design.
2. **required_secrets sweep** (`docs/retros/2026-05-31-plugin-required-secrets-sweep-retro.md`):
   design assumed all 18 target plugins had a `workflow-registry` manifest to
   edit; **3 (entra/scalekit/auth0) had none** — discovered at execution (jq
   failed on a missing file), forcing a mid-execution scope-lock amendment. One
   `ls plugins/<name>/manifest.json` at design time would have caught it.

The two adjacent existing classes don't cover it:
- `Plugin-loader runtime layout` → about the plugin *binary* layout, not "does
  the target artifact exist".
- `Config-validation schema rules` → about new config files satisfying a schema,
  not "does the generated artifact execute" or "does the thing I'm mutating
  exist".

## Goals

- Add one bug-class that flags any design/plan asserting artifact *content*
  correctness without an *existence* (for mutated artifacts) or *behavior*
  (for generated artifacts) check.
- Scan it in **both** review phases (design + plan), per the issue title.
- Match the existing rows' voice: declarative definition grounded in concrete,
  repo-real examples + an explicit "flag X" instruction.

## Non-Goals

- No new report-format field, no new `## section`, no worked-example subsection.
- No change to the FAIL/PASS convergence loop or severity model.
- No second row — one combined class, not split existence/runtime rows.
- No change to any other skill (`demonstration-fidelity` already covers the
  *faked-demo* failure downstream; this is the upstream design/plan complement).

## Global Design Guidance

`Guidance: none found as docs/design-guidance.md; canon from README §Cross-LLM,
docs/plans/2026-04-25-cross-llm-portability-design.md, ADR 0001.`

| guidance | design response |
|---|---|
| Host-neutral / cross-LLM first | Pure SKILL.md prose; no host-specific tool or hook. |
| Checklist is the floor, not the ceiling | New row joins the mandatory-scan set; reviewer must report Finding/Clean for it like every other row. |
| Ground classes in concrete invariants | Row cites the two real retro misses verbatim (`wfctl ci run --phase migrate`; missing `workflow-registry` manifest). |
| Minimal surface | One table row + version bump + release notes. No structural change. |

## Approach Options

| option | summary | trade-off |
|---|---|---|
| **Recommended: one row in the design-phase checklist** | Design-phase classes are inherited by the plan phase (`SKILL.md:101` — "plan-phase reviewer scans the design-phase classes above"). One row → scanned in both phases. | Smallest surface; exactly matches "design + plan phases". Existence half is design-altitude; runtime half complements plan-phase `Verification-class mismatch` from upstream. |
| Two rows (existence in design, runtime-validity in plan) | Split the concern by altitude. | Duplicates the idea; issue asks for *a* (singular) combined class; more text, no extra coverage. |
| One row in the plan-phase checklist only | Sit next to its cousins (`Plugin-loader runtime layout`). | Misses the design phase — but the required_secrets miss was a *design*-time existence gap. Rejected. |

## Design

Single edit to `skills/adversarial-design-review/SKILL.md`: append one row to the
**design-phase** bug-class table (lines 85–97). The plan-phase table already
declares (line 101) that it scans the design-phase classes, so the new class is
covered in both invocations with no second edit.

Row wording (matches existing declarative + concrete-example voice):

> **Existence / runtime-validity** — For any design/plan that mutates or
> generates an external artifact (registry manifest, plugin release, CI workflow
> step, API endpoint, config the tool consumes): does it verify (a) each
> artifact it *mutates* actually **exists** — an `ls`/`gh` at design time (e.g.
> confirm a target plugin has a `workflow-registry` manifest before the plan
> edits it; a missing one forced a mid-execution amendment in the
> required_secrets sweep) — and (b) each artifact it *generates* actually
> **executes / contract-checks** against the real consumer — run it / dry-run it
> (e.g. the emitted CI step is a real command, not `wfctl ci run --phase
> migrate`, which no subcommand accepts), not merely that the intended content
> parses? Flag any design that asserts content correctness without an existence
> or behavior check. Cheap to satisfy (usually one `ls`/`gh`/dry-run);
> complements `demonstration-fidelity` by pushing the check upstream into
> design/plan.

Version: bump `6.2.1 → 6.2.2` (patch — additive skill content, no behavior
break) across the three manifests via `scripts/bump-version.sh 6.2.2`. Add a
`RELEASE-NOTES.md` entry. Merge to main auto-triggers `release-tag.yml`.

## Security Review

None. Documentation-only change to a skill markdown file. No secrets, no network,
no new permissions, no executable surface.

## Infrastructure Impact

None at runtime. Release path is the existing `release-tag.yml` (push to main
touching `.claude-plugin/plugin.json` → version-check → tag → marketplace
dispatch). No new infra.

## Multi-Component Validation

The "components" are the two reviewer invocations. Validation is structural:
- `tests/version-check.sh` confirms all three manifests agree post-bump.
- `tests/skill-content-check.yml` (skill-content lint) passes on the edited
  SKILL.md.
- Inheritance is asserted by the existing `SKILL.md:101` line — verified present
  before relying on it (no second edit needed). The plan-phase reviewer will now
  enumerate the new class because it scans the design-phase table.

## Assumptions

| id | assumption | challenge | fallback |
|---|---|---|---|
| A1 | Design-phase classes are scanned in the plan phase | `SKILL.md:101` could change | Verified the line is present this session; if it were removed the row would need duplicating into the plan table. |
| A2 | Patch bump is correct (additive, non-breaking) | Could be seen as minor feature | Additive checklist row changes no existing behavior or contract → patch per semver. |
| A3 | `release-tag.yml` fires on plugin.json change at merge | Workflow could be disabled | Workflow file present + path-filtered on `.claude-plugin/plugin.json`; verified this session. |

## Rollback

Revert the PR. The row is purely additive prose; removing it restores the prior
checklist with no migration. Version bump reverts with the same commit.

## Self-Challenge

- **Simplest alternative:** raw one-line edit, no design doc. Rejected — repo
  convention runs the pipeline even for one-row skill changes (precedent:
  `2026-05-31-session-owned-lock-claims-design.md`).
- **Fragile assumption:** A1 (inheritance). Mitigated by verifying `SKILL.md:101`
  this session.
- **YAGNI sweep:** no second row, no new report field, no worked example — all
  rejected as surface the issue didn't ask for.
