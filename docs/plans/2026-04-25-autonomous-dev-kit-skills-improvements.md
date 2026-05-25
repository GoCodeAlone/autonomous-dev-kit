# Autonomous Dev Kit Skills Improvements — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Address ten observed failure patterns in the autonomous-development pipeline by upgrading six existing skills and adding one new mini-skill for cross-cutting runtime-launch validation.

**Architecture:** Edit-in-place for most patterns; extract `runtime-launch-validation` as a single new skill so `finishing-a-development-branch` and `writing-plans` can both reference it without duplication. Each substantive addition is paired with a test fixture demonstrating the before/after behavior, per the `writing-skills` discipline.

**Tech Stack:** Markdown skill files; bash for fixture commands; Graphviz/dot for any flow diagrams; the repo's existing skill-validation conventions.

**Sanitization:** Public skill set — every example, fixture, and comment must be generic. No specific project, company, version, or incident references. Generic technology terms used as examples (e.g. Go, Markdown, bash) are fine.

**Design doc:** `docs/plans/2026-04-25-autodev-skills-improvements-design.md` (commit 6bb1833)

---

## PR splitting

Five PRs, sequenced for dependency + review ergonomics:

| PR | Bundle | Why bundled |
|---|---|---|
| 1 | `requesting-code-review` rewrite + fixtures | Highest impact, largest single edit |
| 2 | `test-driven-development` additions + fixtures | Independent |
| 3 | `runtime-launch-validation` new skill + `finishing-a-development-branch` additions + fixtures | #3's gate references the new skill |
| 4 | `writing-plans` additions + `brainstorming` `--design-only` flag + fixtures | The flag propagates between them |
| 5 | `subagent-driven-development` DRY refactor + fixture | Independent; lands last to dogfood the earlier work |

Each PR independently goes through finishing-a-development-branch + pr-monitoring. Implementer: per the orchestrator's team configuration.

---

## PR 1 — `requesting-code-review` rewrite

**Branch off:** `feat/skills-improvements-from-failure-modes` (this is the working branch; PR opens against `main`)

### Task 1: Read existing skill, draft section structure

**Files:**
- Read: `skills/requesting-code-review/SKILL.md`

**Step 1: Read current skill**

Run: `cat skills/requesting-code-review/SKILL.md`
Expected: skill content visible. Note the existing sections.

**Step 2: Draft the new section structure as a comment in your scratch buffer**

Sections to add (in order at top of skill, after frontmatter):
1. "Reviewer brief — adversarial framing"
2. "Scope-vs-dispatch compliance gate (RUN FIRST)" ← runs before bug-class scan
3. "Bug-class checklist (must scan)"
4. "Output format (per-finding, inline at file:line)"
5. "Iterative loop protocol"
6. "Verdict vocabulary"

No commit; preparation only.

---

### Task 2: Write fixture — sibling-asymmetry bug (RED for old skill)

**Files:**
- Create: `skills/requesting-code-review/test-fixtures/sibling-asymmetry/diff.patch`
- Create: `skills/requesting-code-review/test-fixtures/sibling-asymmetry/dispatch.md`
- Create: `skills/requesting-code-review/test-fixtures/sibling-asymmetry/old-prompt.md`
- Create: `skills/requesting-code-review/test-fixtures/sibling-asymmetry/expected-old-result.md`

**Step 1: Write `diff.patch` — a minimal generic diff with a sibling-asymmetry bug**

```diff
--- a/lib/dispatcher.go
+++ b/lib/dispatcher.go
@@ -10,6 +10,12 @@ func (d *Dispatcher) Create(req Request) error {
   return d.client.Send("create", map[string]any{
     "kind":    d.kind,
     "name":    req.Name,
     "payload": req.Payload,
   })
 }

+func (d *Dispatcher) Inspect(req Request) error {
+  return d.client.Send("inspect", map[string]any{
+    "name":    req.Name,
+    "payload": req.Payload,
+  })
+}
+
 func (d *Dispatcher) Delete(req Request) error {
   return d.client.Send("delete", map[string]any{
     "kind":    d.kind,
     "name":    req.Name,
   })
 }
```

The bug: the new `Inspect` method omits `"kind": d.kind` from its args map. Every sibling method (Create, Delete, and unseen others) sets it. This is exactly the class invariant violation pattern from the design.

**Step 2: Write `dispatch.md` — the orchestrator's instruction to the implementer**

```markdown
Add an `Inspect(req Request) error` method to `Dispatcher` mirroring the existing
`Create` and `Delete` shape. The new method must produce a Send call whose args
match the same convention as siblings.
```

**Step 3: Write `old-prompt.md` — the current pre-rewrite reviewer brief verbatim**

(Copy the existing brief from `requesting-code-review/SKILL.md` review-request template.)

**Step 4: Write `expected-old-result.md` — what the old prompt typically produces**

```markdown
The Inspect method follows the same Send-with-args pattern as Create and Delete.
Looks good. Approved.
```

(This is the failure mode: the old prompt approves the asymmetry.)

**Step 5: Commit**

```bash
git add skills/requesting-code-review/test-fixtures/sibling-asymmetry/
git commit -m "skill(requesting-code-review): fixture — sibling-asymmetry bug, old-prompt approves"
```

---

### Task 3: Add new "Reviewer brief — adversarial framing" section

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

**Step 1: Insert section near top of skill (after frontmatter, before existing content)**

```markdown
## Reviewer brief — adversarial framing

The reviewer subagent's instructions must use **adversarial framing**, not validation framing.

**Required prompt phrasing in every dispatch:**

> Find at least three things wrong with this code, even if they seem minor. Bias toward finding issues. You are NOT validating that the code matches the dispatch — you are looking for bugs the original author missed.

Why: the same base model produces dramatically different output under "find what's wrong" vs. "review the work." Validation framing biases toward approval; adversarial framing biases toward rigor. The shift is mechanical and reproducible.

**Forbidden phrasing**: "review the work", "verify the implementation matches the plan", "confirm correctness", any prompt that implies the reviewer's job is to validate. These produce sign-offs that miss real bugs.

**Reflexive approval is forbidden.** If the reviewer finds nothing wrong, they must state which checks were run (the bug-class checklist below) and what specifically they verified. A bare "looks good" is rejected.
```

**Step 2: Verify**

Run: `head -30 skills/requesting-code-review/SKILL.md`
Expected: new section is at the top, framing is adversarial.

**Step 3: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "skill(requesting-code-review): adversarial framing section"
```

---

### Task 4: Add bug-class checklist section

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

**Step 1: Insert after the "Reviewer brief — adversarial framing" section**

```markdown
## Bug-class checklist (must scan)

The reviewer must explicitly scan for each of these bug classes on every diff. The checklist is the floor, not the ceiling — additional findings are welcome.

| Class | Definition |
|---|---|
| **Symmetry violations** | Sibling methods in the same struct/class/handler family follow a convention; one method drifts from it. The new method omits a key the others set, or wraps an error the others don't, or returns a shape the others don't. |
| **Error swallowing** | `_, err := ...; result` patterns, `_ = err`, `if err != nil { log(err) }` followed by silent recovery, errors caught and not propagated when they should be. |
| **Comment-vs-code drift** | Comments describing behavior the code no longer has; comments naming files, functions, or variables that have been renamed. |
| **Test-name-vs-body mismatch** | A test named `..._HandlesNotFound` that actually simulates a list-API error rather than the not-found path. The name and the body disagree. |
| **Missing edge cases** | Tests covering only the happy path. No empty/nil/malformed inputs. No network-error or timeout paths. No boundary values. |
| **Concurrency bugs** | Goroutines/threads without sync, race conditions, channel-close patterns, missing locks, double-unlock. |
| **Type-coercion silent failures** | Encode/decode where `int → float64` is silently lossy, where `[]any → []string` is rejected without a clear error, where `nil` and zero-value diverge. |
| **Dead/unreachable code** | Branches no test exercises and no caller can reach. Either delete or cover. |
| **Scope-vs-dispatch drift** | The implementation ships materially MORE or LESS than the dispatch asked for. Both directions are findings. (See the dedicated gate below.) |

For each finding, the reviewer cites the bug class explicitly. This makes patterns visible across reviews and lets the team identify recurring weaknesses.
```

**Step 2: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "skill(requesting-code-review): bug-class checklist (9 classes)"
```

---

### Task 5: Add output format mandate

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

**Step 1: Insert after the bug-class checklist**

````markdown
## Output format (per-finding, inline at file:line)

Every finding is one block in this shape:

```
### Finding N — <one-line summary>
- **Severity**: Critical | Important | Minor | Nit
- **Bug class**: <from the checklist or "other (describe)">
- **Location**: `path/to/file.ext:line`
- **What's wrong**: <one sentence>
- **Why it matters**: <one sentence — what breaks, when, for whom>
- **Suggested fix**: <one sentence or short snippet>
```

**Forbidden output styles:**
- Prose summary as the primary review ("the changes look good overall, with a few small issues...")
- Findings without `file:line` references
- Findings without an explicit bug class
- Findings without a severity tier
- Mixing multiple findings into one block

**Why:** prose summaries glide over specifics. The same reviewer producing a paragraph approves bugs they would have flagged if forced into a per-finding format. Inline anchored output reproduces what a focused external reviewer naturally produces.
````

**Step 2: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "skill(requesting-code-review): output format mandate (inline, file:line)"
```

---

### Task 6: Add iterative loop protocol

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

**Step 1: Insert after output format**

```markdown
## Iterative loop protocol

One review pass is insufficient. After implementer addresses findings, the reviewer **re-reads the new diff from scratch** and runs the full bug-class checklist again. New issues commonly surface — fixes introduce new bugs, fixes only address the symptom, or the implementer interprets the finding too narrowly.

Loop:

1. Implementer dispatches review.
2. Reviewer scans (bug-class checklist) → produces findings.
3. Implementer addresses each finding, pushes new commits.
4. **Reviewer re-reads the new diff (not just the diff-of-diffs)** and runs the full checklist again.
5. Repeat until reviewer's verdict is SHIP-IT with no Critical or Important findings.

Maximum loops: 5 per PR. If the reviewer still finds Critical/Important issues after round 5, the verdict becomes REVERT-AND-REWRITE; the implementer takes a different approach.

**The loop runs even if intermediate rounds had findings of Minor severity only.** The bar is "find what's wrong" — Minor findings don't trigger automatic re-review, but the human or orchestrator inspects them before merge.
```

**Step 2: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "skill(requesting-code-review): iterative loop protocol (max 5 rounds)"
```

---

### Task 7: Add scope-vs-dispatch compliance gate

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

**Step 1: Insert this BEFORE the bug-class checklist (it runs first)**

```markdown
## Scope-vs-dispatch compliance gate (RUN FIRST)

Before any other check, the reviewer compares the PR diff against the dispatch text — the message that asked the implementer to do the work.

**Diff-vs-dispatch comparison:**

1. List each thing the dispatch asked for (acceptance criteria, named files, named tests, named behaviors).
2. For each, find the corresponding change in the PR diff.
3. List each thing the PR diff does that the dispatch did NOT ask for.

**Both sides are findings:**

- Dispatch asked for X, PR doesn't include X → **MISSING** (Important or Critical)
- PR includes Y not in dispatch → **SCOPE CREEP** (Minor unless it's risky, then Important)

A common pattern this catches: dispatch says "table-driven test covering N methods", PR delivers "single-line assertion on one method." Old reviewer (validation framing) signs off. New reviewer (compliance gate) flags as MISSING.

**This gate runs before the bug-class scan** because scope mismatch is often the most expensive finding to fix late, and signing off on a too-narrow PR locks in the gap.

If the implementer's choice differs from the dispatch but is justified, the implementer must say so explicitly in the PR body before review (e.g., "dispatch asked for X; I instead did Y because..."). Reviewer then evaluates the justification on its merits rather than flagging as drift.
```

**Step 2: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "skill(requesting-code-review): scope-vs-dispatch compliance gate"
```

---

### Task 8: Add verdict vocabulary section

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

**Step 1: Insert at the bottom of the skill (after the existing content)**

```markdown
## Verdict vocabulary

Reviewer ends every review with exactly one of these verdicts:

- **SHIP-IT** — no Critical, no Important, optionally a few Minor/Nit. Merge.
- **FIX-FORWARD** — substantive findings, but they're additive. Merge this PR; open a follow-up PR for the findings. Use when the current PR's value is independent and the findings are new work.
- **REQUEST-CHANGES** — Critical or Important findings that block merge of this PR. Implementer addresses, re-review.
- **REVERT-AND-REWRITE** — fundamental approach issue; the right answer is a different design. Used after iterative-loop max rounds, or for clear architectural mistakes.

Reviewer must justify the verdict in one sentence:

> Verdict: REQUEST-CHANGES — three Critical findings (sibling-method asymmetry, missing nil-check, unreachable test branch); fixing requires non-trivial code change.

Reflexive SHIP-IT without justification is forbidden.
```

**Step 2: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "skill(requesting-code-review): verdict vocabulary"
```

---

### Task 9: Update review-request template to incorporate new brief

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md` (existing template section)

**Step 1: Locate the existing review-request template (section that shows what to send to the reviewer subagent)**

Run: `grep -n "review.*template\|## Template\|## Request" skills/requesting-code-review/SKILL.md`

**Step 2: Update the template to include**

```markdown
## Review-request template

When dispatching a code-review subagent:

```
You are a code reviewer with adversarial framing. Find at least three things
wrong with this code, even if they seem minor. Bias toward finding issues.

## Diff under review
<diff>

## Original dispatch (what the implementer was asked to do)
<dispatch text>

## Required output

Run these checks IN ORDER:

1. Scope-vs-dispatch compliance gate. List dispatch asks vs. PR delivers.
   Flag MISSING and SCOPE CREEP findings.
2. Bug-class scan. For each class in the checklist
   (skills/requesting-code-review/SKILL.md), state which you ran and
   what you found.
3. End with one verdict: SHIP-IT | FIX-FORWARD | REQUEST-CHANGES |
   REVERT-AND-REWRITE, plus a one-sentence justification.

For each finding, use the per-finding format:
- Severity, Bug class, Location (file:line), What's wrong, Why it matters,
  Suggested fix.

Reflexive approval is forbidden. If you find nothing wrong, state which
checks were run.
```

**Step 3: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "skill(requesting-code-review): update dispatch template with new brief"
```

---

### Task 10: Add fixture — same diff under new prompt (GREEN)

**Files:**
- Create: `skills/requesting-code-review/test-fixtures/sibling-asymmetry/new-prompt.md`
- Create: `skills/requesting-code-review/test-fixtures/sibling-asymmetry/expected-new-result.md`

**Step 1: Write `new-prompt.md`** — the new dispatch template from Task 9 applied to the fixture diff.

**Step 2: Write `expected-new-result.md`**

```markdown
## Findings

### Finding 1 — Inspect omits `kind` arg present in all sibling methods
- **Severity**: Important
- **Bug class**: Symmetry violations
- **Location**: `lib/dispatcher.go:13`
- **What's wrong**: The new `Inspect` method's args map omits `"kind": d.kind`. Sibling methods `Create` (line 11) and `Delete` (line 17) both set it.
- **Why it matters**: Receivers downstream rely on `kind` to dispatch correctly. Calling Inspect will silently target the wrong dispatch path or return `not found` because the receiver can't disambiguate.
- **Suggested fix**: Add `"kind": d.kind,` as the first arg in the map, matching siblings.

### Verdict: REQUEST-CHANGES
One Important finding (sibling-method asymmetry); fix is one line. Once added and re-reviewed, expected to be SHIP-IT.
```

**Step 3: Verify the fixture demonstrates the before/after gap**

Run: `diff skills/requesting-code-review/test-fixtures/sibling-asymmetry/expected-old-result.md skills/requesting-code-review/test-fixtures/sibling-asymmetry/expected-new-result.md`

Expected: substantial difference — old approves, new flags Important.

**Step 4: Commit**

```bash
git add skills/requesting-code-review/test-fixtures/sibling-asymmetry/new-prompt.md skills/requesting-code-review/test-fixtures/sibling-asymmetry/expected-new-result.md
git commit -m "skill(requesting-code-review): fixture — same diff under new prompt flags asymmetry"
```

---

### Task 11: Add fixture README

**Files:**
- Create: `skills/requesting-code-review/test-fixtures/README.md`

**Step 1: Document the fixture**

```markdown
# requesting-code-review test fixtures

Each fixture demonstrates a class of bug the **old** reviewer brief
let pass and the **new** brief catches. Used to validate the skill's
effectiveness and to prevent regression.

## sibling-asymmetry

Diff with one new method that omits an arg every sibling method sets.
- `diff.patch` — the change under review
- `dispatch.md` — what the implementer was asked to do
- `old-prompt.md` — pre-rewrite reviewer brief (validation framing)
- `expected-old-result.md` — what the old prompt typically returns: approval
- `new-prompt.md` — post-rewrite reviewer brief (adversarial framing + checklist)
- `expected-new-result.md` — what the new prompt returns: Important finding flagged

## How to add a new fixture

1. Write a generic diff that demonstrates a bug class from the checklist.
2. Capture the dispatch text the implementer would have received.
3. Capture both old and new prompt outputs. Prefer real transcripts from live
   subagent runs. Author-written (synthesized) results are acceptable for
   initial demonstrations if labeled `<!-- synthesized -->` as the first line.
4. The new prompt MUST flag where the old approved.
```

**Step 2: Commit**

```bash
git add skills/requesting-code-review/test-fixtures/README.md
git commit -m "skill(requesting-code-review): fixture README"
```

---

### Task 12: Open PR 1, ship through review

**Files:** none (PR open + review)

**Step 1: Push branch**

```bash
git push origin feat/skills-improvements-from-failure-modes
```

(Note: branch was already pushed when the design committed; this is force-with-lease only if needed.)

**Step 2: Open PR**

```bash
gh pr create --base main --head feat/skills-improvements-from-failure-modes \
  --title "skill: requesting-code-review — adversarial framing rewrite" \
  --body "$(cat <<'EOF'
## Summary
Rewrite the code-review brief to use adversarial framing, an explicit
bug-class checklist, mandatory line-anchored output, an iterative
loop protocol, a scope-vs-dispatch compliance gate, and a verdict
vocabulary. Together these reproduce what an external adversarial
reviewer naturally produces.

## Why
Same-LLM reviewers under "find what's wrong" framing consistently
catch bugs that the same model under "validate the work" framing
approves. The change is mechanical and reproducible.

## Test plan
- Fixture `sibling-asymmetry` demonstrates the before/after gap.
- Old prompt approves the diff; new prompt flags the omitted-arg
  symmetry violation as Important.

## Conventions
This PR is part of a sequence of skill upgrades. Per the iterative
loop protocol it introduces, expect at least one re-review round.
Reviewer please use the new brief on this PR — yes, recursively.
EOF
)"
```

**Step 3: Add Copilot reviewer**

```bash
gh pr edit <PR_NUMBER> --add-reviewer copilot-pull-request-reviewer
```

**Step 4: Loop**

Per `pr-monitoring`:
- Watch CI.
- Address review feedback per the new iterative-loop protocol.
- Maximum 5 rounds.
- DM team-lead when CI green and reviewer is at SHIP-IT.

**Step 5: After merge** — the team-lead handles merge + tag if applicable. Implementer marks the PR done in tracking.

---

## PR 2 — `test-driven-development` additions

**Branch off:** main (after PR 1 merges)

### Task 13: Add "Verify Regression Invariant" step

**Files:**
- Modify: `skills/test-driven-development/SKILL.md`

**Step 1: Locate the GREEN section**

Run: `grep -n "GREEN\|verify it passes\|## Step 4\|^## " skills/test-driven-development/SKILL.md`

**Step 2: Insert after the GREEN section, before REFACTOR**

```markdown
## Verify Regression Invariant

After GREEN, prove the test actually catches the bug it gates.

1. Revert the production code change (just the fix).
2. Run the new test.
   **Must FAIL** with a clear message that ties to the bug.
   If it passes, the test doesn't actually exercise the fix path —
   either the test is structured wrong or the fix doesn't address the
   root cause. Stop and rethink.
3. Restore the fix.
4. Run the test again.
   **Must PASS.**
5. Document the proof in the PR body. Paste the relevant lines:

   ```
   With fix reverted:
   $ test run command
     FAIL — <message that names the bug>

   With fix restored:
   $ test run command
     PASS
   ```

**Why:** a passing test proves nothing without this check. The test might pass for the wrong reason (uses the same broken code path; mocks the bug away; tests a tangentially-correct property). The revert-and-restore proof is the only way to know the test would actually have caught the bug if shipped before the fix.

**Iron Law (extension):** No claim of "test catches regression" without revert-and-restore proof in the PR body.
```

**Step 3: Commit**

```bash
git add skills/test-driven-development/SKILL.md
git commit -m "skill(test-driven-development): Verify Regression Invariant step"
```

---

### Task 14: Add "Class invariant violation" section

**Files:**
- Modify: `skills/test-driven-development/SKILL.md`

**Step 1: Insert near bottom of skill (before any "Common Failures" or appendix)**

```markdown
## When the bug is a class invariant violation

A common pattern: one method of a sibling-method group violates a convention the rest of the group follows. The fix is local; the bug is structural.

**Heuristic — does this apply?**

- Is there a sibling-method group? (Several methods on the same struct, same handler family, same RPC service, same hook table.)
- Does the bug stem from the buggy method failing to follow a convention the rest of the group already follows?
- Could a future method drift the same way?

If two yes: the regression test must drive ALL sibling methods — not just the buggy one. Pattern: table-driven test with one entry per sibling method, each asserting the invariant.

**Why:** fixing only the buggy method leaves the bug class open. The next method that drifts ships the same bug. The test must be a gate on the class, not the instance.

**Concrete example (generic):**

A `Dispatcher` struct has methods `Create`, `Read`, `Update`, `Delete`, `Inspect`, etc. Each calls `client.Send(...)` with an args map that must include `"kind": d.kind`. If `Inspect` is the new method and it omits `kind`, the fix is one line — but the regression test should be:

```go
func TestDispatcher_AllMethods_IncludeKind(t *testing.T) {
    cases := []struct {
        name string
        call func(d *Dispatcher) error
    }{
        {"Create",  func(d *Dispatcher) error { return d.Create(...) }},
        {"Read",    func(d *Dispatcher) error { return d.Read(...) }},
        {"Update",  func(d *Dispatcher) error { return d.Update(...) }},
        {"Delete",  func(d *Dispatcher) error { return d.Delete(...) }},
        {"Inspect", func(d *Dispatcher) error { return d.Inspect(...) }},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            spy := &spyClient{}
            d := &Dispatcher{client: spy, kind: "widget"}
            _ = tc.call(d)
            if spy.lastArgs["kind"] != "widget" {
                t.Errorf("%s: missing or wrong kind in args", tc.name)
            }
        })
    }
}
```

The next method that drifts the same way fails this test on first commit.

**Add a comment near the test:** "Regression gate for the class invariant; new methods MUST include the same arg/convention."
```

**Step 2: Commit**

```bash
git add skills/test-driven-development/SKILL.md
git commit -m "skill(test-driven-development): class invariant violation section"
```

---

### Task 15: Fixture — narrow regression test that "passes for the wrong reason"

**Files:**
- Create: `skills/test-driven-development/test-fixtures/narrow-regression/scenario.md`
- Create: `skills/test-driven-development/test-fixtures/narrow-regression/old-flow.md`
- Create: `skills/test-driven-development/test-fixtures/narrow-regression/new-flow.md`

**Step 1: Write scenario**

```markdown
# Narrow regression — passes for the wrong reason

A function `Sum(xs []int) int` is broken: it returns `0` for empty
input AND for input `[1]` (off-by-one in the loop).

The implementer "fixes" the loop and adds a test:

```go
func TestSum_HandlesSingleElement(t *testing.T) {
    if Sum([]int{1}) != 1 { t.Fail() }
}
```

The test passes after their fix. They claim done.
```

**Step 2: Write old-flow** — what happens under the old TDD steps

```markdown
- RED: written, runs, FAILs (since fix not yet applied).
- GREEN: fix applied, test PASSES.
- (No regression-invariant check.)
- Done. PR opened.

Hidden problem: the fix is an over-correction; for input `[]int{}`
the function now panics. Test never exercised the empty-input path.
The original "broken on empty" symptom is now WORSE (panic vs 0),
but the new test doesn't catch it. Reviewer approves.
```

**Step 3: Write new-flow** — what happens under the new TDD steps

```markdown
- RED: written, runs, FAILs.
- GREEN: fix applied, test PASSES.
- **Verify Regression Invariant**:
  - Revert fix. Run `TestSum_HandlesSingleElement`. Must FAIL. ✓ FAILS.
  - Restore fix. Must PASS. ✓ PASSES.
- **Class invariant heuristic check**:
  - Is `Sum` part of a group? (Yes: math operations on slices —
    `Sum`, `Mean`, `Max`, `Min`.)
  - Does the bug stem from one method drifting? (No — only Sum
    is changed; the bug is Sum-internal.)
  - Heuristic does NOT apply, but adjacent class-of-input check should:
- **Edge case sweep** (per "Missing edge cases" in code-review checklist):
  - Empty slice → would test pass? Run: `Sum([]int{})`. PANICS!
  - Implementer realizes the fix is wrong, refactors, and adds:
    `TestSum_HandlesEmpty`, `TestSum_HandlesNegative`, `TestSum_HandlesLarge`.
- The class-of-input regression now covers what the narrow test missed.
- Done. PR opened with proof + sweep.
```

**Step 4: Commit**

```bash
git add skills/test-driven-development/test-fixtures/narrow-regression/
git commit -m "skill(test-driven-development): fixture — narrow regression catches false-positive"
```

---

### Task 16: Open PR 2

**Files:** none

**Step 1: Push + open PR**

```bash
gh pr create --base main --head <branch> \
  --title "skill: test-driven-development — invariant proof + class invariant coverage" \
  --body "..."
```

**Step 2: Loop per `pr-monitoring`** — review rounds, CI, merge.

---

## PR 3 — `runtime-launch-validation` (NEW) + `finishing-a-development-branch` additions

**Branch off:** main (after PR 2 merges)

### Task 17: Create new skill directory

**Files:**
- Create: `skills/runtime-launch-validation/`

**Step 1: Create dir + empty SKILL.md placeholder**

```bash
mkdir -p skills/runtime-launch-validation
touch skills/runtime-launch-validation/SKILL.md
```

**Step 2: Commit**

```bash
git add skills/runtime-launch-validation/
git commit -m "skill(runtime-launch-validation): scaffold"
```

---

### Task 18: Write SKILL.md core

**Files:**
- Modify: `skills/runtime-launch-validation/SKILL.md`

**Step 1: Write core content**

```markdown
---
name: runtime-launch-validation
description: Use after unit tests pass, before merge, when a change affects runtime behavior — launch the built artifact under realistic conditions and observe its behavior
---

# Runtime Launch Validation

## Iron Law

**Unit-test green ≠ launch green.** Engines fail at startup. Build pipelines fail at first run. Migrations fail mid-apply. The only proof a runtime artifact works is launching it.

After unit tests pass and before merge, for any change affecting runtime behavior, the implementer launches the built artifact under the closest-to-production conditions feasible locally, observes its behavior, and captures the transcript.

This skill complements `verification-before-completion` (general principle: evidence before assertion). `runtime-launch-validation` is the operationalization for runtime artifacts.

## When this applies

Triggered by changes to any of:

- Build configuration (Dockerfile, build script, CI build steps)
- Deployment configuration (compose, Kubernetes manifests, deployment workflows)
- Version pins on tooling, runtime, libraries
- Application-startup configuration (config files read at boot)
- Database migrations
- Plugin / extension loading paths

Triggered NOT by:

- Pure refactors of internal logic
- Documentation
- Test-only changes
- Dependency upgrades that are caught by existing tests with no runtime configuration impact

## Per-change-class instructions

| Change class | What to launch | What to observe |
|---|---|---|
| Application binary (server, CLI) | Build, run with production-equivalent config, exercise primary entry point (HTTP healthcheck, CLI `--version` plus a representative subcommand) | Stdout/stderr capture; exit code; healthcheck status |
| Container image | Build, `docker run` with production-equivalent env, hit `/healthz` (or equivalent) | Container logs, exit code, healthcheck status |
| Database migration | Apply against ephemeral DB instance; revert (down migration); re-apply | Idempotent? No orphaned schema objects? |
| Library / SDK | Import into a tiny consumer program, exercise the new public surface | Output, behavior matches docs |
| Plugin / extension | Load it into the host application, exercise a representative call | Host doesn't crash on load; representative call returns |

## Failure-signature scrape

While watching the artifact run, scan output for these patterns. Any hit is a fail.

- Panics / uncaught exceptions / crash dumps
- "fetch from remote: lookup ... no such host" — DNS failure (common for missing version pins)
- "module not found" / "import error"
- "version mismatch" / "incompatible API version"
- "schema drift" / "missing column" / "constraint violation"
- "permission denied" on resources the artifact should be able to access
- Stack traces (any language)
- "address already in use" — port collision (often from prior runs not cleaned)

If any pattern hits, the launch validation fails. Capture the exact line + 5 lines of context.

## Transcript format for PR body

Include in the PR description:

```
## Runtime launch transcript

Build:
$ <build command>
<relevant lines, not full dump>

Launch:
$ <launch command>
<startup lines until ready>
<healthcheck observation>

Failure-signature scrape: clean (or: list of hits with context)

Verdict: PASS / FAIL
```

## Fall-back when local launch is infeasible

If the change touches runtime behavior but the implementer's local environment can't realistically launch (no Docker, no target OS, no required external service), they must:

1. State the constraint explicitly in the PR body.
2. Propose how the launch will happen (e.g., "CI image-launch job runs on every PR; this PR enables that path") OR
3. Ask the orchestrator to launch on a capable host before merge.

The constraint is not an excuse to skip; it's a request for help.

## See also

- `skills/verification-before-completion/SKILL.md` — general evidence-before-assertion principle
- `skills/finishing-a-development-branch/SKILL.md` — Step 1b invokes this skill
- `skills/writing-plans/SKILL.md` — per-change-class verification table cross-references this skill
```

**Step 2: Commit**

```bash
git add skills/runtime-launch-validation/SKILL.md
git commit -m "skill(runtime-launch-validation): core skill content"
```

---

### Task 19: Fixture — runtime-fail not caught by unit tests

**Files:**
- Create: `skills/runtime-launch-validation/test-fixtures/missing-pin-skew/scenario.md`

**Step 1: Write scenario**

```markdown
# Missing-pin runtime skew

A repository pins `tooling` at v1.2 in build pipeline yaml. The
runtime depends on `engine`, which is at v1.6 elsewhere in the repo.

`tooling@v1.2` and `engine@v1.6` use incompatible plugin discovery
layouts: v1.6 expects plugins at `data/plugins/<name>/<name>`,
v1.2 expects them at `plugins/<name>` (legacy).

A change bumps `engine` to v1.7. All unit tests pass — they don't
exercise plugin discovery paths because they mock those out.

## Without runtime-launch-validation

PR opens. Reviewer approves. Merge. Deploy. **Production fails at
startup**: engine looks for plugins at the new path, doesn't find
them (build pipeline put them at the old path), falls back to
fetching from a network registry that doesn't resolve, panics.

Total time to fix: hours of triage + emergency hotfix.

## With runtime-launch-validation

PR's "finishing-a-development-branch Step 1b" triggers because the
change touched a version pin. The implementer:

- Builds the runtime artifact locally.
- Launches it (`docker run`).
- Observes startup logs.
- Failure-signature scrape catches "fetch from remote: lookup ...
  no such host".
- Verdict: FAIL.
- Implementer investigates: realizes tooling@v1.2 needs to bump too.
- Bumps both pins, re-launches, scrape clean.
- PR opens with transcript already pasted.

Total time to fix: <10 minutes.
```

**Step 2: Commit**

```bash
git add skills/runtime-launch-validation/test-fixtures/missing-pin-skew/
git commit -m "skill(runtime-launch-validation): fixture — missing-pin runtime skew"
```

---

### Task 20: Add Step 1b — Runtime Launch Verification

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md`

**Step 1: Locate Step 1**

Run: `grep -n "## Step 1\|## Step 2\|verify tests\|determine base" skills/finishing-a-development-branch/SKILL.md`

**Step 2: Insert new Step 1b between Step 1 and Step 2**

```markdown
## Step 1b: Runtime Launch Verification (conditional)

**Trigger:** the diff includes any of:

- Build configuration (Dockerfile, build script, CI build steps)
- Deployment configuration (compose, Kubernetes manifests, deployment workflows)
- Version pins on tooling, runtime, libraries
- Application-startup configuration (config files read at boot)
- Database migrations
- Plugin / extension loading paths

If triggered: invoke `skills/runtime-launch-validation/SKILL.md`. Build and launch the artifact under production-equivalent conditions, run the failure-signature scrape, capture the transcript, paste it into the PR body.

If NOT triggered (pure logic refactor, doc-only, test-only): skip this step.

**The launch transcript is required in the PR body when this step triggers.** Without it, the PR is not ready for merge — even if all unit tests pass.

## Step 1c: Version-Skew Audit (conditional)

**Trigger:** the diff updates any version pin (any "version: vX.Y.Z", "image: foo:vX.Y.Z", or `<package>@vX.Y.Z`).

Action:

1. Grep the repo for related pins (other versions of the same component, sibling tooling, components in the same release group).
2. For each related pin, compare lag.
3. If lag is >2 minor versions, flag in PR body:
   ```
   Version skew detected: pinned ToolingA@v1.2.0 while related EngineA@v1.6.0
   (4 minor versions ahead). Compatibility verified via: <link or note>.
   ```
4. Resolve before merging — bump the lagging pin, OR state explicitly why the skew is intentional and safe.

Action does NOT apply to: dev-only tooling pins (linters, formatters), where skew is generally benign.
```

**Step 3: Commit**

```bash
git add skills/finishing-a-development-branch/SKILL.md
git commit -m "skill(finishing-a-development-branch): Step 1b runtime-launch + Step 1c version-skew"
```

---

### Task 21: Open PR 3 (runtime-launch-validation + finishing additions bundled)

**Files:** none

**Step 1: Push + open PR with the bundle.** Body includes the runtime-launch transcript demonstrating self-eaten dogfood: when adding the runtime-launch-validation skill, the implementer launched the new skill's fixture against the new finishing pipeline and validated the trigger fires.

---

## PR 4 — `writing-plans` + `brainstorming` additions

**Branch off:** main (after PR 3 merges)

### Task 22: Add per-change-class verification table to writing-plans

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

**Step 1: Insert before "Bite-Sized Task Granularity"**

```markdown
## Verification per change class

When writing a plan task, the verification step must match the change class. A green unit-test run is sufficient ONLY for internal-logic refactors. Other classes need stronger evidence.

| Change class | Verification | Expected output |
|---|---|---|
| Internal logic refactor | unit tests | all green |
| Schema migration | apply against ephemeral DB; down + re-apply | idempotent, no orphans |
| API endpoint | exercise endpoint with representative inputs (curl, gRPC, etc.) | correct status + body |
| Build pipeline / Dockerfile | build artifact + launch + healthcheck (see runtime-launch-validation) | transcript captured |
| Version pin update | run version-skew audit + relaunch artifact | transcript + audit clean |
| CLI command | `cmd --help` + representative invocation | help text correct, exit 0 |
| UI component | render in browser/dev server | screenshot or visual confirmation |
| Plugin / extension | load into host + exercise representative call | host doesn't crash, call returns |
| Documentation / comments | spell-check + render preview | no broken anchors |
| Hook / trigger / event handler | fire the event; observe handler runs | logged side effect; assertion |

Plan tasks falling in any class except "internal logic refactor" or "documentation / comments" must include a runtime-validation step in their TDD breakdown — typically by invoking `runtime-launch-validation` from `finishing-a-development-branch` Step 1b.

The plan author writes the expected output literally — not "passes tests" but "logs `engine ready` within 10 seconds and `/healthz` returns 200".
```

**Step 2: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "skill(writing-plans): per-change-class verification table"
```

---

### Task 23: Add `--design-only` flag to writing-plans

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

**Step 1: Insert after "Autonomous Mode" section**

```markdown
## Design-only mode

When the orchestrator wants the pipeline to halt after alignment-check (no execution dispatched), they pass `--design-only`, OR the plan's first line is a header comment `<!-- design-only -->`, OR the brainstorm that called writing-plans propagated the same flag.

**Behavior under `--design-only`:**

1. Save the plan to `docs/plans/<filename>.md` as normal.
2. Commit the plan as normal.
3. Invoke `autodev:alignment-check` as normal.
4. **On alignment PASS: STOP.** Do NOT invoke subagent-driven-development.
5. The plan + design sit in `docs/plans/` for future execution. The orchestrator (or a future invocation) can resume by passing the plan to `subagent-driven-development` directly.

**When to use:**

- Design exploration ahead of available implementation capacity.
- Cross-cutting designs that affect multiple workstreams; lock the design in before any one workstream starts.
- Designs with prerequisites in-flight elsewhere; queue the plan now, execute when prerequisites land.

**Default (no flag):** alignment-check PASS → invoke subagent-driven-development. Same as before.
```

**Step 2: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "skill(writing-plans): --design-only flag"
```

---

### Task 24: Mirror `--design-only` flag in brainstorming

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

**Step 1: Locate the autonomous-handoff section**

Run: `grep -n "Autonomous handoff\|writing-plans\|^## " skills/brainstorming/SKILL.md`

**Step 2: Insert design-only documentation near the autonomous-handoff section**

```markdown
## Design-only mode

When the user wants design exploration without execution, they pass `--design-only` to brainstorming.

**Behavior under `--design-only`:**

1. Run the full brainstorming flow (explore context → questions → approaches → design → write design doc → commit).
2. When invoking writing-plans, propagate the `--design-only` flag.
3. writing-plans honors the flag: alignment-check PASS → STOP.
4. The pipeline ends with a committed design doc + plan in `docs/plans/`. No execution dispatched.

**Default (no flag):** brainstorming → writing-plans → alignment-check → subagent-driven-development → … (autonomous handoff to execution).
```

**Step 3: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "skill(brainstorming): --design-only flag, propagates to writing-plans"
```

---

### Task 25: Fixture — design-only flag plumbing

**Files:**
- Create: `skills/writing-plans/test-fixtures/design-only-flag/scenario.md`

**Step 1: Write scenario**

```markdown
# Design-only mode propagation

The orchestrator runs:
```
brainstorming --design-only --topic "feature X"
```

Expected behavior:
- brainstorming runs full design flow.
- brainstorming hands off to writing-plans WITH --design-only set.
- writing-plans runs full plan flow.
- writing-plans invokes alignment-check.
- alignment-check returns PASS.
- writing-plans STOPS — does NOT invoke subagent-driven-development.

Verification:
- `docs/plans/...-design.md` and `...-plan.md` both committed.
- No subagent-driven-development invocation in the session log.
- Orchestrator can later resume by passing the plan path to
  subagent-driven-development directly when ready.
```

**Step 2: Commit**

```bash
git add skills/writing-plans/test-fixtures/design-only-flag/
git commit -m "skill(writing-plans): fixture — --design-only flag end-to-end"
```

---

### Task 26: Open PR 4

**Files:** none

PR body should include a runtime-launch transcript per the new finishing-a-development-branch Step 1b — even though this PR is doc-only, the implementer dogfoods by verifying the design-only flag in brainstorming + writing-plans flow on a synthetic test.

---

## PR 5 — `subagent-driven-development` DRY refactor

**Branch off:** main (after PR 4 merges)

### Task 27: Extract team-conventions to shared file

**Files:**
- Create: `agents/team-conventions.md`
- Modify: `skills/subagent-driven-development/SKILL.md`

**Step 1: Write `agents/team-conventions.md`**

```markdown
# Team Conventions

Shared rules every team agent (implementer, spec-reviewer, code-reviewer)
follows. Referenced from skill prompts so each dispatch doesn't re-state
them.

## Implementer

- Follow `skills/test-driven-development/SKILL.md` strictly.
  - RED → GREEN → Verify Regression Invariant → REFACTOR.
  - No production code without a failing test.
  - When fixing a class invariant violation, table-driven coverage
    of all sibling methods.
- Follow `skills/verification-before-completion/SKILL.md`.
  - Iron law: evidence before assertions. Fresh runs only.
- Follow `skills/runtime-launch-validation/SKILL.md` when the change
  affects runtime behavior. Capture transcript in PR body.
- Run version-skew audit when changing version pins.
- Self-review checklist before requesting code review:
  - All tests pass (paste output).
  - Regression-invariant proven (revert + restore transcript).
  - Runtime-launch transcript captured if triggers fire.
  - PR scope matches dispatch text. Differences justified.
- Request code review per `skills/requesting-code-review/SKILL.md`
  using the adversarial-framing brief.
- Address review per `skills/receiving-code-review/SKILL.md`.

## Spec reviewer

- Read the dispatch text + the PR diff.
- Apply the scope-vs-dispatch compliance gate from
  `skills/requesting-code-review/SKILL.md`.
- Flag MISSING and SCOPE CREEP findings before quality review begins.

## Code reviewer

- Apply adversarial framing — find at least three things wrong.
- Run the bug-class checklist on every diff.
- Output per-finding inline at file:line.
- Iterate until verdict is SHIP-IT (or REVERT-AND-REWRITE after max
  rounds).
- Reflexive approval is forbidden.

## All agents

- DRY: when re-stating a convention, prefer "per `<skill>`" over
  inlining the rule.
- DM team-lead when blocked, when CI breaks, when ready for merge.
- Sanitization: in public repos, no project / company / version /
  incident references.
```

**Step 2: Update implementer-prompt template in subagent-driven-development**

Locate: `grep -n "implementer-prompt\|implementer prompt" skills/subagent-driven-development/SKILL.md`

Replace inlined boilerplate with:

```markdown
You are implementer-{N} on team {team-name}.

Follow team conventions: see `agents/team-conventions.md` (committed in
this repo) for the discipline rules every implementer applies (TDD with
regression-invariant proof, verification-before-completion,
runtime-launch-validation when triggers fire, version-skew audit,
self-review checklist, code-review request via adversarial brief).

Your specific task:
{task}

Your specific success criteria:
{criteria}

When complete, dispatch code review per
`skills/requesting-code-review/SKILL.md` using the adversarial brief.
DM team-lead with PR link when CI green and reviewer at SHIP-IT.
```

Same shape for spec-reviewer and code-reviewer prompts: brief identity + ref to conventions + specific task.

**Step 3: Commit**

```bash
git add agents/team-conventions.md skills/subagent-driven-development/SKILL.md
git commit -m "skill(subagent-driven-development): DRY team conventions to agents/team-conventions.md"
```

---

### Task 28: Fixture — DRY verification

**Files:**
- Create: `skills/subagent-driven-development/test-fixtures/dry-conventions/before-after.md`

**Step 1: Write before/after**

```markdown
# DRY conventions before/after

## Before (inlined)

Each implementer dispatch ~80 lines, repeating:
- TDD discipline reminder
- Self-review checklist
- Code-review request protocol
- Merge approval rules
- Sanitization rules

Each dispatch must restate these. Drift across dispatches.

## After (referenced)

Each implementer dispatch ~12 lines:
- Identity + team
- "See agents/team-conventions.md for discipline rules"
- Task description
- Specific success criteria
- Closing instructions

Conventions live in one place. Edits propagate without re-emitting.
~85% reduction in dispatch boilerplate; orchestrator can focus
prompts on task-specific content.
```

**Step 2: Commit**

```bash
git add skills/subagent-driven-development/test-fixtures/dry-conventions/
git commit -m "skill(subagent-driven-development): fixture — DRY conventions before/after"
```

---

### Task 29: Open PR 5

**Files:** none

PR body should reference (NOT inline) the team conventions — dogfooding the new pattern.

---

## Pipeline closure

After all 5 PRs merge:

- The implementer (impl-migrations) DMs team-lead with a summary listing the 5 merged PRs and a link to each.
- Team-lead marks the brainstorm task done.
- Pipeline ends.

## Discipline reminders for the implementer

(These are what the team-lead embedded in the dispatch — do NOT re-state in PR bodies; reference team-conventions instead per the goal of this work.)

- Branch protection is active on `main`. Every PR.
- Dogfood: use the regression-invariant proof on every test in this work. Use the adversarial code-review brief on every PR in this work. Yes, recursive — that is the point.
- Sanitization: every commit, every PR body, every line of skill text — generic only. Reviewer will reject any project bleed.
- Loop discipline: max 5 review rounds per PR.
- Sequential PRs: ship 1 → 2 → 3 → 4 → 5 in order so each builds on its predecessor; do not parallelize.
