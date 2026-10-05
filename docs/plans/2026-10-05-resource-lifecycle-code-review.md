# Resource lifecycle independent code review

Initial verdict BLOCK; exact final-head recheck pending.

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
