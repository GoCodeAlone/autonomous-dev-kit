---
name: brainstorming
description: "You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation."
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Brainstorming Ideas Into Designs

## Overview

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions using adaptive batching to refine the idea. Once you understand what you're building, present the design and get user approval.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single-function utility, a config change — all of them. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short (a few sentences for truly simple projects), but you MUST present it and get approval.

## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Explore project context** — check files, docs, recent commits
2. **Apply project design guidance** — invoke `autodev:project-design-guidance`; read existing guidance or run its Q&A if no durable guidance exists
3. **Ask clarifying questions** — adaptive batching: group related questions to reduce round-trips; use targeted singles for follow-ups
4. **Propose 2-3 approaches** — with trade-offs and your recommendation
5. **List load-bearing assumptions explicitly** — every design rests on assumptions ("upstream API is idempotent", "single-tenant", "user has admin"); write them down so the adversarial reviewer can attack them
6. **Self-challenge round** — before presenting to the user, role-play a skeptic against your own design and surface the top 3 doubts (see "Self-challenge round" below). Cleans up obvious issues before the user sees the design.
7. **Present design** — in sections scaled to their complexity, get user approval after each section. Include the assumption list, project-guidance fit, and the top doubts surfaced by the self-challenge so the user sees them.
8. **Write design doc** — save to `docs/plans/YYYY-MM-DD-<topic>-design.md` and commit. Use `autodev:condensed-pipeline-writing` for internal density. The doc MUST include `## Global Design Guidance`, `## Security Review`, `## Infrastructure Impact`, `## Multi-Component Validation`, `## Assumptions`, and a `## Rollback` section for change classes that affect runtime (build, deployment, version pins, startup config, migrations, plugin loading paths) — same trigger list as `runtime-launch-validation`.
9. **Adversarial design review** — invoke `adversarial-design-review --phase=design`. On FAIL, revise per tangible Critical/Important findings and re-run until the review converges to no tangible issues (remaining nitpicks become Minor PASS items). On PASS, proceed.
10. **Transition to implementation** — invoke writing-plans skill to create implementation plan

## Process Flow

```dot
digraph brainstorming {
    "Explore project context" [shape=box];
    "Apply project guidance" [shape=box];
    "Ask clarifying questions" [shape=box];
    "Propose 2-3 approaches" [shape=box];
    "List assumptions" [shape=box];
    "Self-challenge round" [shape=box];
    "Present design sections" [shape=box];
    "User approves design?" [shape=diamond];
    "Write design doc" [shape=box];
    "Adversarial design review" [shape=diamond];
    "Invoke writing-plans skill" [shape=doublecircle];

    "Explore project context" -> "Apply project guidance";
    "Apply project guidance" -> "Ask clarifying questions";
    "Ask clarifying questions" -> "Propose 2-3 approaches";
    "Propose 2-3 approaches" -> "List assumptions";
    "List assumptions" -> "Self-challenge round";
    "Self-challenge round" -> "Present design sections";
    "Present design sections" -> "User approves design?";
    "User approves design?" -> "Present design sections" [label="no, revise"];
    "User approves design?" -> "Write design doc" [label="yes"];
    "Write design doc" -> "Adversarial design review";
    "Adversarial design review" -> "Write design doc" [label="FAIL: revise"];
    "Adversarial design review" -> "Invoke writing-plans skill" [label="PASS"];
}
```

**The terminal state is invoking writing-plans** (after adversarial review passes). Do NOT invoke frontend-design, mcp-builder, or any other implementation skill. The ONLY skill you invoke after brainstorming is `adversarial-design-review` and then `writing-plans`.

## The Process

**Understanding the idea:**
- Check out the current project state first (files, docs, recent commits)
- Invoke `autodev:project-design-guidance` before finalizing questions or approaches. If no durable guidance exists, ask the guidance Q&A first so the feature-specific brainstorm is not designed in isolation.
- Ask questions using adaptive batching — group related questions to reduce round-trips:
  - **First batch:** covers purpose, constraints, scope, and tech choices
  - **Follow-ups:** Targeted single questions based on interesting or ambiguous answers

  <host: claude-code>
  - Use multiple choice options when possible (AskUserQuestion supports 2-4 options per question)
  - AskUserQuestion supports up to 4 questions per form — use this to reduce round-trips
  </host>

  <host: codex, opencode, cursor, zed-agent>
  - Present options as a numbered list and ask the user to reply with the chosen number
  - Group no more than 3 questions per turn to avoid overloading the chat
  </host>

  <host: hermes-agent>
  - Use the `clarify` tool for multiple-choice questions (up to 4 options)
  - Group no more than 3 questions per turn to avoid overloading the chat
  </host>

- Focus on understanding: purpose, constraints, success criteria

**Exploring approaches:**
- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why

**Presenting the design:**
- Once you believe you understand what you're building, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing, **global design guidance fit**, **security review**, **infrastructure impact**, **multi-component validation**, **assumptions** (load-bearing claims), **rollback** (for runtime-affecting change classes)
- Include the top 3 doubts surfaced by the self-challenge round so the user can react before approving
- Be ready to go back and clarify if something doesn't make sense

## Self-challenge round

Before presenting the design to the user, role-play a skeptic against your own design for one short pass. The goal is to clean up the obvious issues *before* the user sees them and *before* the heavyweight `adversarial-design-review` runs.

Ask yourself, in order, and keep notes:

1. **What's the laziest plausible solution to the user's actual ask?** Could a flat file, a cron job, or a single SQL view do it? If yes, why does the design pick something heavier?
2. **Which of my listed assumptions, if false, would break this design?** Pick the most fragile one.
3. **What does this design solve that the user did NOT ask for?** YAGNI sweep — list any feature, knob, or generality that isn't traceable to the user's stated goals.
4. **What fails first under partial failure / restart-mid-operation / malformed input?** Pick one and decide whether the design addresses it.
5. **Does this design fight any existing pattern in the repo?** If yes, name the conflicting `path/file.md`.

If any answer surfaces a real issue, revise the design before presenting it. Otherwise, surface the top 3 doubts to the user when you present (so they can decide whether the trade-offs are acceptable). This is a 30-second exercise, not a debate.

This is intentionally lightweight; the heavyweight pass is `adversarial-design-review`, which runs after the design is committed.

## Question-batch budget (cost-control gate)

A brainstorming session has a **soft cap of 5 question-batches** before the agent must converge. A "batch" is one round-trip — one outgoing message that contains questions (whether one targeted follow-up or four AskUserQuestion-style options). The cap exists so a session cannot spiral indefinitely while the user keeps answering; convergence is a feature, not an accident.

**Counting rule:** every outgoing message that asks the user a question counts as one batch, regardless of how many sub-questions it bundles. Re-asking a question to clarify the user's prior answer also counts. Pure status messages ("I'm exploring the codebase…") do not count.

**On reaching the cap:**

1. **Stop asking.** Do not send a 6th question batch.
2. **Present the best-current-approximation design** using whatever signal you have. State explicitly which sections you are less confident about and why (which questions were not asked, which were answered ambiguously).
3. **Ask the user, with three multiple-choice options, how to proceed:**
   - **Approve as-is** — accept the approximation; proceed to design doc + adversarial review.
   - **Refine specific sections** — name the sections; the agent gets ONE additional batch (capped at 4 questions) targeting those sections only, then re-presents.
   - **Extend the budget** — explicit user opt-in to N more batches (user picks N; agent confirms before continuing).

The "extend the budget" option exists because some genuinely complex designs need more conversation; the cap is soft, not a hard refusal. But the user must explicitly opt in — the agent cannot extend on its own.

**Why a cap at all:** brainstorming is the most user-facing skill in the plugin. Question fatigue is a real failure mode. Capping at 5 batches forces the agent to commit to an approximation rather than stalling — and the user can always explicitly extend.

## Design-only mode

When the user wants design exploration without execution, they pass `--design-only` to brainstorming.

**Behavior under `--design-only`:**

1. Run the full brainstorming flow (explore context → project-design-guidance → questions → approaches → assumptions → self-challenge → design → write design doc → commit).
2. Invoke `adversarial-design-review --phase=design`. On FAIL, revise the design and re-run while tangible Critical/Important findings remain. When only nitpicks remain, record them as Minor and proceed on PASS. Escalate only for unresolved tangible findings that require user input — no plan dispatched.
3. On PASS, invoke writing-plans, propagating the `--design-only` flag.
4. writing-plans honors the flag: adversarial-design-review (plan phase) PASS → alignment-check PASS → STOP (no execution dispatched). On FAIL at any gate, writing-plans revises and re-checks per its normal FAIL handling, then stops — still no execution dispatched. On persistent tangible findings that require user input, escalates to user — no execution dispatched regardless.
5. The pipeline ends with a committed design doc + plan in `docs/plans/` plus the adversarial review reports.

**Default (no flag):** brainstorming → adversarial-design-review (design) → writing-plans → adversarial-design-review (plan) → alignment-check → subagent-driven-development → … (autonomous handoff to execution).

## After the Design

**Documentation:**
- Committed artifacts use repo-relative paths; illustrate machine paths only with `<placeholder>` segments (e.g. `/Users/<name>/…`); never a literal operator-home path. Enforced by `tests/no-machine-paths.sh`.
- Write the validated design to `docs/plans/YYYY-MM-DD-<topic>-design.md`
- Include explicit `## Global Design Guidance`, `## Security Review`, `## Infrastructure Impact`, `## Multi-Component Validation`, `## Assumptions`, and `## Rollback` sections (rollback only required for change classes that affect runtime — see the trigger list in `runtime-launch-validation` / `finishing-a-development-branch` Step 1b)
- Use elements-of-style:writing-clearly-and-concisely skill if available
- **Record decisions** — if the design triggers any condition in `skills/recording-decisions/SKILL.md` (divergence from precedent, non-trivial trade-off between ≥2 plausible approaches, adversarial-review override, cross-skill structural change), invoke `recording-decisions` to add an ADR in `decisions/`, then cite it from this design doc
- Commit the design document to git (and any new ADRs in the same commit)

**Adversarial review (mandatory):**
- Invoke `adversarial-design-review --phase=design` against the committed design
- On PASS, proceed to autonomous handoff
- On FAIL, revise the design based on Critical and Important findings and re-run until the review stops finding tangible issues; remaining nitpicks are recorded as Minor and do not keep the loop alive
- The user may override a finding (mark it accepted with reasoning recorded in the design doc)

**Autonomous handoff:**
- This is the user's **last interaction point** — everything after runs autonomously
- Invoke the writing-plans skill with autonomous context: the design is approved AND adversarially reviewed, no further user input needed
- The writing-plans skill will prefer host-native planning mode when available, falling back to its built-in planning process otherwise
- The pipeline from here: writing-plans → adversarial-design-review (plan phase) → alignment-check → team execution → PR creation → PR monitoring
- Do NOT invoke any other skill. `adversarial-design-review` runs first; on PASS, writing-plans is the next step. It handles the rest of the autonomous pipeline.

## Key Principles

- **Adaptive question batching** - Group related questions to reduce round-trips; use targeted singles for follow-ups
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Make assumptions explicit** - Load-bearing assumptions belong in writing, not in the agent's head
- **Inherit project guidance** - Every design reads or creates project-wide guidance before choosing an approach
- **Self-challenge before presenting** - Cleans up obvious issues; saves the user a round-trip
- **Adversarial review before execution** - The cheapest place to kill a bad idea is before the plan is written
- **Incremental validation** - Present design, get approval before moving on
- **Be flexible** - Go back and clarify when something doesn't make sense
- **Design approval = autonomy handoff** - After design approval AND adversarial review pass, the pipeline runs without user input
