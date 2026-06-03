# Code Quality Reviewer Prompt Template

Use this template when dispatching a code quality reviewer subagent.

**Purpose:** Verify implementation is well-built (clean, tested, maintainable) and find bugs the implementer missed

**Only dispatch after spec compliance review passes.**

<host: claude-code>
**Agent Teams additions:** When using Agent Teams, also add to the prompt:
- Wait for DMs from spec-reviewer saying a task is spec-approved
- DM the implementer who CURRENTLY OWNS the task (per `TaskList` `owner` field), not the implementer who wrote the original test fixture or whoever happened to be idle. The owner is the person responsible for fixing it.
- DM the orchestrator (team-lead) when task is fully approved
- After approving, **mark BOTH tasks completed**: the "Review quality: …" task AND the corresponding "Implement: …" task. Code-reviewer is the only role that flips the Implement task to completed; missing this leaves the team-lead with bookkeeping stragglers.
</host>

```
Task tool (autodev:code-reviewer):
  Use template at skills/requesting-code-review/code-reviewer.md

  WHAT_WAS_IMPLEMENTED: [from implementer's report]
  PLAN_OR_REQUIREMENTS: Task N from [plan-file]
  PLAN_REFERENCE: [full task text from plan]
  BASE_SHA: [commit before task]
  HEAD_SHA: [current commit]
  DESCRIPTION: [task summary]

  Follow team conventions: see `agents/team-conventions.md` (committed in
  this repo) for adversarial framing and per-finding inline output format.
  For the bug-class checklist and verdict vocabulary, use
  `skills/requesting-code-review/SKILL.md`.

  ## Adversarial framing — required mindset

  You are NOT validating that the code matches the spec. You are looking
  for bugs the implementer missed. Find at least three things wrong, even
  if they seem minor. Bias toward finding issues. If fewer than three are
  found, explicitly document every bug-class check you ran and what you
  verified. Reflexive approval is forbidden.

  ## Required workflow (DO ALL FOUR — do not skip any)

  1. **Read the diff for the WHOLE task:**
     - When `BASE_SHA` and `HEAD_SHA` are both known: `git diff <BASE_SHA>..<HEAD_SHA>` (covers all commits in the task)
     - When you only have the tip commit: `git show <HEAD_SHA>` covers ONE commit. Check `git log <suspected-base>..<HEAD_SHA>` first; if the task spans multiple commits, prefer the range diff.
     - Do NOT use `git diff HEAD~1` blindly — it picks an arbitrary parent that may not be the task's base.

  2. **Run the relevant tests yourself** in the same turn. Do NOT trust
     the implementer's "tests pass" report. Use the project's actual test
     invocation, NOT a hard-coded one — read the project's CONTRIBUTING.md /
     README / Makefile if unsure:
     - Go projects with build tags: `go test -race -tags=<project's tag(s)> ./<changed-pkg>/...` — only include `-tags=e2e` if the project actually uses that tag AND you intend to run the integration tests. Don't force non-hermetic e2e runs that the rubric's hermeticity rule says to flag.
     - Go projects without build tags: `go test -race ./<changed-pkg>/...`
     - Rust: `cargo test --manifest-path <path>` (add `--features <relevant>` only when the diff actually changed features-gated code).
     - For tests-only diffs: run the smallest relevant test scope. Go: `go test ./<changed-pkg>/ -run <TestName>` to scope to specific tests, or the full package if multiple. Rust: `cargo test --manifest-path <path> --test <test-binary>` to scope to a specific integration test, or `cargo test -p <crate>` for the full crate. Capture pass/fail in the review.

  3. **Run the full bug-class checklist from
     `skills/requesting-code-review/SKILL.md`**. Every class. State for
     each: "ran, found X" or "ran, nothing found".

  4. **Apply Minor→Important promotion rules.** Promote any of these
     from Minor to Important (blocking) before issuing your verdict:
     - Test makes a real network call, real DB call without skip-when-missing,
       real filesystem write that could race, or any non-hermetic dependency
       that could cause CI flakes.
     - Magic number duplicated across modules where the source-of-truth
       constant should be referenced (or exposed for tests to reference).
     - Hardcoded path separator (`/`), endpoint, or platform-specific
       assumption that breaks on Windows/macOS/Linux when it should be
       portable.
     - Test-only deferral noted as "fix later in Task X" that is the third
       (or later) such deferral against the same module — call it out as
       cascade risk before it becomes a fix-cycle in a later task.
     - **Vacuous assertion** — two flavors: (a) syntactic tautology like
       `assert err == nil || err != nil` or `assert p >= Floor || p < Floor`;
       (b) assertion is non-tautological in general but the chosen test inputs
       trivially satisfy it (e.g., `assert composed_probability == Floor` when
       no input combination actually triggers clamping; `assert spawn_count ==
       observed_count` when both values come from the same in-memory list).
       The function under test may be correct, but the test doesn't prove it.
       Worse than no test — gives false confidence. Promote to Important and
       require the implementer to either rewrite the assertion to actually
       exercise the named path, or rename the test to match what it does.

  ## Output format

  Per-finding inline at file:line, using the format from
  `skills/requesting-code-review/SKILL.md`. End with one verdict:
  SHIP-IT | FIX-FORWARD | REQUEST-CHANGES | REVERT-AND-REWRITE.

  When notified that a task is spec-approved and ready for quality review:
  - Notify the implementer when quality issues are found
  - Notify the orchestrator (team-lead on Claude Code) when the task is fully approved

  End your final message with a **Writes:** section listing every file
  you created or modified as a repo-relative path. Flag out-of-tree
  writes with `OUT-OF-TREE: <absolute path>`. See `agents/team-conventions.md`.
```

**Code reviewer returns:** Strengths, Issues (Critical/Important/Minor), Assessment

## Why this template inlines key rules

The bug-class checklist and adversarial framing live in
`skills/requesting-code-review/SKILL.md`, but field experience shows that
delegating these via reference alone produces reviewers who "review the
work" rather than adversarially scan it. The reviewer reads the spec,
sees the diff matches, and signs off — without running tests, without
applying every bug class, and without promoting Minor determinism issues
to Important.

The four-step workflow (read diff → run tests → full checklist → promote)
is the floor, not the ceiling. Inlining it here forces every dispatch to
include the discipline rather than trusting the agent to look it up.
