# Pipeline Evidence + Doc-Sync Hardening — Adversarial Review

**Phase:** design
**Artifact:** `docs/plans/2026-06-03-pipeline-evidence-doc-sync-design.md`
**Status:** FAIL → revised (see Resolution column); re-run pending

## Findings

| id | sev | class | loc | issue | resolution |
|---|---|---|---|---|---|
| D1 | Critical | Repo-precedent / Existence | D1 §Design | Two committed review files already exist (`2026-05-31-session-owned-lock-claims-design-review.md`/`-plan-review.md`) under convention `<stem>-design-review.md`/`<stem>-plan-review.md`. The invented `-adversarial-<phase>.md` name diverges; #69's "never written" premise overstated — practice exists ad-hoc but isn't skill-mandated, has no stable IDs, no guaranteed path. | Adopted existing `<stem>-design-review.md`/`<stem>-plan-review.md` naming. Reframed #69 as "systematize the ad-hoc practice + add stable IDs + mandate path so retro can glob reliably." |
| D2 | Critical | Missing failure mode | D2 §Design | Retro fix updated Step 5 process text but left the output-format template (retro SKILL.md:99 "Pull from `tests/skill-activation-audit.sh`") + the `**Reads:**` bullet pointing at the kit-local script — every future retro re-embeds the broken instruction. | D2 scope now explicitly updates retro SKILL.md:99 (format template) + the `**Reads:**` bullet + Step 5 together. |
| D3 | Important | Circular / dogfood framing | §Multi-Component Validation | Skill edits don't land until their task runs; during THIS feature's own pipeline the report is manually emulated, not skill-written. "First real artifacts of the new behavior" misleads. | Added explicit note: D1 behavior is manually emulated for this feature's own design/plan reviews until the skill-edit task lands; implementing agents must not assume the skill auto-commits before that task. |
| D4 | Important | Assumptions (A1) | D2 §Design | Retro reads phase from `args` of `skill` entries; the reviewer **subagent** is dispatched via Agent tool → `ev:"agent"` record has no `sk`/`args`/phase. Conflation risk. | Clarified: retro keys off `ev:"skill"` entries (the lead's `Skill` invocation carries `args:"--phase=…"`); the Agent-dispatched reviewer is a separate sub-record the retro ignores for phase. |
| D5 | Important | YAGNI | D1 §Stable IDs | `Resolution:` field as a per-revision-cycle mutable field adds maintenance with no consumer (retro Step 2 scores from downstream evidence, never reads it). | Reframed: `Resolution` is OPTIONAL, filled ONCE at end-state (commit SHA / `accepted — reason` / `false-positive`), and D2 now wires retro Step 2 to read it as a hint (falls back to downstream evidence) — giving it a real consumer at low maintenance. |
| D6 | Important | Trap / self-pass | D3 §Step 1e | Step 1e is pure judgment, no script, no exit-code, no halt path like Step 1d → can silently self-pass under autonomy (the exact "trap" the user flagged). | Narrowed trigger to "diff commits a design doc, README/reference doc, or example artifact" (rare/cheap) + require a visible one-line `Doc-reconciliation:` note in the PR body (concrete accountability token, no scanner — honors the user's LIGHT choice). |
| D7 | Minor | Repo-precedent | D1 | Existing 2 review files use no finding IDs (old `\| sev \| class \| loc \|` table); post-v6.4.0 corpus will be mixed-format. | Retro degrades gracefully: reads new ID format and pre-v6.4.0 reports (no IDs) alike. |
| D8 | Minor | Failure mode | D1 | Concurrent review writes (lead + manual) → last-write-wins on the report file. | Noted overwrite is safe only under sequential execution; no lock needed at this scale. |
| D9 | Minor | Precedent overlap | D4 §Design | New plan-phase "naming-convention match" row sits adjacent to existing `Config-validation schema rules` row → reader may conflate. | D4 row text now states it's distinct (this = human naming-convention consistency; that = tool-enforced schema invariants). |
| D10 | Minor | Infra | D1 | `tests/skill-cross-refs.sh` must resolve any new step references; should be an explicit plan task. | Plan will run `skill-cross-refs.sh` + `skill-content-grep.sh` as a verification task before PR. |

## Bug-Class Scan Transcript

| Class | Result | Note |
|---|---|---|
| Project-guidance conflicts | Clean | No `docs/design-guidance.md`; design acknowledges + inherits the user's "not too long/onerous" constraint. |
| Assumptions under attack | Finding (D4) | A1 live-confirmed; phase-disambiguation clarified for skill-vs-agent records. |
| Repo-precedent conflicts | Finding (D1, D7) | Existing `-design-review.md`/`-plan-review.md` convention adopted. |
| Artifact-class precedent | Finding (D1) | 2 prior committed review files surveyed; naming adopted. |
| YAGNI violations | Finding (D5) | `Resolution` reframed optional/end-state with a wired consumer. |
| Missing failure modes | Finding (D2, D8) | Retro format-template fix added; concurrent-write noted. |
| Security/privacy | Clean | Report holds design findings only; jsonl args truncated 80 chars; no PII. |
| Infrastructure impact | Clean (D10 minor) | No runtime impact; CI skill-checks added to plan. |
| Multi-component validation | Finding (D3) | Dogfood asymmetry flagged + D1↔D2 path-contract kept literally identical. |
| Rollback story | Clean | Revert-merge + re-tag; graceful-degrade covers report absence. |
| Simpler alternative | Clean | Heuristic doc-scanner explicitly rejected per user LIGHT choice. |
| User-intent drift | Finding (D6) | Step 1e tightened to avoid no-op gate; honors "no traps". |
| Existence / runtime-validity | Finding (D1, D2) | Existing report files + retro:99 template confirmed by `ls`/`sed`. |

## Options the author may not have considered
1. **Adopt existing naming convention** — taken (D1).
2. **Drop `Resolution` entirely** — partially taken: kept but reframed optional/end-state with a wired retro consumer, because the user explicitly wants reviews logged to ease retros across compaction; finding-IDs + an optional resolution hint serve that without per-cycle churn.
3. **Give Step 1e an output token** — taken (D6): visible PR-body `Doc-reconciliation:` line instead of a scanner.

**Verdict reasoning:** Two Criticals (false "never written" premise + naming divergence; incomplete retro fix leaving the broken template line) plus four Importants are all addressed in the revised design without adding a skill or a scanner. The revision adopts the repo's own convention, completes the retro fix, de-risks the Step 1e trap with a visible token, and reframes the only YAGNI surface (`Resolution`) to have a consumer. Re-run after revision to confirm convergence.
