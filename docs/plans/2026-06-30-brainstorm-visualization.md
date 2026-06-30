# Brainstorm Visualization Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Add host-neutral brainstorm/design visualization companion guidance for issue #78.

**Architecture:** Extend `skills/brainstorming/SKILL.md` with just-in-time visual companion rules while keeping existing gates intact. Add a lazy-loaded guide, behavior fixture, focused regression guard, coverage/doc updates, and a follow-up for deferred browser parity.

**Tech Stack:** Markdown skills/docs; Bash regression tests; GitHub issue/PR workflow.

**Base branch:** main

---

## Scope Manifest

**PR Count:** 1
**Tasks:** 4
**Estimated Lines of Change:** ~260

**Out of scope:**
- Browser server/runtime companion.
- Click/event capture or telemetry.
- Claiming Mermaid rendering is runtime-integrated on hosts where it has not been observed.

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Add brainstorm visual companion guidance | Task 1, Task 2, Task 3, Task 4 | issue-78-brainstorm-visualization |

**Status:** Draft

---

## Task 1: Skill Regression Guard and Behavior Fixture

**Files:**
- Create: `tests/brainstorm-visual-companion.sh`
- Create: `skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md`

**Step 1: Write the failing regression guard**

Create `tests/brainstorm-visual-companion.sh`:

```bash
#!/usr/bin/env bash
# Regression guard for issue #78 brainstorm visualization companion.
set -uo pipefail
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
hasE "$BRAIN" 'not[ -]upfront|NOT upfront' && pass "visual companion is not offered upfront" || bad "visual companion upfront prohibition missing"
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
fi

[ -f "$FIXTURE" ] && pass "behavior fixture exists" || bad "behavior fixture missing"
if [ -f "$FIXTURE" ]; then
  for marker in "conceptual text-only" "visual offer" "declines" "accepts" "stale visual" "RED baseline"; do
    has "$FIXTURE" "$marker" && pass "fixture covers $marker" || bad "fixture missing $marker"
  done
fi

has "$AGENTS" "tests/brainstorm-visual-companion.sh" && pass "AGENTS documents visual companion test" || bad "AGENTS missing visual companion test"
has "$CAPS" "Visual companion" && pass "capability matrix includes visual companion" || bad "capability matrix missing visual companion"
has "$SKILL_COVERAGE" "visual companion" && pass "skill coverage notes visual companion" || bad "skill coverage missing visual companion note"

echo ""; echo "Results: $fail failure(s)"; [ "$fail" -eq 0 ]
```

**Step 2: Verify RED**

Run: `bash tests/brainstorm-visual-companion.sh`

Expected: FAIL with at least these missing-contract messages:

```text
FAIL: brainstorming missing Visual Companion section
FAIL: visual companion guide missing
FAIL: behavior fixture missing
FAIL: AGENTS missing visual companion test
```

**Step 3: Add behavior fixture**

Create `skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md` with:

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

**Step 4: Commit policy**

Do not commit yet if the test is still red. Continue Task 2 to make this guard pass.

---

## Task 2: Brainstorming Skill and Visual Companion Guide

**Files:**
- Modify: `skills/brainstorming/SKILL.md`
- Create: `skills/brainstorming/visual-companion.md`
- Uses tests from Task 1.

**Step 1: Update `SKILL.md`**

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

**Step 2: Add guide**

Create `skills/brainstorming/visual-companion.md` with bounded reference content:

- `# Visual Companion Guide`
- `## Lazy-load rule`
- `## When to use visuals`
- `## When to stay text-only`
- `## Mermaid and diagram examples`
- `## Mockups and comparisons`
- `## Accessibility and fallback`
- `## Privacy and safety`
- `## Stale visuals`

**Step 3: Verify GREEN for skill/guide markers**

Run: `bash tests/brainstorm-visual-companion.sh`

Expected: still FAIL only for durable docs not yet updated:

```text
FAIL: AGENTS missing visual companion test
FAIL: capability matrix missing visual companion
FAIL: skill coverage missing visual companion note
```

If any skill/guide/fixture assertion fails, fix before continuing.

---

## Task 3: Durable Docs and Follow-Up

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/cross-llm-coverage.md`
- Modify: `tests/cross-llm-coverage.md`
- Create: `docs/FOLLOWUPS.md`

**Step 1: Update documented checks**

In `AGENTS.md`, under skill content checks, add:

```bash
bash tests/brainstorm-visual-companion.sh
```

**Step 2: Update capability matrix**

In `docs/cross-llm-coverage.md`, add a capability row:

```markdown
| Visual companion output | ⚠️ markdown/Mermaid best-effort; browser deferred | ⚠️ markdown/Mermaid best-effort; browser deferred | ⚠️ markdown/Mermaid best-effort; browser deferred | ⚠️ markdown/Mermaid best-effort; browser deferred | ⚠️ markdown/Mermaid best-effort; browser deferred | ⚠️ markdown plus best-effort Mermaid rendering; browser deferred |
```

Add a note: rendered diagrams require text fallback; browser/event capture is deferred.

**Step 3: Update skill coverage**

In `tests/cross-llm-coverage.md`, update brainstorming note to mention:

```text
Visual companion guidance is host-neutral and best-effort; browser/event capture is deferred.
```

**Step 4: Add deferred follow-up**

Create `docs/FOLLOWUPS.md` if absent:

```markdown
# Follow-ups

## Brainstorm visual companion browser parity

- **Source:** issue #78 / `docs/plans/2026-06-30-brainstorm-visualization-design.md`
- **Status:** Deferred
- **Follow-up:** Evaluate whether ADK should ship an upstream-like browser companion with tab launch, click/event capture, session security, cleanup, and host process validation.
```

**Step 5: Verify GREEN**

Run: `bash tests/brainstorm-visual-companion.sh`

Expected:

```text
PASS: brainstorming has Visual Companion section
...
Results: 0 failure(s)
```

**Step 6: Commit Tasks 1-3**

Run:

```bash
git add AGENTS.md docs/cross-llm-coverage.md tests/cross-llm-coverage.md docs/FOLLOWUPS.md tests/brainstorm-visual-companion.sh skills/brainstorming/SKILL.md skills/brainstorming/visual-companion.md skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md
git commit -m "Add brainstorm visual companion guidance"
```

---

## Task 4: Behavior Proof and Full Validation

**Files:**
- No production file changes expected unless behavior proof finds a gap.
- PR body must include behavior proof summary and test output.

**Step 1: Run subagent behavior proof**

Dispatch a reviewer with this prompt:

```text
Read `skills/brainstorming/SKILL.md`, `skills/brainstorming/visual-companion.md`, and `skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md`.

Assess whether the current skill instructions force all expected behavior paths: conceptual text-only, visual offer, declines, accepts, stale visual. Bias toward finding gaps. Return PASS only if each path is explicitly supported by skill/guide text, citing the lines/sections.
```

Expected: PASS for all five paths.

If FAIL: update `SKILL.md` or guide minimally, rerun `bash tests/brainstorm-visual-companion.sh`, rerun behavior proof, and commit fixes.

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

If Step 1-3 required edits:

```bash
git add <changed-files>
git commit -m "Tighten visual companion validation"
```

If no edits, no commit.

**Rollback:** revert the implementation commit(s) and rerun the full documented suite. No runtime state or migrations.
