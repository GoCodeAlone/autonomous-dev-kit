# Pipeline Evidence + Doc-Sync Hardening Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Fix autodev issues #69/#70/#71/#72 by systematizing the committed adversarial-review report, pointing the retro at the activation log the hook already writes, and adding one pre-PR doc-reconciliation gate + one plan-phase naming-convention check — with zero new skills/scripts and no heuristic scanner.

**Architecture:** Pure skill-markdown edits to 3 skills (`adversarial-design-review`, `post-merge-retrospective`, `finishing-a-development-branch`), guarded by one new grep-assertion regression test wired into the existing `skill-content-check.yml` CI, plus the standard 3-manifest v6.4.0 version bump. Reuses the existing `record-activity` PostToolUse hook (writes `.claude/autodev-state/in-progress.jsonl` in any repo) and the existing `<stem>-design-review.md`/`<stem>-plan-review.md` report convention.

**Tech Stack:** Bash (tests + hooks), Markdown (skills), GitHub Actions (CI), the kit's `scripts/bump-version.sh` + `tests/version-check.sh`.

**Base branch:** main

---

## Scope Manifest

**PR Count:** 1
**Tasks:** 7
**Estimated Lines of Change:** ~300 (skill markdown + 1 test + version bump)

**Out of scope:**
- Heuristic doc-content scanner that diffs every prose identifier against the manifest (#71 primary rec — rejected per user LIGHT choice; would be false-positive-prone bloat).
- New skills, new standalone scripts, or per-gate manual activation-append calls (the `record-activity` hook already covers Skill-invoked gates).
- Migrating the 2 pre-existing `2026-05-31-session-owned-lock-claims-*-review.md` files to the new finding-ID format (back-compat: retro reads both old + new shapes).
- Retro restructure beyond the two evidence sources (committed report + jsonl) and the one Step-1e missed-activation row.
- Changes to `tests/skill-activation-audit.sh` itself (it stays as a kit-dev convenience; only its *references in the retro* are demoted).

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | Pipeline evidence + doc-sync hardening (#69 #70 #71 #72) → v6.4.0 | Task 1, Task 2, Task 3, Task 4, Task 5, Task 6, Task 7 | feat/pipeline-evidence-doc-sync |

**Status:** Draft

---

### Task 1: Failing regression test for all four contracts

**Change class:** Hook/trigger-adjacent (grep-assertion test). Verification: the test itself (RED now, GREEN after Tasks 2–5).

**Files:**
- Create: `tests/pipeline-evidence-doc-sync.sh`

**Step 1: Write the failing test.** Create a bash test (mirroring the `pass()/fail()` + counter style of `tests/hook-contracts.sh`, non-zero exit on any fail) with these assertions against the repo's **skill** files (greps target `skills/…`, never `docs/plans/…`, so the plan's own design docs can't false-match). The assertions are written to be genuinely RED before Tasks 2–5 and GREEN after (plan-review P1: avoid substring matches that pass against pre-existing prose like "committed"):

```bash
#!/usr/bin/env bash
# tests/pipeline-evidence-doc-sync.sh
# Regression guard for issues #69/#70/#71/#72 (v6.4.0). Asserts the skill
# contracts these issues fixed remain present, so they cannot silently regress.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADR="$ROOT/skills/adversarial-design-review/SKILL.md"
RETRO="$ROOT/skills/post-merge-retrospective/SKILL.md"
FIN="$ROOT/skills/finishing-a-development-branch/SKILL.md"
fail=0
pass(){ printf 'PASS: %s\n' "$1"; }
bad(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
has(){ grep -qiF "$2" "$1"; }       # literal substring
hasE(){ grep -qiE "$2" "$1"; }      # regex

# --- #69 (D1): adversarial-design-review mandates committing the report ---
hasE "$ADR" '(-design-review\.md|-plan-review\.md)' \
  && pass "#69 ADR cites the <stem>-design-review.md/-plan-review.md convention" \
  || bad  "#69 ADR missing committed-report convention path"
# P1: assert the SPECIFIC new mandate wording, not the ambient word "commit"
has "$ADR" "Write AND commit the report" \
  && pass "#69 ADR mandates writing+committing the report" \
  || bad  "#69 ADR does not mandate writing+committing the report"
hasE "$ADR" 'stable finding ID|stable .*ID' \
  && pass "#69 ADR defines stable finding IDs" \
  || bad  "#69 ADR missing stable finding IDs"
# P4: guard the load-bearing D1<->D2 path contract — retro must cite the same derivation
hasE "$RETRO" 'same deterministic rule|-plan-review\.md' \
  && pass "#69/#70 retro derives the report path by the same rule (D1<->D2 contract)" \
  || bad  "#69/#70 retro missing the shared path-derivation rule"

# --- #70 (D2): retro reads the jsonl as PRIMARY; script demoted, NOT a hard dep ---
# P1: assert the jsonl is the PRIMARY source (only true after Task 4), not merely mentioned
hasE "$RETRO" 'primary source.*in-progress\.jsonl|in-progress\.jsonl.*primary' \
  && pass "#70 retro makes in-progress.jsonl the primary activation source" \
  || bad  "#70 retro does not promote in-progress.jsonl to primary"
# The format template must NOT instruct 'Pull from tests/skill-activation-audit.sh'
grep -qiE 'Pull from .*skill-activation-audit\.sh' "$RETRO" \
  && bad  "#70 retro STILL instructs 'Pull from tests/skill-activation-audit.sh' (line ~99 not demoted)" \
  || pass "#70 retro format template no longer hard-depends on the kit-local script"
has "$RETRO" "kit-dev" \
  && pass "#70 retro marks the audit script kit-dev-only" \
  || bad  "#70 retro does not demote the audit script to kit-dev-only"

# --- #71/#72 (D3): finishing has Step 1e in BOTH body and autonomous list ---
hasE "$FIN" 'Step 1e' \
  && pass "#71/#72 finishing has Step 1e body" \
  || bad  "#71/#72 finishing missing Step 1e body"
has "$FIN" "Doc-reconciliation" \
  && pass "#71/#72 finishing emits Doc-reconciliation token" \
  || bad  "#71/#72 finishing missing Doc-reconciliation accountability token"
# Step 1e must be referenced in the Autonomous Mode numbered list region (top of file, before '### Step 1:')
auto_region="$(awk '/^## Autonomous Mode/{f=1} /^### Step 1: Verify Tests/{f=0} f' "$FIN")"
printf '%s' "$auto_region" | grep -qiE 'Step 1e' \
  && pass "#71/#72 Step 1e wired into Autonomous Mode list" \
  || bad  "#71/#72 Step 1e NOT in Autonomous Mode list (would never fire autonomously)"

# --- #72 (D4): plan-phase naming-convention checklist row ---
hasE "$ADR" 'naming.convention match|Identifier / naming' \
  && pass "#72 ADR plan-phase has Identifier/naming-convention row" \
  || bad  "#72 ADR plan-phase missing naming-convention row"

echo ""; echo "Results: $fail failure(s)"; [ "$fail" -eq 0 ]
```

**Step 2: Run, verify it FAILS.** Run: `bash tests/pipeline-evidence-doc-sync.sh`
Expected: multiple `FAIL:` lines (skills not yet edited), final `Results: N failure(s)`, exit 1.

**Step 3: Commit the failing test.**
```bash
chmod +x tests/pipeline-evidence-doc-sync.sh
git add tests/pipeline-evidence-doc-sync.sh
git commit -m "test: regression guard for pipeline evidence + doc-sync (#69 #70 #71 #72) [red]"
```

---

### Task 2: D1 — adversarial-design-review mandates a committed findings report

**Change class:** Documentation/skill-content. Verification: Task-1 test #69 assertions pass + `skill-content-grep.sh` + `skill-cross-refs.sh` clean.

**Files:**
- Modify: `skills/adversarial-design-review/SKILL.md` (Process step 7; Report format header; "Dispatching the reviewer agent" output instruction; Integration "Writes" — add if absent)

**Step 1:** In **Process step 7** ("Write the report"), replace the inline-only instruction with the mandate to persist+commit, stating the **deterministic path rule** verbatim:
> 7. **Write AND commit the report.** Derive the path from the artifact filename: drop `.md`, then for `--phase=design` append `-review.md` (e.g. `…-doc-sync-design.md` → `…-doc-sync-design-review.md`); for `--phase=plan` append `-plan-review.md` (e.g. `2026-06-03-…-doc-sync.md` → `2026-06-03-…-doc-sync-plan-review.md`). This matches the existing `docs/plans/2026-05-31-session-owned-lock-claims-design-review.md` convention. The **lead** writes the report text the reviewer produced to that path and commits it alongside the artifact (the subagent has no git authority). Re-runs update the same single per-phase file (append a `## Cycle N` section across cycles); safe under sequential execution.

**Step 2:** In the **Report format**, keep the existing three `**Findings (Critical|Important|Minor):**` sections **unchanged in structure** (so the PASS/FAIL semantics and Dispatch "Required output" blocks that key off "Critical findings"/"Important findings" keep working verbatim — plan-review P6: no table conversion, no ripple). Add only: each finding bullet is **prefixed with a stable finding ID** and may carry an optional inline resolution. Update the format example lines to:
> **Findings (Critical):**
> - `D1` [class] [section/line]: <description>. Recommendation: <concrete fix>. _Resolution: <optional — filled once at end-state: commit SHA / `accepted — reason` / `false-positive`; omit if open>._
>
> Add a one-line note under the format: "Design-phase finding IDs are `D1, D2, …`; plan-phase `P1, P2, …`. IDs are the durable anchor `post-merge-retrospective` correlates against; the optional `Resolution` is a scoring hint (retro falls back to downstream evidence when omitted)." The literal phrase **"stable finding ID"** must appear (the Task-1 test asserts it).

(Keep the `Bug-class scan transcript`, `Options`, and `Verdict reasoning` sections, and the PASS/FAIL semantics section, unchanged.)

**Step 3:** In **"Dispatching the reviewer agent"** output instructions, add one line: the reviewer returns the report text; **the lead commits it to the derived path** (so the subagent isn't asked to do git).

**Step 4:** Add to **Integration** a `**Writes:**` line: `docs/plans/<artifact-stem>-design-review.md` / `-plan-review.md` (committed report).

**Step 5: Run the test slice.** Run: `bash tests/pipeline-evidence-doc-sync.sh`
Expected: the three `#69` assertions now `PASS:` (overall still failing until later tasks).

**Step 6: Commit.**
```bash
git add skills/adversarial-design-review/SKILL.md
git commit -m "feat(adversarial-review): mandate committed findings report w/ stable IDs (#69)"
```

---

### Task 3: D4 — plan-phase Identifier/naming-convention checklist row

**Change class:** Documentation/skill-content. Verification: Task-1 test `#72` ADR assertion passes + content-grep clean.

**Files:**
- Modify: `skills/adversarial-design-review/SKILL.md` ("Bug-class checklist — plan phase" table)

**Step 1:** Add one row to the plan-phase table (after `Config-validation schema rules`):
> \| **Identifier / naming-convention match** \| Config keys, flags, env vars, and command/code examples in the plan match the repo's established naming convention and the identifiers the code will actually use (grep the repo for the convention; a plan showing `snake_case` keys where the codebase uses `camelCase` = finding). **Distinct from `Config-validation schema rules`**, which checks tool-enforced schema invariants — this row checks human naming-convention consistency. Catches design-vs-code drift before code is written. \|

**Step 2: Run the test slice.** Run: `bash tests/pipeline-evidence-doc-sync.sh`
Expected: `#72 ADR plan-phase has Identifier/naming-convention row` → `PASS:`.

**Step 3: Commit.**
```bash
git add skills/adversarial-design-review/SKILL.md
git commit -m "feat(adversarial-review): plan-phase naming-convention checklist row (#72)"
```

---

### Task 4: D2 — retro reads committed report + activation jsonl (3 edit sites + token consumer)

**Change class:** Documentation/skill-content. Verification: Task-1 test `#70` assertions pass + content-grep clean. **This is the highest-care task — three edit sites + scalpel precision.**

**Files:**
- Modify: `skills/post-merge-retrospective/SKILL.md` (Step 2; Step 5; the `## Missed skill activations` format template ~line 99; the `**Reads:**` integration bullets ~line 159–160; add the Step-1e missed-activation row)

**Step 1 — Step 2 (score findings):** state that the report path is derived by the **same deterministic rule as D1** (drop `.md`; design→`+-review.md`, plan→`+-plan-review.md`); read each finding's stable ID; read the optional `resolution` column as a scoring hint, **falling back to downstream evidence (code-review threads, CI) when blank or when the report is an old no-ID format**. If the report is absent → "no committed review report; reconstructed from revision history" (the explicit fallback; note most pre-v6.4.0 features have none).

**Step 2 — Step 5 (score activations):** make `.claude/autodev-state/in-progress.jsonl` the **primary** source (written by `record-activity` in any repo); read phase from the `args` field of **`ev:"skill"`** entries (the Agent-dispatched reviewer's `ev:"agent"` record has no phase — ignore it for phase). Demote `tests/skill-activation-audit.sh` to "(kit-dev convenience; absent in consumer repos)". If the jsonl is absent → "activation log unavailable" rows, **never** "script does not exist".

**Step 3 — format template (`## Missed skill activations`, ~line 99):** change `Pull from \`tests/skill-activation-audit.sh\`.` to read from `.claude/autodev-state/in-progress.jsonl` (the audit script noted as kit-dev-only). Add one row to that table's example: `| finishing Step 1e (doc-reconciliation) | yes/unverified | only when the diff touched docs/examples |`.

**Step 4 — Step-1e token consumer (D2/N3):** add a sentence to Step 5 (or the Missed-activations section): "When the merged PR's diff touched docs/examples, record `finishing Step 1e` as fired iff a `Doc-reconciliation:` line is present in the PR body, else `unverified`. If the diff touched no docs/examples, record no row (Step 1e legitimately did not fire)." *(precondition resolves cycle-3 M1.)*

**Step 5 — Reads bullets (~line 159–160, SCALPEL):** keep the `.claude/autodev-state/in-progress.jsonl (if present)` line as-is; on the `tests/skill-activation-audit.sh (this repo)` line, change to `tests/skill-activation-audit.sh (kit-dev convenience; absent in consumer repos)`. Also update the line-156 `docs/plans/ (design, plan, adversarial-review reports)` to note reports are now committed by `adversarial-design-review` per the deterministic path.

**Step 6: Run the test slice.** Run: `bash tests/pipeline-evidence-doc-sync.sh`
Expected: all three `#70` assertions `PASS:` (incl. the negative assertion that "Pull from …skill-activation-audit.sh" is gone).

**Step 7: Commit.**
```bash
git add skills/post-merge-retrospective/SKILL.md
git commit -m "feat(retro): read committed report + activation jsonl; demote kit-local script (#70)"
```

---

### Task 5: D3 — finishing-a-development-branch Step 1e (doc-reconciliation gate)

**Change class:** Documentation/skill-content. Verification: Task-1 test `#71/#72` finishing assertions pass + content-grep clean. **Two edit sites: the Step body AND the Autonomous Mode list.**

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md` (Autonomous Mode numbered list ~line 23; new `### Step 1e` after the Step 1d section ~line 157; the `Continue to Step 1d`/`continue to Step 2` transition pointers)

**Step 1 — Autonomous Mode list (~line 23):** after the existing "Run Step 1d (Scope Completeness Check)" item, insert: "Run Step 1e (Doc-Reconciliation Check) — conditional on the diff containing a design/reference doc or example artifact." (Renumber the following list items.)

**Step 2 — new `### Step 1e: Doc-Reconciliation Check`** (after the Step 1d section, before `### Step 2`):
> **Trigger:** the PR's diff commits a design doc, reference/standards doc, or example artifact that describes the feature's behavior. Skip for code-only / test-only diffs. (A doc with no corresponding `docs/plans/` design/plan trivially passes `clean`.)
>
> For each such committed doc/example, verify:
> - **(a) Scope (forward-ref, #71):** every behavior/identifier it describes is in *this PR's* manifest scope, OR explicitly labeled `Planned (PR #N)` / `Planned — later PR`. Unlabeled forward references = finding → label them or move the prose to the later PR.
> - **(b) Identifier drift (#72):** concrete identifiers (config keys, flags, env vars, command invocations, DDL/code snippets, format strings) match the identifiers the code on this branch actually uses + the repo's naming convention. Mismatch = finding → reconcile the doc to the built code.
>
> This is a checklist gate (read the diff, grep identifiers), **not** an automated scanner. On a finding in autonomous mode, fix the doc in-branch before PR (in-scope doc edit, no manifest change). Distinct from `scope-lock`'s assumption-backport (which is for *disproved assumptions*) — this is routine accuracy reconciliation.
>
> **Accountability token:** emit one line into the PR body — `Doc-reconciliation: clean` or `Doc-reconciliation: N item(s) fixed — <summary>` — so pr-monitoring, the human reviewer, and `post-merge-retrospective` (Step 5 missed-activation row) can confirm the gate ran without a script.

**Step 3 — transition pointers:** ensure the Step 1d section ends pointing to Step 1e, and Step 1e ends pointing to Step 2 (Determine Base Branch). Update the line-157 "Do not proceed past Step 1d …" wording only if it implies 1d is the last sub-step.

**Step 4: Run the test slice.** Run: `bash tests/pipeline-evidence-doc-sync.sh`
Expected: all `#71/#72` finishing assertions `PASS:` (incl. the Autonomous-Mode-region check).

**Step 5: Commit.**
```bash
git add skills/finishing-a-development-branch/SKILL.md
git commit -m "feat(finishing): Step 1e doc-reconciliation gate, body + autonomous list (#71 #72)"
```

---

### Task 6: Wire the regression test into CI + full local verification

**Change class:** Hook/trigger (CI) + verification. Verification: the new test GREEN; `skill-content-grep.sh` clean; `skill-cross-refs.sh` clean; YAML valid.

**Files:**
- Modify: `.github/workflows/skill-content-check.yml` (add a step running the new test + add it to the `paths` filters)

**Step 1:** In `skill-content-check.yml`, add `tests/pipeline-evidence-doc-sync.sh` **and** `tests/skill-cross-refs.sh` to both `push.paths` and `pull_request.paths`, and add two steps after the existing content-grep step (plan-review P2: `skill-cross-refs.sh` already exists but was local-only — wire it into CI for free while the workflow is open):
```yaml
      - name: Pipeline evidence + doc-sync contracts
        run: bash tests/pipeline-evidence-doc-sync.sh
      - name: Skill cross-references resolve
        run: bash tests/skill-cross-refs.sh
```
*(If `skill-cross-refs.sh` surfaces a pre-existing unresolved reference unrelated to this PR, do not expand scope to fix unrelated skills — instead keep it local-only for this PR and note the pre-existing failure in the PR body. Only wire it into CI if it passes clean on the current tree.)*

**Step 2: Run the FULL local gate** (all must be green now that Tasks 2–5 landed):
```bash
bash tests/pipeline-evidence-doc-sync.sh   # Expected: Results: 0 failure(s), exit 0
bash tests/skill-content-grep.sh           # Expected: exit 0 (no host-token leaks in edited skills)
bash tests/skill-cross-refs.sh             # Expected: exit 0 (new step/path references resolve)
```
Expected: all three exit 0. *(Resolves design D10.)* If `skill-content-grep.sh` flags a host-token in any edited skill, move that token inside a `<host: …>` block.

**Step 3: Commit.**
```bash
git add .github/workflows/skill-content-check.yml
git commit -m "ci: run pipeline-evidence-doc-sync contract test on skill changes"
```

---

### Task 7: Version bump → v6.4.0

**Change class:** Version pin (runtime-affecting — release). Verification: `tests/version-check.sh` green (3 manifests agree). **Rollback: revert the merge commit + re-tag the prior version (v6.3.1); no data/migration to unwind.**

**Files:**
- Modify (via script): `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.cursor-plugin/plugin.json`

**Step 1:** Run the bump script:
```bash
bash scripts/bump-version.sh 6.4.0
```

**Step 2: Verify the 3 manifests agree.** Run: `bash tests/version-check.sh`
Expected: exit 0 (all three manifests report `6.4.0`).

**Step 3: Confirm no stray version mismatch.** Run: `grep -rn '"version"' .claude-plugin/plugin.json .claude-plugin/marketplace.json .cursor-plugin/plugin.json`
Expected: each shows `6.4.0`.

**Step 4: Commit.**
```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .cursor-plugin/plugin.json
git commit -m "chore(release): bump to v6.4.0 (#69 #70 #71 #72)"
```

*(Pushing this commit to `main` triggers `release-tag.yml`, which tags `v6.4.0` after `version-check.sh` passes. The GH Release is created manually post-merge per the kit's convention.)*

---

## Verification Summary (whole-PR)

Before PR creation, all green:
- `bash tests/pipeline-evidence-doc-sync.sh` → `Results: 0 failure(s)`
- `bash tests/skill-content-grep.sh` → exit 0
- `bash tests/skill-cross-refs.sh` → exit 0
- `bash tests/version-check.sh` → exit 0
- Step 1e self-check on THIS PR: it commits design/plan/review docs → emit `Doc-reconciliation: …` in the PR body (dogfood the new gate).

## Rollback (whole-PR)

All edits are skill-markdown + one test + a version bump. Rollback = `git revert` the squash-merge commit + re-tag `v6.3.1` as latest. The committed-report path is additive (reverting just stops writing it; the retro's graceful-degrade covers absence). No runtime state, migrations, or external resources involved.
