# Autonomous Dev Kit Skills Improvements — Design

**Status:** Approved by user; full execution pipeline will run.
**Branch:** `feat/skills-improvements-from-failure-modes`
**Date:** 2026-04-25

## Why this exists

Multi-agent autonomous development sessions over recent weeks revealed ten failure patterns where the current skill set let real bugs reach production. None of the patterns are exotic — they're mundane discipline gaps that the skills don't enforce. This design proposes targeted, generic improvements to address them.

The driving observation: a third-party adversarial code reviewer running on a fresh diff read consistently catches bugs that the team's own reviewer agent has already approved — same base LLM, same diff, very different outcomes. The framing differs, the brief differs, the loop differs, and the result differs by order of magnitude. Closing that gap is the single highest-impact change in this design.

This work targets the public `autonomous-dev-kit` skill set. **All changes are generic** — no project, company, technology, or incident references bleed in. Lessons abstract; specifics scrub.

## Goals

1. **Close the adversarial-review gap.** When a code-reviewer subagent runs, it should produce roughly the same result an external adversarial reviewer would — bug-class checklist, line-anchored output, iterative loop, scope-vs-dispatch compliance, find-three-things-wrong framing.
2. **Make TDD's regression-catching guarantee provable.** Every regression test must be proven to fail without the fix it gates.
3. **Add a runtime-launch gate to the finishing pipeline.** For changes that affect runtime behavior, a green test run is not enough; the built artifact must launch and respond to a healthcheck before merge.
4. **Make "validate locally" specific per change class.** A refactor needs `go test`. A schema change needs ephemeral-DB migration. A build-pipeline change needs `docker run + curl /healthz`. The skills should say which.
5. **Make the autonomous pipeline's terminal step explicit.** Add a `--design-only` mode to brainstorming and writing-plans for design-only workstreams whose execution is deferred.
6. **DRY team-conventions boilerplate** out of dispatch-time briefs.
7. **Cover sibling-method bug classes by default in TDD** — when fixing a class invariant violation, the test must cover all sibling methods, not just the one that was buggy.

## Non-goals

- Not creating a fragmented, micro-skill-per-pattern landscape. Keep the surface small.
- Not duplicating what `verification-before-completion`, `receiving-code-review`, or `dispatching-parallel-agents` already cover well.
- Not introducing project-specific examples; every example in skill text must be generic and language-agnostic where possible.
- Not changing the autonomous pipeline's overall shape (brainstorm → write plan → align → execute → finish → monitor).

## Existing skill landscape (relevant subset)

Survey confirmed the following skills are present and the listed gap patterns map to them:

| Skill | Current strength | Gap relevant to this design |
|---|---|---|
| `requesting-code-review` | Provides severity tiers + file:line refs; dispatches reviewer subagent | **No bug-class checklist; no adversarial framing; no iterative-loop protocol; no scope-vs-dispatch gate; line-anchored output not mandatory** (P6) |
| `receiving-code-review` | Verification before implementation, push-back encouraged | Adequate; no change needed |
| `test-driven-development` | RED → GREEN → REFACTOR; iron-law no-prod-without-failing-test | **No revert-to-confirm-fail step (P3); no sibling-method coverage rule when fix is class invariant (P2)** |
| `finishing-a-development-branch` | Verifies tests pass, four-options menu, autonomous PR creation | **No runtime-launch verification step (P7); no version-skew audit (P4)** |
| `subagent-driven-development` | Agent Teams default, two-stage review (spec then quality), persistent roles | **Implementer prompt template repeats team boilerplate that could reference `verification-before-completion` instead (P10)** |
| `brainstorming` | Adaptive question batching, 2-3 approach exploration, autonomous handoff | **No `--design-only` flag (P9)** |
| `writing-plans` | Bite-sized tasks, exact paths, expected output, frequent commits | **No per-change-class verification table (P8); no `--design-only` flag (P9)** |
| `verification-before-completion` | Iron law: evidence before assertions, fresh-run mandate | Adequate; **referenced from new runtime-launch-validation** |
| `alignment-check` | Forward + reverse trace; PASS/FAIL with drift | Adequate; no change needed |
| `dispatching-parallel-agents` | Decision flowchart, fan-out concurrent independent workstreams | **Already addresses P5 — no change needed** |
| `pr-monitoring` | CI-failure auto-fix, safety limits | Tangential to this design |
| `using-git-worktrees` | Worktree directory selection, clean-baseline verification | Tangential |
| `writing-skills` | TDD-for-skills meta-discipline | Tangential |

## Three approaches considered

### Approach A — Edit existing skills in place

Add new sections, checklists, and protocols directly to the existing `SKILL.md` files. Don't introduce new skills.

**Pros:**
- Smallest surface change; everything stays where readers expect it.
- No skill-discovery problem ("which skill do I use for X?").
- Easy to review (one PR, mostly file edits).

**Cons:**
- A few of the additions (runtime-launch validation, bug-class checklist) are cross-cutting — they're referenced from multiple skills. In-place editing duplicates content.
- `requesting-code-review` rewrite is substantial; landing it as one giant edit risks reviewer fatigue.

### Approach B — Constellation of new mini-skills + light edits to existing

Introduce three new skills: `adversarial-code-review`, `runtime-launch-validation`, `regression-invariant-proof`. Make existing skills reference them.

**Pros:**
- Each cross-cutting concern lives in one place.
- Skill descriptions help discoverability ("when fixing a class invariant violation, see regression-invariant-proof").

**Cons:**
- Skill proliferation. Three new skills for ~10 lessons feels heavy.
- Risk of fragmented narrative — readers have to chase references.
- More PRs to land.

### Approach C — Hybrid: edit in place for most, **one** new mini-skill for the cross-cutting concern (RECOMMENDED)

Most patterns fit cleanly as targeted additions to one existing skill each. The exception is **runtime-launch validation**, which is referenced from `finishing-a-development-branch` (the gate) AND `writing-plans` (the per-change-class validation table cites it). Pull that one out into a new `skills/runtime-launch-validation/` so both can reference it without duplication.

The bug-class checklist, adversarial framing, scope-vs-dispatch gate, and iterative loop all live in `requesting-code-review` directly — they're not cross-cutting in the same way; they're a focused upgrade to one skill.

**Pros:**
- Smallest viable surface change.
- Cross-cutting content lives in one referenceable file.
- One new skill is much easier to maintain than three.

**Cons:**
- `requesting-code-review` becomes the largest single edit — needs careful review.

**Why C wins:** the recommendation pattern from `dispatching-parallel-agents` (already-good model in this codebase: targeted skill + cross-references) shows that one cross-cutting skill is the right granularity. Three would be over-fragmentation.

## Per-skill changes (detailed)

### 1. `skills/requesting-code-review/SKILL.md` — adversarial-framing rewrite

This is the largest single change in the design. It addresses Pattern 6 (the headline finding).

**Add a new section "Reviewer brief" near the top, mandating:**

- **Adversarial framing.** The reviewer prompt explicitly says: "Find at least three things wrong with this code, even if they seem minor. Bias toward finding issues. You are NOT validating that the code matches the dispatch — you are looking for bugs the original review missed." Replace any "review the work" phrasing with "find what's wrong."

- **Bug-class checklist.** Enumerate the classes the reviewer must scan for, with one-line definitions:
  - **Symmetry violations.** Sibling methods in the same struct/class should follow the same pattern. If method X handles case Y and method Z doesn't, flag it.
  - **Error swallowing.** `_, err := …; result` patterns. `_ = err`. Errors caught and only logged when they should propagate.
  - **Comment-vs-code drift.** Comments that describe behavior the code no longer has, or that name files/functions that have been renamed.
  - **Test-name-vs-body mismatch.** A test named `…_HandlesNotFound` that actually simulates a list-API error, not the not-found case.
  - **Missing edge cases.** Tests covering only the happy path; no empty/nil/malformed inputs; no network-error paths.
  - **Concurrency bugs.** Goroutines/threads without sync; race conditions; channel-close patterns.
  - **Type-coercion silent failures.** Encode/decode where `int → float64` is silently lossy or `[]any → []string` is rejected without a clear error.
  - **Dead/unreachable code.** Branches that no test exercises and no caller can reach.
  - **Scope-vs-dispatch drift.** Did the implementation ship MORE or LESS than the dispatch asked for? Flag both directions.

- **Output format mandate.** Per-finding inline output anchored at file:line, with: severity (Critical / Important / Minor / Nit), bug class (from the list above or "other"), one-sentence "what's wrong," one-sentence "why it matters," one-sentence suggested fix. Prose summaries are forbidden as the primary output.

- **Iterative loop protocol.** Reviewer runs once, surfaces findings; implementer addresses; reviewer **re-reads the new diff from scratch** and runs the full bug-class checklist again. Repeat until clean. The skill should make explicit that one-pass review is insufficient — multiple rounds are expected, mirroring how external adversarial reviewers operate.

- **Scope-vs-dispatch compliance gate.** Before any other check, the reviewer compares the PR diff against the dispatch text (the message that asked the implementer to do the work). If the diff is materially narrower or wider than the dispatch, flag as a blocking finding before reviewing the rest. This is what catches "dispatch said table-driven 9-method test, PR delivered 3 lines on one method."

- **Verdict vocabulary.** Reviewer ends with one of: SHIP-IT, FIX-FORWARD (open follow-up PR), REQUEST-CHANGES (block this PR until fixed), REVERT-AND-REWRITE. Reflexive approval is forbidden — if no findings, state which checks were run.

**Why this works:** the framing change ("find what's wrong") + the checklist (specific bug classes) + iterative loop + line-anchored format together reproduce what external adversarial reviewers do. The same LLM with the same diff produces dramatically different output under this brief vs. the current "review against the plan and standards" prompt.

### 2. `skills/test-driven-development/SKILL.md` — invariant proof + sibling coverage

**Add a new step after GREEN: "Verify Regression Invariant."**

Required steps, in order:
1. Revert the production code change (the fix).
2. Run the new test. **Must FAIL** with a clear message tied to the bug.
3. Restore the fix.
4. Run the test. **Must PASS.**
5. Document the proof in the PR body: paste both runs (or the relevant lines).

Without this proof, the test is unverified — it might pass for the wrong reason (e.g., uses the same broken code path).

**Add a new section: "When the bug is a class invariant violation."**

Heuristic: if the bug arose because one method of a sibling-method group violated a pattern the rest of the group followed, the regression test must drive ALL sibling methods, not just the buggy one. Pattern: table-driven test with one entry per sibling method, asserting the invariant. Failing to do this leaves the bug class open — the next method that drifts the same way ships the same bug.

A heuristic to detect "is this a class invariant violation?" when the implementer is reviewing their own diff:
- Is there a sibling-method group (e.g., several methods on the same struct, same handler family, same RPC service)?
- Does the bug stem from the buggy method failing to follow a convention the rest of the group follows?
- If both yes: the test must be table-driven across the group.

### 3. `skills/finishing-a-development-branch/SKILL.md` — runtime-launch gate + version-skew audit

**Insert a new "Step 1b: Runtime Launch Verification" between Step 1 (Verify Tests) and Step 2 (Determine Base Branch).**

Trigger: the change touches runtime behavior. Specifically, if the diff includes any of:
- Build configuration (Dockerfile, build script, CI build steps)
- Deployment configuration (compose, k8s manifests, deployment workflows)
- Version pins on tooling, runtime, libraries
- Application-startup configuration (config files read at boot)
- Database migrations
- Plugin/extension loading paths

Then before merge or PR open: launch the built artifact under realistic conditions per the new `runtime-launch-validation` skill (see below). Capture the launch transcript + healthcheck observation. Paste into PR body. Without this transcript, the PR is not ready.

Trigger does NOT apply for: pure refactors, documentation, test-only changes, dependency upgrades that are caught by existing tests with no runtime configuration impact.

**Insert a new "Step 1c: Version-Skew Audit" check.**

Trigger: the change includes a version pin update (any "version: vX.Y.Z" or "image: foo:vX.Y.Z" or `go get foo@vX.Y.Z`).

Action:
- Grep the repo for related version pins (other versions of the same component, components in the same release group, sibling tooling).
- For each related pin, check the lag between this version and the related ones.
- If lag is > 2 minor versions, flag in PR body: "version skew detected — pinned X@A.B.0 while related Y@C.D.0; verified compatibility via [reference]."
- Resolve before merging.

Action does NOT apply for: dev-tooling pins (linters, formatters), where skew is benign.

### 4. `skills/runtime-launch-validation/SKILL.md` — NEW SKILL

A small, focused skill referenced by `finishing-a-development-branch` and `writing-plans`.

**Core directive:** After unit tests pass, before merge, launch the built artifact under the closest-to-production conditions feasible locally. Capture the transcript. The launch is the gate; tests are not.

**Per change class:**
- **Application binary (server, CLI):** build it, run it with the production-equivalent config, exercise its primary entry point (HTTP healthcheck, CLI `--version` plus a representative subcommand, etc.), capture stdout/stderr.
- **Container image:** build it, `docker run` with the production-equivalent env, hit `/healthz` (or equivalent), capture container logs and exit code.
- **Database migration:** apply against an ephemeral DB instance, then revert (down migration), then re-apply. Confirm idempotent; confirm no orphaned schema objects.
- **Library/SDK:** import into a tiny consumer program, exercise the new public surface, capture its output.
- **Plugin/extension:** load it into the host application, exercise a representative call, confirm the host doesn't crash on load.

**Failure-signature scrape:** while watching the artifact run, scan output for known failure patterns: panics/uncaught exceptions, "fetch from remote: lookup … no such host" (a missing-pin tell), "module not found," "version mismatch," "schema drift," "permission denied" on resources the artifact should be able to access. Treat any hit as a fail.

**Transcript format for PR body:** the exact commands run, their outputs (relevant lines, not full dumps), the verdict.

**Iron law:** unit-test green ≠ launch green. Engines fail at startup, not at unit-test time. The only proof a runtime artifact works is launching it.

This skill complements `verification-before-completion` (general principle: evidence before assertion). `runtime-launch-validation` is the specific operationalization for runtime artifacts.

### 5. `skills/writing-plans/SKILL.md` — per-change-class verification table + design-only flag

**Add a new section: "Verification per change class."**

A table the plan author uses to populate each task's verification step:

| Change class | Verification | Expected output |
|---|---|---|
| Internal logic refactor | unit tests | all green |
| Schema migration | apply against ephemeral DB; down + re-apply | idempotent, no orphans |
| API endpoint | `curl` (or gRPC) the endpoint with representative inputs | correct status + body |
| Build pipeline / Dockerfile | build artifact + launch + healthcheck (see `runtime-launch-validation`) | transcript captured |
| Version pin update | run version-skew audit + relaunch artifact | transcript + audit clean |
| CLI command | `cmd --help`, then run a representative invocation | help text correct, exit 0 |
| UI component | render in browser/dev server | screenshot or visual confirmation |
| Plugin / extension | load into host + exercise representative call | host doesn't crash on load |
| Documentation / comments | spell-check + render preview | no broken anchors |

Plan tasks that fall in any class except "internal logic refactor" or "documentation" must include a runtime-launch step in their TDD breakdown.

**Add `--design-only` flag.**

When the plan author wants the pipeline to halt after alignment-check (no execution), they pass `--design-only` (or equivalent: a header comment in the plan's first line `<!-- design-only -->`). Writing-plans + alignment-check honor it; subagent-driven-development is not invoked.

The skill explicitly documents this:
- "Default: alignment-check PASS → invoke subagent-driven-development."
- "With `--design-only`: alignment-check PASS → STOP. The plan + design sit in `docs/plans/` for future execution. Useful for design exploration ahead of capacity."

### 6. `skills/brainstorming/SKILL.md` — design-only flag

Mirror the same `--design-only` behavior on the brainstorming skill: when set, brainstorming hands off to writing-plans WITH `--design-only` propagated. Writing-plans halts at alignment-check.

Document the propagation explicitly so a user passing `--design-only` to brainstorming gets the expected behavior all the way through.

### 7. `skills/subagent-driven-development/SKILL.md` — DRY team boilerplate

The implementer-prompt template currently inlines team conventions ("commit before review request," "self-review checklist," "TDD discipline," etc.). Each spawn re-emits this. P10 fix:

- Move the boilerplate to a single referenced file: `agents/team-conventions.md` (or similar shared template).
- Implementer prompt becomes: "You are implementer-N on team X. Follow team conventions: <link/include team-conventions.md>. Your task: <task description>." The body of conventions is one source of truth.
- Same for spec-reviewer and code-reviewer prompts.

This makes orchestrator briefs shorter, reduces drift between dispatches, and makes the conventions easier to evolve in one place.

### 8. No changes to: `alignment-check`, `verification-before-completion`, `using-git-worktrees`, `writing-skills`, `dispatching-parallel-agents`, `receiving-code-review`, `pr-monitoring`

These skills are either already correct on the relevant patterns (verification-before-completion, dispatching-parallel-agents, receiving-code-review, alignment-check) or tangential to this design (using-git-worktrees, writing-skills, pr-monitoring).

## Pattern → skill mapping (forward trace)

| Pattern | Skill modified | Section added |
|---|---|---|
| P1 ("Local validation" unreliable) | `runtime-launch-validation` (new) + `finishing-a-development-branch` (Step 1b) + `verification-before-completion` (already strong) | Runtime-launch gate when triggers fire |
| P2 (Narrow regression tests) | `test-driven-development` | "When the bug is a class invariant violation" |
| P3 (No invariant proof) | `test-driven-development` | "Verify Regression Invariant" step after GREEN |
| P4 (Version skew unflagged) | `finishing-a-development-branch` | "Step 1c: Version-Skew Audit" |
| P5 (Sequential dispatch) | (already addressed in `dispatching-parallel-agents`) | none |
| P6 (Adversarial review gap) | `requesting-code-review` | Major rewrite — bug-class checklist, adversarial framing, iterative loop, scope-vs-dispatch gate, line-anchored output, verdict vocabulary |
| P7 (No runtime-launch gate) | `finishing-a-development-branch` (gate) + `runtime-launch-validation` (new skill) | Step 1b runtime verification |
| P8 ("Validate locally" undefined) | `writing-plans` | "Verification per change class" table |
| P9 (Pipeline auto-chains) | `brainstorming` + `writing-plans` | `--design-only` flag |
| P10 (Boilerplate per dispatch) | `subagent-driven-development` | DRY team-conventions extraction |

## Architecture / cross-skill flow

```
brainstorming
    │
    ├── (default) → writing-plans
    │                    │
    │                    ├── (default) → alignment-check ✓ → subagent-driven-development
    │                    │                                          │
    │                    │                                          ├── implementer dispatched (uses team-conventions.md DRY)
    │                    │                                          ├── implementer follows test-driven-development
    │                    │                                          │   • RED → GREEN
    │                    │                                          │   • [NEW] Verify Regression Invariant
    │                    │                                          │   • [NEW] Sibling-method coverage if class invariant
    │                    │                                          ├── spec-reviewer
    │                    │                                          ├── code-reviewer (NEW BRIEF)
    │                    │                                          │   • Adversarial framing
    │                    │                                          │   • Bug-class checklist
    │                    │                                          │   • Scope-vs-dispatch gate
    │                    │                                          │   • Line-anchored output
    │                    │                                          │   • Iterative loop until clean
    │                    │                                          └── finishing-a-development-branch
    │                    │                                                 • Step 1: tests green
    │                    │                                                 • [NEW] Step 1b: runtime-launch-validation if triggers
    │                    │                                                 • [NEW] Step 1c: version-skew audit if pins changed
    │                    │                                                 • Step 2+: PR / merge
    │                    │
    │                    └── (--design-only) → alignment-check ✓ → STOP
    │
    └── (--design-only) → writing-plans (--design-only propagated)
```

## Phasing

This is one autonomous run. The implementer will likely split into multiple PRs for review ergonomics — that's their call. Suggested split (advisory, not prescriptive):

- **PR 1**: `requesting-code-review` rewrite (the big one). Land independently because it's the biggest impact and the largest file change.
- **PR 2**: `test-driven-development` additions (invariant proof + sibling coverage).
- **PR 3**: `finishing-a-development-branch` additions (runtime gate + version-skew audit) + new `runtime-launch-validation` skill (since #3 references it).
- **PR 4**: `writing-plans` additions (verification table + design-only flag) + `brainstorming` design-only flag (because they propagate together).
- **PR 5**: `subagent-driven-development` DRY refactor.

Implementer can bundle if review capacity allows; the dependency between #3's two parts and between #4's two parts is the only ordering constraint.

## Testing strategy

This is a documentation/skills repo. Testing for skills uses the `writing-skills` discipline: each new section/protocol should have a baseline test that demonstrates its absence allowed a known failure mode, and a passing test that demonstrates the new content prevents recurrence.

For each major addition:

1. **Adversarial-review brief (P6)**: a fixture diff with a known sibling-asymmetry bug. Run the OLD reviewer prompt → confirm it approves (baseline). Run the NEW prompt → confirm it flags. Capture both transcripts as test fixtures.

2. **Invariant proof step (P3)**: a fixture commit where a "test was written" but actually doesn't fail without the fix. Show that the OLD test-driven-development steps would let this through; the NEW invariant proof catches it.

3. **Runtime-launch gate (P7)**: a fixture diff that bumps a tooling version pin where the new version's launch contract differs incompatibly. OLD finishing-a-development-branch → would PR. NEW gate → catches.

4. **Version-skew audit (P4)**: a fixture diff with version pin lag of 4 minor versions on a related component. OLD → would merge. NEW → flagged.

5. **Sibling-method coverage (P2)**: a fixture diff where one method of a 9-method group violates an invariant the others follow. OLD test-driven-development → narrow test passes review. NEW → table-driven test required.

The implementer will create these fixtures as part of the work and document the before/after behavior in the PR body. This is the writing-skills discipline applied to skill changes.

## Risk and rollback

- **Risk: skill-spreading-out makes existing flows slower.** Mitigation: every new step has a clear trigger condition. A pure refactor or doc change still runs the original quick path.
- **Risk: the bug-class checklist becomes a checkbox exercise** that loses adversarial spirit. Mitigation: the framing prompt ("find at least three things wrong") is explicit and adversarial; the checklist is the floor, not the ceiling.
- **Risk: runtime-launch-validation requires Docker/runtime tooling that not every contributor has.** Mitigation: the trigger conditions are narrow; refactor-only changes still pass without runtime launch. The skill includes a "fall-back to system tools / skip with documented reason" escape for environments without Docker, but the implementer must justify in the PR body.
- **Rollback:** every change is additive to existing skill files (or a new skill). Reverting a single PR removes the change cleanly. The `requesting-code-review` rewrite is the largest file change but it replaces a section, not the whole skill.

## Approval

Approved by user via the autonomous-mode brainstorm dispatch with full pipeline (brainstorm → writing-plans → alignment-check → subagent-driven-development → finishing → pr-monitoring). Implementer: per the orchestrator's team configuration. PR(s) targeted at `GoCodeAlone/autonomous-dev-kit` main with newly-active branch protection.
