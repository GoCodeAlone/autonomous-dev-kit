# ADK Path Canonicalization — Adversarial Review

**Phase:** design
**Artifact:** `docs/plans/2026-06-03-adk-path-canonicalization-design.md`
**Status:** FAIL → revised (all findings resolved in design text); re-run pending

## Findings (cycle 1)

| id | sev | class | issue | resolution |
|---|---|---|---|---|
| C-1 | Critical | Correctness | Resolver `cd "$(git rev-parse --git-common-dir)/.."` returns `/` (not `$cwd`) when git absent / non-git dir (empty substitution → `cd "/.."`). Reproduced: from `/tmp` → `/`. Violates the "degrade to today's behavior" invariant. | Resolver rewritten: capture `_gcd` first, guard `[ -n "$_gcd" ]` before the `cd`, else fall back to `$cwd`. |
| C-2 | Critical | Self-referential trap | The gate scans `docs/` for `/Users/<name>/`; the design doc + plan + retro for THIS feature must *document* that pattern, so a blanket grep fails on its own artifacts (design line had `/Users/jon/...`). | Gate regex made **placeholder-aware**: `(/Users/\|/home/)[A-Za-z0-9][A-Za-z0-9._-]*` matches a real username segment but ignores `<placeholder>` and ellipsis; author convention = illustrate with `/Users/<name>/`; plus a `path-hygiene-allow` line sentinel. All this feature's artifacts sanitized to placeholders (verified gate-clean). |
| I-1 | Important | Robustness | Inline fallback `source \|\| define-fn` only fires on source *failure*; a lib that sources OK but lacks the function → exit 127 under `set -euo pipefail` kills the hook. | Replaced with post-source `declare -f autodev_repo_root >/dev/null 2>&1 \|\| autodev_repo_root(){...}` — covers missing-lib AND missing-function. |
| I-2 | Important | CI wiring gap | `skill-content-check.yml` `paths:` filter is `skills/**`/`agents/**` — a docs-only/decisions-only leak PR would never trigger the gate (false guarantee). | Gate moved to a **dedicated `path-hygiene.yml`** with NO `paths:` filter → always runs on push + PR. |
| I-3 | Important | Multi-component / accuracy | Retrofit list wrong by 3: `pretool-demo-fidelity-guard` MISSING (has state ref @ line 92); `posttool-pr-created` + `scope-lock-apply` listed but have NO state ref. | Replaced with the authoritative 12 from `grep -rlE 'autodev-state\|\.autodev/state' hooks/`; excluded-list documented; plan re-runs the grep as a guard. |
| m-1 | Minor | Edge case | Bare repo: `--git-common-dir` returns `.` → resolver returns the bare dir's *parent* (not a fallback). | Documented in A2 as nil-impact (hooks never run in a bare repo), never hard-fails. |
| m-2 | Minor | Repo precedent | Source line used `$0`; repo convention is `${BASH_SOURCE[0]:-$0}`. | Adopted `${BASH_SOURCE[0]:-$0}`. |
| m-3 | Minor | Behavioral disclosure | `scope-lock-complete`/`-abandon` currently derive `repo_root` from the plan path; switching to git-canonical changes worktree behavior (intentional). | Called out explicitly in C1 as an intentional behavioral change + noted they pass `$PWD`. |
| m-4 | Minor | YAGNI / honor-system | C2 ledger has no validator → degrades over time. | Acknowledged as a deliberate soft convention; orchestrator falls back to diff inspection. |

## Bug-class scan transcript (cycle 1)
| Class | Result | Note |
|---|---|---|
| Assumptions | Finding (C-1, m-1) | non-git → `/` bug; bare-repo edge |
| Repo-precedent | Finding (m-2) | `$0` vs `${BASH_SOURCE[0]:-$0}` |
| Artifact-class precedent | Clean | adopts existing `<stem>-design-review.md` convention (v6.4.0) |
| YAGNI | Finding (m-4) | C2 honor-system acknowledged |
| Missing failure modes | Finding (C-1, I-1) | resolver `/` return; function-absent exit 127 |
| Security | Clean | net reduction (stops machine-path leaks); env override operator-only |
| Infrastructure | Finding (I-2) | CI paths-filter gap → dedicated workflow |
| Multi-component | Finding (I-3) | retrofit list wrong by 3 |
| Rollback | Clean | revert-merge + re-tag; no migration |
| Simpler alternative | Clean | `--show-toplevel` rejected (gives worktree root); `--git-common-dir` correct |
| User-intent drift | Clean | C1/C2/C3 map directly to the 3 stated pains |
| Existence/runtime-validity | Finding (C-2) | self-referential gate failure on own docs |

## Options taken
1. Single-pass git-common-dir with null guard — **taken** (C-1).
2. Dedicated `path-hygiene.yml` with no `paths:` filter — **taken** (I-2).
3. Placeholder-aware regex + `path-hygiene-allow` sentinel — **taken** (C-2).

**Verdict reasoning:** Two Criticals (resolver `/`-return + self-referential gate trap) + three Importants (incomplete fallback guard, CI paths-filter false guarantee, retrofit list wrong by 3) all had concrete low-effort fixes, now in the design text. The git primitive (`--git-common-dir`) is correct; the main repo + linked-worktree path is verified. Re-run to confirm convergence.

## Cycle 2 (convergence) — PASS

All cycle-1 findings (C-1, C-2, I-1, I-2, I-3, m-1..m-4) verified genuinely reflected in the revised design text; resolver traced correct for all 4 cwd cases with no `set -u` hazard; gate regex empirically placeholder-aware; live grep confirms exactly 12 hooks; `declare -f` safe (all 12 hooks are `#!/usr/bin/env bash`). **Converged.**

Two new Minors → plan-time implementation notes (not design blockers):
- **scope-lock-claim dead-code:** it references `session-locks.jsonl` in a read path; retrofit should anchor the read it actually performs and not add an unused `STATE_DIR`. Plan: apply the resolver only where the file path is genuinely used.
- **`local` in the lib:** `cwd`/`_gcd`/`_root` are function-global (no `local`). All consumers are bash so `local` is available; the lib will either use `local` or carry a comment that the names are intentionally global + assigned-before-read (so a future reorder can't break `set -u`). Plan decides; either is safe.

**Final design verdict: PASS @ cycle 2.** Proceed to writing-plans.
