# Resource lifecycle prevention design

Authorization: the user requested optimizations to reduce repeated disk exhaustion,
an independently reviewed release, and preservation of active caches/installations.
The separate disk cleanup work owns its approved deletions; this change performs none.

## Guidance and evidence

- `AGENTS.md`: generic multi-host workflows, isolated changes, repository contracts,
  synchronized manifests and existing release process.
- Parent audit: 113 temporary Go caches (107.53 GiB); 238 new Docker volumes
  (30.24 GiB), 236 anonymous, since October 3. Active caches and unique database
  data require preservation. This is delegated audit evidence, not a fresh disk scan.
- [Go build cache documentation](https://pkg.go.dev/cmd/go#hdr-Build_and_test_caching):
  native cache reuse supports concurrent Go commands and compiler/options changes;
  changed C libraries require explicit rebuild handling.
- [Docker volume documentation](https://docs.docker.com/engine/storage/volumes/):
  anonymous volumes persist and are not automatically reused between containers.
- [Issue #101](https://github.com/GoCodeAlone/autonomous-dev-kit/issues/101):
  supported resource/runtime acceptance and explicit ownership remain follow-ups.

## Bounded response

R1: Existing execution/implementation/finishing guidance must prefer the effective
Go cache or a compatible stable project/toolchain cache. Preserve existing
`GOCACHE`; never change global Go settings. Require a concrete isolation reason
before a new cold cache, record its owner and closeout. Cache compatibility is not
database compatibility: identify every Docker mount and explicitly classify data.

R2: An optional POSIX Python standard-library helper records resources, closes
the calling job, and reports cleanup review candidates. It never executes Go,
Docker, removal, process stopping, or resource creation. Only its project-local
metadata is written. Guidance is usable without the helper on other platforms.

R3: Active, unknown, failed, reusable, database, Docker-volume and worktree
resources remain protected. A disposable directory can become a review candidate
only inside the project's `.autodev/tmp`, with a stated reason, existing directory,
no symlink/escape/worktree marker, and every recorded owner explicitly closed
successfully. Candidates cannot contain or lie within a protected recorded path.
Ancestor and descendant worktree markers, symlink descendants, unreadable trees,
or inspection beyond a bounded entry budget keep the directory protected.
Ancestor inspection stops before the enclosing project root, whose own Git
marker is expected; a positive normal-Git-project fixture verifies this boundary.
Output is a stale-able hint: live consumers and data intent must be
checked again before any separately authorized deletion.

R4: Concurrent writers must not lose ownership records. Session/job identities
are explicit attribution, not authentication. A different session cannot close a
job; closed jobs cannot be silently reused. Shared resources merge toward more
protective retention and purpose. Corrupt/unknown metadata is never reset. Failed
commands/crashes leave active ownership until explicit closeout, not PID/age guesses.

R5: Integrate meaningful helper and guidance regressions into CI, perform real CLI
and repeated Go-build smoke, review independently, and release v6.6.3 through the
existing tag/marketplace process. Preserve active native installation until the
existing maintenance condition is satisfied. No new hook declaration or claim of
Codex lifecycle invocation: this is explicit skill guidance and optional CLI use.

## Interface and ownership model

`scripts/job-resources.py --project <root> record --session <id> --job <id>
--kind directory|docker-volume|worktree --resource <path-or-name>
--purpose build-cache|test-fixture|database|unknown
--retention protected|reusable|disposable [--reason <brief>]`

`closeout --session <id> --job <id> --outcome success|failure` and `report`
return JSON. Record creates an active job on its first resource; no implicit owner
claim from timestamps, directory names, container state, or another session's log.
Default purpose and retention are unknown/protected. Disposable declarations for
external paths, databases, volumes or worktrees fail instead of weakening policy.

Metadata lives at `.autodev/state/job-resources.json` with a schema version and
project identity. POSIX `flock` uses a separate stable lock file that the helper
never replaces; only the JSON ledger is atomically replaced. Lock acquisition has
a bounded timeout. Metadata operations use no-follow directory descriptors and
descriptor-relative file opens/replacements, with parent/lock identity checks
before reads and commits. Observed directory/lock swaps fail without following
replacement targets. Cooperating helper writers are serialized; a same-user actor
can still move an already-opened original directory after validation. Such
tampering is not an authentication boundary: writes remain in that original owned
inode, not a replacement symlink's target, and detected changes are reported.
Read-only empty reports create nothing. Candidate paths are
revalidated at report time. The helper records identifiers and concise reasons,
not full command lines, environment dumps or credentials.

## Alternatives and limits

- Chosen: reuse native cache behavior plus explicit resource metadata and safe
  closeout guidance. See `decisions/0007-resource-closeout-is-nondeleting.md`.
- Rejected: cleanup daemon, global cache rewrites, automatic volume pruning,
  ownership inferred from age/PIDs, or migration of existing caches.
- Rejected: a new custom cache allocator. Native Go already provides stable reuse;
  another per-job allocator could reproduce the reported growth.
- Limits: guidance does not programmatically block arbitrary future allocations.
  The ledger knows only declared owners and cannot prove a path has no live
  consumers. Docker/database data always requires manual review. Abrupt job loss
  preserves resources and may leave conservative active records.

## Validation and rollback

Tests cover same-resource concurrent sessions, cross-session closeout rejection,
active/unknown/failed owners, policy escalation, repeated jobs, missing/corrupt or
future schema, lock/write failures, path traversal and deterministic directory/
lock swaps, nested/ancestor worktrees, protected parent/child overlaps, and byte
preservation of external/cache/database sentinels. Candidate
reporting must never remove or modify a resource. Test fixtures are owned temporary
directories; no real Docker volumes or other worktrees are touched.

Runtime smoke uses the shipped CLI and two real Go builds of an owned tiny project
with an existing effective cache, recording the same cache as reusable. Record
effective GOCACHE before/after and assert the unchanged second `go build -x`
contains no package compilation, rather than treating a shared path as reuse proof.
No new cold Go cache for demonstration. Host hook dispatch remains unverified and unused.
Rollback is a successor patch/revert; leave resource metadata/resources intact.
No installation refresh, destructive data migration, or protection-setting change.

## Backport 2026-10-05: review-discovered interleavings

Native concurrent nonexclusive lock creation reproduced intermittent ENOENT.
Use exclusive first creation plus bounded existing-open retry; never recreate a
missing lock beside an existing ledger. Independent review also demonstrated
duplicate JSON fields dropping unknown ownership and candidate scans of detached
old inodes. Reject duplicate fields and revalidate ancestor links plus bounded
descendant identities/timestamps before returning a hint. Inspection also stops
at 64 directory levels. Existing Tasks 1/3 cover these regressions; manifest unchanged.
