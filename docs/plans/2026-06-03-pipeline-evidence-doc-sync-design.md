# Pipeline Evidence + Doc-Sync Hardening — Design

**Date:** 2026-06-03
**Issues:** #69, #70, #71, #72 (all GoCodeAlone/autonomous-dev-kit)
**Target release:** v6.4.0
**Author:** autonomous pipeline (brainstorming)

## Problem

Four issues, two themes, one root: the pipeline emits design/plan/review artifacts but the
*connective tissue* between them is weak or fictional.

**Theme A — retro evidence is broken:**
- **#69:** `post-merge-retrospective` reads "adversarial-review reports committed in `docs/plans/`"
  (SKILL.md:22, :33, :156). But `adversarial-design-review` only emits its report **inline**
  (step 7 "Write the report" + the Dispatch subagent returns text). The committed file the retro
  depends on is **never written** → phantom dependency. Every retro reconstructs findings from
  revision notes/PR threads. Worsens under long/compacted context (transcript lost).
- **#70:** retro tells the agent to run `tests/skill-activation-audit.sh` *"(this repo)"* — a
  **kit-dev-only** script absent in consumer repos → "Missed skill activations" table is "script
  does not exist" every time. Meanwhile the `record-activity` PostToolUse hook (shipped:
  `hooks/hooks.json:53`, `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd record-activity`) **already**
  appends every Skill activation to `<cwd>/.claude/autodev-state/in-progress.jsonl` in **any**
  repo. The retro just isn't pointed at it.

**Theme B — committed docs drift from reality:**
- **#71:** in split-PR features, PR-1 commits docs/examples describing the **full** feature
  (endpoints/helpers/metrics that ship in later PRs). `alignment-check`/`scope-lock` trace
  task/PR manifest, not committed **doc content** → forward-references slip to human review.
- **#72:** during in-scope execution, identifiers get convention-conforming refinements (config
  key snake→camel, example snippet changes). Not a disproved assumption (so scope-lock's backport
  path never triggers), not a manifest change → nothing reconciles the design doc with built code.
  Design ships stale-on-arrival; reviewers burn cycles on doc-vs-code drift.

## Goals / Non-goals

**G1:** adversarial-design-review commits a durable, scannable findings report with stable
  finding IDs (#69).
**G2:** retro scores findings from that committed report, and scores activations from the
  `in-progress.jsonl` the hook already writes — degrading gracefully, not pointing at a kit-local
  script (#70).
**G3:** a single pre-PR doc-reconciliation gate catches both forward-references (#71) and
  identifier drift (#72) in committed docs/examples.
**G4:** plan-phase adversarial review gains one checklist row: plan identifiers/examples match
  implemented identifiers + repo naming convention (#72, catch-before-code).

**Non-goals (YAGNI):**
- No heuristic doc-content scanner that diffs every identifier in prose against the manifest
  (issue #71's *primary* rec). Rejected: false-positive-prone, unbounded, the "onerous/trap"
  class the user explicitly warned against. We take #71's own lighter fallback (explicit labeling
  + identifier match).
- No new skill. No new test script. No per-gate manual activation-append (the hook covers
  Skill-invoked gates; manual appends would be redundant bloat).
- No retro restructure beyond the two evidence sources.

## Design

### D1 — Committed adversarial-review report (#69, G1)

`adversarial-design-review` step 7 + Dispatch + Report-format change:
- After producing the report, **write it to `docs/plans/<artifact-stem>-adversarial-<phase>.md`**
  (e.g. design `…-pipeline-evidence-doc-sync-design.md` → report
  `…-pipeline-evidence-doc-sync-adversarial-design.md`; plan stem → `-adversarial-plan.md`) and
  **commit it alongside** the artifact. The Dispatch subagent still produces the report text; the
  lead writes+commits the returned text to the path.
- **Stable finding IDs:** design-phase findings `D1, D2, …`; plan-phase `P1, P2, …`. Each finding
  line is prefixed with its ID.
- New per-finding **`Resolution:`** field, initially `pending`. Filled during the revision loop /
  execution with: a commit SHA, `accepted — <reason>`, or `false-positive`. This is what lets the
  retro auto-correlate a finding to what resolved it.
- Idempotent across revision cycles: re-running the review on a revised artifact **overwrites**
  the same report file (latest state), not appends a new file per cycle.

### D2 — Retro reads committed report + activation jsonl (#70, G2)

`post-merge-retrospective`:
- Step 2 (score findings): read the committed `…-adversarial-<phase>.md` report(s). If absent
  (ad-hoc PR or pre-v6.4.0 branch), state "no committed adversarial report; reconstructed from
  revision history" — i.e. the *current* behavior becomes the explicit fallback, not the default.
- Step 5 (score activations): **primary source = `.claude/autodev-state/in-progress.jsonl`**
  (written by `record-activity` in any repo). Cross-check `--phase=design|plan` via the `args`
  field of `skill` entries. `tests/skill-activation-audit.sh` demoted to "(kit-dev convenience;
  not present in consumer repos)". If the jsonl is absent → emit "activation log unavailable" rows,
  **never** "script does not exist".
- Integration "Reads" list updated to match.

### D3 — Pre-PR doc-reconciliation gate (#71 + #72a, G3)

`finishing-a-development-branch` new **Step 1e: Doc-Reconciliation Check** (after 1d Scope
Completeness, before Step 2). Triggers when the PR commits any design doc, README, reference doc,
or example artifact. The agent verifies, for committed docs/examples in this PR:
- **(a) Scope (forward-ref, #71):** every behavior/identifier described is either in *this PR's*
  manifest scope, OR explicitly labeled `Planned (PR #N)` / `Planned — later PR`. Unlabeled
  forward references = finding → label them or move the prose to the later PR.
- **(b) Identifier drift (#72):** concrete identifiers in the design doc / examples — config keys,
  flags, env vars, command invocations, DDL/code snippets, format strings — match the identifiers
  the code on this branch actually uses (and the repo's naming convention). Mismatch = finding →
  reconcile the doc to the built code.
- Checklist gate (agent reads the diff + greps identifiers), **not** an automated scanner. On a
  finding in autonomous mode: fix the doc in-branch before PR (in-scope doc edit, no manifest
  change). This is distinct from scope-lock's assumption-backport (disproved assumptions) — this
  is routine accuracy reconciliation.

### D4 — Plan-phase naming-convention checklist row (#72b, G4)

`adversarial-design-review` plan-phase bug-class checklist gains one row:
**Identifier / naming-convention match** — "config keys, flags, env vars, and command/code
examples in the plan match the repo's established naming convention and the identifiers the code
will actually use (grep the repo for the convention; a plan showing `snake_case` keys where the
codebase uses `camelCase` = finding)." Catches the drift in D3(b) **before a line of code is
written**, which is cheaper than reconciling after.

## Global Design Guidance

No `docs/design-guidance.md` in this repo (checked). The kit's durable guidance lives in the
skills themselves. Relevant inherited principles: skills must stay tight (user constraint:
"not too long or onerous"); no circular logic / phantom dependencies (#69 *is* one — fixing it
reduces circularity); reuse existing machinery over adding new (hooks, report format, audit
script all pre-exist).

## Security Review

Low surface. All changes are skill-markdown instruction edits + one committed-report file path.
- The committed adversarial report lives in `docs/plans/` (already-committed-artifact territory);
  no secrets — it summarizes design findings. Reviewer must not paste secrets into findings (same
  discipline as existing design docs).
- Reading `.claude/autodev-state/in-progress.jsonl`: local file, no network, no PII beyond skill
  names + truncated args (hook already truncates args to 80 chars). No new exposure.
- No auth/authz, no external calls, no new dependencies.

## Infrastructure Impact

None at runtime. No build/deploy/k8s/migration changes. The only "infra" touchpoint: v6.4.0
release bumps the 3 version manifests (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`,
`.cursor-plugin/plugin.json`) → `release-tag.yml` auto-tags on push to main. Standard kit release
path, unchanged.

## Multi-Component Validation

The cross-component boundary here is **skill → hook → state-file → retro**:
- D2 depends on `record-activity` writing `in-progress.jsonl`. **Verified live**: this session's
  own `brainstorming` invocation produced `{"ts":"2026-06-03T16:31:07Z","ev":"skill",
  "sk":"autodev:brainstorming"}` in the kit repo's state file, and the hook is plugin-level
  (`hooks/hooks.json:53`) so it fires in consumer repos too.
- D1↔D2 contract: the report path written by adversarial-design-review (D1) is the exact path the
  retro reads (D2). Plan must keep these literally identical (one source constant in prose).
- `tests/skill-cross-refs.sh` and `tests/skill-content-grep.sh` are the kit's own CI gates over
  skill markdown — all skill edits must keep cross-references resolvable and host-tokens inside
  `<host:>` blocks. The plan includes running both before PR.
- **Dogfood:** this very feature runs through the pipeline, so D1 (committed report) is exercised
  on its own design + plan adversarial reviews — the first real artifacts of the new behavior.

## Assumptions

- **A1:** `record-activity` fires in consumer repos (plugin-level PostToolUse hook). *Evidence:*
  `hooks/hooks.json:53` + live entry this session. **Load-bearing for D2.**
- **A2:** Skill-invoked gates are what the retro needs to score; gates invoked as non-Skill
  sub-steps (rare) not appearing in the jsonl is acceptable (graceful-degrade covers it).
- **A3:** The adversarial Dispatch subagent can return report text the lead commits; the lead
  (not the subagent) owns the git write. *Matches existing Dispatch pattern.*
- **A4:** Writing one report file per phase per feature (overwritten across revision cycles) is
  acceptable repo noise — same order as the design/plan docs already committed.
- **A5:** A checklist-style Step 1e (human/agent judgment over the diff) catches the doc drift
  classes without a scanner. *If false* (agent skips it), the human reviewer remains the backstop —
  same as today, so no regression.

## Rollback

Change class: skill-content + plugin version bump (release-affecting). Rollback = revert the merge
commit + re-tag prior version. No data/migration/runtime state to unwind. The committed-report
path is additive; reverting simply stops writing it (retro's graceful-degrade handles its absence).
Per-task rollback notes in the plan for the version-bump task.

## Self-challenge (top doubts surfaced)

1. **Is D1 adding bloat to an already-335-line skill?** Net +~18 lines to adversarial-design-review,
   but it makes an existing *fictional* contract real and removes the retro's reconstruction burden.
   The report *format* already exists — we add a path + IDs + a Resolution field, not a new section.
2. **Could D3's Step 1e become a rubber-stamp the agent skips?** Possibly — it's judgment, not a
   script. Mitigation: it's gated in autonomous mode (like 1d) and scoped to *only fire when docs/
   examples are in the diff*, so it's cheap and skippable-only-when-irrelevant. The plan-phase row
   (D4) is the earlier, cheaper catch; 1e is the safety net.
3. **Does pointing retro at `in-progress.jsonl` over-trust a best-effort hook?** The hook is
   best-effort (jq-absent / no-stdin → no-op). D2 degrades gracefully on absence, so worst case is
   "activation log unavailable" — strictly better than today's "script does not exist".
