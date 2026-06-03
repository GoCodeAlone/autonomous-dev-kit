# ADK Path Canonicalization — Plan-Phase Adversarial Review

**Phase:** plan
**Artifact:** `docs/plans/2026-06-03-adk-path-canonicalization.md`
**Status:** FAIL → revised (all findings resolved); re-run pending

## Findings (cycle 1)

| id | sev | class | issue | resolution |
|---|---|---|---|---|
| C-1 | Critical | Verification-class / regression | Retrofitting `scope-lock-complete`/`-abandon` to `autodev_repo_root "$PWD"` breaks `hook-contracts.sh`: its **bare** invocations at lines 641 + 707 run from `$REPO_ROOT` (a real git checkout) with a `$tmp` plan, so post-retrofit state ops land in the real checkout → every pruning assertion fails. Plan claimed `hook-contracts.sh` stays green but gave no test-fix instruction. | Task 3 **Step 4** added: rewrite lines 641 + 707 to `( cd "$tmp" && "$REPO_ROOT/hooks/scope-lock-complete" docs/plans/example.md … )`, matching the already-correct cd-wrapped siblings at 746/790/833. `$tmp` is non-git → resolver falls back to `$tmp`, restoring expected behavior. Verified: 641/707 are the only two bare invocations; all abandon tests + 746/790/833 already cd. |
| I-1 | Important | Repo-precedent / wrong instruction | (a) `scope-lock-claim` has NO `cwd_dir` and no runtime state I/O — its grep hit is a comment (line 11). Retrofitting it is wrong. (b) `session-start` uses a two-step init (`cwd_dir="${PWD}"` @38, payload override @45); the generic "after `[ -z "$cwd_dir" ]`" anchor doesn't exist and inserting before L45 derives the root from `$PWD` not the payload `.cwd`. | (a) `scope-lock-claim` **dropped** from the retrofit → **11 hooks**; Task 1 Group B list, Task 3 file list, Step 0 grep note, design retrofit list, and Out-of-scope all updated. (b) Task 3 gives an explicit per-hook anchor table; `session-start` = "after line 45 (`[ -n "$cwd_from_hook" ] && cwd_dir="$cwd_from_hook"`)". |
| I-2 | Important | Missing failure mode | `pre-compact-snapshot` reads+writes `reminder_marker="${cwd_dir}/.claude/autodev-state/pr-reminder-seen"` at L43–55 **before** its common-case `noop_json` early-exit; the special-cases note omitted it, risking a split state (marker cwd-scoped, lock snapshot canonical) that breaks pr-reminder dedup across worktrees. | Task 3 special-case for `pre-compact-snapshot` added: insert (after L33) precedes L43 so `ADK_ROOT` is in scope; the `reminder_marker` substitution must be included. |
| m-1 | Minor | Existence/validity | Group C degradation test was vacuous — `record-activity` exits 0 regardless, so rc≠127 proves nothing. | Group C strengthened to a **behavioral** proof: run lib-hidden record-activity with a non-git cwd, assert it wrote `degrade-probe` to `$cwd/.claude/autodev-state/in-progress.jsonl` (fallback fired) AND didn't crash. |
| m-2 | Minor | Accuracy | Plan said "all artifacts use placeholders" but the design-review doc passed only via a coincidental `path-hygiene-allow` substring. | Design-review doc rephrased to remove the literal operator-home example → genuinely gate-clean (verified, no sentinel reliance). |
| m-3 | Minor | CI wiring ambiguity | Task 9 "add to the workflow paths" was ambiguous (path-trigger vs run-step). | Task 9 split into (a) add to both `push.paths`+`pull_request.paths` AND (b) a `run:` step. |
| m-4 | Minor | Portability | `git init -q main` needs git ≥2.28. | Task 1 fixture uses `mkdir main && (cd main && git init -q …)` — portable. |

## Bug-class scan transcript
| Class | Result | Note |
|---|---|---|
| Assumptions / Verification-class / Multi-component | Finding (C-1) | $PWD-resolution vs test invoking from $REPO_ROOT — fixed via test cd. |
| Repo-precedent | Finding (I-1) | scope-lock-claim comment-only; session-start non-standard init. |
| Missing failure modes | Finding (I-2) | pre-compact reminder_marker pre-early-exit. |
| Existence/runtime-validity | Finding (m-1) | vacuous degradation test → behavioral proof. |
| YAGNI / Security / Infra / Rollback / Simpler-alt / User-intent / Over-decomp / Hidden-serial / Missing-rollback-wiring | Clean | No new scope; dedicated workflow sound; rollback notes present; 10 tasks appropriate grain; single PR so no mid-PR red ships. |

## Options taken
1. Test-cd fix for the two bare invocations (vs a `--repo-root` flag) — **taken** (minimal, matches existing sibling pattern).
2. Behavioral degradation assertion — **taken** (m-1).

**Verdict reasoning:** One Critical (a concrete `hook-contracts.sh` regression the plan didn't instruct to fix) + two Importants (wrong retrofit target `scope-lock-claim`; non-standard `session-start` anchor + missing `pre-compact-snapshot` special case) + four Minors — all verified against the real hook code, all with narrow fixes now in the plan text. The resolver design and the worktree fixture proof are sound. Re-run to confirm convergence.

## Cycle 2 (re-run) — all cycle-1 resolved; revision introduced 1 Critical, now fixed

| id | sev | class | issue | resolution |
|---|---|---|---|---|
| C-2 | Critical | Portability / test correctness | macOS `/var`→`/private` symlink asymmetry: the resolver returned the **logical** path (`/var/...`) for a main checkout (relative `.git` + `pwd`) but the **physical** path (`/private/var/...`) for a linked worktree (git's absolute common-dir), so Group-A assertion (b) failed the mandatory **local** green gate (passed in CI/Linux — worst TDD failure mode). The reviewer's `--show-toplevel` fix would have broken case (a). | Resolver git-branch uses **`pwd -P`** (physical) so main-checkout and worktree invocations return the IDENTICAL physical root; Task-1 `main_root` uses `pwd -P` too. **Empirically verified** on macOS: (a) main, (b) worktree both → `/private/var/.../main`; (c) non-git → raw `$cwd`; (d) override — all 4 OK. Also strictly more robust in production (symlink-stable). Design resolver updated to match. |

**Cycle-2 verdict:** 7/7 cycle-1 findings verified resolved in plan text against the real hooks; the 1 new Critical (resolver symlink normalization) is fixed via `pwd -P` and proven on the author's macOS. Re-run cycle 3 to confirm convergence.

## Cycle 3 (convergence) — PASS

Zero Critical, zero Important, zero Minor. The `pwd -P` fix traced correct on all 4 cases: (a) main + (b) worktree both → identical physical root; (c) non-git fallback raw on both sides; (d) override short-circuits. No production physical/logical fragmentation (an invocation is exclusively in-git→physical or non-git→raw, never mixed for one repo path; all callers converge via `pwd -P`). Group C fallback never calls `pwd -P`. All 7 cycle-1 findings remain resolved. **Converged. Ready for execution.**
