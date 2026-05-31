# Existence / Runtime-Validity Bug-Class Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Add one "Existence / runtime-validity" bug-class row to the design-phase checklist of `adversarial-design-review`, then release as v6.2.2.

**Architecture:** Single additive table row in `skills/adversarial-design-review/SKILL.md` (design-phase table, inherited by the plan phase via `SKILL.md:101`). Version bump across the three manifests + RELEASE-NOTES entry. Merge to main auto-triggers `release-tag.yml`.

**Tech Stack:** Markdown skill files; bash test scripts (`tests/version-check.sh`, `tests/skill-content-grep.sh`); GitHub Actions release-tag workflow.

**Base branch:** main

---

## Scope Manifest

**PR Count:** 1
**Tasks:** 3
**Estimated Lines of Change:** ~20 (informational; not enforced)

**Out of scope:**
- A second row in the plan-phase table (design rejected this — one row, inherited).
- Any new report-format field, `## section`, or worked-example subsection in the skill.
- Changes to any other skill (`demonstration-fidelity` already covers the downstream faked-demo case).
- Any code/behavior change — this is documentation + a version bump only.

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | feat: add Existence/runtime-validity bug-class to adversarial-design-review (#55) | Task 1, Task 2, Task 3 | feat/existence-runtime-validity-bugclass-55 |

**Status:** Draft

---

## Project Design Guidance

`Guidance: none at docs/design-guidance.md; canon = README §Cross-LLM + docs/plans/2026-04-25-cross-llm-portability-design.md.` Guidance → work mapping:
- Host-neutral / cross-LLM → the row is pure SKILL.md prose, no host-specific token (verified by `tests/skill-content-grep.sh` in Task 1).
- Checklist is the floor → the row joins the mandatory-scan set; no opt-out.
- Ground classes in concrete invariants → row cites the two real retro misses verbatim.

---

### Task 1: Add the bug-class row to the design-phase checklist

**Files:**
- Modify: `skills/adversarial-design-review/SKILL.md` (insert after the `User-intent drift` row at line ~97 — the LAST design-phase row — and before the blank line at ~line 98 that precedes the `## Bug-class checklist — plan phase` heading; do not collapse that blank separator)

**Step 1: Verify the inheritance line the approach depends on still exists + record the baseline class-row count**

Run: `grep -n "plan-phase reviewer scans the design-phase classes above" skills/adversarial-design-review/SKILL.md`
Expected: one match at ~line 101 (confirms the new row is scanned in both phases without a second edit). If absent → STOP, the design's A1 assumption is broken.

Run: `grep -c "^| \*\*" skills/adversarial-design-review/SKILL.md`
Expected: `19` (11 design-phase + 8 plan-phase class rows; table headers use `| Class | Definition |` and do NOT match `^| \*\*`). Record this baseline for Step 3.

**Step 2: Insert the row**

Insert this exact line as the last row of the **design-phase** table (after `| **User-intent drift** | ... |`, before the blank line preceding `## Bug-class checklist — plan phase`):

```
| **Existence / runtime-validity** | For a design/plan that touches an artifact another tool/contract consumes (registry manifest, plugin release, CI workflow step, API endpoint, config a tool reads): (a) for any artifact it *edits but did not create*, does it verify the artifact **exists** before the plan mutates it — an `ls`/`gh` at design time (e.g. confirm a target plugin has a `workflow-registry` manifest before editing it; a missing one forced a mid-execution amendment in the required_secrets sweep)? (b) for any artifact it *emits*, does it verify the emitted call targets a **real** consumer surface — e.g. confirm `wfctl ci run --phase migrate` is an actual subcommand/phase (it is not) by checking `wfctl help`/the consumer schema/a dry-run, rather than assuming the generated content merely parses (you confirm the consumer command/schema exists, not that you pre-run output that may not exist yet)? Flag any design that asserts content correctness without the matching existence/behavior check. If the design neither edits an existing consumed artifact nor emits one a consumer must accept, mark **Clean**. Cheap to satisfy (usually one `ls`/`gh`/dry-run); complements `demonstration-fidelity` by pushing the check upstream into design/plan. |
```

**Step 3: Verify the table still parses + the row is in the design-phase table**

Run: `awk '/## Bug-class checklist — design phase/{d=1} /## Bug-class checklist — plan phase/{d=0} d && /Existence . runtime-validity/{print NR": "$0}' skills/adversarial-design-review/SKILL.md`
Expected: one line printed (the new row), proving it sits inside the design-phase section, not the plan-phase one.

Run: `grep -c "^| \*\*" skills/adversarial-design-review/SKILL.md`
Expected: `20` (the Step 1 baseline of 19 + exactly 1; zero header rows match this pattern). Confirm the single added row with `git diff --stat`.

**Step 4: Skill-content lint (no forbidden host tokens)**

Run: `bash tests/skill-content-grep.sh 2>&1 | tail -5`
Expected: exit 0 / no forbidden-token failure for `adversarial-design-review/SKILL.md`. (Documentation change class — lint is the verification; this script is the repo's skill gate.)

**Step 5: Commit**

```bash
git add skills/adversarial-design-review/SKILL.md
git commit -m "feat(adversarial-design-review): add Existence/runtime-validity bug-class (#55)"
```

Rollback: revert this commit — the row is purely additive prose, no migration.

---

### Task 2: Add the RELEASE-NOTES.md entry

**Files:**
- Modify: `RELEASE-NOTES.md` (insert a new `## v6.2.2 — 2026-05-31` section directly below the `# Autonomous Dev Kit Release Notes` title, above the existing `## v6.2.1` section)

**Step 1: Insert the entry**

Insert directly after the title line (`# Autonomous Dev Kit Release Notes`) and its blank line, before `## v6.2.1 — 2026-05-31`:

```markdown
## v6.2.2 — 2026-05-31

New **Existence / runtime-validity** bug-class in `adversarial-design-review`
(design-phase checklist, inherited by the plan phase), closing a 2-retro gap
where a review verified an artifact's intended content but never that the
artifact **exists** or **runs** as the design assumed (issue #55).

- `skills/adversarial-design-review/SKILL.md`: one new design-phase row. (a) For
  any artifact a design *edits but did not create*, require an `ls`/`gh`
  existence check before mutation (the required_secrets sweep hit a missing
  `workflow-registry` manifest at execution). (b) For any artifact a design
  *emits*, require verifying the consumer surface is real (the smart-CI gen
  emitted `wfctl ci run --phase migrate`, no such phase). Explicit `Clean`
  escape hatch for designs that neither edit nor emit a consumed artifact.
  Complements `demonstration-fidelity` by pushing the check upstream.
```

**Step 2: Verify no broken markdown anchors / structure**

Run: `grep -n "^## v6.2.2" RELEASE-NOTES.md && grep -n "^## v6.2.1" RELEASE-NOTES.md`
Expected: v6.2.2 line number < v6.2.1 line number (new entry is on top).

**Step 3: Commit**

```bash
git add RELEASE-NOTES.md
git commit -m "docs: release notes for v6.2.2 (#55)"
```

Rollback: revert this commit.

---

### Task 3: Version bump to 6.2.2 + consistency check

**Files:**
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.cursor-plugin/plugin.json` (all via the script)

**Step 1: Confirm starting version + that the target tag does not already exist**

Run: `grep '"version"' .claude-plugin/plugin.json | head -1; git ls-remote --tags origin refs/tags/v6.2.2`
Expected: version is `6.2.1`; the `git ls-remote` prints nothing (no `v6.2.2` tag yet). If `v6.2.2` exists → STOP and pick the next patch.

**Step 2: Run the bump script**

Run: `scripts/bump-version.sh 6.2.2`
Expected: `Bumping version: 6.2.1 → 6.2.2` and success across all three manifests.

**Step 3: Verify all manifests agree (this is the exact gate `release-tag.yml` runs)**

Run: `bash tests/version-check.sh`
Expected: `OK: All version files agree on version 6.2.2`

**Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .cursor-plugin/plugin.json
git commit -m "chore: bump version to 6.2.2 (#55)"
```

Rollback: `scripts/bump-version.sh 6.2.2 6.2.1` + revert commit; since the release tag is created only on merge-to-main, a pre-merge revert prevents the tag entirely.

---

## Verification summary (change-class mapping)

| Task | Change class | Verification | Expected |
|---|---|---|---|
| 1 | Documentation (skill prose) | `tests/skill-content-grep.sh` + awk section-scope check + `grep -c` count = 20 | exit 0; row inside design-phase table; count 19→20 |
| 2 | Documentation | markdown anchor/order grep | v6.2.2 above v6.2.1 |
| 3 | Version pin (manifests) | tag-uniqueness pre-check (`git ls-remote ... v6.2.2` empty, Task 3 Step 1) + `tests/version-check.sh` | no existing tag; all three agree on 6.2.2 |

No runtime/build/deploy/migration/plugin-loading change → no `runtime-launch-validation` task required (none of the `finishing-a-development-branch` Step 1b triggers are met by a markdown + manifest-string change). The version bump is a manifest *string* change consumed only by `release-tag.yml`, whose own gate (`version-check.sh`) is run in Task 3.

## Multi-Component / Integration proof

The two "components" are the two reviewer invocations. The inheritance path (design-phase row → scanned in plan phase) is asserted by Task 1 Step 1 (grep for `SKILL.md:101`) + Step 3 (awk proves the row is in the design-phase section). The release "boundary" (manifests → `release-tag.yml`) is proven by Task 3 Step 3 running the identical `version-check.sh` the workflow runs.
