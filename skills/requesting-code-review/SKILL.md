---
name: requesting-code-review
description: Use when completing tasks, implementing major features, or before merging to verify work meets requirements
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Requesting Code Review

## Reviewer brief — adversarial framing

The reviewer subagent's instructions must use **adversarial framing**, not validation framing.

**Required prompt phrasing in every dispatch:**

> Find at least three things wrong with this code, even if they seem minor — or, if fewer than three are found, explicitly document every bug-class check you ran and what you found (or didn't). Bias toward finding issues. You are NOT validating that the code matches the dispatch — you are looking for bugs the original author missed.

**Clarification:** "NOT validating that the code matches the dispatch" applies to the **bug-class scan** phase — the reviewer's mindset when hunting for bugs should be adversarial, not confirmatory. This is distinct from the **scope-vs-dispatch compliance gate** (see next section), which is a separate structural check that runs first and explicitly compares the diff against the dispatch. Both mandates are valid; they apply to different phases:

1. Compliance gate (runs first) — structural check: did the PR deliver what was asked?
2. Bug-class scan (runs second) — adversarial hunt: what bugs did the author miss?

Why: the same base model produces dramatically different output under "find what's wrong" vs. "review the work." Validation framing biases toward approval; adversarial framing biases toward rigor. The shift is mechanical and reproducible.

**Forbidden phrasing**: "review the work", "verify the implementation matches the plan", "confirm correctness", any prompt that implies the reviewer's job is to validate. These produce sign-offs that miss real bugs.

**Reflexive approval is forbidden.** If the reviewer finds nothing wrong, they must state which checks were run (the bug-class checklist below) and what specifically they verified. A bare "looks good" is rejected.

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

## Bug-class checklist (must scan)

The reviewer must explicitly scan for each of these bug classes on every diff. The checklist is the floor, not the ceiling — additional findings are welcome.

| Class | Definition |
|---|---|
| **Symmetry violations** | Sibling methods in the same struct/class/handler family follow a convention; one method drifts from it. The new method omits a key the others set, or wraps an error the others don't, or returns a shape the others don't. |
| **Error swallowing** | `_, err := f(); _ = err` patterns (error silently discarded), `if err != nil { log(err) }` followed by silent recovery, errors caught and not propagated when they should be. |
| **Comment-vs-code drift** | Comments describing behavior the code no longer has; comments naming files, functions, or variables that have been renamed. |
| **Test-name-vs-body mismatch** | A test named `..._HandlesNotFound` that actually simulates a list-API error rather than the not-found path. The name and the body disagree. |
| **Missing edge cases** | Tests covering only the happy path. No empty/nil/malformed inputs. No network-error or timeout paths. No boundary values. |
| **Concurrency bugs** | Goroutines/threads without sync, race conditions, channel-close patterns, missing locks, double-unlock. |
| **Type-coercion silent failures** | Encode/decode where `int → float64` is silently lossy, where `[]any → []string` is rejected without a clear error, where `nil` and zero-value diverge. |
| **Dead/unreachable code** | Branches no test exercises and no caller can reach. Either delete or cover. |
| **Scope-vs-dispatch drift** | The implementation ships materially MORE or LESS than the dispatch asked for. Both directions are findings. (See the dedicated gate above.) |
| **Shortcut / band-aid fix** | The fix suppresses a symptom without addressing the root cause. Examples: nil-guard on a value that should never be nil (ask why it is nil); retry loop masking a race condition; special-casing one known-bad input instead of fixing the upstream producer; deleting a failing test instead of fixing the underlying code. Ask: "if the root cause were restored and only the symptom suppressor kept, would the test still pass?" If yes, the test proves nothing about correctness. |
| **One-sided boundary wiring** | A change touches an interface boundary (producer→consumer, caller→callee, plugin→host, sender→handler — see `agents/boundary-classes.md` for the canonical list) but only one side is implemented or tested. The other side is a stub, TODO, or unchecked assumption. Both sides of every boundary must be wired, and at least one test must exercise the full crossing end-to-end (not mock both sides independently). |
| **Declared integration not consumed** | A diff adds or updates an integration declaration (manifest, config, lockfile, dependency, deployment descriptor, module registration, provider install, plugin enablement), but no real host/consumer code path discovers and exercises it. Flag install-only changes unless the PR explicitly marks the item `config-only` or `deferred` with rationale/tracking. This applies to any extension model, not only plugin UI. |
| **Test hermeticity / non-determinism** | A test makes a real network call (e.g. `connect("localhost:50051")`), depends on a real DB without a `t.Skip`-when-missing guard, writes to a shared filesystem path that races with parallel tests, depends on the system clock without injection, or relies on external services that may flake. CI should be reproducible from a clean checkout; tests that touch the world without mediation are landmines. Promote to **Important** even if the test currently passes — non-determinism only fails on the day you most need green CI. |
| **Cross-platform / portability** | A path uses `/` literals or string-`contains("\\")` checks where `std::path::Path::components` (Rust) or `filepath.Join`/`filepath.Separator` (Go) would be portable. Code spawns shell commands with bash-only syntax. Code reads Unix-only env vars (`HOME`, `XDG_*`, `SHELL`) without falling back on Windows. Code splits `PATH` on `:` rather than the platform separator (`;` on Windows). Asset paths assume one filesystem layout. CI matrices commonly hit Linux first, so these regressions slip past local development. |
| **Vacuous assertion** | A test whose body asserts something tautologically true so it cannot fail meaningfully. Two flavors: (1) syntactic tautology — `assert err == nil \|\| err != nil`, `assert result == result`, `assert p >= Floor \|\| p < Floor`. (2) trivially satisfied for every test input — assertion is non-tautological in general but the test inputs never exercise the failing branch (e.g., `assert composed_probability == Floor` on inputs that never trigger clamping; `assert spawns_observed == spawns_recorded` where both sides come from the same in-process list). The function under test may be correct, but the test proves nothing. Worse than no test — gives false confidence. Either rewrite the assertion to exercise the named path, or rename the test to match what it does. |

For each finding, the reviewer cites the bug class explicitly. This makes patterns visible across reviews and lets the team identify recurring weaknesses.

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

## Iterative loop protocol

One review pass is insufficient. After implementer addresses findings, the reviewer **re-reads the new diff from scratch** and runs the full bug-class checklist again. New issues commonly surface — fixes introduce new bugs, fixes only address the symptom, or the implementer interprets the finding too narrowly.

Loop:

1. Implementer dispatches review.
2. Reviewer runs: **(a)** scope-vs-dispatch compliance gate, then **(b)** full bug-class checklist → produces findings.
3. Implementer addresses each finding, pushes new commits.
4. **Reviewer re-reads the new diff (not just the diff-of-diffs)** and repeats **(a)** + **(b)** in full.
5. Repeat until reviewer's verdict is SHIP-IT with no Critical or Important findings.

Maximum loops: 5 per PR. If the reviewer still finds Critical/Important issues after round 5, the verdict becomes REVERT-AND-REWRITE; the implementer takes a different approach.

**Minor findings do not auto-trigger a new review round.** The loop re-runs only when there are unresolved Critical or Important findings. When a round produces only Minor/Nit findings, the verdict is SHIP-IT (or FIX-FORWARD) and the human or orchestrator inspects the Minor findings before merge — they do not block it, but they should be acknowledged.

## Verdict vocabulary

Reviewer ends every review with exactly one of these verdicts:

- **SHIP-IT** — no Critical, no Important, optionally a few Minor/Nit. Merge.
- **FIX-FORWARD** — substantive findings, but they're additive. Merge this PR; open a follow-up PR for the findings. Use when the current PR's value is independent and the findings are new work.
- **REQUEST-CHANGES** — Critical or Important findings that block merge of this PR. Implementer addresses, re-review.
- **REVERT-AND-REWRITE** — fundamental approach issue; the right answer is a different design. Used after iterative-loop max rounds, or for clear architectural mistakes.

Reviewer must justify the verdict in one sentence:

> Verdict: REQUEST-CHANGES — three Critical findings (sibling-method asymmetry, missing nil-check, unreachable test branch); fixing requires non-trivial code change.

Reflexive SHIP-IT without justification is forbidden.

Dispatch autodev:code-reviewer subagent to catch issues before they cascade.

**Core principle:** Review early, review often.

## When to Request Review

**Mandatory:**
- After each task in subagent-driven development
- After completing major feature
- Before merge to main

**Optional but valuable:**
- When stuck (fresh perspective)
- Before refactoring (baseline check)
- After fixing complex bug

## Review-request template

When dispatching a code-review subagent, use this brief verbatim:

```
You are a code reviewer with adversarial framing. Find at least three things
wrong with this code, even if they seem minor — or, if fewer than three are
found, explicitly document every bug-class check you ran and what you found
(or didn't). Bias toward finding issues.

Note on "NOT validating": the adversarial framing below applies to the
bug-class scan (phase 2). Phase 1 is a structural compliance gate that
explicitly compares the diff against the dispatch — that IS intentional.
Both phases are required; they serve different purposes.

## Diff under review
<diff>

## Original dispatch (what the implementer was asked to do)
<dispatch text>

## Required output

Run these checks IN ORDER:

1. Scope-vs-dispatch compliance gate (structural check). List dispatch asks
   vs. PR delivers. Flag MISSING and SCOPE CREEP findings.
2. Bug-class scan (adversarial). You are NOT validating that the code matches
   the dispatch — you are looking for bugs the original author missed. For
   each class in the checklist (skills/requesting-code-review/SKILL.md),
   state which you ran and what you found.
3. End with one verdict: SHIP-IT | FIX-FORWARD | REQUEST-CHANGES |
   REVERT-AND-REWRITE, plus a one-sentence justification.

For each finding, use this exact format:

### Finding N — <one-line summary>
- **Severity**: Critical | Important | Minor | Nit
- **Bug class**: <from the checklist or "other (describe)">
- **Location**: `path/to/file.ext:line`
- **What's wrong**: <one sentence>
- **Why it matters**: <one sentence>
- **Suggested fix**: <one sentence or short snippet>

Reflexive approval is forbidden. If you find nothing wrong, state which
checks were run.
```

## How to Request

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Dispatch code-reviewer subagent:**

Use the review-request template above. Replace `<diff>` with the output of
`git diff $BASE_SHA..$HEAD_SHA` and `<dispatch text>` with the original
task description.

**3. Act on feedback per the iterative loop protocol:**
- Fix Critical and Important issues; push new commits.
- Reviewer re-reads from scratch and re-runs checklist.
- Repeat until SHIP-IT verdict.

## Example

```
[Just completed Task 2: Add verification function]

You: Let me request code review before proceeding.

BASE_SHA=$(git rev-parse HEAD~1)  # or: git log --oneline | grep "Task 1" | head -1 | awk '{print $1}'
HEAD_SHA=$(git rev-parse HEAD)

[Dispatch autodev:code-reviewer subagent — brief filled in verbatim from the review-request template:]

You are a code reviewer with adversarial framing. Find at least three things
wrong with this code, even if they seem minor — or, if fewer than three are
found, explicitly document every bug-class check you ran and what you found
(or didn't). Bias toward finding issues. You are NOT validating that the
code matches the dispatch — you are looking for bugs the original author
missed.

## Diff under review
<output of git diff $BASE_SHA..$HEAD_SHA>

## Original dispatch (what the implementer was asked to do)
Add verifyIndex() and repairIndex() with 4 issue types (Task 2)

## Required output
[... per review-request template ...]

[Subagent returns]:

### Finding 1 — verifyIndex does not emit progress during long scans
- **Severity**: Important
- **Bug class**: Missing edge cases
- **Location**: `store/index.go:47`
- **What's wrong**: The loop over all index entries has no progress output; callers have no signal during long-running verification.
- **Why it matters**: On large indexes the caller blocks silently; operators cannot distinguish a hung process from normal operation.
- **Suggested fix**: Emit a log line every N entries (e.g., `log.Printf("verified %d/%d entries", i, total)`).

### Finding 2 — Magic number 100 in repairIndex batch size
- **Severity**: Minor
- **Bug class**: other (magic literal)
- **Location**: `store/index.go:112`
- **What's wrong**: Batch size is hard-coded as `100` with no named constant or comment.
- **Why it matters**: Future readers cannot distinguish intentional tuning from accidental value.
- **Suggested fix**: Extract `const repairBatchSize = 100` and reference it.

Verdict: REQUEST-CHANGES — one Important finding (missing progress indicators); fix before merge.

You: [Fix progress indicators, extract constant, push new commit]

[Dispatch autodev:code-reviewer subagent — round 2, full diff re-read, same verbatim brief]
HEAD_SHA=$(git rev-parse HEAD)  # re-run: HEAD now points to the new fix commit(s)
(diff range $BASE_SHA..$HEAD_SHA — same base, new tip that includes the fix commits)

[Subagent returns]:

Scope-vs-dispatch gate: PASS. Bug-class scan: no Critical or Important findings.
Finding 2 (Minor) from round 1 addressed — constant extracted.

Verdict: SHIP-IT — no Critical or Important findings remain.

[Continue to Task 3]
```

## Integration with Workflows

**Subagent-Driven Development:**
- Review after EACH task
- Catch issues before they compound
- Fix before moving to next task

**Executing Plans:**
- Review after each batch (3 tasks)
- Get feedback, apply, continue

**Ad-Hoc Development:**
- Review before merge
- Review when stuck

## Red Flags

**Never:**
- Skip review because "it's simple"
- Ignore Critical issues
- Proceed with unfixed Important issues
- Argue with valid technical feedback

**If reviewer wrong:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification
