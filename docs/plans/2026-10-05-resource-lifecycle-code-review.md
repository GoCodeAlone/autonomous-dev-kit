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
