# Build caches and job resources

Before disk-heavy work, identify the effective cache, every container mount and
the job owning each newly created resource. Reuse compatible resources instead of
allocating a fresh cache for every task, review or retry. A low-space condition
should defer new heavy work for scoped owner review; preserve running jobs and data.

For Go, inspect `go env GOCACHE` and preserve inherited `GOCACHE`. Prefer the native
cache, or an existing stable project/toolchain cache when the project's constraints
require it. Go's native cache supports concurrent commands and compiler/options
changes. Changed C libraries require explicit rebuild handling. Do not run global
`go env -w GOCACHE=...`, default to a new `mktemp` cache per job, or empty another
job's cache. A cold cache needs a concrete isolation/reproduction reason, an owner
and an explicit closeout record. See [Go cache documentation](https://pkg.go.dev/cmd/go#hdr-Build_and_test_caching).

For Docker, declare each mount's name/path, purpose, owner and persistence before
launch. Prefer stable named build caches where compatible; anonymous volumes
persist and are not automatically reused. Database/application volumes are
protected data, including anonymous PostgreSQL volumes with unknown provenance.
Do not infer disposability from names, age, absence of containers, or reference
count zero. Never use broad prune, Docker reset/restart or process termination as
routine resource closeout. See [Docker volume documentation](https://docs.docker.com/engine/storage/volumes/).

At success **and failure**, record the job outcome and resource disposition in
the task's evidence. Preserve active, unknown, failed and reusable resources.
List exact cleanup review candidates with ownership and isolation reasons;
recheck live use and data intent before any separately authorized deletion.
Do not infer completed ownership from PID disappearance or elapsed time.
Worktrees/source, database data, host configuration and plugin caches stay protected.

## Optional metadata helper

`scripts/job-resources.py` requires Python 3.9+ and POSIX flock/no-follow directory
support. On other hosts, keep equivalent explicit records manually. This is
optional skill guidance and direct CLI use; it adds no lifecycle hook, daemon,
automatic host dispatch, disk quota, cache allocator, or deletion command.
Adoption cannot guarantee bounded disk usage.

Run the helper from the actual installed plugin/checkout location. In these
examples, `ADK_ROOT` is that location and `PROJECT_ROOT` is the existing project
or worktree owning the resources. Repeated jobs use new job IDs; session/job IDs
are attribution, not authentication. Keep IDs/reasons concise; never record
credentials, full command lines or environment dumps.

```bash
# Record an existing effective cache; this command does not run Go or create it.
python3 "$ADK_ROOT/scripts/job-resources.py" --project "$PROJECT_ROOT" record \
  --session "$SESSION_ID" --job "$JOB_ID" --kind directory \
  --resource "$EXISTING_CACHE" --purpose build-cache --retention reusable

# Only an already-created, isolated directory strictly within .autodev/tmp can
# be declared disposable. Explain why this job required a fresh resource.
python3 "$ADK_ROOT/scripts/job-resources.py" --project "$PROJECT_ROOT" record \
  --session "$SESSION_ID" --job "$JOB_ID" --kind directory \
  --resource "$PROJECT_ROOT/.autodev/tmp/$JOB_ID" --purpose test-fixture \
  --retention disposable --reason 'cold-cache regression requires isolation'

python3 "$ADK_ROOT/scripts/job-resources.py" --project "$PROJECT_ROOT" closeout \
  --session "$SESSION_ID" --job "$JOB_ID" --outcome success
# Use --outcome failure after a failed job. Abrupt loss leaves active ownership.
python3 "$ADK_ROOT/scripts/job-resources.py" --project "$PROJECT_ROOT" report
```

The helper writes only `.autodev/state/job-resources.json` and its stable lock/
transaction metadata. Defaults are unknown/protected. Volume/worktree declarations
stay protected; disposable database/volume/worktree or external-path declarations
are rejected. Every declared owner must close successfully before a disposable
directory can become a `review-candidate`. Protected path overlaps, symlinks,
nested/ancestor worktrees (excluding the enclosing project's own Git marker),
unreadable/changed directories, more than 10,000 inspected entries or 64 directory
levels keep it
protected. Reports never remove or modify resource contents.

Cooperating writers serialize on a stable lock; JSON updates are atomic. Unknown,
corrupt, mismatched or oversized (1 MiB) metadata fails without resetting it.
Operational errors return JSON on stderr with exit 2; argument syntax uses normal
CLI help/errors. Lock acquisition times out after five seconds. A failed commit
may have reached disk before a later durability/identity error; inspect the ledger
before retrying. Never remove the lock or repair metadata while another job uses it.
Same-user tampering is outside the attribution boundary: no-follow descriptors
avoid following replacement targets, but an opened original directory can still
be moved. Detected changes fail conservatively. No age/PID owner reclaim exists.

Candidates are stale-able review hints, never deletion permission. The ledger knows
only declared owners and cannot prove absence of live consumers. Rollback leaves
metadata and resources intact; there is no required migration of existing caches.
