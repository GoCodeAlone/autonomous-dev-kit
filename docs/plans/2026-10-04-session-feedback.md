# Session Feedback Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Correct stale-status guards, clarify checkpoint acceptance, and publish/install a verified patch.
**Architecture:** Existing Bash hooks and regression harness; additive JSONL guidance; existing native release/install path.
**Tech Stack:** Bash, jq, Git, gh, Codex CLI.
**Base branch:** main

## Scope Manifest

**PR Count:** 1
**Tasks:** 3
**Estimated Lines of Change:** ~200
**Out of scope:**
- Other sessions, plan ownership migration, BMW fixes, protection bypass, destructive cache/config changes, generalized status parser, new release automation.

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Fix stale plan checks and checkpoint acceptance | Task 1, Task 2, Task 3 | fix/session-checkpoint-release-feedback |

**Status:** Draft

## Guidance and Trace

R1 → Task 1; R2 → Task 2; R3 → Task 3. Generic host behavior, synthetic fixtures, and isolated writes apply to every task. Declared integration: native Codex plugin = runtime-integrated (Task 3); other hosts = existing unchanged contracts, no new integration claim.

### Task 1: Current-status guards

Files: `tests/hook-contracts.sh`; `hooks/completion-claim-guard`, `hooks/prompt-strict-interpretation`, `hooks/pre-compact-snapshot`, `hooks/scope-lock-complete`.
1. Add attributed Abandoned/Complete fixtures carrying historical inline Locked text; require no reminders and completion helper rejection with identical plan/lock/state. Add genuine Locked whitespace and attribution positives.
2. Run `bash tests/hook-contracts.sh`; expect new assertions FAIL before fix.
3. Replace unanchored status checks with `grep -qE '^\*\*Status:\*\*[[:space:]]+Locked'`; align completion AWK matcher. Anchor compact status-line extraction.
4. Run same command; expect `All hook contract tests passed.` Existing drift and active-plan guards must pass.
5. Commit task.

### Task 2: Checkpoint and parent acceptance

Files: `hooks/completion-claim-guard`, `skills/condensed-pipeline-writing/SKILL.md`, `tests/hook-contracts.sh`, `tests/pipeline-evidence-doc-sync.sh`.
1. Add assertions for checkpoint-only meaning, `pa:open`, parent acceptance evidence, and no legacy inference. Run tests; expect FAIL before guidance change.
2. Update emitted phase-row advice and condensed key table/example. Keep `st:done` backward compatible; no old-row migration.
3. Run hook and pipeline evidence contracts; expect exit 0. Read a pressure scenario (tests green, phase done, uncommitted source, release pending): answer must keep parent acceptance open. Do not claim behavioral compliance from text grep alone.
4. Commit task.

### Task 3: Patch release and native installation

Files: four plugin manifests via `scripts/bump-version.sh`; `RELEASE-NOTES.md`; `docs/README.codex.md` if native update clarification is needed.
1. Run all AGENTS commands plus CI-specific subagent guard, Zed install, path hygiene, shell syntax, scope-lock verification. Expect exit 0 for each; inspect baseline failures separately.
2. `bash scripts/bump-version.sh 6.6.2`; add release notes; `bash tests/version-check.sh` → PASS.
3. Independent full code review; push one PR and attach it. Monitor exact-head CI and review threads. Normal squash merge only after applicable rules/checks satisfied; blocked last-push approval is a publication blocker.
4. Verify automatic immutable tag peeled commit, manifest/source, release notes; publish GitHub Release against existing tag using `gh release create --verify-tag --notes-file`; verify marketplace notification/version (do not silently downgrade).
5. Preserve private backup of config/plugin metadata/cache; validate native marketplace refresh/add/list and source hashes in temporary Codex home. Repeat only scoped user marketplace refresh/install; compare unrelated config settings, trust metadata, and old cache preservation.
6. Fire real installed hook wrapper with synthetic attributed active/terminal fixtures. Expected terminal no block, active checkpoint contains `pa:open`; cleanup only owned fixtures. Confirm installed/list version6.6.2 and explain active sessions pick up changes on next start.
Rollback: immutable prior release/tag and preserved old cache; supported native pinned-marketplace add only, no trust bypass or active restart.

## Completion Boundary

Source implementation/review/PR checkpoint can finish before publication. This plan remains open while merge/release/install is blocked. Mark whole plan complete only after Task3 external verification. Parent report includes session evidence links without raw transcripts.
