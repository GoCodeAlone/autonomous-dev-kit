# Session-Owned Lock Claims Adversarial Review

**Phase:** design
**Artifact:** `docs/plans/2026-05-31-session-owned-lock-claims-design.md`
**Status:** PASS

## Findings

| sev | class | loc | issue | fix |
|---|---|---|---|---|
| Important | Assumptions under attack | Design §Design, §Assumptions | "First user message" fails long-lived sessions that pivot, which is exactly issue #52's latest visible task mismatch. | Revised design/ADR/plan to hash latest user-visible message. |
| Minor | Security/privacy | Design §Security Review | Objective excerpts may contain local task details. | Capped local-only excerpts accepted; no network; state already repo-local. |
| Minor | Simpler alternative | Design §Approach Options | Prompt-only resume checkpoint is cheaper. | Rejected because the bug is stale prose being trusted. |

## Bug-Class Scan Transcript

| Class | Result | Note |
|---|---|---|
| Project-guidance conflicts | Clean | Host-neutral bash hook path matches README/cross-LLM guidance. |
| Assumptions under attack | Finding resolved | First-message assumption revised to latest-message objective. |
| Repo-precedent conflicts | Clean | Extends existing `session-locks.jsonl` attribution pattern. |
| YAGNI violations | Clean | No server, lease, liveness detector, or branch lock. |
| Missing failure modes | Clean | Legacy/unverifiable rows block unless `--confirmed`; hookless hosts are documented manual mode. |
| Security/privacy | Minor | Local capped excerpts are acceptable for this repo-local state. |
| Infrastructure impact | Clean | No infra. |
| Multi-component validation | Clean | Hook contract tests exercise real stdin JSON + state files. |
| Rollback story | Clean | Revert PR; extra JSONL fields ignored. |
| Simpler alternative not considered | Minor | Prompt-only alternative considered and rejected. |
| User-intent drift | Clean | Directly targets issue #52 claim/resume mismatch. |

## Verdict Reasoning

PASS after revising objective source from first user message to latest
user-visible message. Remaining findings are documented trade-offs, not blockers.
