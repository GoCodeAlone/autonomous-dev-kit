---
name: recording-decisions
description: Use when the design or plan makes a non-trivial trade-off that future contributors will need context for - records an Architecture Decision Record (ADR) in decisions/ so the rejected alternatives and reasoning are durable, not lost in transcript history
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Recording Decisions

ADR = durable "why this, not that." Design/plan = what; ADR = trade-off, rejected paths, consequences.

## Use

Write ADR when ≥1 true:

| trigger | record |
|---|---|
| precedent Δ | repo pattern changed |
| real trade-off | ≥2 plausible options, choice not obvious from code |
| review override | Important/Critical finding accepted-with-reason, not fixed |
| cross-skill shape Δ | pipeline/gate/contract affects multiple skills |
| locked manifest amendment | human-approved scope/task/PR change; cite from manifest + PRs |

Skip if no future maintainer would ask "why?"

## Flow

1. Find next id:
   ```bash
   ls decisions/ | grep -E '^[0-9]{4}-' | sort | tail -1
   ```
2. Copy `decisions/0000-template.md` → `decisions/NNNN-short-slug.md`; slug kebab, ≤6 words.
3. Fill Context/Decision/Consequences. Target ≤150 words/section.
4. Status: new = `Accepted`; old decision changed = old `Superseded by NNNN`, new cites old.
5. Back-link from triggering design/plan: `See decisions/NNNN-short-slug.md`.
6. Commit ADR with the design/plan that made the choice.

## Template

```markdown
# NNNN. <Short verb-led title>

**Status:** Accepted | Superseded by MMMM | Deprecated
**Date:** YYYY-MM-DD
**Decision-makers:** <handles/roles>
**Related:** <design>, <plan>, <review>, <prior ADRs>

## Context

<situation, constraints, forces, knowns/unknowns, cited evidence>

## Decision

<We will X because Y. Alternatives rejected: A because..., B because...>

## Consequences

<2-5 effects. Include positive + negative. Include undo/migration cost.>
```

## Smells

- "We built X" → task log, not ADR.
- Proposal/future tense → design doc until accepted.
- Editing accepted ADR body → write superseding ADR.
- No alternatives → not an ADR.

## Integration

Called by: `brainstorming`, `writing-plans`, `adversarial-design-review`, manual retroactive recording.

Calls: none.
