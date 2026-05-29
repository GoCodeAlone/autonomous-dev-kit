# Demonstration Fidelity — Design

**Date:** 2026-05-29
**Branch:** feat/demonstration-fidelity-2026-05-29T1128
**Author:** autonomous pipeline (dogfood)
**Status:** Draft

## Problem

An agent implements a real artifact, then produces a "demo" intended to show
that artifact working — but the demo does **not** execute the artifact. Observed
failure (production, daily Claude + Codex use): agent wrote the feature in one
language, then built a demo in a *different* language that **hard-coded** the
outputs for presentation. The demo proved nothing about the real code, yet was
presented as proof it works. "Fake code."

This is a verification-theater failure specific to demonstration artifacts. It
slips past every existing gate:

| Existing gate | Why it misses this |
|---|---|
| `scope-lock` ("there is no demo mode") | Kills *partial-scope* work shipped as a demo. Says nothing about a *full-scope* demo that fakes its output. |
| `runtime-launch-validation` | Triggered by change-class (build/deploy/migration…), not by "I'm writing a demo." Its "Library/SDK → tiny consumer program" row never forbids that consumer being a reimplementation or printing literals. |
| `verification-before-completion` | "Evidence before assertion," but its claim matrix has no `demo/example works` row, so a fabricated demo never gets challenged. |

**Gap:** nothing in the kit owns the invariant *a demonstration must execute the
real artifact.*

## Invariant (the teaching)

A demonstration / example / showcase / sample / quickstart / "proof it works"
artifact MUST exercise the real artifact through its real public interface, and
the output it shows MUST be produced by that execution.

Forbidden **regardless of language**:

- **Reimplementation / transliteration** — re-coding the logic for the demo
  instead of calling it.
- **Hard-coded output** — hand-authoring the "expected" output and presenting it
  as produced output.
- **Stub/mock substitution** — wiring the demo to a fake in place of the
  artifact-under-demonstration.
- **Detached prototype** — building a parallel throwaway instead of invoking the
  shipped entry point.

**Critical nuance (target fidelity, not language sameness):** cross-language is
*not* the crime. A real client written in another language that crosses a real
interface into the running artifact — e.g., a Python client making real HTTP
calls to a running Go service — is a *valid* demo, **provided that crossing is
actually exercised** (this is exactly the `runtime-launch-validation` boundary
rule: no mock/stub on either end). The crime is the demo not executing the real
artifact. The rule keys on *did the real code run to produce this output*, never
on *is the demo in the same language*.

## Approaches considered

- **A. New skill `demonstration-fidelity` + pipeline wiring + advisory hook
  (CHOSEN).** Discoverable at demo-writing time (its own trigger), harness-agnostic
  teaching, plus a write-time backstop on Claude/Codex/Cursor. Defense in depth.
- **B. Extend `runtime-launch-validation` + `verification-before-completion`
  only.** Lower sprawl, but an agent mid-demo does not think "runtime launch
  validation"; weak discoverability at the moment of failure.
- **C. Skill only, no hook.** Simplest; loses the write-time reminder.

User selected **A**, advisory (never-blocking) hook, single PR.

## Components

1. **`skills/demonstration-fidelity/SKILL.md`** — universal, host-neutral. The
   load-bearing layer (every harness reads skill markdown). Contains: overview +
   invariant, when-to-use triggers, a 3-question fidelity test, the valid
   cross-interface pattern, one fake-vs-faithful example pair, a rationalization
   table seeded from the RED baseline, red-flags, common mistakes, cross-refs to
   `runtime-launch-validation` / `verification-before-completion` / `scope-lock`.
   No Claude-only tokens (passes `tests/skill-content-grep.sh`).

2. **Pipeline wiring (cross-refs):**
   - `runtime-launch-validation`: new change-class row "Demonstration / example /
     showcase artifact" + a "See also" entry. The demo must drive the real
     artifact; reuses the boundary "no mock/stub on either end" rule.
   - `verification-before-completion`: claim-matrix row
     `demo/example works | the real artifact executed via the demo produced the
     shown output | hand-written/hard-coded output, a reimplementation`.
   - `finishing-a-development-branch`: Step 1b note — if the change shipped any
     demo/example artifact, `demonstration-fidelity` applies before merge.
   - `using-autodev`: add to the skill listing / red-flags so it is discoverable.
   - `README.md` skills library + `tests/cross-llm-coverage.md` row (host-neutral).

3. **`hooks/pretool-demo-fidelity-guard`** — advisory, **never blocks**.
   PreToolUse on `Write|Edit`. When the target path looks like a demo artifact
   (basename or dir matches `demo`, `example`, `sample`, `showcase`, `quickstart`;
   or under `examples/`, `demos/`), emit
   `hookSpecificOutput.additionalContext` with a one-line fidelity reminder
   pointing at the skill. No `decision:block`. Honors `SUPERPOWERS_HOOKS_DISABLE=1`.
   Session-scoped dedup (one reminder per path) to avoid nagging on repeated
   edits. Emits a *static* reminder string only — never echoes file contents (no
   leakage). Registered in `hooks/hooks.json` under the existing `Write|Edit`
   PreToolUse group.

4. **Tests:**
   - `tests/hook-contracts.sh`: add cases — fires `additionalContext` on a demo
     path; silent on a non-demo path; never blocks; respects the disable env;
     emits valid JSON; dedups within a session.
   - Keep `tests/skill-content-grep.sh`, `tests/skill-cross-refs.sh` green.

## Global Design Guidance

`Guidance: none found as docs/design-guidance.md; constraints cited from canon
equivalents (README §Cross-LLM, docs/plans/2026-04-25-cross-llm-portability-design.md,
skills/writing-skills).`

| guidance (source) | design response |
|---|---|
| Harness-agnostic / host-neutral first (README §Cross-LLM; cross-llm-portability design) | Skill is host-neutral and load-bearing for *all* harnesses; hook reaches Claude+Codex+Cursor; no Claude-only tokens; coverage table row added. |
| Skills = judgment calls; mechanical constraints = automate (writing-skills "Don't create for mechanical constraints") | Fidelity is a *judgment* call (cross-language can be valid) → the skill is primary; the hook is advisory-only, not a regex gate that would false-positive on valid client demos. |
| TDD Iron Law for skills (writing-skills) | RED baseline captured before the skill is written; rationalization table seeded from it. |
| Token efficiency (writing-skills) | Skill core kept lean; condensed phrasing. |
| One excellent example, not multi-language dilution (writing-skills) | Exactly one fake-vs-faithful example pair. |
| Scope-lock discipline | Single-PR Scope Manifest; explicitly out-of-scope: a general "anti-fabrication" skill. |

## Security Review

- **Auth/secrets/PII:** none introduced. Hook reads only the tool-input file
  path from stdin JSON and writes a small dedup marker under
  `.claude/autodev-state/` (same mechanism existing hooks use). No network, no
  secrets, no PII.
- **Least privilege / abuse:** hook never executes the file under write, never
  echoes file contents (emits a fixed reminder string only — no content leak),
  never blocks. Honors `SUPERPOWERS_HOOKS_DISABLE=1`. Fails open (any parse error
  → exit 0, silent) so it can never wedge a session.
- **Trust boundary:** advisory `additionalContext` is model-facing text only; it
  cannot alter files or run commands.

## Infrastructure Impact

None. Plugin-only change; no cloud resources, deploys, migrations, or cost.
`hooks/hooks.json` gains one PreToolUse entry — a plugin-loading-path change,
which is itself a `runtime-launch-validation` trigger (validated by running
`tests/hook-contracts.sh` + a manual stdin invocation of the hook).

## Multi-Component Validation

- **Hook ↔ harness boundary:** `tests/hook-contracts.sh` feeds real stdin JSON
  to the real hook script and asserts the emitted JSON contract (real boundary,
  not a mock).
- **hooks.json ↔ dispatcher:** registration parsed; `run-hook.cmd` dispatch path
  exercised by the contract suite.
- **Skill ↔ cross-refs:** `tests/skill-cross-refs.sh` resolves the new references
  across `skills/` + README.
- **Skill ↔ grep guard:** `tests/skill-content-grep.sh` confirms host-neutrality.

## Assumptions

1. Agents load a skill by its description when about to write a demo (CSO).
   *Fragile* — mitigated by cross-refs from RLV/finishing/verification + the
   write-time hook reminder.
2. The `hookSpecificOutput.additionalContext` schema is consumed by Claude **and**
   Codex (verified — daily use on both).
3. Demo-file naming heuristics cover most real demos. Inline/README demos are
   missed by the hook — acceptable; the skill covers those, the hook is
   best-effort advisory.
4. Advisory `additionalContext` on PreToolUse is non-blocking and won't disrupt
   flow.

## Rollback

Change classes touched: plugin-loading path (new hook + `hooks.json` entry).
Rollback = revert the PR (removes skill, wiring, hook, hooks.json entry, version
bump 6.1.5→6.2.0). No state migration; the dedup marker file is additive and
ignorable. Safe, single-step.

## Self-challenge — top doubts surfaced

1. **Skill sprawl** (24th skill). Justified by a *distinct trigger* (writing a
   demo) and a rich rationalization surface that would bloat RLV if inlined.
   Adversarial review will pressure-test this.
2. **Hook noise.** Mitigated: advisory-only + session-scoped dedup; cannot block.
3. **Cross-language false guilt.** If the invariant read "same language," it would
   wrongly condemn valid client demos. Baked the fidelity-not-sameness nuance into
   the invariant up front.
