# 0006. Separate checkpoints from parent acceptance

**Status:** Accepted
**Date:** 2026-10-04
**Decision-makers:** authorized maintenance agent
**Related:** `docs/plans/2026-10-04-session-feedback-design.md`

## Context

Phase progress can report a completed software checkpoint while its task, product, or release remains unaccepted. Existing `ev:phase, st:done` rows do not encode that distinction. Historical state and legacy consumers must remain usable.

## Decision

Keep `st:done` scoped to the named checkpoint. Add optional `pa:open` to record parent acceptance still open, with evidence and next action. Absence of `pa` means unknown; it never implies acceptance. Whole-plan completion still requires the scope-lock completion path and full verification.

Reject a mandatory new schema or historical migration: neither is necessary to fix misleading checkpoint interpretation. Reject treating all done rows as accepted: that loses actual release and runtime gates.

## Consequences

New hook advice and condensed writing examples agree without invalidating old rows. The field is guidance, not a machine-enforced acceptance validator. Future consumers must not promote checkpoint completion into whole-plan acceptance.
