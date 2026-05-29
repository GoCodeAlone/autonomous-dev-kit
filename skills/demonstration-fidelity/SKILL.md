---
name: demonstration-fidelity
description: Use when creating a demo, example, quickstart, showcase, sample, or any artifact meant to prove an implementation works — before writing it. Triggers when about to "show it working", build a proof-of-concept, or generate sample output, especially under time pressure or when the real code is awkward to run. Catches fake demos that reimplement the logic, hard-code the output, or rewrite it in another language instead of executing the real artifact.
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Demonstration Fidelity

## Iron Law

**A demonstration must execute the real artifact, and the output it shows must be produced by that execution.**

A demo, example, quickstart, showcase, screenshot, or "here's it working" proof is a *claim that the code works*. If it doesn't run the real code, the claim is fabricated — however convincing the output looks. This operationalizes `autodev:verification-before-completion` for demo artifacts and is a sibling of `autodev:runtime-launch-validation`.

## Forbidden — regardless of language

- **Reimplementation** — re-coding the artifact's logic in the demo instead of calling it.
- **Hard-coded output** — hand-authoring "expected" output and presenting it as produced output.
- **Stubbing the artifact-under-demonstration** — wiring the demo to a fake *in place of the thing you are demonstrating*.
- **Detached prototype** — a parallel throwaway instead of the shipped entry point.

These prove nothing. They are fake code.

## Allowed — with disclosure

Substituting a **dependency** at a **real interface seam** (data store, external service, clock) so the demo runs locally — **provided** the artifact's own code path runs unchanged (you stubbed a *dependency*, not the artifact) **and** you state it plainly ("data source is an in-memory fixture; the handler is the real one"). This is the `autodev:runtime-launch-validation` posture (ephemeral DB row; Fall-back section). Disclosed seam-substitution is honest; faking the artifact is not.

## Fidelity, not language sameness

Cross-language is **not** the crime. A real client in another language crossing a **real interface** into the running artifact — e.g. a Python client making real HTTP calls to a running Go service — is valid, as long as that crossing is exercised (no stub on either end of *that* boundary). The question is always **"did the real code run to produce this output?"** — never "same language?".

## The 3-question fidelity test

1. **Execution:** does the demo call/import/invoke the real artifact — not a copy of it?
2. **Provenance:** was every value shown produced by that run and captured — not typed by you?
3. **Seams:** if you substituted anything, was it a *dependency* (not the artifact), and did you disclose it?

Any "no" → the demo is fake. Fix it before presenting.

## Example — fake vs. faithful

Artifact: Go `text.Dedupe(s string) string`.

**Fake** (different language, hard-coded — proves nothing):

```python
# demo.py — DO NOT DO THIS
print("BEFORE:\n a\n a\n b")
print("AFTER:\n a\n b")   # hand-typed; Dedupe never ran
```

**Faithful** (runs the real function, prints its real return value):

```go
// demo/main.go
package main

import ("fmt"; "example.com/app/text")

func main() {
    in := "a\n a\n b"
    fmt.Printf("AFTER:\n%s\n", text.Dedupe(in)) // real output, captured by running it
}
```

If the module tooling is awkward, sidestep the *tooling* (throwaway module, ephemeral dependency) — never sidestep *execution*.

## Rationalizations — STOP

| Excuse | Reality |
|---|---|
| "Build/DB tooling is finicky — I'll just print the expected output." | Sidestep the tooling, not the execution. A throwaway module / in-memory dependency runs the real code; printed literals run nothing. |
| "A hard-coded demo looks identical on screen." | Looking identical is the trap. The value of a demo is that the real code produced it. |
| "Quicker to rewrite it in Python/bash for the demo." | Fine only if that script actually calls/crosses into the real artifact. A script printing literals is fake in any language. |
| "The real thing needs a DB/service I can't stand up." | Substitute the *dependency* at a real seam and disclose it; run the real artifact. Never fake the artifact. |
| "It's just for the meeting / illustrative." | A demo presented as proof is a claim — `autodev:verification-before-completion` applies. |
| "I simplified the logic for clarity." | A simplified reimplementation is a different program. Demo the real one. |

## Red flags

- The demo imports nothing from the module under demonstration.
- You typed or pasted the "output" instead of capturing a run.
- The demo is in another language and never crosses a real interface into the artifact.
- "Simulated" / "for demonstration purposes" / "pretend" appears in the demo.
- You have not actually run it and watched the output.

## See also

- `autodev:verification-before-completion` — evidence before any "works/done" claim (its claim matrix has a `demo/example works` row).
- `autodev:runtime-launch-validation` — launch the built artifact; its "Demonstration / example / showcase" change-class row points here.
- `autodev:scope-lock` — "there is no demo mode" for *partial scope* (distinct from fidelity).
