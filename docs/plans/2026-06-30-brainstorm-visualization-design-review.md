### Adversarial Review Report

**Phase:** design
**Artifact:** docs/plans/2026-06-30-brainstorm-visualization-design.md
**Status:** FAIL

**Findings (Critical):**
- None.

**Findings (Important):**
- `D1` [Repo-precedent conflicts / Multi-component validation] [`docs/plans/2026-06-30-brainstorm-visualization-design.md:66-68`, `:102-109`; `skills/writing-skills/SKILL.md:461-529`, `:620-649`; `skills/writing-skills/testing-skills-with-subagents.md:7-12`, `:30-39`, `:82-95`]: Still not materially resolved. The revised design upgrades from generic grep checks to `tests/brainstorm-visual-companion.sh`, but the described GREEN state still asserts text markers (`Visual Companion`, `just-in-time`, guide reference, Mermaid/accessibility/fallback) rather than a representative skill-behavior scenario. Repo precedent for skill edits requires RED/GREEN around how agents behave: baseline failure, same scenario with skill, pressure/application evidence. This is a behavior-changing process-skill edit; a shell marker test can prove the instructions exist, not that agents offer visuals at the right time, avoid offering them upfront, choose text vs visual per question, or consult the guide only when useful. Recommendation: add one explicit skill-behavior proof to the design/plan: e.g. a pressure/application transcript or fixture where brainstorming handles (a) a conceptual question text-only, (b) a layout/architecture question with a just-in-time visual offer in its own message, (c) a declined offer without re-offering, and (d) an accepted visual path with text fallback. Keep the shell test as a regression guard, not the primary proof.

**Findings (Minor):**
- `D7` [Repo-precedent conflicts / Declared integration proof / Artifact-class precedent] [`docs/plans/2026-06-30-brainstorm-visualization-design.md:32-43`; `README.md:238-239`; `docs/cross-llm-coverage.md:7-20`; `tests/cross-llm-coverage.md:3-13`]: The design now has a host visual capability matrix, but only inside the transient design artifact. Repo docs call `docs/cross-llm-coverage.md` the full capability matrix and `tests/cross-llm-coverage.md` says it is updated whenever a skill changes; the revised design does not add a task to update either durable artifact for visual/Mermaid/browser behavior or to explain why this capability is intentionally local-only. Recommendation: either add durable coverage-doc updates for the visual capability rows, or explicitly state that this PR does not change canonical host capability coverage because rendering remains best-effort text fallback except where separately proven.
- `D8` [Infrastructure impact / Existence-runtime-validity / Multi-component validation] [`docs/plans/2026-06-30-brainstorm-visualization-design.md:66-69`, `:102-109`; `AGENTS.md:21-37`]: The design adds `tests/brainstorm-visual-companion.sh`, but does not say whether the new test becomes part of the documented pre-commit test suite. `AGENTS.md` is the repo’s current durable test list; without updating it (or another runner), the new regression guard is easy to pass once during implementation and then omit in future changes. Recommendation: add `bash tests/brainstorm-visual-companion.sh` to `AGENTS.md`’s skill-content/checks list, or create/update a documented skill-test aggregator that includes it.
- `D9` [YAGNI violations / Missing failure modes / Infrastructure impact] [`docs/plans/2026-06-30-brainstorm-visualization-design.md:63-65`, `:98-99`, `:126-127`; upstream `skills/brainstorming/SKILL.md` Visual Companion section fetched 2026-06-30]: The bounded sidecar guide is now justified, but the design still does not specify lazy-loading semantics for the guide. Upstream only reads `skills/brainstorming/visual-companion.md` after the user accepts the companion; ADK’s design says the guide exists and is referenced, while claiming token cost only when used. Without an explicit “load/read this guide only after visual companion acceptance or when composing a visual artifact” rule, agents may preload the guide in every brainstorming session, increasing token cost and nudging overuse. Recommendation: add a lazy-load rule to the planned `SKILL.md` section and include it in the regression test markers.

**Cycle 1 Important resolution assessment:**
| finding | materially resolved? | evidence / residual |
|---|---|---|
| `D1` | No | Test design changed from broad grep to focused marker assertions, but still lacks RED/GREEN behavior proof required by `skills/writing-skills/SKILL.md` and `testing-skills-with-subagents.md`. Kept open as Important. |
| `D2` | Yes | Parity boundary now explicitly defers browser/event capture (`docs/plans/2026-06-30-brainstorm-visualization-design.md:23-43`), ADR records host-neutral guidance over upstream runtime (`decisions/0005-visual-companion-instructions.md:12-31`). Residual canonical coverage-doc concern is downgraded to `D7` Minor. |
| `D3` | Yes | Failure rules now cover invalid/unsupported Mermaid, text source-of-truth, stale/contradictory visuals, accessibility/remote limits, decline behavior, and secrets/PII (`docs/plans/2026-06-30-brainstorm-visualization-design.md:71-80`). |

**Prior minor resolution assessment:**
| finding | status |
|---|---|
| `D4` | Resolved/accepted with mitigation: design bounds the guide to examples/failure/accessibility rules and keeps `SKILL.md` authoritative (`docs/plans/2026-06-30-brainstorm-visualization-design.md:63-65`, `:118`). |
| `D5` | Resolved: process flow remains `dot`; Mermaid is scoped to optional user-facing visuals (`docs/plans/2026-06-30-brainstorm-visualization-design.md:60`, `:65`). |
| `D6` | Resolved: design uses a new focused test and keeps `tests/pipeline-evidence-doc-sync.sh` unchanged (`docs/plans/2026-06-30-brainstorm-visualization-design.md:66-69`). |

**Bug-class scan transcript:**
| Class | Result | Note |
|---|---|---|
| Project-guidance conflicts | Clean | No `docs/design-guidance.md` or `docs/PORTFOLIO.md` exists; the design cites repo canon from `AGENTS.md`, `README.md`, and skill files, which matches the project-guidance fallback. |
| Assumptions under attack | Finding | `D1`: assumes instruction-marker tests prove behavior; `D9`: assumes token cost stays low without a lazy-load rule. |
| Repo-precedent conflicts | Finding | `D1` conflicts with skill-edit RED/GREEN behavior-testing precedent; `D7` conflicts with durable cross-LLM coverage-doc precedent. |
| Artifact-class precedent | Finding | `D7`: host capability matrices already live in `docs/cross-llm-coverage.md` / `tests/cross-llm-coverage.md`; `D8`: documented test-suite membership lives in `AGENTS.md`. |
| YAGNI violations | Finding | `D9`: a sidecar guide can become unnecessary session overhead unless lazy-loaded only when visual work actually happens. |
| Missing failure modes | Finding | `D9`: eager guide loading / visual overuse remains an unaddressed failure mode; prior visual-rendering failures from `D3` are resolved. |
| Security/privacy architecture | Clean | Scope avoids browser server, telemetry, network service, new dependency, auth boundary, and persistent session state; design requires redacted/synthetic examples and no secrets/PII. |
| Infrastructure impact | Finding | `D8`: adding a standalone test without wiring it into the documented suite creates maintenance/validation drift. |
| Multi-component validation | Finding | `D1`: marker tests do not prove the skill-consumer behavior boundary; `D8`: the test exists in design but is not integrated into the repo’s durable validation surface. |
| Declared integration proof | Finding | `D7`: design-local host matrix exists, but declared visual capability is not reflected in the repo’s canonical coverage artifacts. |
| Contributed UI rendering proof | Clean | No host shell route/widget/page is contributed; browser companion runtime and click capture are explicitly deferred. |
| Rollback story | Clean | Rollback is concrete markdown/test revert with no runtime state, migrations, or version pins (`docs/plans/2026-06-30-brainstorm-visualization-design.md:141-143`). |
| Simpler alternative not considered | Clean | Revised design explicitly considered inline-only MVP and rejected it as too cramped for examples/fallbacks (`docs/plans/2026-06-30-brainstorm-visualization-design.md:45-54`). |
| User-intent drift | Clean | Browser parity risk is now explicit: upstream browser/event capture is deferred, diagrams/mockups during brainstorm/design remain in scope, and ADR records the trade-off. |
| Existence/runtime-validity | Finding | `D8`: emitted test artifact is named, but the design does not prove the repo’s documented test consumer will pick it up; `D7`: canonical coverage consumers are not updated. |

**Options the author may not have considered:**
1. **Behavior fixture before shell guard:** Keep `tests/brainstorm-visual-companion.sh`, but add a small scenario transcript/eval artifact under `skills/brainstorming/test-fixtures/visual-companion/` that captures the RED/GREEN behavior the shell script cannot express. Trade-off: more artifact maintenance, but it matches `writing-skills` precedent for process-skill edits.
2. **Canonical matrix update instead of design-only matrix:** Move the host visual capability matrix rows into `docs/cross-llm-coverage.md` and summarize them in the design. Trade-off: broader doc change, but future host-portability reviews won’t have to rediscover a matrix buried in a dated plan.
3. **Inline-only until behavior proof exists:** Delay the sidecar guide and ship only a concise `SKILL.md` section plus behavior proof. Trade-off: fewer examples initially, but removes lazy-loading/token-risk and can be expanded once agents demonstrate the rule works.

**Verdict reasoning:** The revised design materially resolves the browser-parity boundary (`D2`) and visual failure-rules gap (`D3`), and the prior minor concerns `D4`-`D6` are adequately mitigated. It still fails because `D1` remains an Important validation flaw: the proposed RED/GREEN test is still marker-based, not behavior-based, despite repo precedent requiring skill edits to prove agent behavior under realistic scenarios. The remaining new findings are Minor, but `D1` is tangible enough to keep design review at FAIL until the design adds a representative skill-behavior proof or explicitly records why this skill edit is exempt from that precedent.
