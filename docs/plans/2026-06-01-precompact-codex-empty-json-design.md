# Fix: PreCompact invalid-JSON on Codex (#66) — Design

**Status:** Approved (autonomous bug-fix; user-directed; v6.3.1 release after merge)
**Date:** 2026-06-01
**Issue:** #66 (regression/uncovered-path of #41)
**Type:** Bug fix (systematic-debugging root-caused)
**Adversarial review:** design cycle 1 = FAIL (0C/2I/3m) → resolved this revision (I1 test-inventory + I2 jq-present scoping + m1 schema-vs-syntax + m2 TTY + m3 test-(b) note).

## Root cause

`hooks/pre-compact-snapshot` exits with **empty stdout** on five paths — the common one
being **no locked plan in `docs/plans/`** (`[ -z "$state_section" ] && exit 0`, line 132),
plus disabled / TTY-stdin / no-jq / empty-input. Claude Code tolerates empty PreCompact
output (no-op); **Codex rejects it** ("hook returned invalid PreCompact hook JSON output").
The v6.3.0 wrapper (#41) routes *non-JSON* to stderr and recovers JSON behind warnings, but
its empty-output branch emits **nothing** (`: # nothing to emit`) — so the empty path is
still empty on the wrapper route too. Most sessions at compaction have no autodev locked
plan (incl. the reporter's workflow-compute session) → the empty path is the *common* case.

Evidence constraint: cannot run Codex here. Conclusion derived from the hook's exit paths +
the exact error wording (empty ≠ valid JSON) + the common-case match. This is the
highest-confidence, verifiable-on-source-layout root cause.

## Invariant (the fix)

**Every hook emits a valid JSON object on stdout on every exit path; empty becomes `{}`.**
`{}` is the minimal valid JSON object and a universal **no-op** across all Claude Code hook
events (SessionStart=no context, PreToolUse/PostToolUse=no decision→proceed,
UserPromptSubmit=no context/no block, Stop/SubagentStop=no block, PreCompact=no-op) — so it
changes no Claude Code behavior — while satisfying Codex's "valid JSON" requirement.

Fix at **two layers** (defense in depth, covers both invocation paths — #66 asks "not only
the Claude wrapper path", "the installed hook the way Codex invokes it"):

1. **`hooks/pre-compact-snapshot`** — replace each empty `exit 0` (lines 18/20/21/24/132)
   with `printf '{}\n'; exit 0` (via a `noop_json` helper; `printf` needs no jq, so the
   no-jq path is covered). The content path (line ~163, after `emit_additional_context`)
   is unchanged. Covers **direct invocation** (Codex bypassing the wrapper). (Line 20 is the
   TTY guard — an interactive-only path no host triggers with TTY stdin; adding `noop_json`
   there is harmless, m2.)
2. **`hooks/run-hook.cmd`** — the empty-hook-output branch emits `{}` instead of nothing.
   Covers all hooks on the wrapper path **when jq is present** (the jq-absent branch is a
   verbatim `exec bash` passthrough — that path is covered for pre-compact-snapshot only,
   by its own `printf`-based fix; I2). Safe no-op on Claude Code for every event type.

## Tests requiring update (I1 — these existing tests assert empty output)

Three existing `hook-contracts.sh` tests run pre-compact-snapshot on a *no-snapshot*
scenario and assert `[ -n "$output" ]` is empty; after the fix `output="{}"`, so they must
change to "no *populated* snapshot" rather than "empty string":
- `test_scope_lock_complete*` (~line 654): completed (not locked) plan → no snapshot.
- `pre_compact_ignores_prose_mention_of_locked_status` (~line 1182): draft plan → no snapshot.
- `pre_compact_ignores_single_workspace_lock_when_session_has_no_lock` (~line 1279).

New assertion (robust to both old-empty and new-`{}`): **fail only if the output contains a
populated snapshot** —
```bash
if printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  fail "... expected no lock snapshot, got a populated one: $output"
fi
```
(`jq -e .hookSpecificOutput.additionalContext` is false for both `{}` and empty, true only
for a real snapshot.) The existing with-locked-plan test (asserts the populated
`hookSpecificOutput`) is unchanged.

`tests/hook-stdout-discipline.sh` test (b) (noise-only fixture) is **unaffected** (noise
routes via the wrapper's `else` branch, not the empty branch, so stdout stays empty there);
the new wrapper test is a **distinct case (e): a fixture that emits nothing at all → wrapper
emits `{}`**.

## Tests (the regression #66 explicitly requests)

- `tests/hook-contracts.sh`: `test_pre_compact_snapshot_emits_json_when_no_locked_plans` —
  run the hook **directly** (`run_hook`, NOT the wrapper — Codex-style) against a tmp cwd
  with no `docs/plans/`, assert stdout parses as JSON (`jq -e .`) and is non-empty. Plus the
  disabled-env path (`SUPERPOWERS_HOOKS_DISABLE=1`) also emits `{}`. The existing
  with-locked-plan test continues to assert the `hookSpecificOutput` shape.
- `tests/hook-stdout-discipline.sh`: a fixture that emits empty → the wrapper emits `{}`
  (valid JSON), not empty.
- CI: `hooks-check.yml` (added in v6.3.0) gates both on Linux.

## Global Design Guidance

`Guidance: README §Cross-LLM. The contract is host-neutral: stdout must be valid JSON for
the strictest host (Codex). `{}` is the lowest-common-denominator no-op.`

## Security Review

`{}` carries no directive — a PreToolUse/Stop hook emitting `{}` = no block = proceed,
identical to today's empty/exit-0 behavior. No block decision is weakened (the v6.3.0
discipline still recovers an explicit `{"decision":"block"}` behind a warning). No secrets,
no network.

## Infrastructure Impact

None. Hook + wrapper + tests + version bump (v6.3.0 → v6.3.1, patch). Release via
`release-tag.yml`.

## Multi-Component Validation

The `test_pre_compact_snapshot_emits_json_when_no_locked_plans` runs the **real** hook the
way Codex invokes it (direct, no wrapper) — the actual boundary #66 names. The wrapper test
runs the **real** `run-hook.cmd` against an empty-output fixture.

## Assumptions

| id | assumption | challenge | fallback |
|---|---|---|---|
| A1 | Codex rejects empty PreCompact stdout but accepts a valid JSON object | Could reject `{}` specifically if it enforces a strict typed schema | `{}` is the minimal valid object; if Codex needs specific fields, that requires Codex-side repro (documented limitation — I cannot run Codex). Emitting valid JSON is strictly better than empty. **`{}` solves only the "not valid JSON" rejection class — NOT a "wrong schema shape" rejection.** If Codex enforces a typed PreCompact schema that rejects unknown objects, a *different* error will surface; the issue-close note must capture this distinction so the next investigator isn't misled (m1). |
| A2 | `{}` is a no-op for every Claude Code hook event | Some event might warn on `{}` | All events treat `{}` as "no directives"; the existing with-content tests confirm no regression to the populated path. |
| A3 | Codex invokes the installed hook (direct and/or via wrapper) | Unknown exact path | Fixed at BOTH layers so either path emits valid JSON. |

## Rollback

Revert the PR; the hook returns to empty-exit, the wrapper to empty-branch. No migration.
Do not tag v6.3.1 if reverted pre-merge.

## Honesty note (verification-before-completion)

I cannot reproduce on Codex from here. This fix is verified on the **source layout** by the
new direct-invocation regression (the hook now emits valid JSON on every path, including the
empty/no-locked-plans case that previously emitted nothing). That removes the
highest-confidence root cause (empty ≠ valid JSON). Final Codex confirmation belongs to a
Codex session; the issue close note will state this.
