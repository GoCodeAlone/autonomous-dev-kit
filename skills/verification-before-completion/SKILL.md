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
| lint clean (Go-repo PR) | `golangci-lint run` exit 0 | tests green alone |
| demo/example works | the real artifact executed via the demo produced the shown output (see `autodev:demonstration-fidelity`) | hand-written/hard-coded output, a reimplementation, a different-language fake |
| declared integration integrated | integration matrix covers every declared item as `config-only`, `runtime-integrated`, or `deferred`; runtime-integrated rows are exercised through the real host/consumer with representative lifecycle evidence; stateful/admin/identity flows prove state after reload/restart where feasible; authz negative path checked where applicable | dependency installed, lockfile/config updated, provider unit tests, metadata only, provider package exercised without the host/consumer |
| modular UI/plugin contribution integrated | provider emits metadata + host lists/authorizes it + shell nav links it + each new route renders non-empty contribution-specific content under a real session + unauthorized access is rejected | provider unit tests, route registration, contribution API only, screenshots of unrelated shell chrome |
| PR body ready | full PR body inspected for live secrets and uses placeholders for tokens/API keys/cookies/passwords | raw terminal transcript pasted without redaction, inline `GITHUB_TOKEN=<real-value>`, bearer/cookie values |

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

Modular UI/plugin contribution:
`launch host → login/issue real session → list contributions → open each new shell route → assert contribution-specific content and unauthorized 401/403`.

Declared integration:
`read manifests/config/deps → build integration matrix → mark each item config-only/runtime-integrated/deferred → launch host/consumer → exercise representative lifecycle for runtime-integrated items → prove reload/persistence and authz negatives where relevant → cite issues for deferred rows`.

PR body:
`inspect final Markdown/tempfile → grep for token patterns → replace values with <redacted> or secret names → only then create/update PR`.

## Bottom Line

Run the proof. Read it. Then claim exactly what it proves.
