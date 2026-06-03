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
   (`/Users/<name>/Documents/GitHub/...`) baked into one of them leaks the operator's machine
   layout forever. This already happened: `docs/testing.md` contains an operator-home example path.

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
  # C-1 fix: capture --git-common-dir FIRST and guard non-empty before cd, so an absent
  # git / non-git dir yields an empty $_gcd → fallback to $cwd (NOT `/` from `cd ""/..`).
  _gcd="$(cd "$cwd" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null || true)"
  _root=""
  [ -n "$_gcd" ] && _root="$(cd "$cwd" 2>/dev/null && cd "$_gcd/.." 2>/dev/null && pwd || true)"
  if [ -n "$_root" ]; then printf '%s\n' "$_root"; else printf '%s\n' "$cwd"; fi
}
```

Each consumer sources the lib and then **guards on the function actually existing** (I-1 fix —
covers both "lib missing" AND "lib present but function absent", which under `set -euo pipefail`
would otherwise exit 127 and kill the hook):
```sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/lib-autodev-paths.sh" 2>/dev/null || true
declare -f autodev_repo_root >/dev/null 2>&1 || autodev_repo_root() { printf '%s\n' "${1:-$PWD}"; }
ADK_ROOT="$(autodev_repo_root "$cwd_dir")"
STATE_DIR="${ADK_ROOT}/.claude/autodev-state"
```

**Robustness invariant (the #66 lesson — hooks must never break):** the `declare -f` guard
defines an identity-on-cwd fallback whenever `autodev_repo_root` is not in scope after the source
attempt, so a missing OR broken-interface lib degrades to **exactly today's cwd-scoped behavior**
rather than erroring. Verified by the lib-missing + empty-lib tests (Multi-Component Validation).
Uses `${BASH_SOURCE[0]:-$0}` to match the repo's existing `SCRIPT_DIR` convention (m-2).

**Consumers to retrofit — authoritative list (I-3 fix), the exact 12 files from
`grep -rlE 'autodev-state|\.autodev/state' hooks/`:**
`completion-claim-guard`, `pre-compact-snapshot`, `pre-tool-scope-guard`,
`pretool-demo-fidelity-guard`, `pretool-pr-review-reminder`, `prompt-strict-interpretation`,
`record-activity`, `scope-lock-abandon`, `scope-lock-claim`, `scope-lock-complete`,
`session-start`, `subagent-scope-guard`.

Explicitly **excluded**: `scope-lock-apply` and `scope-lock-publish` (write only the `.scope-lock`
sidecar next to the plan — not state dirs), `posttool-pr-created` (a PR-creation reminder, no
state), and `scope-lock-claim` (its single `autodev-state` mention is a **doc comment** — no
runtime state I/O; the session-lock write is delegated to `pre-tool-scope-guard`). So the grep
returns 12 paths but only **11** are real state writers to retrofit. The plan re-runs the grep as
its first step and treats `scope-lock-claim` as the known comment-only exclusion.

**Behavioral-change note (m-3):** `scope-lock-complete` and `scope-lock-abandon` currently derive
`repo_root` from the **plan path** (`cd "${plan_dir}/../.." && pwd`, assuming `docs/plans/` depth);
they will switch to `autodev_repo_root "$PWD"` (git-canonical). In a worktree this **intentionally**
changes the result from the worktree root to the main root — that is the whole point of the change,
but the plan must call it out so the implementer doesn't treat it as a bug. These two helpers take
the shell `$PWD` (not a hook payload `.cwd`) as the cwd argument.

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

**Honor-system caveat (m-4):** C2 is a convention, not a mechanical gate — there is no CI validator
that a subagent emitted a ledger (the orchestrator just reads it when present). This is deliberate
(a ledger-presence linter on free-text subagent output would be brittle), but it means the ledger's
value depends on the prompt templates keeping it salient; if subagents stop emitting it the
orchestrator simply falls back to inspecting the diff, as today. Accepted as a soft convention.

### C3 — Artifact path-hygiene gate

New `tests/no-machine-paths.sh`: greps the committed-artifact set (`docs/`, `decisions/`) for
operator-home absolute paths and fails with the offending `file:line`.

**Placeholder-aware regex (C-2 fix — the self-referential trap).** A feature *about* machine paths
must be able to *document* the forbidden pattern. The gate matches a home root followed by a **real
segment that begins with an alphanumeric**: `(/Users/|/home/)[A-Za-z0-9][A-Za-z0-9._-]*`. This
catches a real leak (home root + a literal username segment) but **ignores an angle-bracket placeholder**
(`/Users/<name>/...` — `<` is not alphanumeric, so no match) and ellipsis (`/Users/...`). The
**author convention** therefore is: to illustrate a machine path in any artifact, write it with an
angle-bracket placeholder segment (`/Users/<name>/...`, `/home/<user>/...`). Belt-and-suspenders:
any line containing the literal sentinel `path-hygiene-allow` (e.g. in an HTML comment) is skipped,
for the rare case a literal real-looking path must appear. Narrow by construction — targets
home-rooted paths only, so `/healthz`, `/tmp/x`, `/etc/...` pass untouched.

**This design doc, its plan, and the retro all use `/Users/<name>/` placeholders** so the gate is
green on landing. The pre-existing real leak in `docs/testing.md` is rewritten to a placeholder in
the same PR.

**CI wiring (I-2 fix).** A **dedicated** `.github/workflows/path-hygiene.yml` with **no `paths:`
filter** runs `tests/no-machine-paths.sh` on every push + PR. The existing
`skill-content-check.yml` filters on `skills/**`/`agents/**`, so a docs-only or decisions-only PR
that adds a leak would never trigger it — a false guarantee. A standalone always-on workflow closes
that hole permanently.

Plus a one-line rule in the artifact-writing skills (`brainstorming`, `writing-plans`,
`post-merge-retrospective`, `adversarial-design-review`, `recording-decisions`): committed
artifacts use repo-relative paths; illustrate machine paths only with `<placeholder>` segments;
never a literal operator-home path. Local state logs (`.claude/autodev-state/*`, gitignored) may
hold absolute paths; the tracked `.autodev/state/phase-progress.jsonl` stays repo-relative
(already is).

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
  can find the git common dir. If not (cwd outside any repo / git absent), the C-1-fixed resolver
  returns `$cwd` (empty `--git-common-dir` → fallback), preserving today's behavior — no regression.
  *Edge (m-1):* inside a **bare** repo `--git-common-dir` returns `.`, so the resolver returns the
  bare dir's parent rather than falling back; practical impact is nil (ADK hooks never run in a bare
  repo) and it never hard-fails, so this is documented, not guarded.
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
