# ADR 0007: resource closeout records review hints without deleting

**Status:** Accepted
**Date:** 2026-10-05

Repeated temporary build caches and anonymous volumes consume disk, but stale
appearance does not establish ownership or disposable database data. Active caches
and concurrent jobs require preservation.

Use existing native/stable compatible cache reuse in workflow guidance, and an
optional project-local ownership ledger with explicit job closeout. The helper
writes metadata only. Default/unknown/active/failed/reusable resources stay
protected; eligible disposable directories become manual review hints. Docker
volumes, databases and worktrees stay protected. No timeout/PID ownership reclaim.

Rejected: automatic cleanup/prune, global GOCACHE rewrite, a new cache allocator,
resource migration, or undocumented host-hook enforcement. Those approaches add
data-loss/concurrency risks or recreate per-job cache growth.

Consequences: no guaranteed disk quota or automatic reclamation. Crashed jobs can
leave active metadata until their owner explicitly closes them. Live consumer and
data checks are required before any separately authorized removal. Source skills
and direct CLI tests do not prove Codex lifecycle hook invocation.
