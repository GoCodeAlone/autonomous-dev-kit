# Retro: ADK Path Canonicalization + Write-Location Transparency + Artifact Hygiene

**PR:** #75 — ADK path canonicalization (v6.5.0)
**Merged:** 2026-06-03
**Branch:** feat/adk-path-canonicalization
**Design:** docs/plans/2026-06-03-adk-path-canonicalization-design.md
**Plan:** docs/plans/2026-06-03-adk-path-canonicalization.md
**Committed adversarial reports (dogfood #69):** -design-review.md (2 cycles) · -plan-review.md (3 cycles)
**Related ADRs:** none (no new non-trivial trade-off beyond the design's choices)
**Origin:** the v6.4.0 retro's #70 residual (worktree-fragmented activation log).

## Adversarial-review findings, scored

Scored from the committed review reports.

| Phase | Finding | Severity | Outcome |
|---|---|---|---|
| design | C-1 resolver returns `/` on non-git/git-absent (empty `cd ""/..`) | Critical | Prescient — empirically reproduced; null-guard fix |
| design | C-2 self-referential gate trap (the gate's own docs contain the forbidden pattern) | Critical | Prescient — drove the placeholder-aware regex + `path-hygiene-allow` sentinel |
| design | I-1 fallback didn't cover lib-present-function-absent (exit 127 under set -e) | Important | Resolved upfront — `declare -f` guard |
| design | I-2 CI `paths:` filter would let docs-only leaks bypass the gate | Important | Resolved upfront — dedicated always-on `path-hygiene.yml` |
| design | I-3 retrofit list wrong by 3 entries | Important | Resolved upfront — authoritative grep |
| plan | C-1 `scope-lock-complete` retrofit breaks `hook-contracts.sh` bare invocations | Critical | Prescient — would have failed CI; test-cd fix |
| plan | I-1 `scope-lock-claim` is comment-only (don't retrofit); `session-start` non-standard anchor | Important | Prescient — 12→11 hooks; explicit anchor |
| plan | I-2 `pre-compact-snapshot` reminder_marker special-case | Important | Resolved upfront |
| plan (cycle 2) | C-2 macOS `/var`→`/private` symlink: resolver logical vs physical mismatch | Critical | Prescient — `pwd -P`, empirically verified all 4 cases |
| code | **Critical: worktree prune compared `$ADK_ROOT` not `$PWD` → stale lock never pruned** | Critical | **Prescient — the single highest-value catch; the implementer introduced it; Group D revert-restore-proven fix** |
| code | Important: gate didn't scan `skills/` while the rule claimed enforcement | Important | Resolved — extended scan + 3 pre-existing leaks fixed |

## Gate misses

No gate misses this PR. Every code-review finding was a refinement/bug in the *implementation* of an already-sound design, caught before merge; CI was green on the first push (CodeQL, hooks, path-hygiene, skill-content-check, version, Analyze ×3). The code-review Critical (worktree prune compare-base) was an *implementation* bug, not a design-class miss — the design's m-3 even flagged the scope-lock-complete behavioral change as the area to watch, and the code reviewer walked exactly that path.

## Missed skill activations

Full canonical chain fired (design ×2 + plan ×3 adversarial cycles + alignment + scope-lock + execute + adversarial code review + this retro). No misses.

## What worked

- **The code-review caught a subtle worktree-only prune bug the implementer introduced.** `scope-lock-complete`/`-abandon` compared stored lock entries against `$ADK_ROOT` (main) while `plan_abs` used `$PWD` (worktree) → silent no-op prune in exactly the worktree scenario the feature exists for. The `hook-contracts.sh` tests missed it because they run in a non-git `$tmp` where both bases coincide. Fix + a **Group D worktree regression test** (RED with the bug, GREEN with the fix — revert-restore proven). This is adversarial review doing precisely its job on the seam the design called out.
- **Empirical resolver proof over reasoning.** The macOS `/var`→`/private` symlink mismatch (plan cycle-2 C-2) and the non-git `/`-return (design C-1) were both *reproduced in a shell* before fixing — not argued. The resolver is proven against a real temp git + linked worktree, not a mock.
- **The self-referential gate trap (design C-2) forced a genuinely better gate.** A feature about machine paths must document the pattern; the placeholder-aware regex (ignore `<name>`) lets the artifacts describe the rule without tripping it.
- **#69 dogfooded again** — this retro scored from committed review reports, no reconstruction.

## What didn't

- **#70's fix is shipped but not yet *active* for this very session.** The new canonical-root hooks ship in v6.5.0, but the running plugin during this session was the older cwd-scoped build, so this pipeline's own activation log still fragmented under the worktree (the new resolver takes effect for the *next* session after the user re-syncs the marketplace). Same bootstrap asymmetry #69 had in v6.4.0 — the fix proves out on the *next* run, not its own. Honest caveat, not a defect.
- **`docs/design-guidance.md` still absent** — flagged across the last several retros. Durable lessons (anti-bloat; phantom-dependency/circular-logic class; evidence-must-live-where-consumer-reads; empirical-proof-over-reasoning) keep landing in retros + memory rather than one inherited file.

## Plugin-level follow-ups

1. **Bootstrap `docs/design-guidance.md` (recurring — now 3+ retros).** Seed it with the durable principles that keep recurring so the next design inherits them instead of re-deriving. This is the same follow-up the v6.4.0 retro raised; it has now recurred enough to be worth a dedicated small PR. **Trend, not a one-off.**
2. **(from this PR) Consider extending the canonical resolver to the few non-hook ADK writers if any emerge** — all current state I/O now routes through `autodev_repo_root`; if a future skill writes state directly (not via a hook), it should source the same lib.

## Project guidance updates

| Guidance file | Change | Reason |
|---|---|---|
| `docs/design-guidance.md` | no change (absent) | Durable lesson ("reproduce path/symlink/worktree assumptions in a shell before fixing; a feature that enforces a rule on artifacts must let those artifacts document the rule") captured here + in memory. Bootstrapping the file is follow-up #1 — now a cross-retro trend. |
