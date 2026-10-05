# Resource Lifecycle Implementation Plan

**Goal:** Reduce fresh build-cache allocation and make job resources attributable
and visible at closeout, without automatic deletion.
**Architecture:** Existing workflow guidance plus an optional POSIX metadata ledger.
**Tech Stack:** Python 3.9+ standard library, Bash contracts, Git/gh release tooling.
**Base branch:** main

## Scope Manifest

**PR Count:** 1
**Tasks:** 4
**Estimated Lines of Change:** ~1000
**Out of scope:**
- Actual cleanup, Docker/Go command automation, cache allocation/migration, cleanup
  daemon, global GOCACHE changes, security expansion, other worktrees/sessions,
  general ownership supersession, and active plugin upgrade before maintenance.

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Record resource ownership and prefer stable cache reuse | Task 1, Task 2, Task 3, Task 4 | fix/resource-lifecycle-guidance |

**Status:** Locked 2026-10-05T05:42:00Z

## Guidance and trace

Design R1 → Task 2; R2/R3/R4 → Task 1; R5 → Tasks 3/4. One source PR; the
existing marketplace workflow may generate its normal version notification PR.
User-authorized admin merge is permitted only after exact-head checks and clean
independent review, with no unresolved concern. Active install remains held.

### Task 1: Nondeleting resource ledger and regression suite

Files: create `scripts/job-resources.py`, `tests/job-resources.py`.
1. Write meaningful unittest/CLI regressions first; run against absent helper and
   capture the expected failure. Use real subprocess concurrency and owned fixtures.
2. Implement record/closeout/report, safe metadata containment/locking/atomic writes,
   conservative ownership/retention merge, schema preservation, and review hints.
3. Verify active/unknown/failed protection, cross-session attribution rejection,
   competing writers across ledger replacements with stable lock identity,
   missing/corrupt/future state, failed writes/locks, path/symlink/worktree rejection,
   deterministic directory/lock swaps, protected parent/child overlaps, nested and
   ancestor worktrees, and unchanged sentinel bytes. Attribution is not authentication.
   No Go/Docker/delete subprocesses in helper.
4. Run `python3 tests/job-resources.py` and
   `python3 -m py_compile scripts/job-resources.py tests/job-resources.py`;
   expect all tests/compile exit 0. Commit the bounded helper/test change.

### Task 2: Cache reuse and explicit resource guidance

Files: create `docs/resource-lifecycle.md`, `tests/resource-lifecycle-docs.sh`;
modify `skills/executing-plans/SKILL.md`,
`skills/subagent-driven-development/implementer-prompt.md`,
`skills/finishing-a-development-branch/SKILL.md`, `docs/README.codex.md`.
1. Add doc-contract checks for every entrypoint, native/stable cache reuse,
   inherited GOCACHE preservation, cold-cache reason, explicit Docker mounts/data,
   closeout candidates, failure/unknown protection, and optional CLI limits.
2. Write concise actionable guidance and real helper examples using placeholders.
   Keep database data protected; avoid anonymous volumes in durable/repeated jobs.
3. Run `bash tests/resource-lifecycle-docs.sh`, `bash tests/skill-content-grep.sh`,
   and `bash tests/skill-cross-refs.sh`; expect exit 0. Read a failure/parallel-job pressure
   scenario. Text checks do not establish runtime agent compliance or host dispatch.
4. Commit guidance and document concrete behavioral limits.

### Task 3: CI and runtime/source verification

Files: create `.github/workflows/resource-lifecycle.yml`; evidence in owned task
verification directory; committed design/plan review and code-review reports.
1. Wire helper and doc tests into a path-filtered Ubuntu CI job using Python3/Bash.
2. Run every AGENTS contract and existing CI-specific hook/Zed/path check plus new
   resource tests. Verify plan/hash, diff hygiene and syntax; compare inherited lint.
3. `python3 scripts/job-resources.py --help` must list record/closeout/report.
   Run actual CLI record→active report→success closeout→candidate report, verifying
   resource sentinel bytes survive. Run two unchanged `go build -x` commands in an
   owned project with the existing effective GOCACHE; before/after cache values
   must match and second output must contain no package compilation. No new cold
   cache or Docker resource. Capture commands/exit statuses as runtime evidence.
4. Independent spec/code review, including failure/concurrency/containment attacks;
   fix findings and recheck exact final head. Record qualified runtime evidence.

### Task 4: Reviewed patch release and maintenance handoff

Files: all four manifests via `scripts/bump-version.sh`; `RELEASE-NOTES.md`.
1. Prepare v6.6.3 notes/manifests, then run the complete final relevant checks.
2. Push one source PR; attach when app tools are available. Confirm exact-head CI,
   independent review and unresolved threads before normal/authorized admin squash.
3. Wait for merge-commit checks and official tag workflow. Verify peeled tag equals
   merge commit and reviewed tree; publish immutable latest GitHub Release using
   the existing tag and checked-in notes. Verify both source archives/manifests.
4. Verify marketplace notification/version PR checks and exact manifest delta.
5. Report active installed version without refreshing it; preserve settings/old
   paths. Safe native installation requires natural completion of old-cache users
   or explicit maintenance authorization. Overall acceptance stays open until then.

## Completion boundary

Source/release checkpoints are distinct from installation acceptance. No partial
source implementation, fabricated hook proof, or cleanup action is authorized.
Resource candidates are review inputs, never permission to remove them.
