# ADK Path Canonicalization + Write-Location Transparency — Design

**Date:** 2026-06-03
**Target release:** v6.5.0
**Origin:** #70 residual (autodev v6.4.0 retro) — the activation log fragmented under worktree pipelines because every hook computes its state dir from the payload `.cwd`.

## Problem

Three related directory-confusion failure modes:

1. **Inconsistent ADK state location.** Every hook independently computes
   `STATE_DIR="${cwd_dir}/.claude/autodev-state"` from the hook payload `.cwd` (fallback `$PWD`).
   There is **no shared resolver**. Under a git worktree the `.cwd` is the worktree, so state
   (activation log, session-locks, pr-reminder marker, lock snapshots) is written *into the
   worktree*. When the worktree is removed (normal cleanup after a merged PR), that state is
   discarded — exactly what made the v6.4.0 retro read a fragmented activation log. Concurrent
   worktrees also each get their own divergent copy.
2. **Opaque subagent writes.** A dispatched subagent works in some directory (a worktree, a
   sibling checkout) and writes files, but its final report doesn't say *where*. When the
   orchestrator later finds an error in a path — or the subagent wrote to the wrong worktree —
   there's no ledger to relocate or reconcile the state from.
3. **Machine paths leaking into committed artifacts.** Designs, plans, retros, review reports,
   and ADRs are committed to public history. An absolute operator path
   (`/Users/jon/Documents/GitHub/...`) baked into one of them leaks the operator's machine layout
   forever. This already happened: `docs/testing.md:152` contains a `/Users/jon/...` example path.

## Goals / Non-goals

**G1 (consistent writes):** all ADK state writes/reads resolve to **one canonical location per
repository**, stable across worktrees and surviving worktree removal.
**G2 (transparency):** dispatched subagents report a **write-location ledger** so the orchestrator
can verify, and relocate/reconcile state if a path is wrong.
**G3 (path hygiene):** committed artifacts (design/plan/retro/review/ADR) carry **repo-relative
paths only** — never absolute machine paths — enforced by CI. Local state logs are exempt.

**Non-goals (YAGNI):**
- No change to *what* state is recorded, only *where* it lands.
- No new state file, no new hook, no schema change to existing state rows.
- No rewrite of `.cwd` semantics — the hook payload is unchanged; we resolve a canonical root *from* it.
- Not gitignoring `.autodev/state/phase-progress.jsonl` (it is intentionally tracked); we keep it
  clean (it already uses repo-relative paths) and merely anchor its location.
- No absolute-path ban on *all* files — only on the committed-artifact set. Code examples,
  `/healthz`, `/tmp/...` in scripts, etc. are untouched (the check targets operator-home paths only).

## Design

### C1 — Canonical state-path resolver (shared lib)

New `hooks/lib-autodev-paths.sh`, sourced by every hook/helper that touches `.claude/autodev-state`
or `.autodev/state`. It exports one function:

```sh
# autodev_repo_root <cwd> -> echoes the canonical repo root for ADK state.
# Resolution order:
#   1. $AUTODEV_STATE_ROOT if set and non-empty (explicit override; used by tests).
#   2. The git COMMON dir's parent, resolved from <cwd>: `git rev-parse --git-common-dir`
#      returns the shared main `.git` from any linked worktree, so its parent is the ONE
#      root all worktrees of a repo agree on (survives worktree removal).
#   3. Fallback: <cwd> itself (non-git dir, or git unavailable) — i.e. today's behavior.
autodev_repo_root() {
  cwd="${1:-$PWD}"
  if [ -n "${AUTODEV_STATE_ROOT:-}" ]; then printf '%s\n' "$AUTODEV_STATE_ROOT"; return 0; fi
  root="$(cd "$cwd" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd)"
  if [ -n "$root" ]; then printf '%s\n' "$root"; else printf '%s\n' "$cwd"; fi
}
```

Each consumer replaces `STATE_DIR="${cwd_dir}/.claude/autodev-state"` with:
```sh
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib-autodev-paths.sh" 2>/dev/null || autodev_repo_root() { printf '%s\n' "${1:-$PWD}"; }
ADK_ROOT="$(autodev_repo_root "$cwd_dir")"
STATE_DIR="${ADK_ROOT}/.claude/autodev-state"
```

**Robustness invariant (the #66 lesson — hooks must never break):** if the lib can't be sourced,
the inline fallback defines `autodev_repo_root` as the identity-on-cwd function, so the hook
degrades to **exactly today's cwd-scoped behavior** rather than erroring. A missing/again-broken
lib is a no-op regression, never a hook failure.

**Consumers to retrofit** (every file referencing the state dirs):
`session-start`, `pre-compact-snapshot`, `subagent-scope-guard`, `prompt-strict-interpretation`,
`record-activity`, `completion-claim-guard`, `pretool-pr-review-reminder`, `pre-tool-scope-guard`,
`posttool-pr-created`, and the helpers `scope-lock-apply`, `scope-lock-claim`,
`scope-lock-complete`, `scope-lock-abandon`, `scope-lock-publish`. (Exact list confirmed by
`grep -rl 'autodev-state\|\.autodev/state' hooks/` at plan time.)

`post-merge-retrospective` (the #70 consumer) reads `.claude/autodev-state/in-progress.jsonl` from
the same canonical root, closing the original residual.

### C2 — Subagent write-location ledger

Convention added to `agents/team-conventions.md` and the three subagent prompt templates
(`implementer-prompt.md`, `spec-reviewer-prompt.md`, `code-quality-reviewer-prompt.md`) +
`subagent-driven-development` SKILL: **every** subagent's final message ends with a `Writes:`
ledger — one line per file it created/modified, as a **repo-relative path**, plus an explicit flag
if any write landed outside the expected repo/worktree (`OUT-OF-TREE: <absolute path>`). The
orchestrator reads the ledger to (a) confirm work landed where expected and (b) relocate/reconcile
state if a path is wrong before committing. Repo-relative in the ledger keeps absolute paths out of
anything that might be quoted into an artifact; the one allowed absolute path is the explicit
`OUT-OF-TREE:` escape, which exists precisely to surface a mistake to the orchestrator (transcript
only, never committed).

### C3 — Artifact path-hygiene gate

New `tests/no-machine-paths.sh`: greps the committed-artifact set (`docs/`, `decisions/`) for
operator-home absolute paths — `/Users/<name>/`, `/home/<name>/`, and literal `$HOME`/`~/` expanded
forms — and fails with the offending `file:line`. Narrow by construction: it targets home-rooted
machine paths, not all absolute paths (so `/healthz`, `/tmp/x`, `/etc/...` in legitimate examples
pass). Wired into `.github/workflows/skill-content-check.yml` (which already gates docs/skills) +
its `paths:` filter. The existing leak at `docs/testing.md:152` is fixed to a placeholder
(`/path/to/autodev` or `<repo-root>/...`) in the same PR so the gate is green on landing.

Plus a one-line rule in the artifact-writing skills (`brainstorming`, `writing-plans`,
`post-merge-retrospective`, `adversarial-design-review`, `recording-decisions`): committed
artifacts use repo-relative paths; never absolute machine paths. Local state logs
(`.claude/autodev-state/*`, gitignored) may hold absolute paths; the tracked
`.autodev/state/phase-progress.jsonl` stays repo-relative (already is).

## Global Design Guidance

No `docs/design-guidance.md` (recurring gap, noted again in the v6.4.0 retro — not bootstrapped
here to avoid scope creep). Inherited principles honored: skills/hooks stay tight; hooks must never
break (#66); evidence/state must live where its consumer reads it
(v6.4.0 `feedback_evidence_artifact_must_live_where_consumer_reads`); no absolute machine paths in
committed history.

## Security Review

Net **reduction** in exposure: C3 stops operator machine-layout (usernames, home structure) leaking
into public git history. C1 reads only local git metadata + an env var; no network, no secrets, no
new file contents. C2's ledger is transcript-only and repo-relative. The `AUTODEV_STATE_ROOT`
override is operator-controlled (an env var) — no untrusted input path. No auth/authz surface.

## Infrastructure Impact

No runtime/cloud/deploy change. CI gains one test step in an existing workflow. v6.5.0 bumps the 3
plugin manifests → `release-tag.yml` auto-tags (standard kit path). The canonical-root change moves
where *local* state files are written; it does not move any committed file except fixing the one
`docs/testing.md` leak.

## Multi-Component Validation

The cross-component boundary is **worktree-cwd → resolver → canonical state dir → retro/consumer**.
Proof obligations for the plan:
- A test that, from a simulated linked worktree, `autodev_repo_root` returns the **main** root
  (not the worktree) — and from a non-git dir returns cwd (fallback). Use a throwaway `git init` +
  `git worktree add` in a temp dir, assert the resolver output. This is the load-bearing claim.
- A test that `record-activity` (run with a worktree-style `.cwd`) appends to the **canonical**
  `in-progress.jsonl`, and that the retro reads it from the same place.
- The `no-machine-paths.sh` gate run against the current tree (must pass after the testing.md fix;
  must FAIL on a deliberately seeded `/Users/...` line — revert-restore proof).
- Lib-missing degradation: temporarily hide the lib, confirm a retrofitted hook still emits valid
  output (degrades to cwd-scoping, no error) — the #66 robustness invariant.

## Assumptions

- **A1:** `git rev-parse --git-common-dir` from a linked worktree's cwd returns the shared main
  `.git`, whose parent is the canonical root. *Load-bearing for C1; verified by the worktree test.*
- **A2:** Hooks are always invoked with a cwd inside (or under) the target repo, so the resolver
  can find the git common dir. If not (cwd outside any repo), fallback-to-cwd preserves today's
  behavior — acceptable, no regression.
- **A3:** Sourcing a sibling `lib-autodev-paths.sh` via `dirname "$0"` works under `run-hook.cmd`
  (which invokes `bash ${SCRIPT_DIR}/<name>`, so `$0` is the hook's own path). *Verified by the
  install-layout + a content test.*
- **A4:** Anchoring `.autodev/state/phase-progress.jsonl` to the canonical (main) root, while it is
  a tracked file, will not create problematic dirty-tree noise beyond today's — worktree runs
  already could touch it; consolidating to one location is strictly more predictable.
- **A5:** Concurrent worktree pipelines interleaving into one append-only JSONL log is acceptable
  (timestamped rows; a unified cross-worktree view is desirable, not a hazard).

## Rollback

Change classes: hook/startup-config (state path) + plugin version pin. Rollback = revert the merge
commit + re-tag v6.4.0. No migration: the canonical dir is computed at runtime; reverting restores
cwd-scoping. Any state already written to a canonical dir is harmless if later read cwd-scoped
(worst case: same fragmentation as before). Per-task rollback notes in the plan for the
version-bump + the hook-retrofit tasks.

## Self-challenge (top doubts surfaced)

1. **~14 retrofitted hooks is a big mechanical diff — bloat risk?** Each change is ~3 lines
   (source + resolve + one substitution) and *removes* divergence rather than adding behavior. The
   net is a single new lib + uniform call sites; a half-retrofit would re-create the exact
   inconsistency we're fixing (user chose full retrofit for this reason).
2. **Could the resolver subtly relocate state mid-pipeline and orphan an in-flight lock?** During
   the transition PR, a session that wrote a cwd-scoped lock before upgrade could look for it at the
   canonical path after. Mitigation: the scope-lock helpers resolve the same way for write+read, so
   within a version they're consistent; cross-version, the worst case is a stale local marker (the
   nag hooks already tolerate absent markers). Called out for the adversarial reviewer.
3. **`git-common-dir` edge cases (submodules, bare repos, `$GIT_DIR` set).** Fallback-to-cwd covers
   the unknowns; the resolver never hard-fails. The reviewer should probe submodule + detached
   scenarios.
