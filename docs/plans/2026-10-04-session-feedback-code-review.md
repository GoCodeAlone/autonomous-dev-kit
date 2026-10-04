# Independent Code Review

Range: main `ac761fe` through candidate `f8e2c63`. Structural gate PASS; no scope creep. Newer main improvements preserved. Release/install acceptance remains open.

## Findings

- C1 Minor, Error swallowing, `tests/hook-contracts.sh`: whitespace helper test discarded exit status. Scratch mutant completed then exited17 and falsely passed. Resolution b5abeea: capture `rc`, require zero plus resulting status/lock assertions.
- C2 Minor, Missing edge cases, same file: terminal no-mutation test omitted `in-progress.jsonl`. Scratch mutant overwrote compact state before rejection and falsely passed. Resolution b5abeea: seed/compare compact state and all state paths; retain plan/lock/session/progress equality.

| Bug class | Scan result |
|---|---|
| Symmetry violations | Selectors/rewrite match established sibling convention. |
| Error swallowing | C1 addressed. |
| Comment-vs-code drift | Advisory acceptance claims scoped correctly. |
| Test-name-vs-body mismatch | No material mismatch. |
| Missing edge cases | C2 addressed; terminal/attributed/tab cases covered. |
| Concurrency bugs | No new shared-state algorithm. |
| Type-coercion silent failures | No new conversion; `pa` advisory. |
| Dead/unreachable code | New advice/matcher paths exercised. |
| Scope-vs-dispatch drift | Structural PASS. |
| Shortcut/band-aid fix | Baseline fails; candidate corrects selectors. |
| One-sided boundary wiring | Actual scripts/files; host dispatch explicitly deferred. |
| Declared integration not consumed | Installation/smoke distinct from deferred host dispatch. |
| Test hermeticity/non-determinism | Owned tmp fixtures, no network. |
| Cross-platform/portability | macOS Bash3.2 proof; Linux delegated to actual CI. |
| Vacuous assertion | Baseline detects regressions; C1/C2 narrowed blind spots. |

Reviewer verification: candidate hook/evidence suites PASS; baseline hooks/skill restored against candidate tests produced17 hook failures and4 evidence-contract failures. Version/syntax/plan/lock/diff checks PASS. Verdict SHIP-IT: no Critical/Important source defect; two Minor coverage fixes applied and lead verification passed.

## Pressure Exercises

Qualitative exercises using edited condensed skill; no causal baseline or native-host behavior claim.

- A (tests green, checkpoint done, source uncommitted, required release pending): software checkpoint verified; parent acceptance open. Review/commit, merge checks, authorized release and verification remain; do not complete whole plan.
- B (checkpoint done, no release in authorized parent scope, time pressure): verify remaining aggregate requirements, then scope-lock completion with evidence if satisfied. No invented publication or extra human approval gate.

User installation safety remains held: native upgrade prunes prior version cache; isolated native rollback works, but old-path preservation requires verified recovery. Whole plan not complete.
