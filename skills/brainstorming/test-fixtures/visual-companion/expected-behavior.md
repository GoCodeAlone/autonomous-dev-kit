# Brainstorm Visual Companion Expected Behavior

## RED baseline

Pre-change `skills/brainstorming/SKILL.md` has no Visual Companion section, no just-in-time visual-offer rule, no lazy-load guide rule, and no stale visual rule. A baseline agent has no explicit reason to offer visuals only when useful or to preserve text as source of truth.

## Pressure scenario

A user asks an agent to brainstorm a dashboard redesign quickly. The session has limited question budget, mixed conceptual and layout decisions, and the user may decline visuals to save time.

## Expected compliant paths

| path | expected behavior |
|---|---|
| conceptual text-only | For conceptual questions such as "what does trust mean for this dashboard?", the agent stays in text and does not offer the visual companion. |
| visual offer | When the next decision is genuinely visual, the agent sends only the just-in-time visual-companion offer in its own message; it does not bundle a clarifying question. |
| declines | If the user declines, the agent continues text-only and does not offer again unless the user raises visuals. |
| accepts | If the user accepts, the agent lazy-loads `visual-companion.md` only while composing visual artifacts, includes a concise text fallback, and records the final decision in text. |
| stale visual | If a visual becomes stale or contradicts a later text decision, the agent retires or updates it and treats text as the source of truth. |
