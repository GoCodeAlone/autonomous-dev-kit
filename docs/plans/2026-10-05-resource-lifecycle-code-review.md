# Resource lifecycle independent code review

Final verdict SHIP-IT; no remaining findings. Independent review inspected
implementation HEAD `7d2e4d923f1642b7afc7b0d934672b15e0bff9a1`, tree
`56b6c2ecd41cf2d5f293fdf82be7e382a146cb39`; initial BLOCK findings resolved.

| ID | Severity | Finding | Resolution |
|---|---|---|---|
| RCR-01 | Important | Concurrent first lock creation intermittently fails; early test assertion leaves owned children unreaped. | Exclusive-create/existing-open bounded protocol; preserve missing existing-ledger lock; reap every child before assertions. Thirty stress batches pass. |
| RCR-02 | Important | Duplicate JSON fields silently drop unknown owners. | Reject duplicate object keys; report/record/closeout preserve ambiguous bytes. |
| RCR-03 | Important | Candidate scan can inspect detached old directory after path replacement. | Final ancestor-link and descendant identity/timestamp validation; candidate/ancestor/descendant/new-entry regressions preserve data. |

Reviewer inspected full spec/diff, safety attacks, static guidance/version checks,
and actual helper/Go smoke evidence. No resource command, cache rewrite, scope
expansion or manifest mismatch found. Integration proof remains direct CLI/Go;
optional adoption and host hook invocation are not established.

Follow-up RCR-04 (Minor): timeout while reaping a child could leave other owned
fixture processes alive. Added finally kill/reap and a real timeout regression;
this affects only test fixtures. A shared five-second lock deadline also matches
documented acquisition limits. Independent 36-test run, eight mutation attacks and
96 fresh-ledger concurrent operations passed before this harness-only addition.
Final independent run passed all 37 helper tests, nine mutation/corruption attacks
and 96 concurrent operations. Requirements/trace/scope, runtime proof, failure/
recovery, corruption/schema, ownership/identifiers, concurrency, containment/
privacy, performance bounds, compatibility, CI, rollback/release/version skew
and user guidance were scanned. No open production or harness finding remains.
