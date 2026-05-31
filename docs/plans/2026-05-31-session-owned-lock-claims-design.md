# Session-Owned Lock Claims Design

**Status:** Approved
**Date:** 2026-05-31
**Issue:** https://github.com/GoCodeAlone/autonomous-dev-kit/issues/52
**ADR:** `decisions/0002-lock-claims-require-objective-match.md`

## Problem

A resumed Codex session trusted stale compacted context and executed a locked
Hover plan while the user-visible task was Workflow admin/auth/authz work. The
current lock system verifies manifest integrity and session attribution, but
`scope-lock-claim` can attribute any intact locked plan to any fresh session.
That lets a stale summary or mistaken resume target switch work streams.

## Goals

- A fresh/resumed session cannot claim a locked plan already owned by a
  different objective without explicit re-anchor.
- Intentional handoff remains possible through `scope-lock-claim --confirmed`.
- Resume/compaction context tells agents to verify repo/branch/plan/objective,
  not trust prose that says "active plan is X."
- Existing `.scope-lock` hash files and plan-scope checks remain compatible.
- Works across Claude Code/Codex/Cursor-style hooks; degrades to documented
  manual verification when a harness lacks transcript identity.

## Non-Goals

- No multi-agent coordination server or lease expiry.
- No branch-locking or process liveness detection.
- No change to Scope Manifest hashing or `.scope-lock` first-hash format.
- No automatic inference that a similarly named task is the same objective.

## Global Design Guidance

`Guidance: none found as docs/design-guidance.md; canon from README §Cross-LLM,
docs/plans/2026-04-25-cross-llm-portability-design.md, and ADR 0001.`

| guidance | design response |
|---|---|
| Host-neutral / cross-LLM first | Hook behavior is bash+jq and keeps legacy fallback only when no transcript identity exists. Skill docs describe manual re-anchor for hookless hosts. |
| Scope Manifest is the contract | Manifest hash stays untouched; ownership is separate session state. |
| Explicit lifecycle over inference | Claim requires objective match; mismatch needs explicit `--confirmed`. |
| Avoid stale locks nagging unrelated sessions | Existing session-scoped nag remains; this fix tightens how claims enter that state. |

## Approach Options

| option | summary | trade-off |
|---|---|---|
| Recommended: objective metadata in `session-locks.jsonl` | `pre-tool-scope-guard` records objective hash/excerpt on `scope-lock-apply`/`scope-lock-claim`; claim mismatch blocks unless `--confirmed`. | Uses existing hook path that knows transcript/session; `.scope-lock` stays compatible. |
| Structured `.scope-lock` metadata comments | Add owner/objective comments around the existing hash. | Durable in the sidecar, but helper lacks transcript context and legacy writers can overwrite metadata. |
| Resume prompt only | Tell agents to ask before acting after compaction. | Necessary but insufficient; stale summaries already fooled the agent. |

## Design

1. `pre-tool-scope-guard` derives `current_objective` from the latest
   user-visible message in `transcript_path`, normalizes whitespace, and
   computes SHA-256. This matches issue #52's "latest task conflicts with
   compacted active plan" failure mode better than the session's first prompt.
2. `record_session_lock` writes compact ownership fields on recognized
   `scope-lock-apply` and `scope-lock-claim` Bash commands: session, plan, repo,
   branch, objective hash, objective excerpt, and `confirmed` when present.
3. For `scope-lock-claim`, before writing a new row, the hook scans existing
   rows for the same plan. If any prior row has a different objective hash or no
   comparable objective, it blocks with a resume-target checkpoint: current
   repo/branch/plan/objective excerpt, recorded owner excerpt, and the
   `scope-lock-claim --confirmed <plan>` escape hatch for user-directed handoff.
4. Same `(session, plan)` claims stay idempotent.
5. `hooks/session-start` adds a resume-target checkpoint on compact/resume:
   current repo/branch, transcript objective excerpt, attributed locked plans,
   and a warning that lock snapshots/activity are not ownership proof.
6. `skills/scope-lock/SKILL.md` documents claim verification, mismatch handling,
   and the intentional handoff syntax.

## Security Review

- **Secrets/PII:** objective excerpts come from user messages already present in
  local transcripts. Excerpts are capped and stay in repo-local `.claude`
  state. No network calls.
- **Abuse case:** an agent can pass `--confirmed`; docs require this only after
  user-visible re-anchor. The flag is auditable in JSONL (`confirmed:true`).
- **Least privilege:** no new permissions; hook writes existing state file only.
- **Trust boundary:** compacted prose is treated as untrusted unless it matches
  recorded session ownership.

## Infrastructure Impact

None. Local plugin hooks and skill docs only. Release path is the existing tag
workflow.

## Multi-Component Validation

- Hook boundary: `tests/hook-contracts.sh` invokes real hook scripts with real
  stdin JSON and tmp transcript/state files.
- Claim mismatch: seed an owner row for objective A, invoke claim from objective
  B, assert block JSON and no new row.
- Claim match: objective A → objective A writes row.
- Confirmed handoff: objective B with `--confirmed` writes row and records
  `confirmed:true`.
- Resume context: `session-start` compact/resume output includes a
  resume-target checkpoint and warns that snapshots are not ownership proof.

## Assumptions

| id | assumption | challenge | fallback |
|---|---|---|---|
| A1 | `transcript_path` exists on supported hook hosts | Some harnesses omit it | Existing workspace fallback remains; skill docs require manual re-anchor. |
| A2 | Latest user-visible message is stable enough objective material | A user may issue a short "continue" prompt | Hash is a guardrail, not semantic proof; `--confirmed` handles intentional handoff. |
| A3 | Existing rows may lack objective metadata | Legacy state persists | Treat unverifiable prior ownership as mismatch unless `--confirmed`. |

## Rollback

Revert the PR. Extra JSONL fields are ignored by older hooks. No migration.

## Self-Challenge

- **Simplest alternative:** prompt-only resume warning. Rejected because issue #52
  is a prompt/prose trust failure.
- **Fragile assumption:** latest user message may be short. Mitigated by
  explicit confirmation path and visible excerpts.
- **YAGNI check:** no lock server, no liveness, no branch leases.
