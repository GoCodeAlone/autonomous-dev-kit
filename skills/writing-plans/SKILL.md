---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** This should be run in a dedicated worktree (created by brainstorming skill).

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

## Native Planning Mode Detection

**Prefer host-native planning mode when available.** If the current agent interface offers a dedicated planning mode, use it to draft the implementation plan. If no planning mode is available, use the Built-In Planning Process below.

### Using Host-Native Planning Mode

1. **Enter planning mode** — explore the codebase, analyze the design, and draft the implementation plan using the host's native planning workflow
2. **Follow the plan format below** — structure your Plan Mode output using the same Plan Document Header and Task Structure defined in this skill
3. **Exit planning mode** — once the plan is fully drafted
4. **Save the plan** — write the plan to `docs/plans/YYYY-MM-DD-<feature-name>.md` using the exact format from Plan Document Header and Task Structure sections below
5. **Continue the pipeline** — proceed to Execution Handoff as normal

The plan document you save MUST follow the same format described in Plan Document Header and Task Structure below, regardless of whether it was drafted in Plan Mode or with the built-in process. This ensures downstream skills (alignment-check, executing-plans, subagent-driven-development) work correctly.

### Built-In Planning Process

When host-native planning mode is not available, use the full planning process described in the sections below to write the plan directly.

## Autonomous Mode

When invoked from brainstorming with autonomous context (design already approved AND adversarially reviewed):

1. **Skip user plan review** — write the plan directly without presenting it for approval
2. **Invoke `autodev:adversarial-design-review --phase=plan`** — adversarially attack the plan (and inherited design) before structural alignment is checked
3. **On adversarial-review PASS** — invoke `autodev:alignment-check`
4. **On adversarial-review FAIL** — revise the plan based on tangible Critical and Important findings, re-run adversarial review until it converges to no tangible issues; remaining nitpicks become Minor PASS items
5. **On alignment PASS** — invoke `autodev:subagent-driven-development` to begin execution
6. **On alignment FAIL** — revise the plan based on drift items, re-check (max 2 cycles)
7. **On persistent FAIL at any gate** — escalate to user only when unresolved tangible findings/drift require human input

The autonomous flag propagates through the entire pipeline: writing-plans → adversarial-design-review (plan phase) → alignment-check → execution → PR creation → PR monitoring.

## Design-only mode

Design-only mode is active if ANY of: `--design-only` flag or propagation from brainstorming. If signals conflict, the most-restrictive wins (i.e., design-only takes effect).

This section applies to the autonomous brainstorming → writing-plans → alignment-check → execution pipeline. In that pipeline, the default (no flag) is to dispatch execution after alignment passes. For direct/manual invocations of `writing-plans`, execution is never auto-dispatched regardless — the user chooses (see Manual Mode below). In other words, `--design-only` suppresses the automatic execution handoff in autonomous runs; it does not change manual invocation behavior.

Do not add YAML frontmatter to signal design-only mode. Saved plan documents must keep the standard format so downstream skills can parse them reliably, with `# [Feature Name] Implementation Plan` as the first line of the file.

**Behavior in design-only mode:**

1. Save the plan to `docs/plans/YYYY-MM-DD-<feature-name>.md` as normal.
2. Commit the plan as normal.
3. Invoke `autodev:adversarial-design-review --phase=plan` as normal.
4. On adversarial-review FAIL: revise the plan based on tangible findings and re-run adversarial review until it converges to no tangible issues.
5. On adversarial-review PASS: invoke `autodev:alignment-check` as normal.
6. **On alignment PASS: STOP.** Do NOT invoke `autodev:subagent-driven-development`.
7. **On alignment FAIL:** revise the plan based on drift items and run `autodev:alignment-check` again, with a maximum of 2 alignment-check cycles total. If a revised plan passes alignment, still STOP and do not proceed to execution.
8. **On persistent FAIL at any gate:** escalate to the user with an unresolved findings/drift summary only when tangible findings or drift require human input. Do NOT invoke `autodev:subagent-driven-development` or dispatch any execution.
9. The plan + design + adversarial review reports sit in `docs/plans/` for future execution. The orchestrator (or a future invocation) can resume by passing the plan to `autodev:subagent-driven-development` directly once gate issues are resolved.

**When to use:**

- Design exploration ahead of available implementation capacity.
- Cross-cutting designs that affect multiple workstreams; lock the design in before any one workstream starts.
- Designs with prerequisites in-flight elsewhere; queue the plan now, execute when prerequisites land.

**Default (no flag):** `autodev:adversarial-design-review --phase=plan` PASS → `autodev:alignment-check` PASS → invoke `autodev:subagent-driven-development`. Adversarial review runs **before** alignment check so that idea-level findings are resolved before structural trace.

## Verification per change class

When writing a plan task, the verification step must match the change class. A green unit-test run is sufficient ONLY for internal-logic refactors. Other classes need stronger evidence.

| Change class | Verification | Expected output |
|---|---|---|
| Internal logic refactor | unit tests | all green |
| Schema migration | apply against ephemeral DB; down + re-apply | no orphaned tables; migration tool reports applied / schema version updated |
| API endpoint | exercise endpoint with representative inputs (curl, gRPC, etc.) | HTTP 200 + expected JSON body |
| Build pipeline / Dockerfile | build artifact + launch + healthcheck (see `runtime-launch-validation`) | transcript captured; exit 0 |
| Version pin update | run version-skew audit (see `finishing-a-development-branch` Step 1c) + relaunch artifact | transcript captured; audit clean |
| CLI command | `cmd --help` + representative invocation | help text correct; exit 0 |
| UI component | render in browser/dev server | screenshot or visual confirmation |
| Plugin / extension | load into host + exercise representative call | exit 0; representative call returns expected value |
| Documentation / comments | spell-check + render preview | no broken anchors |
| Hook / trigger / event handler | fire the event; observe handler runs | logged side effect confirmed; assertion passes |
| Multi-component boundary | run an integration/E2E path with real adjacent components where feasible | request/event crosses boundary; downstream side effect observed |
| Infrastructure change | render/validate/plan/dry-run plus targeted apply in safe env when available | expected resource diff; no destructive prod action without approval |
| Go-repo code change | `golangci-lint run --new-from-rev=origin/<base>` before push | exit 0 |

These examples are illustrative minimums; per-task `Expected:` fields must be literal values the check can assert against.

Every plan task must include the verification step appropriate to its change class, as defined in the table above. For tasks whose `finishing-a-development-branch` Step 1b trigger conditions are met (build configuration, deployment configuration, version pins on runtime components, startup configuration, migrations, plugin loading paths), include the runtime-launch-validation step in the TDD breakdown as well **and include a one-line rollback note** in the task ("Rollback: revert commit + re-run migration tool down + smoke check"; "Rollback: pin to previous version X.Y.Z and rebuild"). Hook/trigger/event-handler changes are NOT in the Step 1b trigger list — they use only the class-appropriate verification from the table.

The rollback note exists so that adversarial-design-review (plan phase) can verify the design's rollback story is actually wired into the plan, not orphaned in a paragraph. Plans without rollback notes for runtime-affecting tasks will fail adversarial review.

## Multi-Component and Infrastructure Proof

Plans must turn design-level validation into executable checks:

- **Multi-component systems:** include at least one task or verification step that
  exercises the real boundary. Examples: API writes DB and worker consumes row;
  frontend calls backend and renders returned state; plugin loads in host and
  executes representative call; CLI command reaches service and observes side
  effect. Mock-only tests are allowed only when the design explains why the real
  boundary cannot be exercised locally.
- **Infrastructure changes:** include render/validate/plan/dry-run checks for
  IaC or deployment config. If a safe sandbox apply is available, include it.
  Destructive or production actions require explicit human approval already
  recorded in the plan.
- **Security-sensitive changes:** include verification for auth/authz behavior,
  secret redaction, least-privilege permissions, and representative abuse cases
  when applicable.

## Recording decisions

If the plan introduces a non-trivial choice that wasn't already captured by an ADR cited in the design (e.g., a library pick, a sync-vs-async choice, a polling-vs-webhook decision made at plan time rather than at design time), invoke `skills/recording-decisions/SKILL.md` to add an ADR in `decisions/` and cite it from the relevant task. ADRs are how the *why* survives renames and refactors; the design and plan answer *what*.

If every decision in the plan is already covered by ADRs cited from the design, skip this step.

The plan author writes the expected output literally — not "passes tests" but "logs `engine ready` within 10 seconds and `/healthz` returns 200".

## Project Design Guidance

Before writing tasks, invoke `autodev:project-design-guidance` and read the
guidance source cited by the design's `## Global Design Guidance` section.

Plans must map guidance to work:

- If guidance requires behavior, add or cite a task that implements it.
- If guidance requires verification, include the exact command or inspection.
- If guidance requires rollback, privacy, observability, accessibility, or
  deployment safeguards, wire those into relevant tasks.
- If the plan intentionally violates guidance, cite the ADR that approves the
  exception. Without an ADR, the plan should fail adversarial review.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Base branch:** [main | develop | other]

---
```

## Scope Manifest (REQUIRED)

Every plan MUST contain a `## Scope Manifest` section immediately after the header. This section is the **scope contract** between the plan author and the execution pipeline. After `alignment-check` passes, the manifest is locked (see `skills/scope-lock/SKILL.md`). Without the manifest, alignment-check fails and execution cannot start.

```markdown
## Scope Manifest

**PR Count:** N
**Tasks:** N
**Estimated Lines of Change:** ~N (informational; not enforced)

**Out of scope:**
- <explicit non-goal>
- <explicit non-goal — if truly nothing, write "(none)" — empty bullets are not allowed>

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | <PR title> | Task 1, Task 2 | feat/<slug>-1 |
| 2 | <PR title> | Task 3, Task 4 | feat/<slug>-2 |
| ... | ... | ... | ... |

**Status:** Draft
```

**Authoring rules:**

- **PR Count must match the PR Grouping table row count.** If the work fits in a single PR, the table has one row — write it anyway. The downstream gate enforces this.
- **Tasks must match the count of `### Task N:` headings in the plan body.** Every task in the body appears in exactly one PR row. No orphan tasks; no phantom tasks.
- **`**Out of scope:**` is not optional.** If the design genuinely has no non-goals, write `(none)`. Forcing the author to think about what is *not* being built reduces the chance the executing agent will helpfully add it.
- **Each PR is independently reviewable and revertible.** If you can't say what each PR delivers in one sentence, the grouping is wrong — go back to the design.
- **Status starts as `Draft`.** `alignment-check` flips it to `Locked …` after PASS. Manual edits to the Status line by anyone other than alignment-check / scope-lock are a contract violation.

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

**Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

**Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## Remember
- Exact file paths always
- Complete code in plan (not "add validation")
- Exact commands with expected output
- Reference relevant skills with @ syntax
- DRY, YAGNI, TDD, frequent commits

## Execution Handoff

### Autonomous Mode (from brainstorming pipeline)

When running autonomously (design already approved AND adversarially reviewed, no user interaction):

1. Save the plan to `docs/plans/<filename>.md` using `autodev:condensed-pipeline-writing` for internal density
2. Commit the plan
3. Invoke `autodev:adversarial-design-review --phase=plan` to attack the plan's ideas
4. On adversarial-review PASS: invoke `autodev:alignment-check` to verify design-to-plan structural alignment
5. On alignment PASS: invoke `autodev:subagent-driven-development` (which uses Agent Teams when available)
6. On adversarial-review FAIL: revise per tangible findings and re-run until no tangible Critical/Important issues remain; on alignment FAIL: revise per drift and re-check (max 2 alignment cycles), then either continue or escalate to user when human input is required
7. Do NOT ask the user for execution choice — the pipeline is autonomous

### Manual Mode (direct invocation)

When invoked directly by the user (not from brainstorming pipeline):

**"Plan complete and saved to `docs/plans/<filename>.md`. Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use autodev:subagent-driven-development
- Stay in this session
- Fresh subagent per task + code review

**If Parallel Session chosen:**
- Guide them to open new session in worktree
- **REQUIRED SUB-SKILL:** New session uses autodev:executing-plans
