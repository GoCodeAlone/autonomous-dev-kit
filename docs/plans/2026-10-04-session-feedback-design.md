# Session feedback and release design

Authorization: user requested evidence-backed bounded fixes, release, and installation. No permission to bypass repository protections or restart other sessions.

## Global Design Guidance

Source: `AGENTS.md`; workspace design guidance requires generic plugin behavior, clean isolated work, evidence, privacy, and immutable release provenance. Current initiative: Autodev maintenance and Codex host coverage.

## Evidence and Priorities

| Priority | Evidence | Response |
|---|---|---|
| P1 | Recent permitted project progress records distinguish phase `done` from unaccepted tasks/releases; stale June-plan Stop reminders recur. | R1 anchored current-status checks; R2 explicit parent acceptance in checkpoint advice. |
| P1 | Session selectors in completion/prompt/compact hooks use unanchored status grep; workspace/pre-tool selectors already anchor it. Completion helper has the same gap. | Reproduce attributed terminal-status docs with historical inline Locked text, then fix four selectors and matching completion rewrite. |
| P2 | Official tag v6.6.1 exists; installed cache matches current main except mutable progress state. Marketplace advertises v6.5.11; latest GitHub Release is v6.5.0 because automation creates only tags. | R3 publish v6.6.2 using existing tag/marketplace process plus a GitHub Release; verify exact source before native install. |

Observed stale reminders are not all attributed to the selector bug: a primary checkout can remain Locked while another worktree owns an Abandoned copy. Do not rewrite another workstream's plan or attribution.

## Requirements

- R1: historical inline status text must not activate terminal plans; current anchored Locked status must retain guards. Completion helper must reject terminal plans before changing state and support existing whitespace convention.
- R2: `ev:phase, st:done` means the named checkpoint only. Add optional `pa:open` parent-acceptance guidance; acceptance needs full manifest/release/runtime evidence. No historical state migration.
- R3: all manifests version 6.6.2; keep newer main changes; official immutable tag and Release; native Codex installation verified against release source without restarting active sessions.

## Alternatives and Self-Challenge

- Recommended: small selector corrections plus explicit checkpoint semantics. Reuse established anchored regex and existing test harness.
- Alternative: central status parser/state migration. More scope and compatibility risk than this evidence supports; defer.
- Alternative: reminders disabled or blanket cleanup. Hides active work and weakens scope protection; reject.
- Doubts: authoritative worktree disagreement is not solved here; optional fields cannot force honest acceptance; repository merge rules may require a human approval before publication. Report each limit.

## Assumptions

| ID | Assumption | Fallback |
|---|---|---|
| A1 | Status is an anchored Markdown line as existing guards require. | Preserve existing syntax; test tabs/spaces and terminal states. |
| A2 | Legacy consumers tolerate additive JSONL fields. | Do not rewrite prior rows or require `pa` for legacy data. |
| A3 | Normal protected squash merge can satisfy org rules. | Report exact missing approval; never admin-bypass. |
| A4 | Native `codex plugin add` upgrades the configured Git plugin. | Verify in temporary Codex home first; stop on unsupported behavior. |

## Security Review

No secrets/transcripts/private personal content in committed evidence. Synthetic fixtures only. No added dependencies, cloud calls, authorization bypass, or other-session messages. Parent alone receives coordination.

## Infrastructure Impact

One repository PR; tag/Release plus existing marketplace notification. No protection edits or destructive data migration. Installation affects future sessions; active sessions continue.

## Multi-Component Validation

Real hook scripts receive synthetic events and inspect actual fixture status/state; helper rejection asserts no mutation. Full AGENTS/CI contract checks. Native Codex marketplace/add/list in isolated home, then authorized user install with source identity and hook-wrapper smoke.

## Rollback

Revert PR with a successor patch version; never retag. Preserve previous installed cache and relevant config/plugin metadata in a private local backup. Use supported native plugin commands with an isolated pinned marketplace for rollback validation; never hand-edit trust or remove active caches. If native rollback is unsupported, report before changing the user install.
