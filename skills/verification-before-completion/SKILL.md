---
name: verification-before-completion
description: Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Verification Before Completion

## Law

`NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE`

No fresh command this turn → no pass/fixed/done/complete claim. Evidence before assertion.

## Gate

Before any success/completion wording:

1. ID proof: which command/check proves it?
2. Run full command fresh.
3. Read full output + exit code + failure count.
4. Compare output to claim.
5. State actual status with evidence; only claim success if output proves it.

Skip step = unverified claim.

## Claim Matrix

| claim | needs | not enough |
|---|---|---|
| tests pass | test output: exit 0 / 0 fail | old run, "should" |
| lint clean | linter output: 0 errors | partial scan |
| build works | build exit 0 | tests/lint only |
| bug fixed | original symptom/regression passes | code changed |
| regression test works | red → green proof | green only |
| agent completed | inspect diff + verify | agent report |
| requirements met | checklist vs plan/design | tests alone |

## Red Flags

Stop before saying: "should", "probably", "seems", "done", "fixed", "works", "all set", "perfect", "complete", "passes" unless fresh proof exists.

Also stop before commit/PR/next task if verification has not run after final edits.

## Patterns

Tests:
`run tests → read 34/34 pass → "Tests pass: <cmd> exited 0."`

Regression:
`write test → pass → revert fix → must fail → restore fix → pass`

Build:
`run build → exit 0`; lint is not build.

Requirements:
`re-read plan/design → checklist each item → report gaps or evidence`.

Delegation:
`agent says done → inspect VCS diff → run verification → report observed state`.

## Bottom Line

Run the proof. Read it. Then claim exactly what it proves.
