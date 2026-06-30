# Brainstorm Visualization Design

**Issue:** #78 — Brainstorm visualization
**Date:** 2026-06-30
**Status:** Approved by user instruction; revised after adversarial review cycle 1
**ADR:** `decisions/0005-visual-companion-instructions.md`

## Original Ask

> At https://github.com/obra/superpowers, their skill has been updated to add a visualization companion for brainstorms/designs, with diagrams, etc. This is quite handy, we should add something similar.

## Global Design Guidance

`Guidance: none found as docs/design-guidance.md; constraints cited from repo canon.`

| source | guidance | design response |
|---|---|---|
| `AGENTS.md` | Skills use host-gated content; forbidden host-specific tokens only in host blocks; recognized hosts include `zed-agent`. | Add host-neutral visual guidance; avoid new host-specific tool names outside host blocks. |
| `README.md` Cross-LLM/plugin positioning | ADK bundles portable skills/hooks/agents/commands for multiple hosts. | Prefer host-neutral Markdown plus optional Mermaid where rendered; never require an upstream-only browser server. |
| `skills/brainstorming/SKILL.md` | Brainstorming has adaptive batching, assumptions, self-challenge, adversarial review, and design docs. | Insert visual companion as a just-in-time optional aid without weakening gates. |
| `skills/writing-skills/SKILL.md` | Skill edits require failing tests first and supporting files only when useful. | Add a focused RED/GREEN shell test for visual-companion behavior markers; keep SKILL.md authoritative and the companion guide bounded to examples/fallback rules. |

## Parity Boundary

| upstream capability | ADK issue #78 scope | rationale |
|---|---|---|
| Browser tab companion | Deferred | ADK does not ship the server/scripts; adding them needs runtime/process/security validation across hosts. |
| Click/event capture | Deferred | Requires browser session state and privacy policy; out of scope for this markdown-only PR. |
| Diagrams/mockups during brainstorm/design | In scope | Add just-in-time visual guidance using host-native chat/markdown artifacts. |
| Text fallback | Required | Host rendering differs; text remains source of truth. |

## Host Visual Capability Matrix

| host | Markdown text | Mermaid/rendered diagrams | Browser companion |
|---|---|---|---|
| `zed-agent` | runtime-integrated: markdown chat output | runtime-integrated: Zed renders Mermaid in assistant markdown when supported; must include text fallback | deferred |
| `claude-code` | config-only: markdown output | config-only/best-effort: render support varies by surface | deferred |
| `codex` | config-only: markdown output | config-only/best-effort | deferred |
| `opencode` | config-only: markdown output | config-only/best-effort | deferred |
| `cursor` | config-only: markdown output | config-only/best-effort | deferred |
| `hermes-agent` | config-only: markdown output | config-only/best-effort | deferred |

`config-only` rows mean the skill can emit markdown/diagram code, but this PR does not prove host rendering beyond plain text. ∴ every visual must have a concise textual equivalent and decisions must be recorded in text.

## Approaches Considered

| option | summary | trade-off |
|---|---|---|
| A. Copy upstream browser companion verbatim | Add upstream `Visual Companion` text and server instructions. | Fast but references scripts/tools ADK does not ship; host-portability and security gaps. |
| B. Host-neutral progressive companion | Add just-in-time offer rules, diagram/mockup decision test, failure rules, host matrix, and bounded guide. | Solves issue now; browser click capture remains deferred. Recommended. |
| C. Inline-only MVP | Put all guidance in `SKILL.md`, no guide file. | Smallest patch but clutters an already-long skill and lacks room for examples/fallbacks. |
| D. Full browser companion runtime | Add scripts, frame template, event state, and docs. | Larger runtime feature; requires multi-host launch validation beyond issue scope. |

**Decision:** B. See `decisions/0005-visual-companion-instructions.md`.

## Design

- Modify `skills/brainstorming/SKILL.md`:
  - Add checklist item after project guidance: offer visual companion just-in-time, not upfront.
  - Keep process-flow diagram in `dot` to match existing skill precedent.
  - Add process bullets: offer visuals only when a question is genuinely clearer shown than described.
  - Add `## Visual Companion` section: per-question decision rules, text-source-of-truth, stale/invalid visual fallback, and guide reference.
- Add bounded `skills/brainstorming/visual-companion.md`:
  - Role: reference examples and failure/accessibility rules only; `SKILL.md` remains authoritative.
  - Covers diagrams/mockups, Mermaid examples, visual/text decision test, no-secrets rule, stale visual retirement, and plain-text fallback.
- Add focused regression test `tests/brainstorm-visual-companion.sh`:
  - RED before implementation: `skills/brainstorming/SKILL.md` lacks `Visual Companion`, `just-in-time`, and guide reference; guide file missing.
  - GREEN after implementation: asserts just-in-time offer, not-upfront rule, per-question decision, text fallback/source of truth, guide existence, and guide mentions Mermaid plus accessibility/fallback.
- Keep `tests/pipeline-evidence-doc-sync.sh` unchanged; do not overload its issue-specific contract.

## Failure Rules

| failure | required behavior |
|---|---|
| Mermaid invalid or unsupported | Continue with plain text; never claim rendered proof unless observed. |
| Visual contradicts text | Text design/plan is source of truth; fix or withdraw visual before proceeding. |
| Visual becomes stale after decision changes | Retire/update the visual; do not leave obsolete artifact as active guidance. |
| Accessibility or remote-host limitation | Include concise text equivalent for every visual and accept text-only feedback. |
| User declines visual companion | Continue text-only; do not offer again unless user raises visuals. |
| Sensitive data in visual | Redact or use synthetic examples; no secrets/PII in diagrams/mockups. |

## Security Review

| area | assessment |
|---|---|
| Auth/authz | No auth boundary changes. |
| Secrets/PII | Guide requires redacted/synthetic visual examples; no secrets/PII. |
| Dependency/trust | No dependency, network service, telemetry, or browser session state. |
| Abuse case | Avoid opening browsers/servers by default; visuals are optional and text-backed. |
| Least privilege | No filesystem writes except normal design artifacts; no runtime process. |

## Infrastructure Impact

| resource | impact |
|---|---|
| Cloud/network | None. |
| Local runtime | None; no server added. |
| Storage | Adds one bounded skill guide, one focused test, plus design/ADR/plan artifacts. |
| Cost/scale | Slight token cost only when visual companion is used. |
| Release/rollback | Revert markdown/test changes; no migrations. |

## Multi-Component Validation

| boundary | proof |
|---|---|
| Skill behavior markers | `bash tests/brainstorm-visual-companion.sh` → asserts just-in-time/not-upfront/per-question/text fallback/guide contract. |
| Skill text ↔ content rules | `bash tests/skill-content-grep.sh` → host-neutral token guard passes. |
| Skill refs ↔ repo files | `bash tests/skill-cross-refs.sh` → references resolve. |
| Full repo contract | Run AGENTS.md test list before PR. |
| Runtime rendering | Deferred except Zed markdown/Mermaid support where observed by host; all other hosts use text fallback and are marked config-only/best-effort. |

## Assumptions

| id | assumption | challenge | fallback |
|---|---|---|---|
| A1 | Issue #78 accepts host-neutral visual guidance as "similar" to upstream. | User may expect full browser parity. | Parity boundary marks browser/event capture deferred; future server runtime requires separate issue/design. |
| A2 | Markdown/Mermaid diagrams are useful even where rendered as code. | Some hosts show raw code only. | Text source-of-truth + concise text equivalent required. |
| A3 | A bounded guide file is justified. | Existing skill guidance prefers inline when short. | SKILL.md remains authoritative; guide is limited to examples/failure/accessibility details that would bloat SKILL.md. |

## Self-Challenge

| doubt | response |
|---|---|
| Laziest solution: paste upstream section only. | Rejected: it references scripts ADK does not ship and weakens host neutrality. |
| Fragile assumption: no full browser runtime required. | Mitigated by parity boundary, ADR, and deferred browser row. |
| YAGNI risk: guide becomes too broad. | Bound guide role; no runtime implementation, telemetry, session keys, or click-event schema. |
| Failure mode: agent overuses diagrams. | Just-in-time/per-question rules say never offer upfront and use visuals only when clearer than text. |
| Repo pattern conflict: test script misuse. | Use focused `tests/brainstorm-visual-companion.sh`; keep pipeline evidence test unchanged. |

## Review Cycle 1 Resolutions

| finding | resolution |
|---|---|
| D1 | Added focused RED/GREEN behavior-marker test and made grep checks secondary. |
| D2 | Added parity boundary and host visual capability matrix; browser companion deferred. |
| D3 | Added explicit failure rules and text-source-of-truth behavior. |
| D4 | Accepted with mitigation: guide bounded to reference examples/failure rules; SKILL.md authoritative. |
| D5 | Resolved: process flow remains `dot`; Mermaid only for optional generated visuals. |
| D6 | Resolved: use new focused test, not `pipeline-evidence-doc-sync.sh`. |

## Rollback

Revert commits modifying `skills/brainstorming/SKILL.md`, `skills/brainstorming/visual-companion.md`, `tests/brainstorm-visual-companion.sh`, and planning/ADR artifacts; rerun AGENTS.md test list. No runtime state, migrations, or version pins.
