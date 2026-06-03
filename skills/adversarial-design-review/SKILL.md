---
name: adversarial-design-review
description: Use after a design or implementation plan is drafted, before downstream skills accept it - adversarially attacks the ideas in the artifact (not just structural coverage) to surface unstated assumptions, repo-precedent conflicts, YAGNI violations, missing failure modes, security gaps, and simpler alternatives the author didn't consider
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Adversarial Design / Plan Review

## Overview

Every other review gate in this plugin attacks **code**. `alignment-check` attacks
**structure** (forward + reverse trace). Nothing attacks the **ideas** in the
design or plan themselves. This skill closes that gap.

The cheapest place to kill a bad idea is **before** the plan is written. The
second-cheapest is before code is written. After that, costs rise sharply. This
skill runs adversarially at both points.

**Core principle:** a design or plan is a hypothesis. Treat it like a PR diff
that hasn't been reviewed yet. Find what's wrong with it on purpose.

## When to Use

Two phases, two invocations:

- **`--phase=design`** — invoked by `brainstorming` after the design doc is
  written and committed, **before** transitioning to `writing-plans`.
- **`--phase=plan`** — invoked by `writing-plans` after the plan doc is
  written and committed, **before** `alignment-check`.

Manual invocation is also supported on any committed design or plan in
`docs/plans/`.

```dot
digraph adversarial_review_flow {
    "brainstorming" [shape=box];
    "design doc committed" [shape=box];
    "adversarial-design-review --phase=design" [shape=diamond];
    "writing-plans" [shape=box];
    "plan doc committed" [shape=box];
    "adversarial-design-review --phase=plan" [shape=diamond];
    "alignment-check" [shape=box];
    "subagent-driven-development" [shape=doublecircle];

    "brainstorming" -> "design doc committed";
    "design doc committed" -> "adversarial-design-review --phase=design";
    "adversarial-design-review --phase=design" -> "brainstorming" [label="FAIL: revise design", style=dashed];
    "adversarial-design-review --phase=design" -> "writing-plans" [label="PASS"];
    "writing-plans" -> "plan doc committed";
    "plan doc committed" -> "adversarial-design-review --phase=plan";
    "adversarial-design-review --phase=plan" -> "writing-plans" [label="FAIL: revise plan", style=dashed];
    "adversarial-design-review --phase=plan" -> "alignment-check" [label="PASS"];
    "alignment-check" -> "subagent-driven-development";
}
```

## Adversarial Framing (mandatory)

The reviewer's prompt MUST use adversarial framing — not validation framing.
Same discipline as `skills/requesting-code-review/SKILL.md`, applied to design
artifacts.

**Required prompt phrasing in every dispatch:**

> Find at least three things wrong with this design (or plan), even if they
> seem minor — or, if fewer than three are found, explicitly document every
> bug-class check you ran and what you found (or didn't). Bias toward finding
> issues. You are NOT validating that the artifact is good — you are looking
> for misconceptions, unstated assumptions, and ideas the author didn't
> consider. Reflexive approval is forbidden.

**Forbidden phrasing:** "review the design", "verify the plan looks good",
"confirm correctness", any wording that implies the reviewer's job is to
sign off. These produce theatre.

The reviewer is not a yes-person. The reviewer is a skeptic whose job is to
make the design or plan stronger by attacking it.

## Bug-class checklist — design phase (must scan)

The reviewer MUST explicitly scan and report findings for each class. The
checklist is the floor, not the ceiling. Additional findings are welcome.

| Class | Definition |
|---|---|
| **Project-guidance conflicts** | Read `docs/design-guidance.md` or equivalent project guidance. Does the artifact violate product direction, architecture constraints, UX/domain principles, quality/security/ops requirements, or non-goals? Cite both the guidance path/section and the conflicting design/plan section. If guidance is missing and the design does not show Q&A capture, flag it. |
| **Assumptions under attack** | Load-bearing claims, stated or unstated. "We assume the upstream API is idempotent." "We assume single-tenant." "We assume the user has admin." Challenge each assumption, name how it could be false, and flag any where a false assumption collapses the design. |
| **Repo-precedent conflicts** | Does this design fight existing patterns, skills, or conventions in this repo? Cite the conflicting `path/file.md:line`. If the design proposes a new pattern that contradicts an established one, the design must justify the divergence. |
| **Artifact-class precedent** | Survey how the codebase already implements this *artifact class* — not just the *mechanism*. The Repo-precedent class above checks the HOW (e.g. how a plugin registers a module type); this checks the WHERE/shape (e.g. where a scenario stands up a server, where a test fixture lives, where a migration goes). Grep for sibling instances of the same kind of artifact (`ls scenarios/*/cmd/server/main.go`, sibling plugins, migrations, CLI commands, fixtures) and confirm the design follows the established shape — or explicitly justifies divergence. A design that puts a test fixture in the production engine repo when sibling scenarios own their `cmd/server/main.go` = finding. Run the decisive `ls`/`grep` for the artifact class, not just for the mechanism. |
| **YAGNI violations** | Features in the design that aren't justified by stated requirements. Configuration knobs nobody asked for. Generality nobody needs. Future-proofing for cases that may never arrive. |
| **Missing failure modes** | What fails first under partial failure, network partition, restart-mid-operation, malformed input, adversarial input, the dependency being down? If the design doesn't address it, flag it. |
| **Security / privacy at architecture level** | Auth/authz boundaries, secret flow, least privilege, blast radius on compromise, PII exposure, log leakage, dependency/trust boundary, abuse case, CSRF/SSRF/auth-confused-deputy at the design level (not at the code level — that's `requesting-code-review`'s job). |
| **Infrastructure impact** | Does the design create/change/destroy cloud resources, queues, storage, migrations, network exposure, secrets, IAM, scaling, cost, deploy order, or rollback requirements? If impact is absent or hand-waved, flag it. If production approval is required, it must be explicit. |
| **Multi-component validation** | Does the design prove the real boundary works across components (API+DB, app+worker, frontend+backend, plugin+host, CLI+service, IaC+runtime)? Mock-only validation on both sides is insufficient unless justified. |
| **Rollback story** | How do we undo this if it goes wrong in production? For any change class that runtime-launch-validation already triggers on (build/deployment/version pins/startup config/migrations/plugin loading), the design MUST specify a rollback path. If absent → finding. |
| **Simpler alternative not considered** | Name the laziest plausible solution. Did the design consider it and reject it for stated reasons? If not → finding. "Couldn't this be a flat file?" "Couldn't this be a cron job?" "Couldn't this be a single SQL view?" |
| **User-intent drift** | Re-read the original ask. Does the design solve what the user asked for, or does it solve a different problem that was easier to design for? Compare the design's stated goals against the user's stated goals; flag drift. |
| **Existence / runtime-validity** | For a design/plan that touches an artifact another tool/contract consumes (registry manifest, plugin release, CI workflow step, API endpoint, config a tool reads): (a) for any artifact it *edits but did not create*, does it verify the artifact **exists** before the plan mutates it — an `ls`/`gh` at design time (e.g. confirm a target plugin has a `workflow-registry` manifest before editing it; a missing one forced a mid-execution amendment in the required_secrets sweep)? (b) for any artifact it *emits*, does it verify the emitted call targets a **real** consumer surface — e.g. confirm `wfctl ci run --phase migrate` is an actual subcommand/phase (it is not) by checking `wfctl help`/the consumer schema/a dry-run, rather than assuming the generated content merely parses (you confirm the consumer command/schema exists, not that you pre-run output that may not exist yet)? Flag any design that asserts content correctness without the matching existence/behavior check. If the design neither edits an existing consumed artifact nor emits one a consumer must accept, mark **Clean**. Cheap to satisfy (usually one `ls`/`gh`/dry-run); complements `demonstration-fidelity` by pushing the check upstream into design/plan. |

## Bug-class checklist — plan phase (must scan)

The plan-phase reviewer scans the design-phase classes above (since the plan
inherits the design's blast radius) and adds:

| Class | Definition |
|---|---|
| **Over-decomposition / under-decomposition** | Does task granularity match `writing-plans`'s 2–5-minute target per step? A 40-step plan for a CSV export is suspect. A 2-step plan for a schema migration is suspect. Flag both directions. |
| **Verification-class mismatch** | For each task, does its verification step match its change class per the table in `skills/writing-plans/SKILL.md` ("Verification per change class")? A schema migration verified by unit tests = finding. An API endpoint with no curl invocation = finding. |
| **Auth/authz chain composition** | When the design names an auth/authz chain ("behind the X auth filter", "RBAC-enforced", "admin-only"), walk that chain component-by-component against the plan's actual wiring. For each gate, verify it is enforced **server-side against an authenticated principal**, not shape-matched by a client-asserted value. Flag any gate where the plan's check reads from request/client-supplied input (`evidence.granted_permissions`, a header, a body field) instead of an authenticated subject (`authz.Enforce(authenticatedSubject, …)`). A plan that wires a weaker gate than the design's chain implies = finding. |
| **Hidden serial dependencies** | Tasks the plan claims are independent but actually share state (same file, same DB row, same config key). If executed in parallel, they'll collide. Flag any such pair. |
| **Missing rollback wiring** | The design specifies a rollback story (per the design-phase class above). Is it actually implemented in the plan as a task or step? Or is it a paragraph nobody is going to write code for? |
| **Missing integration proof** | For multi-component changes, does the plan include an end-to-end or integration verification that exercises the real boundary? If it only tests each component with mocks, flag it unless the design explicitly justified that as sufficient. |
| **Infrastructure verification mismatch** | For infrastructure-affecting changes, does the plan verify render/plan/apply/dry-run, secret wiring, migration order, rollback, and post-deploy health as appropriate? If not, flag it. |
| **Plugin-loader runtime layout** | Plans that spawn or load an external plugin process must build the binary in a layout the host's discovery code accepts. For wfctl: `$WFCTL_PLUGIN_DIR/<plugin-name>/<plugin-name>` + sibling `plugin.json`. Plans that `go build -o /tmp/single-binary` without the subdir + manifest sidecar will fail at runtime. |
| **Config-validation schema rules** | Plans that create new config files validated by a schema or CLI tool must satisfy that tool's invariants (e.g., for wfctl: `checkEntryPoints` requires ≥1 entry-point module like `http.server`/`scheduler.modular`/`messaging.broker`, OR a trigger/route/subscription/job/pipeline). Plans omitting required entry-point modules pass `bash -n` but fail schema validation at CI. |
| **Identifier / naming-convention match** | Config keys, flags, env vars, and command/code examples in the plan match the repo's established naming convention and the identifiers the code will actually use (grep the repo for the convention; a plan showing `snake_case` keys where the codebase uses `camelCase` = finding). **Distinct from `Config-validation schema rules`**, which checks tool-enforced schema invariants — this row checks human naming-convention consistency. Catches design-vs-code drift before code is written. |

## Process

1. **Read the artifact under review.** For `--phase=design`, read the design
   doc at `docs/plans/YYYY-MM-DD-<topic>-design.md`. For `--phase=plan`, read
   both the design doc AND the plan doc at
   `docs/plans/YYYY-MM-DD-<feature>.md` — the plan inherits the design's
   premises and you must attack both layers.
2. **Read the original user ask.** Where available (transcript, issue body,
   PR description). User-intent drift can't be caught without it.
3. **Spot-check the repo for precedent conflicts.** Grep for related
   skills, similar designs in `docs/plans/`, established patterns. Cite
   what you find.
4. **Read project design guidance.** Invoke `autodev:project-design-guidance`
   or read its canonical file (`docs/design-guidance.md`) if present. Guidance
   conflicts are findings, not style preferences.
5. **Run every bug-class check** in the relevant checklist. For each class,
   record one of:
   - **Finding** with file/section + severity (Critical / Important / Minor)
   - **Clean** with a one-sentence note on what you specifically checked
6. **Surface options, not just objections.** For findings, propose a
   concrete fix or alternative. "This design assumes X" → "Alternative: state
   X explicitly, and add a fallback if X is false at runtime."
7. **Write AND commit the report.** Derive the path from the artifact filename: drop `.md`, then for `--phase=design` append `-review.md` (e.g. `…-doc-sync-design.md` → `…-doc-sync-design-review.md`); for `--phase=plan` append `-plan-review.md` (e.g. `2026-06-03-…-doc-sync.md` → `2026-06-03-…-doc-sync-plan-review.md`). This matches the existing `docs/plans/2026-05-31-session-owned-lock-claims-design-review.md` convention. The **lead** writes the report text the reviewer produced to that path and commits it alongside the artifact (the subagent has no git authority). Re-runs update the same single per-phase file (append a `## Cycle N` section across cycles); safe under sequential execution. Commit verdict: PASS / FAIL. Use `autodev:condensed-pipeline-writing` for report density unless the user asked for prose.
   Committed artifacts use repo-relative paths; illustrate machine paths only with `<placeholder>` segments (e.g. `/Users/<name>/…`); never a literal operator-home path. Enforced by `tests/no-machine-paths.sh`.

## Report format

````markdown
### Adversarial Review Report

**Phase:** design | plan
**Artifact:** docs/plans/YYYY-MM-DD-<file>.md
**Status:** PASS | FAIL

**Findings (Critical):**
- `D1` [class] [section/line]: <description>. Recommendation: <concrete fix>. _Resolution: <optional — filled once at end-state: commit SHA / `accepted — reason` / `false-positive`; omit if open>._

**Findings (Important):**
- `D2` [class] [section/line]: <description>. Recommendation: <concrete fix>. _Resolution: <optional>._

**Findings (Minor):**
- `D3` [class] [section/line]: <description>. Recommendation: <concrete fix>. _Resolution: <optional>._

Design-phase finding IDs are `D1, D2, …`; plan-phase `P1, P2, …`, numbered **sequentially across all findings regardless of severity** (`D1` is the first finding overall, not the first Critical). IDs are the durable anchor `post-merge-retrospective` correlates against; the optional `Resolution` is a scoring hint (retro falls back to downstream evidence when omitted). Each finding has a **stable finding ID** as its first token.

**Bug-class scan transcript:**
| Class | Result | Note |
|---|---|---|
| Project-guidance conflicts | Finding / Clean | <one sentence> |
| Assumptions under attack | Finding / Clean | <one sentence> |
| Repo-precedent conflicts | Finding / Clean | <one sentence> |
| ... | ... | ... |

**Options the author may not have considered:**
1. <alternative approach>: <one paragraph trade-off>
2. <alternative approach>: <one paragraph trade-off>

**Verdict reasoning:** <one paragraph>
````

A bare "looks good" verdict is rejected. The bug-class scan transcript MUST
list every class with a result, even if the result is Clean.

## PASS / FAIL semantics

- **PASS** — no Critical findings; Important findings either resolved or
  explicitly accepted by the author with reasoning.
- **FAIL** — one or more Critical findings, OR Important findings the
  author has not addressed.

## Revision Loop

On FAIL:

- Feed findings back to the upstream skill (`brainstorming` for design
  phase, `writing-plans` for plan phase).
- The upstream skill revises the artifact based on Critical and Important
  findings, then re-invokes adversarial review.
- Continue revision cycles while the review is finding tangible Critical or
  Important issues: broken assumptions, missing failure handling, security
  exposure, scope drift, verification gaps, rollback gaps, or concrete repo
  precedent conflicts.
- Stop the loop when remaining findings are only nitpicks: wording, formatting,
  preference-level alternatives, harmless duplication, or low-confidence
  concerns that do not change design/plan behavior. Record them as Minor and
  PASS with the nitpicks listed.
- If two consecutive cycles produce no new tangible Critical/Important issue
  classes and only rephrase prior concerns, treat the loop as converged. Do not
  keep cycling just to satisfy the "find at least three things wrong" framing.
- The user may **override** a finding (mark it accepted with reasoning).
  Overrides are recorded in the artifact (e.g., "Reviewer flagged X as
  YAGNI; accepted because Y") so the decision is durable.

## Backporting During Execution

If implementation or verification later disproves a design assumption:

1. Append a dated `Backport` note to the design doc using
   `autodev:condensed-pipeline-writing`.
2. State the failed assumption, evidence, and corrected design behavior.
3. If the Scope Manifest is unchanged, no unlock is required; the lock protects
   the manifest, not explanatory design text.
4. If tasks, PR count, or shipped scope changes, use the `scope-lock` amendment
   path before pushing or claiming completion.

On PASS:

- For `--phase=design`: invoke `writing-plans`.
- For `--phase=plan`: invoke `alignment-check` (which is now narrowly
  structural — adversarial concerns are already cleared).

## Dispatching the reviewer agent

Dispatch a `balanced`-tier subagent whenever the host exposes subagent support.
Same tier as `alignment-check` and `requesting-code-review` reviewers — this is
review-class work, not orchestration. Inline adversarial review is a fallback
only for hosts or sessions where subagents are genuinely unavailable.

<host: claude-code>
Use the Agent tool to dispatch:

````
Agent tool (general-purpose, model: balanced):
  description: "Adversarial review: <design|plan>"
  prompt: |
    You are adversarially reviewing a software <design|plan> document.

    Read these files:
    - <design-doc-path>
    - <plan-doc-path>  (only for --phase=plan)
    - docs/design-guidance.md or equivalent project guidance, if present
    - The original user ask (paste it inline below).

    USER ASK (verbatim):
    <paste the user's original ask here>

    ## Required framing
    Find at least three things wrong with this <design|plan>, even if they
    seem minor — or, if fewer than three are found, explicitly document
    every bug-class check you ran and what you found (or didn't). Bias
    toward finding issues. You are NOT validating that the artifact is
    good — you are looking for misconceptions, unstated assumptions, and
    ideas the author didn't consider. Reflexive approval is forbidden.

    ## Required scans
    Scan every bug class listed in the relevant checklist (paste the
    checklist for the chosen phase verbatim into the dispatch prompt — do
    not make the subagent read this skill file; embed the table inline).

    ## Required output
    Use the Report format from the skill. Every bug class must appear in
    the scan transcript with a result (Finding or Clean) and a one-sentence
    note. Findings must include severity, file/section reference, and a
    concrete recommendation.

    Set Status to PASS only if there are zero Critical findings AND every
    Important finding either has a fix recommendation accepted by the
    author or is escalated as an open question. Otherwise FAIL.
````

The reviewer returns the report text. **The lead commits it to the derived path** (drop `.md`, append `-review.md` for design or `-plan-review.md` for plan) — the subagent has no git authority.
</host>

<host: generic-subagent-capable>
When subagent tools are available in the current host/session, dispatch a
subagent with the full adversarial prompt above. Inline adversarial review is
permitted only when subagent tools are genuinely unavailable: read the design
(and plan, if `--phase=plan`) plus `docs/design-guidance.md` or equivalent
project guidance, perform every bug-class scan in the checklist, and produce
the Report format above. The framing requirements still apply — adversarial
mindset, ≥3 findings or full transcript, no reflexive approval.
</host>

## Integration

**Called by:**
- `brainstorming` — `--phase=design`, after design doc is committed.
- `writing-plans` — `--phase=plan`, after plan doc is committed, before
  `alignment-check`.
- Manual — user invokes against any artifact in `docs/plans/`.

**Writes:**
- `docs/plans/<artifact-stem>-design-review.md` (design phase) / `docs/plans/<artifact-stem>-plan-review.md` (plan phase) — committed report.

**Calls:**
- `brainstorming` — on FAIL during `--phase=design`, for revision.
- `writing-plans` — on FAIL during `--phase=plan`, for revision.
- `writing-plans` — on PASS during `--phase=design`.
- `alignment-check` — on PASS during `--phase=plan`.

## Why two phases, not one

Different bug classes live in different artifacts:

- The **design** is the place to ask "is this the right idea?". Catching a
  YAGNI violation here saves N tasks of plan-writing and N×M lines of
  implementation.
- The **plan** is the place to ask "is the breakdown sound?". Verification-
  class mismatches and hidden serial dependencies don't show up in the
  design — only in the plan.

Folding them into one pass at one stage misses half the findings.

## Why "options the author may not have considered" is mandatory

A reviewer that only objects produces a frustrated author. A reviewer that
**also** offers concrete alternatives produces a stronger artifact. The
"Options" section of the report is non-negotiable: every report must include
at least one alternative the author may not have weighed, even if the
verdict is PASS. This is the antidote to reflexive sign-off and the
antidote to demoralizing critique.

## Relationship to other review skills

| Skill | Attacks | When |
|---|---|---|
| `adversarial-design-review --phase=design` | Ideas in the design | After brainstorming |
| `adversarial-design-review --phase=plan` | Ideas in the plan | After writing-plans |
| `alignment-check` | Structural coverage (design ↔ plan trace) | After plan-phase adversarial review |
| `requesting-code-review` | Code (scope + bug classes) | After each task's commit |
| `verification-before-completion` | Claims (evidence before assertions) | Before claiming done |

Each gate has a distinct target. Stacking them does not produce duplicate
findings — they catch different bug classes at different stages.
