# Brainstorm Visualization Design

**Issue:** #78 — Brainstorm visualization
**Date:** 2026-06-30
**Status:** Approved by user instruction; design recorded before implementation
**ADR:** `decisions/0005-visual-companion-instructions.md`

## Original Ask

> At https://github.com/obra/superpowers, their skill has been updated to add a visualization companion for brainstorms/designs, with diagrams, etc. This is quite handy, we should add something similar.

## Global Design Guidance

`Guidance: none found as docs/design-guidance.md; constraints cited from repo canon.`

| source | guidance | design response |
|---|---|---|
| `AGENTS.md` | Skills use host-gated content; forbidden host-specific tokens only in host blocks; recognized hosts include `zed-agent`. | Add host-neutral visual guidance; avoid new host-specific tool names outside host blocks. |
| `README.md` Cross-LLM/plugin positioning | ADK bundles portable skills/hooks/agents/commands for multiple hosts. | Prefer Mermaid/markdown and generic visual artifacts over an upstream-only browser server dependency. |
| `skills/brainstorming/SKILL.md` | Brainstorming already has adaptive batching, assumptions, self-challenge, adversarial review, and design docs. | Insert visual companion as a just-in-time optional aid without weakening existing gates. |

## Approaches Considered

| option | summary | trade-off |
|---|---|---|
| A. Copy upstream browser companion verbatim | Add upstream `Visual Companion` text and server instructions. | Fast but references scripts/tools ADK does not ship; likely host-portability regressions. |
| B. Host-neutral progressive companion | Add just-in-time visual-offer rules, diagram/mockup decision test, host-native fallback, and companion guide. | Solves issue now; does not provide browser click capture. Recommended. |
| C. Build full browser companion runtime | Add scripts, frame template, event state, and docs. | Larger runtime feature; requires multi-host process validation beyond issue scope. |

**Decision:** B. See `decisions/0005-visual-companion-instructions.md`.

## Design

- Modify `skills/brainstorming/SKILL.md`:
  - Add checklist item after project guidance: offer visual companion just-in-time, not upfront.
  - Update process-flow diagram to include the visual-companion decision.
  - Add process bullets explaining when to offer/use visuals.
  - Add `## Visual Companion` section with per-question decision rules.
- Add `skills/brainstorming/visual-companion.md`:
  - Covers when visuals help, artifact types, lightweight Mermaid examples, mockup guidance, accessibility/plain-text fallback, and host limitations.
  - Explicitly says visuals are a tool, not a mode; textual questions stay in chat.
- Add regression assertions to `tests/pipeline-evidence-doc-sync.sh` for #78:
  - `skills/brainstorming/SKILL.md` mentions `Visual Companion`.
  - The skill requires `just-in-time` offering.
  - The guide exists and mentions `Mermaid`.

## Security Review

| area | assessment |
|---|---|
| Auth/authz | No auth boundary changes. |
| Secrets/PII | Visual guidance must not expose secrets/PII; guide will require redacted examples. |
| Dependency/trust | No new dependency or network service. |
| Abuse case | Avoid instructing agents to open browsers/servers by default; visuals are opt-in and can be represented in markdown. |
| Least privilege | No filesystem writes except intentional design artifacts during brainstorming. |

## Infrastructure Impact

| resource | impact |
|---|---|
| Cloud/network | None. |
| Local runtime | None; no server added. |
| Storage | Adds one skill guide markdown file plus design/ADR/plan artifacts. |
| Cost/scale | Slight token cost only when visual companion is used. |
| Release/rollback | Revert markdown/test changes; no migrations. |

## Multi-Component Validation

| boundary | proof |
|---|---|
| Skill text ↔ content rules | `bash tests/skill-content-grep.sh` → host-neutral token guard passes. |
| Skill refs ↔ repo files | `bash tests/skill-cross-refs.sh` → references resolve. |
| #78 regression | `bash tests/pipeline-evidence-doc-sync.sh` → visual companion assertions pass. |
| Full repo contract | Run AGENTS.md test list before PR. |

## Assumptions

| id | assumption | challenge | fallback |
|---|---|---|---|
| A1 | Issue #78 wants workflow guidance, not necessarily a shipped browser server. | User may expect click-driven browser companion parity. | ADR scopes this to host-neutral instructions; future server runtime can be separate issue. |
| A2 | Mermaid/markdown diagrams are available or acceptable across enough hosts. | Some hosts render only plain text. | Guide requires plain-text summary/fallback for every visual. |
| A3 | Adding one companion guide is consistent with skill docs shape. | Existing skills mostly keep logic in SKILL.md. | Keep SKILL.md authoritative; guide is referenced for detailed examples only. |

## Self-Challenge

| doubt | response |
|---|---|
| Laziest solution: paste upstream section only. | Rejected: it references scripts ADK does not ship and weakens host neutrality. |
| Fragile assumption: no full browser runtime required. | Mitigated by explicit scope and ADR; issue says "something similar," not exact parity. |
| YAGNI risk: guide becomes too broad. | Keep examples generic; no runtime implementation, no click-event schema. |
| Failure mode: agent overuses diagrams. | Just-in-time/per-question rules say never offer upfront and use visuals only when clearer than text. |
| Repo pattern conflict: skill process gates. | Visual step is inserted before questions and does not skip project guidance, assumptions, review, or planning gates. |

## Rollback

Revert commits modifying `skills/brainstorming/SKILL.md`, `skills/brainstorming/visual-companion.md`, and `tests/pipeline-evidence-doc-sync.sh`; rerun AGENTS.md test list. No runtime state, migrations, or version pins.
