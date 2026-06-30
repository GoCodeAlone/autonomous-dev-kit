# Brainstorm Visualization Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Add host-neutral brainstorm/design visualization companion guidance for issue #78.

**Architecture:** Extend `skills/brainstorming/SKILL.md` with just-in-time visual companion rules while keeping existing gates intact. Add a lazy-loaded guide, behavior fixture, focused regression guard, coverage/doc updates, follow-up tracking, and transcript-backed pressure proof.

**Tech Stack:** Markdown skills/docs; Bash regression tests; subagent pressure testing; GitHub issue/PR workflow.

**Base branch:** main

---

## Scope Manifest

**PR Count:** 1
**Tasks:** 3
**Estimated Lines of Change:** ~300

**Out of scope:**
- Browser server/runtime companion.
- Click/event capture or telemetry.
- Claiming Mermaid rendering is runtime-integrated on hosts where it has not been observed.

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Add brainstorm visual companion guidance | Task 1, Task 2, Task 3 | issue-78-brainstorm-visualization |

**Status:** Locked 2026-06-30T10:37:25Z

---

## Declared Integration Matrix

| declared visual capability | host(s) | state | plan proof / rationale |
|---|---|---|---|
| Markdown text visual explanations | all supported hosts | config-only | Skill emits normal markdown/chat text; no host-specific runtime API changes. `tests/brainstorm-visual-companion.sh` asserts text fallback/source-of-truth contract. |
| Mermaid/rendered diagrams | all supported hosts | config-only / best-effort | Skill may emit Mermaid, but rendering is not claimed unless observed in a specific host. Every Mermaid visual requires text fallback. |
| Browser companion tab | all supported hosts | deferred | Tracked in `docs/FOLLOWUPS.md`; needs separate runtime/process/security design. |
| Click/event capture | all supported hosts | deferred | Tracked in `docs/FOLLOWUPS.md`; no browser session state in this PR. |

---

## Pressure-Proof Execution Protocol

Behavior proof means an isolated subject applies the skill under pressure; it is not self-review.

1. Prefer a native subagent/delegation tool when the current host exposes one.
2. If native subagents are unavailable, use a fresh isolated host thread/session in the same worktree and paste the exact subject prompt.
3. Capture the subject output and reviewer score in `docs/plans/2026-06-30-brainstorm-visualization-behavior-proof.md`.
4. If no isolated subject can be run, stop before implementation and record the blocker; do not replace the proof with self-review.

---

### Task 1: Integrated TDD Implementation

**Files:**
- Create: `tests/brainstorm-visual-companion.sh`
- Create: `skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md`
- Modify: `skills/brainstorming/SKILL.md`
- Create: `skills/brainstorming/visual-companion.md`
- Modify: `AGENTS.md`
- Modify: `docs/cross-llm-coverage.md`
- Modify: `tests/cross-llm-coverage.md`
- Create: `docs/FOLLOWUPS.md`

**Step 1: RED behavior baseline**

Dispatch a baseline subject agent against the current pre-change `skills/brainstorming/SKILL.md` with this prompt:

```text
You are testing current brainstorming behavior before issue #78 is implemented.
Read `skills/brainstorming/SKILL.md` only.
Scenario: A user is brainstorming a dashboard redesign quickly. First they ask a conceptual question: "what does trust mean for this dashboard?" Later they ask a visual layout choice that would be clearer shown than described. Then they decline visuals to save time. Finally they change a decision after a diagram would have existed.
First answer what messages/actions you would actually take in the scenario using only the current skill. Then separately mark what the current skill explicitly requires for: conceptual text-only, visual offer, declined offer/no re-offer, accepted visual with text fallback, stale visual. Cite skill lines/sections. If the skill lacks a rule, say MISSING.
```

Expected RED: baseline output reports MISSING for visual offer, declined/no re-offer, accepted visual/text fallback, and stale visual. Immediately create `docs/plans/2026-06-30-brainstorm-visualization-behavior-proof.md` with the raw or summarized RED baseline output; append GREEN proof in Task 2.

**Step 2: Write failing shell regression guard**

Create `tests/brainstorm-visual-companion.sh`:

```bash
#!/usr/bin/env bash
# Regression guard for issue #78 brainstorm visualization companion.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRAIN="$ROOT/skills/brainstorming/SKILL.md"
GUIDE="$ROOT/skills/brainstorming/visual-companion.md"
FIXTURE="$ROOT/skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md"
AGENTS="$ROOT/AGENTS.md"
CAPS="$ROOT/docs/cross-llm-coverage.md"
SKILL_COVERAGE="$ROOT/tests/cross-llm-coverage.md"
fail=0
pass(){ printf 'PASS: %s\n' "$1"; }
bad(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
has(){ grep -qiF "$2" "$1"; }
hasE(){ grep -qiE "$2" "$1"; }

has "$BRAIN" "Visual Companion" && pass "brainstorming has Visual Companion section" || bad "brainstorming missing Visual Companion section"
has "$BRAIN" "just-in-time" && pass "visual companion offer is just-in-time" || bad "visual companion offer is not just-in-time"
hasE "$BRAIN" 'not[ -]upfront|never[ -]upfront|NOT upfront' && pass "visual companion is not offered upfront" || bad "visual companion upfront prohibition missing"
has "$BRAIN" "per-question" && pass "visual decision is per-question" || bad "per-question decision rule missing"
has "$BRAIN" "text remains the source of truth" && pass "text source-of-truth rule present" || bad "text source-of-truth rule missing"
has "$BRAIN" "question batch" && pass "visual offer batch-budget rule present" || bad "visual offer batch-budget rule missing"
has "$BRAIN" "lazy-load" && pass "guide lazy-load rule present" || bad "guide lazy-load rule missing"
has "$BRAIN" "visual-companion.md" && pass "guide reference present" || bad "guide reference missing"

[ -f "$GUIDE" ] && pass "visual companion guide exists" || bad "visual companion guide missing"
if [ -f "$GUIDE" ]; then
  has "$GUIDE" "Mermaid" && pass "guide mentions Mermaid" || bad "guide missing Mermaid guidance"
  has "$GUIDE" "accessibility" && pass "guide mentions accessibility" || bad "guide missing accessibility guidance"
  has "$GUIDE" "fallback" && pass "guide mentions fallback" || bad "guide missing fallback guidance"
  has "$GUIDE" "secrets" && pass "guide forbids secrets" || bad "guide missing secrets guidance"
  has "$GUIDE" "SKILL.md remains authoritative" && pass "guide is bounded by SKILL.md authority" || bad "guide authority boundary missing"
fi

[ -f "$FIXTURE" ] && pass "behavior fixture exists" || bad "behavior fixture missing"
if [ -f "$FIXTURE" ]; then
  for marker in "conceptual text-only" "visual offer" "declines" "accepts" "stale visual" "RED baseline"; do
    has "$FIXTURE" "$marker" && pass "fixture covers $marker" || bad "fixture missing $marker"
  done
fi

has "$AGENTS" "tests/brainstorm-visual-companion.sh" && pass "AGENTS documents visual companion test" || bad "AGENTS missing visual companion test"
has "$CAPS" "Visual companion" && pass "capability matrix includes visual companion" || bad "capability matrix missing visual companion"
has "$CAPS" "browser deferred" && pass "capability matrix tracks browser deferral" || bad "capability matrix missing browser deferral"
has "$SKILL_COVERAGE" "visual companion" && pass "skill coverage notes visual companion" || bad "skill coverage missing visual companion note"

echo ""; echo "Results: $fail failure(s)"; [ "$fail" -eq 0 ]
```

Run: `bash tests/brainstorm-visual-companion.sh`

Expected RED representative failures (the full output may include additional missing-marker failures such as `just-in-time`, `per-question`, `question batch`, and `lazy-load`):

```text
FAIL: brainstorming missing Visual Companion section
FAIL: visual companion guide missing
FAIL: behavior fixture missing
FAIL: AGENTS missing visual companion test
Results: <nonzero> failure(s)
```

**Step 3: Add behavior fixture**

Create `skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md`:

```markdown
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
```

**Step 4: Update brainstorming skill**

Modify `skills/brainstorming/SKILL.md`:

- Checklist: insert after project guidance:
  - `Offer the visual companion just-in-time — never upfront; only when a question would genuinely be clearer shown than described.`
- Process flow: add an `Offer visual companion if useful` box between project guidance and clarifying questions.
- Understanding/process bullets:
  - Visual offer is its own message.
  - It counts as one question batch.
  - Use per-question decision: visual only if seeing beats reading.
  - If declined, continue text-only and do not re-offer unless the user raises visuals.
  - Lazy-load `skills/brainstorming/visual-companion.md` only after acceptance or while composing a visual artifact.
- Add `## Visual Companion` section:
  - Visuals are a tool, not a mode.
  - Use visuals for mockups, Mermaid diagrams, flows, state diagrams, architecture maps, side-by-side layout comparisons.
  - Use terminal/text for requirements, conceptual choices, tradeoff tables, scope decisions.
  - Text remains the source of truth.
  - Every visual needs a concise text equivalent/fallback.
  - Invalid/unsupported Mermaid → fall back to text.
  - Stale/contradictory visual → retire/update it.
  - No secrets/PII in visuals.

**Step 5: Add bounded guide**

Create `skills/brainstorming/visual-companion.md` with these sections only: `Lazy-load rule`, `When to use visuals`, `When to stay text-only`, `Mermaid and diagram examples`, `Mockups and comparisons`, `Accessibility and fallback`, `Privacy and safety`, `Stale visuals`. Include one Mermaid example and one mockup guidance list. State: `SKILL.md remains authoritative`; do not duplicate full brainstorming workflow.

**Step 6: Update durable docs**

- `AGENTS.md`: add `bash tests/brainstorm-visual-companion.sh` under skill content checks.
- `docs/cross-llm-coverage.md`: add `Visual companion output` row with markdown/Mermaid best-effort and browser deferred for every host. Add a note that rendered diagrams require text fallback and browser/event capture is deferred.
- `tests/cross-llm-coverage.md`: update brainstorming note: `Visual companion guidance is host-neutral and best-effort; browser/event capture is deferred.`
- Create `docs/FOLLOWUPS.md`:

```markdown
# Follow-ups

## Brainstorm visual companion browser parity

- **Source:** issue #78 / `docs/plans/2026-06-30-brainstorm-visualization-design.md`
- **Status:** Deferred
- **Follow-up:** Evaluate whether ADK should ship an upstream-like browser companion with tab launch, click/event capture, session security, cleanup, and host process validation.
```

**Step 7: Verify GREEN**

Run: `bash tests/brainstorm-visual-companion.sh`

Expected:

```text
PASS: brainstorming has Visual Companion section
...
Results: 0 failure(s)
```

**Step 8: Pre-commit quick checks**

Run:

```bash
bash tests/brainstorm-visual-companion.sh
bash tests/skill-content-grep.sh
bash tests/skill-cross-refs.sh
bash tests/no-machine-paths.sh
```

Expected: all PASS / `Results: 0 failure(s)`.

**Step 9: Commit**

Run:

```bash
git add AGENTS.md docs/cross-llm-coverage.md tests/cross-llm-coverage.md docs/FOLLOWUPS.md tests/brainstorm-visual-companion.sh skills/brainstorming/SKILL.md skills/brainstorming/visual-companion.md skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md docs/plans/2026-06-30-brainstorm-visualization-behavior-proof.md
git commit -m "Add brainstorm visual companion guidance"
```

**Rollback:** revert this commit; rerun `bash tests/brainstorm-visual-companion.sh` only if keeping the test, otherwise rerun full suite after revert.

---

### Task 2: Transcript-Backed Behavior Proof

**Files:**
- Create: `docs/plans/2026-06-30-brainstorm-visualization-behavior-proof.md`
- Modify implementation files only if proof finds gaps.

**Step 1: GREEN isolated-subject pressure run**

Use the Pressure-Proof Execution Protocol above: native subagent if available; otherwise a fresh isolated host thread/session in the same worktree. Give the isolated subject this prompt:

```text
Use `skills/brainstorming/SKILL.md` and, only if the skill instructs you to, `skills/brainstorming/visual-companion.md`.
Scenario: A user is brainstorming a dashboard redesign quickly. First they ask the conceptual question "what does trust mean for this dashboard?" Later they ask a visual layout choice that would be clearer shown than described. Then they decline visuals to save time. Finally imagine they had accepted a visual and then changed a decision so the visual is stale.
Return the exact messages/actions you would take for: conceptual text-only, visual offer, declines, accepts, stale visual. Cite the skill/guide rule that governs each path.
```

Expected: subject demonstrates all five fixture paths and cites current skill/guide rules.

**Step 2: Reviewer scores the transcript**

Dispatch a reviewer with the subject output plus `skills/brainstorming/SKILL.md`, `skills/brainstorming/visual-companion.md`, and `skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md`:

```text
Score the subject transcript against all expected paths. Verify each cited rule exists in the current skill or guide. Bias toward finding failures. PASS only if conceptual text-only, visual offer, declines, accepts, and stale visual paths match the fixture and cite real rules.
```

Expected: PASS.

**Step 3: Write proof artifact**

Append GREEN proof to `docs/plans/2026-06-30-brainstorm-visualization-behavior-proof.md`:

```markdown
# Brainstorm Visualization Behavior Proof

## RED baseline

<summary of baseline subject output from Task 1 Step 1; include MISSING rows>

## GREEN subject run

<subject output summary; include citations>

## Reviewer score

PASS for: conceptual text-only, visual offer, declines, accepts, stale visual.

## Evidence

- `bash tests/brainstorm-visual-companion.sh` → `Results: 0 failure(s)`
```

**Step 4: Fix and re-run if needed**

If reviewer FAILs: update `skills/brainstorming/SKILL.md` or guide minimally, rerun `bash tests/brainstorm-visual-companion.sh`, rerun subject + reviewer proof, then continue.

**Step 5: Commit proof/fixes**

Run:

```bash
git add docs/plans/2026-06-30-brainstorm-visualization-behavior-proof.md skills/brainstorming/SKILL.md skills/brainstorming/visual-companion.md
git commit -m "Prove visual companion behavior"
```

If no implementation fix was needed, commit only the proof artifact.

**Rollback:** revert proof/fix commit; no runtime state.

---

### Task 3: Full Validation and PR Prep

**Files:**
- No production file changes expected unless validation finds a gap.

**Step 1: Documentation validation note**

This repo has no dedicated markdown renderer/spellchecker command. For markdown/doc changes, use the focused shell guard, `skill-cross-refs`, `no-machine-paths`, and manual editor preview where available.

**Step 2: Run targeted checks**

Run:

```bash
bash tests/brainstorm-visual-companion.sh
bash tests/skill-content-grep.sh
bash tests/skill-cross-refs.sh
bash tests/no-machine-paths.sh
```

Expected: all PASS / `Results: 0 failure(s)`.

**Step 3: Run full documented suite**

Run AGENTS.md commands:

```bash
bash tests/skill-content-grep.sh
bash tests/adk-path-canonicalization.sh
bash tests/pipeline-evidence-doc-sync.sh
bash tests/skill-cross-refs.sh
bash tests/brainstorm-visual-companion.sh
bash tests/hook-contracts.sh
bash tests/hook-stdout-discipline.sh
bash tests/plan-scope-check-contracts.sh
bash tests/version-check.sh
```

Expected: all PASS, `OK: All version files agree on version 6.6.1`.

**Step 4: Commit validation fixes if needed**

If Step 2-3 required edits:

```bash
git add <changed-files>
git commit -m "Tighten visual companion validation"
```

If no edits, no commit.

**Step 5: PR body evidence**

PR body must include:

- Issue: closes #78.
- RED baseline summary from behavior proof.
- GREEN subject/reviewer behavior proof summary.
- Targeted and full-suite command outputs.
- Deferred browser/event-capture parity follow-up path: `docs/FOLLOWUPS.md`.

**Rollback:** revert implementation/proof commits and rerun the full documented suite. No runtime state or migrations.
