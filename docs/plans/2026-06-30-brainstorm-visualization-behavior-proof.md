# Brainstorm Visualization Behavior Proof

## RED baseline

Baseline subject read pre-change `skills/brainstorming/SKILL.md` only.

### Actual behavior summary

- Conceptual prompt (`what does trust mean for this dashboard?`) → subject stayed text-only by default using existing clarifying-question workflow.
- Visual layout choice → subject would still present 2–3 text approaches with trade-offs and numbered options.
- Declined visuals → subject would continue text-only, but only by inference because no visual-offer protocol exists.
- Changed decision after diagram → subject would revise design text; no stale-diagram handling exists.

### Missing explicit requirements

| path | baseline result |
|---|---|
| conceptual text-only | MISSING as a distinct visual-companion rule; only general clarifying-question/design rules exist. |
| visual offer | MISSING; no diagrams/mockups/visualization offer rule. |
| declines | MISSING; no declined-offer/no-reoffer state rule. |
| accepts | MISSING; no accepted-visual/text-fallback rule. |
| stale visual | MISSING; no stale visual update/retire rule. |

## GREEN subject run

Subject used the revised `skills/brainstorming/SKILL.md` and loaded `skills/brainstorming/visual-companion.md` only for the accepted-visual path.

| path | subject behavior |
|---|---|
| conceptual text-only | Stayed text-only for `what does trust mean for this dashboard?`; did not load or offer the visual companion. |
| visual offer | Sent a standalone just-in-time offer: `This layout choice would be clearer shown than described. Want me to sketch 2–3 quick wireframe options before you choose?` |
| declines | Continued text-only and explicitly did not re-offer unless asked. |
| accepts | Lazy-loaded the guide, composed a small Mermaid-style visual, included a text fallback, and recorded recommendation in text. |
| stale visual | Retired the stale visual and stated the current text decision as source of truth. |

## Reviewer score

PASS overall.

| path | reviewer verdict | cited rule |
|---|---|---|
| conceptual text-only | PASS | `SKILL.md` text-only rule + guide text-only domain-language rule. |
| visual offer | PASS | `SKILL.md` just-in-time, standalone, question-batch offer rule. |
| declines | PASS | `SKILL.md` decline/no-reoffer rule. |
| accepts | PASS | `SKILL.md` lazy-load + fallback rules; guide fallback guidance. |
| stale visual | PASS | `SKILL.md` text source-of-truth/stale visual rule; guide stale visual rule. |

Reviewer note: accepted-visual transcript used `[Mermaid flowchart]` as shorthand in the reviewer prompt, so it proves behavior selection and fallback, not host-rendered Mermaid output. Rendering remains best-effort/config-only per design.

## Evidence

- `bash tests/brainstorm-visual-companion.sh` → `Results: 0 failure(s)`
- RED baseline isolated subject: MISSING for visual offer, declined/no-reoffer, accepted visual with fallback, and stale visual.
- GREEN isolated subject + reviewer: PASS for conceptual text-only, visual offer, declines, accepts, and stale visual.
