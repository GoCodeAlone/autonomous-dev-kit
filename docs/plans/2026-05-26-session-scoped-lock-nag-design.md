# Session-scoped lock nag + claim/abandon lifecycle

**Status:** Draft
**Date:** 2026-05-26
**Owner:** Jon Langevin (autodev)
**Guidance:** none found; ADR `decisions/0001-complete-scope-locks.md` is the closest canon (lock lifecycle); the Q&A premise is captured here.

## Problem

Locked-plan reminders (the "nag") fire on UserPromptSubmit, PreCompact, PreToolUse (push/PR), and SubagentStop hooks. The intent is to keep the autonomous pipeline honest under a `Status: Locked` manifest. The observed failure mode: locks left in the workspace from prior sessions nag *every* later unrelated session, even when the lock has nothing to do with the current work. Three follow-on gaps:

1. **Workspace fallback in session-aware hooks.** `prompt-strict-interpretation`, `pre-compact-snapshot`, and `pre-tool-scope-guard` already read `.claude/autodev-state/session-locks.jsonl`, but they fall back to a workspace-wide grep for `**Status:** Locked` when no session attribution exists (or when only one plan is locked). That fallback re-introduces the cross-session noise the JSONL was supposed to fix.
2. **`subagent-scope-guard` is not session-aware at all** — it greps the whole `docs/plans` tree and fails any subagent stop whose last commit doesn't satisfy a hash check on every workspace lock, even locks the subagent never touched.
3. **No agent-driven escape valves.** When a stale lock genuinely doesn't apply, the only documented exit is `scope-lock-complete`, which requires a verifiable Scope Manifest hash + completion evidence. Agents have no way to (a) **abandon** a lock that was never completed (e.g. user decided to stop pursuing the design) or (b) **claim** an existing workspace lock for the current session when the previous session was killed by a restart and a fresh agent is resuming the same work.

ADR 0001 introduced `scope-lock-complete` for the happy path. This design adds the unhappy paths (abandon, claim) and tightens nag scoping so completion is the only way a lock affects a session it isn't attributed to.

## Goals

- The locked-plan nag (UserPromptSubmit, PreCompact, PreToolUse push/PR, SubagentStop) fires for the current session iff that session has explicitly claimed the lock via `.claude/autodev-state/session-locks.jsonl`.
- An agent can **claim** an existing locked plan for its session in one bash call. `hooks/scope-lock-claim <plan-path>` writes the session-lock row that `pre-tool-scope-guard`'s `record_session_lock` would write if the agent had just run `scope-lock-apply`. Idempotent.
- An agent can **abandon** a stale workspace lock that was never completed. `hooks/scope-lock-abandon <plan-path> --reason "<reason>"` flips status from `Locked` → `Abandoned <UTC> — <reason>`, deletes the `.scope-lock` file, prunes JSONL traces for all sessions, appends an `Abandoned` row to `phase-progress.jsonl`. Does NOT verify manifest hash (the work was never finished, hash drift is expected).
- Subagent-scope-guard verifies the manifest hash only on plans the current session is attributed to (matching the other hooks).

## Non-goals

- Changing the lock format, manifest extraction rules, or `tests/plan-scope-check.sh`.
- A multi-session lock — claim is per-session; two sessions can claim the same lock independently, both see the nag.
- Re-claiming an `Abandoned` plan automatically. Once abandoned, the operator must re-lock (re-run alignment-check) to re-enter the gate.
- Auto-detecting "stale" locks (timestamp heuristics, branch presence, etc.). Stale-vs-active is judgment; the agent makes the call.

## Global Design Guidance

No `docs/design-guidance.md`. Applicable durable canon:

| guidance | design response |
|---|---|
| ADR 0001 — locks must have an explicit completion path (no inference from PR history) | Claim and abandon are equally explicit. Both are bash helpers, both leave an audit trail. |
| `scope-lock` SKILL — Scope Manifest is the contract; renegotiation goes through brainstorming. | Abandon is not "renegotiation under the lock"; it terminates the lock. The replacement work, if any, starts a new design + plan + lock. |
| `using-autodev` — agents may not bypass pipeline gates by setting env vars. | New helpers do not gate on env vars. They are direct shell scripts invoked from Bash; the existing `pre-tool-scope-guard` `record_session_lock` pattern is extended to recognize them. |
| Pipeline state in `.claude/autodev-state/` is repo-local + JSONL | New helpers write JSONL rows to existing files. No new state files. |

## Approach

### 1. Strict session-scoped nag

`prompt-strict-interpretation`, `pre-compact-snapshot`, `pre-tool-scope-guard`, and `subagent-scope-guard` all converge on a single rule:

> The locked-plan reminder fires for a plan in the current session iff `session-locks.jsonl` has an `ev:"session-lock"` row attributing that plan to the current `session_key`.

No workspace fallback. If the session has no attribution, no nag — even if exactly one locked plan exists in `docs/plans/`. (Today, the "exactly one workspace lock" fallback exists in `prompt-strict-interpretation` and `pre-compact-snapshot`; it goes away.) The cost of removing the fallback is that a fresh session resuming abandoned work won't be reminded until it claims; the new `scope-lock-claim` helper is the recovery path.

`pre-tool-scope-guard`'s `find_locked_plans` already returns only session-attributed plans when a `session_key` is present. It still falls back to a workspace scan when no `session_key` is available (no `transcript_path` in hook input). We keep that final fallback only because absence of `transcript_path` means the host did not provide session identity — in that case workspace-wide is the only safe heuristic. Hosts that always emit `transcript_path` (Claude Code) never hit it.

`subagent-scope-guard` gets the same treatment: extract `transcript_path` from `hook_input`, derive `session_key`, and verify the manifest hash only on plans attributed to that session. If no attribution exists, no check fires.

### 2. `hooks/scope-lock-claim <plan-path>`

Minimal bash script. Verifies the plan exists, has `**Status:** Locked`, and that `.scope-lock` is present (the manifest hash file is the source of truth for the lock — claiming without a hash file is rejected because nothing verifies). Then prints a single line containing the literal token `scope-lock-claim` and the resolved plan path. The actual `session-locks.jsonl` write is performed by `pre-tool-scope-guard`'s `record_session_lock`, which already runs on every Bash tool call and currently only recognizes `scope-lock-apply`. We extend the regex to also match `scope-lock-claim`. This keeps the JSONL append path identical for apply and claim — one writer, one format.

Why route writes through `record_session_lock` rather than have the script write the JSONL itself: `record_session_lock` knows the `session_key` from the hook payload, which the bash subprocess does not. Routing through the hook avoids duplicating session-key discovery and keeps the script free of "did the host pass a transcript path?" code.

Idempotent: if the claim row already exists for `(session, plan)`, no duplicate is written. The current `record_session_lock` already writes one row per invocation; we add a dedupe pass at write time (cheap — typical file is <100 rows).

### 3. `hooks/scope-lock-abandon <plan-path> --reason "<reason>"`

Mirrors `scope-lock-complete` but skips manifest hash verification and uses a distinct lifecycle state. Verifies the plan exists and currently has `**Status:** Locked`. Flips status to `Abandoned <UTC> — <reason>`. Removes `.scope-lock`. Prunes JSONL rows for the plan across all sessions in `session-locks.jsonl` and `in-progress.jsonl`. Appends to `.autodev/state/phase-progress.jsonl`:

```json
{"ts":"<UTC>","ev":"plan","pl":"<name>","st":"abandoned","reason":"<reason>"}
```

Distinct from `complete` so retros and dashboards can tell "verified done" from "stopped pursuing". `--reason` is required (empty string rejected); the value is recorded both in the status line and in the JSONL row.

### 4. `subagent-scope-guard` session-aware refactor

Today it greps the whole `docs/plans` tree. Replace with the same `session_key + session-locks.jsonl` filter used elsewhere. If no `session_key`, fall back to workspace-wide (same behavior the other hooks now have). The protected-file checks for uncommitted `.scope-lock` writes and last-commit `.scope-lock` modifications stay unchanged — those are about subagent behavior, not lock attribution.

### 5. SKILL.md updates

`skills/scope-lock/SKILL.md` learns three things:

- The lock attribution rule: nag fires iff the plan is attributed to the current session.
- The claim command, with the resume-after-restart story as the canonical example.
- The abandon command, with the "user decided to stop pursuing this" story as the canonical example, and the explicit note that abandon does not require completion evidence and does not unblock a re-locked plan.

## Architecture / components

- **No new state files.** Reuses `.claude/autodev-state/session-locks.jsonl`, `.claude/autodev-state/in-progress.jsonl`, and `.autodev/state/phase-progress.jsonl`.
- **New scripts:** `hooks/scope-lock-claim`, `hooks/scope-lock-abandon`.
- **Modified hooks:** `pre-tool-scope-guard` (regex + dedupe), `prompt-strict-interpretation` (remove workspace fallback), `pre-compact-snapshot` (remove workspace fallback), `subagent-scope-guard` (add session filter).
- **Modified skill:** `skills/scope-lock/SKILL.md`.
- **Modified tests:** `tests/hook-contracts.sh` gains coverage for the new behavior; existing `test_prompt_strict_falls_back_to_single_workspace_lock` is replaced with `test_prompt_strict_ignores_single_workspace_lock_when_session_has_no_lock` (semantic flip, single-PR scope).

## Data flow

```
fresh session (transcript_path=A.jsonl)
  └─ bash hooks/scope-lock-claim docs/plans/foo.md
       │
       └─ pre-tool-scope-guard intercepts Bash, sees "scope-lock-claim",
          calls record_session_lock → appends
          {"ts":...,"ev":"session-lock","session":"A.jsonl","pl":"docs/plans/foo.md"}
          to .claude/autodev-state/session-locks.jsonl (idempotent)

  └─ next user prompt: "go ahead and create a PR"
       │
       └─ prompt-strict-interpretation reads session-locks.jsonl, finds
          A.jsonl→foo.md attribution → emits the nag reminder

later (work abandoned)
  └─ bash hooks/scope-lock-abandon docs/plans/foo.md --reason "user pivoted"
       │
       ├─ flips Status to "Abandoned <UTC> — user pivoted"
       ├─ rm docs/plans/foo.md.scope-lock
       ├─ prune all session-lock rows where pl == foo.md
       ├─ prune in-progress.jsonl rows for foo.md
       └─ append phase-progress.jsonl {ev:"plan",st:"abandoned",...}

  └─ subsequent prompts: no session attribution → no nag
```

## Security review

- **No new auth boundary.** Scripts run with the agent's existing shell privileges. They write only to repo-local state files under the cwd.
- **Self-bypass surface.** Neither helper accepts `SUPERPOWERS_*` env vars; they are unconditional helpers. They do not gate anything — they're cleanup. The existing self-bypass guard in `pre-tool-scope-guard` is unaffected.
- **Abandon is destructive** (removes lock + prunes rows). Risk: an agent abandons a lock the user wanted preserved. Mitigation: `--reason` is mandatory and recorded; the plan body remains intact (only `Status` flips); `phase-progress.jsonl` keeps an audit trail. The user can re-run alignment-check to re-lock.
- **Claim is non-destructive.** Worst case: a session claims a plan that doesn't apply to its work and gets unnecessary nags; the cost is one extra reminder per prompt. Reverse is recovering from missing nags after a restart — claim is the asymmetric-cost win.
- **Path traversal.** Both scripts resolve `plan-path` via the same `canonical_path_from_base` helper used by `scope-lock-complete`. Symlink and traversal handling is identical.

## Infrastructure impact

None. All changes are local to the autodev plugin distribution. No runtime services, no migrations, no deploy gates. Released by tag push → marketplace dispatch (the existing pipeline). No `## Rollback` section required — this is not a runtime-affecting change class per `runtime-launch-validation`'s trigger list. If the release goes bad, revert the merge commit and bump again.

## Multi-component validation

Hook integration tests in `tests/hook-contracts.sh` exercise the real bash hooks end-to-end against tmpdirs that simulate the `docs/plans/` + `.claude/autodev-state/` layout. No mocks at the bash/JSONL boundary. Tests cover:

- claim writes the row (via `pre-tool-scope-guard` regex match)
- claim is idempotent
- claim of a plan without `.scope-lock` is rejected
- abandon flips status, deletes lock, prunes session-locks + in-progress, appends phase-progress
- abandon requires `--reason`
- abandon refuses a plan not in `Locked` status
- prompt-strict no longer falls back to single workspace lock (replaces existing fallback test)
- pre-compact-snapshot no longer falls back to single workspace lock
- subagent-scope-guard does not fire on workspace-only locks unattributed to the session
- subagent-scope-guard still fires on the session-attributed lock when manifest drift is detected

## Assumptions

1. `record_session_lock` runs on every Bash tool call. (Verified: `pre-tool-scope-guard` invokes it after the self-bypass guard, before any block check.) If this changes, claim breaks silently.
2. `session_key` (transcript_path basename) is stable for the lifetime of a session including across compactions. (Verified empirically by the existing session-aware hooks; if Claude Code rotated transcript IDs mid-session, the existing nag-scope logic would already be broken.)
3. Sessions running in worktrees still resolve `cwd` to the worktree path, so `.claude/autodev-state/session-locks.jsonl` is worktree-local and a claim made in worktree A does not bleed into worktree B.
4. Operators do not hand-edit `.claude/autodev-state/session-locks.jsonl`. (If they do, dedupe still works; abandon still prunes; nothing relies on row order.)

The most fragile assumption is #1. If `pre-tool-scope-guard`'s `record_session_lock` ever moves to a different hook or gets removed, claim becomes a no-op. A defensive alternative would be to have the helper write JSONL directly using a discovered transcript path; the current design accepts the fragility in exchange for one writer of session-locks.jsonl.

## Self-challenge

1. **Laziest plausible solution.** Just remove the workspace fallback in the three nag hooks. Don't add claim or abandon. Trade-off: agents resuming after restart get no nag at all (silent loss of gate); stale workspace locks need manual deletion of `.scope-lock` + status edit. Rejected: silent loss of the gate is worse than the cost of two helpers, and operators editing state by hand violates ADR 0001's "no manual edits of `.scope-lock`" rule.
2. **Most fragile assumption.** #1 above. Mitigation noted; consequence is non-silent (no nag → user notices stale work).
3. **YAGNI sweep.** No new flags, env vars, config knobs, or hooks. Two helpers, one regex change, one filter add, one workspace fallback removed. No bulk-abandon command — the user wanted per-plan agent action.
4. **First failure under partial restart / mid-operation.** `scope-lock-abandon` interrupted between `rm .scope-lock` and the JSONL prune leaves an Abandoned plan with stale session-lock rows. Next prompt nags about a plan whose lock file is gone. The status line check in `find_locked_plans` already gates on `**Status:** Locked` — Abandoned plans drop out automatically. So the interrupted-abandon failure mode self-heals on the next nag attempt.
5. **Repo precedent conflict.** None. `scope-lock-complete` is the closest existing helper; abandon and claim mirror its argument shape and state-file conventions.

Top 3 doubts surfaced for the reviewer:

1. The "no workspace fallback" rule means a fresh session resuming abandoned work is silent until claim. Is that the right default? (We think yes — silence is recoverable via one bash call; false nags are not recoverable in the moment.)
2. Routing the claim write through `pre-tool-scope-guard`'s regex couples two files. A direct write from `scope-lock-claim` would be more local but would need its own session-key discovery. Acceptable trade?
3. `--reason` on abandon is required. Some agents may resist; making it optional would weaken the audit trail. Acceptable trade?

## Rollback

Not a runtime-affecting change. Revert the merge commit. Marketplace bump PR reverts independently; users on the bumped plugin version see the new helpers as no-ops if they don't invoke them, and the nag behavior degrades safely to the prior workspace-fallback path only when the new pre-tool-scope-guard regex isn't installed — which means a revert restores prior behavior wholesale, no migration needed.

## Open questions for adversarial review

- Should `scope-lock-claim` reject plans whose `.scope-lock` hash doesn't match (i.e. drift detected at claim time)? Today the design says claim only verifies that `.scope-lock` exists. Drift is caught later by `pre-tool-scope-guard`'s push/PR gate. Claiming a drift-broken plan is arguably worse than refusing the claim.
- Should `scope-lock-abandon` write an ADR via `recording-decisions`? Today it does not — abandon is "stop pursuing", not a manifest amendment. But operators may want a durable record. Argue both sides.
