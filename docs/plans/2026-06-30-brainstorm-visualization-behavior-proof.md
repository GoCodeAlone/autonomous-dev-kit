# Brainstorm Visualization Behavior Proof

## RED baseline

Baseline subject read pre-change `skills/brainstorming/SKILL.md` only.

### Raw RED subject output

```text
Actual current-skill behavior in scenario:
1. User asks: "what does trust mean for this dashboard?"
   - Treat as brainstorming/design exploration.
   - Stay text-only by default: clarify purpose, users, constraints, and success criteria.
   - Use adaptive question batching, likely numbered options in Zed.
2. Later visual layout choice would be clearer shown than described
   - Still present 2–3 text approaches with trade-offs and a recommendation.
   - In Zed, present options as a numbered list and ask the user to pick/reply.
3. User declines visuals to save time
   - Since the current skill has no visual-offer protocol, continue text-only.
   - May treat "save time/no visuals" as a constraint, but this is inferred, not explicitly required.
4. User changes a decision after a diagram would have existed
   - Revise the design text / assumptions / chosen approach as needed.
   - No explicit stale-diagram handling exists, because visuals/diagrams are not currently governed.
```

### Missing explicit requirements

| path | baseline result |
|---|---|
| conceptual text-only | MISSING as a distinct visual-companion rule; only general clarifying-question/design rules exist. |
| visual offer | MISSING; no diagrams/mockups/visualization offer rule. |
| declines | MISSING; no declined-offer/no-reoffer state rule. |
| accepts | MISSING; no accepted-visual/text-fallback rule. |
| stale visual | MISSING; no stale visual update/retire rule. |

## GREEN subject run

Subject used revised `skills/brainstorming/SKILL.md` and loaded `skills/brainstorming/visual-companion.md` only for the accepted-visual path.

### Raw GREEN subject output

```text
1. Conceptual text-only
Action: Do not load visual-companion.md; answer in text.
Message: Trust here means the dashboard helps users believe the data is accurate, fresh, explainable, and safe to act on. For this redesign, which trust signal matters most? 1. Data accuracy/provenance 2. Freshness/status 3. Explainability/drilldown 4. Consistency with existing reports. Reply with a number or adjust the wording.
Rule: SKILL.md says to stay text-only for requirements, conceptual choices, tradeoff tables, and scope decisions; visual-companion.md lists domain language like "what does trust mean?" as text-only.

2. Visual offer
Action: Offer visuals just-in-time, as the only content in the message.
Message: This layout choice would be clearer shown than described. Want me to sketch 2–3 quick wireframe options before you choose?
Rule: First visual companion offer must be just-in-time, never upfront, its own message, and count as one question batch.

3. User declines visuals
Action: Continue text-only; do not re-offer unless the user raises visuals.
Message: Got it — we'll stay text-only and optimize for speed. I won't re-offer visuals unless you ask. Text-only layout options: 1. KPI strip + exception queue 2. Narrative summary + drilldowns 3. Role-based sections by team. My recommendation is option 1 if fast trust-building is the goal.
Rule: If the user declines, continue text-only and do not re-offer unless the user raises visuals.

4. User accepts visuals
Action: Lazy-load visual-companion.md, then compose a small visual with a text fallback.
Message: Great — I'll keep it lightweight and decision-focused. Here are three rough layout directions using synthetic content: [Mermaid flowchart]. Text fallback: Option 1 leads with metrics and trust badges, then highlights exceptions. Option 2 leads with a written summary, then lets users drill down. Option 3 groups content by team ownership. I'd choose option 1 for fastest confidence and scanability.
Rule: Load the guide only after acceptance or while composing a visual; visuals must include concise text equivalents.

5. Visual becomes stale
Action: Retire or update the visual before proceeding; keep the text decision as source of truth.
Message: That changes the layout decision, so the previous wireframe is now stale. I'm retiring it rather than relying on it. Current text source of truth: we're prioritizing role-based sections over a universal KPI strip. If we need another visual later, I'll redraw it from that decision.
Rule: If a visual becomes stale or contradicts a later text decision, retire or update it before proceeding; current text design remains the source of truth.
```

## Reviewer score

PASS overall.

### Raw reviewer score

```text
1. Conceptual text-only — PASS. Matches fixture: conceptual/domain-language question stays text-only and does not load/offer visuals. SKILL.md says to stay text-only for requirements/conceptual choices; visual-companion.md lists domain language like "what does trust mean?" as text-only.
2. Visual offer — PASS. Offer is just-in-time, standalone, and does not bundle another clarifying question. SKILL.md requires first visual offer to be just-in-time, its own message, count as one question batch, and not bundle another clarifying question.
3. User declines visuals — PASS. Continues text-only and explicitly avoids re-offering unless user asks. SKILL.md says if the user declines, continue text-only and do not re-offer unless the user raises visuals.
4. User accepts visuals — PASS. Lazy-load action is after acceptance; response includes a visual plus concise text fallback and keeps the decision text-readable. SKILL.md requires lazy-loading only after acceptance/while composing visuals and every visual to include a concise text fallback. Guide says the same. Minor watchpoint: the transcript says "[Mermaid flowchart]" as a placeholder, so this passes only as transcript shorthand, not as an actual rendered artifact.
5. Visual becomes stale — PASS. Correctly retires the stale visual and treats the current text decision as source of truth. SKILL.md says text remains source of truth and stale/contradictory visuals must be retired or updated before proceeding. Guide repeats the stale visual rule.
```

Reviewer note: accepted-visual transcript used `[Mermaid flowchart]` as shorthand, so it proves behavior selection and fallback, not host-rendered Mermaid output. Rendering remains best-effort/config-only per design.

## Evidence

- `bash tests/brainstorm-visual-companion.sh` → `Results: 0 failure(s)`
- RED baseline isolated subject: MISSING for visual offer, declined/no-reoffer, accepted visual with fallback, and stale visual.
- GREEN isolated subject + reviewer: PASS for conceptual text-only, visual offer, declines, accepts, and stale visual.
