# Resource lifecycle design and plan review

Independent read-only adversarial reviewer; initial design FAIL, plan FAIL,
structural alignment PASS. No Critical findings; all inherited design and plan
bug classes scanned. No source/config/session changes by reviewer.

| ID | Phase | Severity | Finding | Author response |
|---|---|---|---|---|
| D1 | design | Important | Exact-resource protection omitted overlapping parents/children. | Suppress protected path overlaps; inspect ancestor/descendant worktree markers, reject ambiguous/budget-exceeded trees. |
| D2 | design | Important | Check/write races and replaceable lock inode could lose ownership. | Separate stable lock, no-follow descriptor-relative operations, parent/lock identity validation and explicit same-user race boundary. |
| D3 | design | Minor | Same cache path does not establish reuse. | Verify effective cache unchanged and second unchanged build avoids package compilation. |
| P1 | plan | Important | Overlap regressions unspecified. | Add protected/reusable/database parent/child and nested/ancestor worktree cases with preservation. |
| P2 | plan | Important | Generic races could miss critical interleavings. | Deterministic directory/lock swap barriers; competing writers across JSON replacements, stable lock and no lost owners. |
| P3 | plan | Minor | Verification commands/results underspecified. | Exact unittest/compile/doc/CLI lifecycle and real Go reuse assertions added. |
| P4 | plan | Minor | Unauthorized wording could imply authentication. | Cross-session attribution rejection; explicit non-authentication limitation. |

Scan: project guidance, assumptions, precedent, artifact class, YAGNI, failure
modes, security/privacy, infrastructure, multi-component/declared proof, UI,
rollback, simpler alternative, user intent and runtime validity. Additional plan
scan: decomposition, verification class, auth chains, dependencies, rollback/
integration wiring, matrix/UI routes, infrastructure, loader layout, schema,
identifiers and compile validity. Findings above cover all non-clean results.

Alternative: retain optional guidance/ledger with conservative overlap and stable
descriptor lock contract. Adoption remains voluntary; no bounded-disk guarantee.
Forward/reverse trace R1→Task2, R2/R3/R4→Task1, R5→Tasks3/4 is structural PASS.

Cycle 2: design PASS, plan PASS, alignment PASS; no open Important/Critical
findings. D4 (Minor) clarified ancestor inspection stops before the project root;
the author added the boundary and will test an ordinary Git project's candidate.
All D1-D4/P1-P4 findings are resolved or assigned to the existing regression task.
