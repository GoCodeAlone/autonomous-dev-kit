# Brainstorm Visualization Design

**Issue:** #78 — Brainstorm visualization
**Date:** 2026-06-30
**Status:** Approved by user instruction; revised after adversarial review cycles 1-2
**ADR:** `decisions/0005-visual-companion-instructions.md`

## Original Ask

> At https://github.com/obra/superpowers, their skill has been updated to add a visualization companion for brainstorms/designs, with diagrams, etc. This is quite handy, we should add something similar.

## Global Design Guidance

`Guidance: none found as docs/design-guidance.md; constraints cited from repo canon.`

| source | guidance | design response |
|---|---|---|
| `AGENTS.md` | Skills use host-gated content; forbidden host-specific tokens only in host blocks; recognized hosts include `zed-agent`; test scripts are documented pre-commit checks. | Add host-neutral visual guidance; update documented checks for the new focused test. |
| `README.md` Cross-LLM/plugin positioning | ADK bundles portable skills/hooks/agents/commands for multiple hosts. | Prefer host-neutral Markdown plus optional Mermaid where rendered; never require an upstream-only browser server. |
| `docs/cross-llm-coverage.md` / `tests/cross-llm-coverage.md` | Capability and skill coverage matrices record host-portability intent. | Add a visual-companion capability row and brainstorming note so the host matrix is durable, not design-local. |
| `skills/brainstorming/SKILL.md` | Brainstorming has adaptive batching, assumptions, self-challenge, adversarial review, and design docs. | Insert visual companion as a just-in-time optional aid without weakening gates. |
| `skills/writing-skills/SKILL.md` | Skill edits require failing tests first and behavior proof, not marker-only tests. | Add a focused shell regression guard plus a behavior pressure-test fixture and subagent pressure run. |

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
| `zed-agent` | runtime-integrated: markdown chat output | runtime-integrated where Zed renders Mermaid in assistant markdown; must include text fallback | deferred |
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
| B. Host-neutral progressive companion | Add just-in-time offer rules, diagram/mockup decision test, failure rules, host matrix, behavior proof, and bounded guide. | Solves issue now; browser click capture remains deferred. Recommended. |
| C. Inline-only MVP | Put all guidance in `SKILL.md`, no guide file. | Smallest patch but clutters an already-long skill and lacks room for examples/fallbacks. |
| D. Full browser companion runtime | Add scripts, frame template, event state, and docs. | Larger runtime feature; requires multi-host launch validation beyond issue scope. |

**Decision:** B. See `decisions/0005-visual-companion-instructions.md`.

## Design

- Modify `skills/brainstorming/SKILL.md`:
  - Add checklist item after project guidance: offer visual companion just-in-time, not upfront.
  - Keep process-flow diagram in `dot` to match existing skill precedent.
  - Add process bullets: offer visuals only when a question is genuinely clearer shown than described.
  - Add `## Visual Companion` section: per-question decision rules, text-source-of-truth, stale/invalid visual fallback, lazy-load guide rule, and guide reference.
- Add bounded `skills/brainstorming/visual-companion.md`:
  - Role: reference examples and failure/accessibility rules only; load only after visual companion acceptance or while composing a visual artifact.
  - Covers diagrams/mockups, Mermaid examples, visual/text decision test, no-secrets rule, stale visual retirement, and plain-text fallback.
- Add focused regression test `tests/brainstorm-visual-companion.sh`:
  - RED before implementation: required skill markers/guide/fixture/coverage rows absent.
  - GREEN after implementation: asserts just-in-time offer, not-upfront rule, per-question decision, text fallback/source of truth, lazy-load rule, guide existence, guide mentions Mermaid plus accessibility/fallback, behavior fixture exists, and coverage/docs checks include visual companion.
- Add behavior fixture `skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md`:
  - Records pressure scenario and expected compliant behavior for four paths: conceptual text-only, visual offer in its own message, declined offer/no re-offer, accepted visual with text fallback.
  - Includes RED baseline notes against pre-change brainstorming: no visual companion rule exists, so the expected just-in-time offer and fallback paths are absent.
- Run behavior proof with a subagent after implementation:
  - Prompt a reviewer with the fixture and current `skills/brainstorming/SKILL.md`.
  - Expected: reviewer reports PASS for all four paths and cites the exact skill/guide lines that force the behavior.
  - This is the primary behavior proof; shell test is the regression guard.
- Update durable docs:
  - `AGENTS.md`: add `bash tests/brainstorm-visual-companion.sh` to skill content checks.
  - `docs/cross-llm-coverage.md`: add visual companion capability row.
  - `tests/cross-llm-coverage.md`: update brainstorming notes with visual companion host-neutral/best-effort behavior.

## Behavior Fixture Expected Paths

| path | compliant behavior |
|---|---|
| Conceptual text-only question | Do not offer visual companion; ask/answer in text because the answer is conceptual. |
| Visual question arises | Send only the just-in-time offer message; no bundled clarifying question. |
| User declines | Continue text-only and do not offer again unless user raises visuals. |
| User accepts | Use the guide only when composing visuals; include text summary/fallback; record final decision in text. |

## Failure Rules

| failure | required behavior |
|---|---|
| Mermaid invalid or unsupported | Continue with plain text; never claim rendered proof unless observed. |
| Visual contradicts text | Text design/plan is source of truth; fix or withdraw visual before proceeding. |
| Visual becomes stale after decision changes | Retire/update the visual; do not leave obsolete artifact as active guidance. |
| Accessibility or remote-host limitation | Include concise text equivalent for every visual and accept text-only feedback. |
| User declines visual companion | Continue text-only; do not offer again unless user raises visuals. |
| Sensitive data in visual | Redact or use synthetic examples; no secrets/PII in diagrams/mockups. |
| Guide loaded eagerly | Violation; companion guide loads only after acceptance or while composing a visual artifact. |

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
| Storage | Adds one bounded skill guide, one fixture, one focused test, plus design/ADR/plan artifacts. |
| Test suite | `AGENTS.md` documented checks gain one shell test. |
| Cost/scale | Slight token cost only when visual companion is used; lazy-load rule avoids every-session overhead. |
| Release/rollback | Revert markdown/test changes; no migrations. |

## Multi-Component Validation

| boundary | proof |
|---|---|
| Skill behavior | Subagent pressure proof against `expected-behavior.md` → PASS for four paths. |
| Skill behavior markers | `bash tests/brainstorm-visual-companion.sh` → asserts just-in-time/not-upfront/per-question/text fallback/lazy-load/guide/fixture/coverage contract. |
| Skill text ↔ content rules | `bash tests/skill-content-grep.sh` → host-neutral token guard passes. |
| Skill refs ↔ repo files | `bash tests/skill-cross-refs.sh` → references resolve. |
| Coverage docs | `bash tests/brainstorm-visual-companion.sh` checks visual rows/notes exist. |
| Full repo contract | Run AGENTS.md test list before PR. |
| Runtime rendering | Deferred except Zed markdown/Mermaid support where observed by host; all other hosts use text fallback and are marked config-only/best-effort. |

## Assumptions

| id | assumption | challenge | fallback |
|---|---|---|---|
| A1 | Issue #78 accepts host-neutral visual guidance as "similar" to upstream. | User may expect full browser parity. | Parity boundary marks browser/event capture deferred; future server runtime requires separate issue/design. |
| A2 | Markdown/Mermaid diagrams are useful even where rendered as code. | Some hosts show raw code only. | Text source-of-truth + concise text equivalent required. |
| A3 | A bounded guide file is justified. | Existing skill guidance prefers inline when short. | SKILL.md remains authoritative; guide is lazy-loaded and limited to examples/failure/accessibility details. |
| A4 | Subagent pressure proof is acceptable for behavior validation. | It is not CI-enforced. | Shell regression guard preserves contract markers; PR body includes behavior proof transcript. |

## Self-Challenge

| doubt | response |
|---|---|
| Laziest solution: paste upstream section only. | Rejected: it references scripts ADK does not ship and weakens host neutrality. |
| Fragile assumption: no full browser runtime required. | Mitigated by parity boundary, ADR, and deferred browser row. |
| YAGNI risk: guide becomes too broad. | Bound + lazy-load guide; no runtime implementation, telemetry, session keys, or click-event schema. |
| Failure mode: agent overuses diagrams. | Just-in-time/per-question rules say never offer upfront and use visuals only when clearer than text. |
| Repo pattern conflict: marker-only testing. | Add fixture + subagent pressure proof as primary; shell test only guards regressions. |

## Review Cycle Resolutions

| finding | resolution |
|---|---|
| D1 | Added behavior fixture + subagent pressure proof as primary validation. |
| D2 | Added parity boundary and host visual capability matrix; browser companion deferred. |
| D3 | Added explicit failure rules and text-source-of-truth behavior. |
| D4 | Accepted with mitigation: guide bounded/lazy-loaded; SKILL.md authoritative. |
| D5 | Resolved: process flow remains `dot`; Mermaid only for optional generated visuals. |
| D6 | Resolved: use new focused test, not `pipeline-evidence-doc-sync.sh`. |
| D7 | Add durable coverage doc updates. |
| D8 | Add focused test to documented `AGENTS.md` checks. |
| D9 | Add lazy-load rule to SKILL.md/guide/test. |

## Rollback

Revert commits modifying `skills/brainstorming/SKILL.md`, `skills/brainstorming/visual-companion.md`, `skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md`, `tests/brainstorm-visual-companion.sh`, `docs/cross-llm-coverage.md`, `tests/cross-llm-coverage.md`, `AGENTS.md`, and planning/ADR artifacts; rerun AGENTS.md test list. No runtime state, migrations, or version pins.
