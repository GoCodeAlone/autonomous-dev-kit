# 0002. Require objective match for lock claims

**Status:** Accepted
**Date:** 2026-05-31
**Decision-makers:** Jon Langevin, Codex
**Related:** `docs/plans/2026-05-31-session-owned-lock-claims-design.md`, `hooks/pre-tool-scope-guard`, `hooks/scope-lock-claim`

## Context

Issue #52 showed that a compacted/resumed agent can inherit another session's
locked plan from stale context. Existing scope locks protect manifest integrity,
but `scope-lock-claim` only verifies the plan hash; it does not prove the
current user-visible objective matches the session that locked or claimed the
plan.

## Decision

We will keep `.scope-lock` as the manifest-hash anchor and add ownership
metadata to `.claude/autodev-state/session-locks.jsonl` rows. Claim/apply rows
record repo, branch, session, plan, and an objective hash/excerpt derived from
the latest user-visible instruction in the session transcript. `scope-lock-claim` is blocked when an existing owner row
for that plan has a different or unverifiable objective, unless the agent uses
an explicit `--confirmed` re-anchor after user direction.

**Alternatives considered and rejected:**

- **Rewrite `.scope-lock` as structured metadata** — compatible in theory via
  comments, but it mixes ownership state into the manifest-integrity anchor and
  complicates legacy lock handling.
- **Trust compacted summaries** — this is the failing mechanism in issue #52.

## Consequences

**Positive:**

- Fresh/resumed sessions cannot silently claim another session's lock when the
  objective differs.
- Existing `tests/plan-scope-check.sh` and legacy `.scope-lock` files remain
  compatible.

**Negative:**

- Hosts without transcript identity can only use the legacy workspace fallback.
- Legitimate handoffs across different objectives require an explicit
  `scope-lock-claim --confirmed`.

**Reversibility:** Low. Revert hook metadata/checks; existing JSONL rows with
extra fields are ignored by older hooks.
