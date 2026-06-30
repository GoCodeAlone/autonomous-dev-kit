# 0005. Add visual companion instructions

**Status:** Accepted
**Date:** 2026-06-30
**Decision-makers:** ADK maintainer via issue #78; implementing agent
**Related:** docs/plans/2026-06-30-brainstorm-visualization-design.md, https://github.com/GoCodeAlone/autonomous-dev-kit/issues/78

## Context

Issue #78 asks ADK to add a brainstorm/design visualization companion similar to the updated `obra/superpowers` brainstorming skill. ADK skills must stay host-neutral and portable across supported agents. This repo does not currently include the upstream browser companion server or its scripts.

## Decision

We will add host-neutral visual-companion guidance to `skills/brainstorming/SKILL.md`, backed by a local `skills/brainstorming/visual-companion.md` guide, because this satisfies the requested workflow without introducing an unproven runtime dependency.

**Alternatives considered and rejected:**

- **Copy upstream browser server contract verbatim** — rejected because ADK does not ship those scripts and host process semantics differ.
- **Add diagrams unconditionally to every design** — rejected because many brainstorm questions are textual; mandatory diagrams add noise and token cost.

## Consequences

**Positive:**

- Brainstorming can offer diagrams/mockups just-in-time when visual reasoning helps.
- Guidance remains portable and can use host-native rendering such as Mermaid before any future server exists.

**Negative:**

- This does not add a browser event loop or click-state capture.
- Future server support will need a separate design and runtime validation.

**Reversibility:** revert the brainstorming skill edits and companion guide; no migrations or generated runtime state are involved.
