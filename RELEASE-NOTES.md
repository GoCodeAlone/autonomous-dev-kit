# Autonomous Dev Kit Release Notes

## v6.5.5 — 2026-06-22

Projects-layer alignment: the `project-design-guidance` skill now also consults the projects tracker (`docs/PROJECTS.md`) for current initiative focus + phase.

- `project-design-guidance`: before designing, consult `docs/PROJECTS.md` (if present) to confirm the work advances an active project's stated `next` step; record the project + phase in the design so effort stays aligned with what the operator is driving (vs. orphan work on a stale/on-hold initiative). Companion to the portfolio-catalog consult added in v6.5.4.

## v6.5.4 — 2026-06-22

Portfolio-system alignment: a new once-per-compaction reminder hook + skill consult keep agents from rebuilding existing tooling.

- `hooks/portfolio-inventory-reminder` (new `UserPromptSubmit` hook): nags once per compaction window to consult the portfolio tooling inventory before building; mirrors `pretool-pr-review-reminder` (session-key = `basename transcript_path`; marker `portfolio-inventory-seen`; cleared by `pre-compact-snapshot` line-filter-rewrite). Lifecycle covered by `tests/hook-contracts.sh`.
- `project-design-guidance`: consult the portfolio catalog's tooling-inventory section (`docs/PORTFOLIO.md`) before building to avoid rebuilding existing plugin/tool capability; record surfaced follow-ups in `docs/FOLLOWUPS.md`.

## v6.5.3 — 2026-06-21

Declared integration proof hardening for issue #79.

- `runtime-launch-validation`: adds a host-agnostic "Declared integration /
  extension" change class. Any manifest/config/lockfile/dependency/deployment
  claim that an integration is installed, enabled, or used now requires an
  integration matrix and launched host/consumer proof unless explicitly marked
  `config-only` or `deferred`.
- `verification-before-completion`: adds a claim-matrix row and proof pattern
  for declared integrations, including stateful reload/persistence checks and
  authz negative paths where relevant.
- `adversarial-design-review`, `writing-plans`, and `requesting-code-review`:
  require plans and reviews to catch install-only/config-only integration claims
  that never prove the real consumer discovers and exercises the integration.
- `tests/pipeline-evidence-doc-sync.sh`: adds regression assertions so the
  issue #79 integration-proof contract cannot silently regress.

## v6.5.2 — 2026-06-20

PR metadata secret-hygiene hardening after a live GitHub token was pasted into a
merged PR body verification command.

- `finishing-a-development-branch`: adds an always-on PR body secret hygiene
  gate before PR creation/update. Verification transcripts must redact tokens,
  API keys, cookies, passwords, and bearer credentials; already-published
  secrets require metadata redaction and operator revocation.
- `verification-before-completion`: adds a `PR body ready` claim requiring final
  Markdown/tempfile inspection for live secrets before publishing.
- `tests/no-machine-paths.sh`: broadens artifact hygiene checks to reject live
  GitHub token patterns and inline secret assignments in committed docs,
  decisions, skills, and agents, while allowing placeholders and GitHub
  `secrets.*` references.

## v6.5.1 — 2026-06-20

Plugin/UI integration proof hardening for issue #80.

- `adversarial-design-review`: adds design- and plan-phase checks for contributed
  UI rendering proof. Plugin admin pages, panels, widgets, routes, and nav items
  now require evidence beyond metadata or route registration.
- `runtime-launch-validation`: adds a modular UI/plugin contribution change
  class. Validation must launch the host, authenticate where needed, enumerate
  contributions, load each new shell route, assert contribution-specific
  content, and verify unauthorized denial.
- `verification-before-completion`: adds a claim-matrix row and pattern for
  modular UI/plugin contribution integration claims, closing the failure mode
  where provider tests and contribution APIs pass while the host shell renders
  blank or stub pages.

## v6.3.1 — 2026-06-01

Bug fix for **#66** — PreCompact hook returned invalid JSON on **Codex**.

- Root cause: `hooks/pre-compact-snapshot` emitted **empty stdout** on its no-locked-plans
  path (the common case at compaction) and other guard paths. Claude Code tolerates empty
  PreCompact output; Codex rejects it as "invalid PreCompact hook JSON output". The v6.3.0
  wrapper recovered JSON behind diagnostics but still emitted nothing for empty output.
- Fix (defense-in-depth, both invocation paths): every exit path now emits a valid JSON
  object — `hooks/pre-compact-snapshot` emits a `{}` no-op instead of empty (covers Codex
  invoking the hook directly), and `hooks/run-hook.cmd` emits `{}` for any empty hook output
  (covers the wrapper path for every hook). `{}` is a universal no-op on Claude Code and
  valid JSON for Codex.
- New regression `tests/hook-contracts.sh::test_pre_compact_snapshot_emits_json_when_no_locked_plans`
  runs the installed hook the way Codex invokes it (directly, no wrapper) and asserts valid
  JSON on the no-locked-plans + disabled paths; `tests/hook-stdout-discipline.sh` case (e)
  asserts the wrapper emits `{}` for empty output. Both CI-gated by `hooks-check.yml`.

## v6.3.0 — 2026-06-01

Pipeline-hardening release closing seven recurring gate-miss / context-waste issues
observed across autonomous runs and Codex compaction.

- **`adversarial-design-review` — auth/authz chain-composition bug-class (#59):** a new
  plan-phase row that walks the design's auth/authz chain component-by-component against
  the plan's wiring and flags any gate enforced by a *client-asserted* value
  (`evidence.granted_permissions`, a header) instead of server-side against an
  authenticated principal.
- **`pr-monitoring` — sanctioned bash poll-loop (#60):** documents the host-scoped
  CI-wait pattern. Under Claude Code, a bounded `run_in_background` bash sleep-loop that
  blocks to completion and re-invokes the lead once on settle (the prior background-Agent
  monitor early-exited ~6× per run); Codex/Cursor use a self-poll-on-wakeup fallback.
- **`subagent-driven-development` / `team-conventions` — completion trust-boundary (#58,
  ADR 0003):** a flipped `Implement: N` is a claim, not evidence — the lead must run
  `verification-before-completion` before trusting it. A deterministic hook-block is
  infeasible (the pre-tool payload lacks the task subject + caller identity), so
  correctness rests on lead verification, not on who flipped the checkbox.
- **`run-hook.cmd` — stdout JSON discipline (#41):** the wrapper now captures each hook's
  stdout and emits only valid-JSON-or-empty to the host's hook parser, recovering a block
  decision even when a locale/diagnostic warning precedes it (previously such noise could
  invalidate the hook's JSON). Diagnostics are routed to stderr; jq-absent hosts pass
  through unchanged. New `tests/hook-stdout-discipline.sh`.
- **`pretool-pr-review-reminder` — once-per-session (#61):** the gh-version/Copilot
  reviewer reminder now emits once per session (deduped via a `.claude/autodev-state`
  marker, quote-strip-matched so a quoted `--body` mentioning `gh pr create` no longer
  trips it) and is reset by `pre-compact-snapshot` so it re-emits once after a compaction.
- **`adversarial-design-review` — artifact-class precedent (#63):** a new design-phase row
  that surveys how the codebase already implements an *artifact class* (where a scenario
  stands up a server, where a fixture lives — `ls scenarios/*/cmd/server/main.go`), not
  just the *mechanism*; grep for sibling instances and follow the established shape or
  justify divergence.
- **`session-start` — Linux time-dedup fix (#64):** the SessionStart hook tried BSD
  `stat -f %m` before GNU `stat -c %Y`; on Linux `stat -f` succeeds-but-wrong (fs info),
  so the time-based dedup never suppressed re-fires. Now GNU-first with a numeric guard —
  fixing re-fire spam for all Linux autodev users.
- **CI:** new `hooks-check.yml` runs the hook contract + stdout-discipline tests on any
  `hooks/`/test change, so these fixes are regression-gated.

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

## v6.2.1 — 2026-05-31

Scope-lock claim ownership hardening for issue #52: a resumed/fresh session can
no longer silently adopt another session's locked plan just because stale
compacted context says it is active.

- `hooks/pre-tool-scope-guard`: session-lock rows now include repo, branch,
  latest user-visible objective hash/excerpt, and `confirmed:true` when an
  intentional handoff is used. `scope-lock-claim` blocks if an existing owner
  row for the plan has a different or unverifiable objective, unless the command
  includes `--confirmed`.
- `hooks/scope-lock-claim`: accepts `--confirmed` for explicit user-directed
  handoff while preserving normal lock/hash validation.
- `hooks/session-start`: compact/resume context now includes a **Resume target
  checkpoint** with cwd, repo, branch, latest objective, and attributed locked
  plans. It explicitly tells agents that compacted summaries and lock snapshots
  are not ownership proof.
- `skills/scope-lock/SKILL.md` and README document objective-bound claims,
  mismatch handling, and manual re-anchor behavior for harnesses without
  transcript identity.
- `tests/hook-contracts.sh`: added contract tests for objective mismatch block,
  matching objective allow, confirmed handoff, and resume checkpoint output.

## v6.2.0 — 2026-05-29

New skill **demonstration-fidelity** + an advisory write-time hook, closing a verification-theater gap: an agent writes real code, then "demonstrates" it with a demo that never executes the real artifact — reimplementing the logic, hard-coding the output, or rewriting it in another language. The demo proves nothing yet is presented as proof.

- **`skills/demonstration-fidelity/SKILL.md`** (host-neutral, load-bearing on every harness): a demonstration MUST execute the real artifact and show output produced by that run. Forbids reimplementation, hard-coded output, stubbing the artifact-under-demonstration, and detached prototypes — regardless of language. Allows substituting a *dependency* at a real interface seam **with disclosure**. Establishes "fidelity, not language sameness" (a real cross-language client crossing a real interface is valid), a 3-question fidelity test, a fake-vs-faithful example, and a rationalization table seeded from RED-baseline transcripts.
- **`hooks/pretool-demo-fidelity-guard`** (advisory, NEVER blocks; Claude + Codex + Cursor via `hooks.json`): on a Write/Edit to a demo-like path, injects a fidelity reminder pointing at the skill. Heuristic is anchored to path *segments* (`demos`/`examples`) + basename prefixes (`demo*`/`example*`/`showcase*`/`quickstart*`) with segment/suffix exclusions (`test`/`spec`/`testdata`/`fixtures`/`vendor` segments, `*_test.*`/`*.spec.*` basenames) — so `example_test.go`/`testdata/` are skipped while `examples/latest-feature-demo.py` still fires. Session dedup keyed on `basename(transcript_path)`; fails **open** (fires) on state I/O failure; honors `SUPERPOWERS_HOOKS_DISABLE=1`.
- **Pipeline wiring:** new `runtime-launch-validation` "Demonstration / example / showcase" change-class row (carving out artifact-stub-forbidden vs. disclosed-dependency-seam-allowed so it does not contradict RLV's "no stub on either end"); a `verification-before-completion` `demo/example works` claim-matrix row; a `finishing-a-development-branch` Step 1b demo note; `using-autodev` cross-cutting listing; README + `tests/cross-llm-coverage.md` rows.
- **Tests:** 22 `tests/hook-contracts.sh` assertions for the new guard (fires/silent/excluded/dedup/fail-open/disable-env/malformed-stdin/never-blocks). Skill is host-neutral (`skill-content-grep.sh`) and cross-refs resolve (`skill-cross-refs.sh`).

## v6.1.5 — 2026-05-28

SessionStart time-based dedup as defense in depth.

- `hooks/session-start`: added a 5-second time-window dedup that suppresses ANY rapid re-fire regardless of payload shape. The per-`session_id:source_kind` dedup added in v6.1.2 only covers startup-class fires where the host populates `session_id` consistently. Codex was observed firing SessionStart 9+ times in rapid succession near session limits — possibly during internal resume/wrap-up lifecycle events — with rotating `session_id` and source values our existing dedup didn't anticipate. Time dedup catches that uniformly: if any SessionStart payload was emitted in the last 5 seconds, the new fire short-circuits silently.
- The 5-second window is intentionally short so legitimate user-driven compacts spaced minutes apart still emit their resumption context. The observed bug was 9 fires inside ~1 second.
- Added regression test asserting four rapid fires with rotating `session_id` + source produce exactly one emission.
- Test isolation: `tests/hook-contracts.sh` SessionStart tests now use isolated tmpdir cwds so the per-cwd dedup state doesn't leak across tests.

## v6.1.4 — 2026-05-28

PreToolUse guard quote-strip extended to all destructive-command checks.

- `hooks/pre-tool-scope-guard`: the force-push, history-rewrite, locked-plan-push, and default-branch-push checks now operate on the quote-stripped form of the Bash `tool_input.command` (`cmd_no_quotes`, already computed for the SUPERPOWERS_ self-bypass check). Previously these four checks scanned the raw command, which produced false-positive blocks when a destructive command appeared as a documentation example inside a quoted heredoc body — e.g. `gh pr create --body "$(cat <<EOF ... git push --force origin main ... EOF)"` was matched as a real force push, blocking the PR creation. Encountered during v6.1.3 release: PR #47's body quoted `git push --force` and the hook blocked the very PR meant to ship the v6.1.3 fix.
- `tests/hook-contracts.sh`: added a regression test that asserts no block fires when force-push appears inside a quoted-string body.

## v6.1.3 — 2026-05-27

PreToolUse / SubagentStop block contract fix for Codex compatibility.

- `hooks/pre-tool-scope-guard` and `hooks/subagent-scope-guard`: the `block()` helper was emitting `{"decision":"block","reason":"..."}` on stdout and then `exit 2`. Both Claude Code and Codex ignore stdout JSON when a hook exits with code 2 — they require the reason on stderr. Codex enforces this strictly and surfaced the error: `PreToolUse hook exited with code 2 but did not write a blocking reason to stderr`. Claude Code silently dropped the reason. Fixed by switching to `exit 0` with stdout JSON (the documented decision-control path on both hosts) and mirroring the reason to stderr for any host that captures stderr regardless of exit code. Same pattern already used by `hooks/completion-claim-guard`.
- Switched `jq -n` → `jq -nc` in both hooks so the emitted JSON is compact (matches the format hosts and grep-based tests expect; trims a few bytes).
- Added two regression tests in `tests/hook-contracts.sh` that assert blocks exit 0, emit stdout JSON, AND mirror the reason to stderr.

## v6.1.2 — 2026-05-27

SessionStart hook payload bloat fix.

- `hooks/session-start`: stop re-embedding the full ~8 KB `using-autodev` SKILL.md body on every fire. Emit a ~340-byte pointer that names the skill and tells the agent to invoke it on demand via the host's Skill tool. Both Claude Code and Codex discover skills natively, so the body inject was redundant.
- `hooks/session-start`: skip injection entirely when `agent_id` is present in the payload. Codex's `run_pending_session_start_hooks` was observed firing per subagent spawn (6+ identical blobs on a single user prompt); guarding on `agent_id` (the cross-host "fires inside a subagent" signal) eliminates that. `agent_type` alone is NOT used as the discriminator because Claude Code populates it on top-level `claude --agent <name>` main sessions.
- `hooks/session-start`: per-`session_id:source_kind` dedup for `startup`/`clear` fires guards against host re-fire bugs (Codex 6+ rapid fires, plugin reload loops, MCP init re-triggers). `compact` and `resume` fires are intentionally NOT deduped so each legitimate lifecycle event still emits its resumption context.
- `hooks/session-start`: stale-state wipe now keyed on `session_id` transitions rather than `source == "startup"`. The old signal caused re-fires of the same session's startup event to repeatedly wipe the SEEN_FILE, defeating dedup.

## v6.1.1 — 2026-05-27

Cascade retro plugin-level follow-ups bundle.

- **adversarial-design-review**: added "plugin-loader runtime layout" + "config-validation schema rules" plan-phase bug classes
- **writing-plans / verification-before-completion**: added `golangci-lint run` pre-push verification for Go-repo PRs
- **scope-lock**: new `hooks/scope-lock-publish` sibling helper publishes a Locked plan + `.scope-lock` sidecar via a chore PR on the default branch (sidesteps the case where design+plan branch never merges)
- **scope-lock**: new `tests/cascade-preflight.sh` verifies each plugin repo's last Release workflow was green before cascade launch (catches ManifestProvider-class gaps cheap)
- **subagent-driven-development**: spec-reviewer for IaC-test-scenario PRs must now execute ≥1 scenario end-to-end before approving (`bash -n` insufficient)
- **RELEASE-NOTES**: backfilled missing v6.1.0 entry

All 5 follow-ups originate from `workflow-plugin-infra/docs/retros/2026-05-27-dns-provider-cascade-retro.md`.

## v6.1.0 — 2026-05-26

Session-scoped lock nag + claim/abandon helpers (PR #42 + #43).

- Anchor-match `Status: Locked` substring (eliminates substring-bug demoed live during PR review)
- Workspace-fallback removed when session has no attribution
- New helpers: `scope-lock-claim` (resume after restart), `scope-lock-abandon` (close never-completed lock)

## v6.0.5 (2026-05-26)

### Scope-lock completion cleanup

- Added `hooks/scope-lock-complete` so completed locked plans can be marked
  `Complete <UTC>`, have their `.scope-lock` file removed, and prune session
  lock/snapshot traces.
- Scoped strict prompt reminders to session-owned locked plans when the host
  provides a transcript path, preventing unrelated historical locks from
  attaching to new autonomous work.
- Changed PreCompact snapshots to include only active locked plans, reducing
  oversized hook JSON in repositories with many old plan documents.
- Clarified that adversarial design/plan review should dispatch a subagent with
  the full adversarial prompt whenever the host exposes subagent support.
- Added hook-contract regressions for completion cleanup, session-scoped prompt
  reminders, and locked-only PreCompact snapshots.

## v6.0.4 (2026-05-26)

### Stop-hook feedback formatting

- Added an explicit separator after the locked plan filename in the stop-hook
  completion checkpoint so hosts that flatten hook feedback do not display
  `plan.mdBefore stopping`.
- Scoped stop-hook completion checks and pre-push lock verification to plans
  locked by the current session when the host provides a transcript path,
  avoiding cross-agent interference from unrelated locked plans in the same
  workspace.
- Added a hook-contract regression that flattens the checkpoint reason and
  verifies the filename remains separated from the next sentence.

## v6.0.3 (2026-05-26)

### Hook JSON reliability

- Normalized unavailable `C.UTF-8` locale settings in the shared hook wrapper
  before launching hook scripts. This prevents bash locale warnings on stderr
  from corrupting strict hook JSON parsing on systems such as macOS.
- Added a hook-contract regression that runs through `hooks/run-hook.cmd` with
  `LC_ALL=C.UTF-8`, `LANG=C.UTF-8`, and `LC_CTYPE=C.UTF-8` and verifies the
  wrapper emits valid JSON with no stderr noise.

## v6.0.2 (2026-05-26)

### Marketplace rename

- Renamed the Claude Code/Codex marketplace from `claude-marketplace` to
  `autodev-marketplace` because Claude Code rejects marketplace names that
  impersonate official Anthropic/Claude marketplaces.
- Updated README install/remove commands and release dispatch workflow targets
  to use `GoCodeAlone/autodev-marketplace`.

## v6.0.1 (2026-05-26)

### Documentation

- Clarified that `npx skills add` installs Codex skills only, not the Codex
  plugin wrapper, hooks, trust state, or marketplace config.
- Added native Codex plugin install and old-plugin removal commands to the
  README.

### Debugging workflow

- Added an explicit bug-backpropagation invariant step to
  `systematic-debugging`: after a root-cause fix, agents must identify the
  durable "System must always/never ..." invariant that would have caught the
  bug, or state why no durable invariant exists.

## v6.0.0 (2026-05-25)

### Rename and ownership

- Renamed the project from `claude-superpowers` to `autonomous-dev-kit`.
- Renamed the skill namespace from `superpowers:` to `autodev:`.
- Renamed the Claude plugin from `superpowers` to `autodev`.
- Renamed the entry skill from `using-superpowers` to `using-autodev`.
- Updated author metadata to Jon Langevin / `jon@gocodealone.com`.
- Updated repository references to `GoCodeAlone/autonomous-dev-kit`.
- Updated the Autodev marketplace target to `GoCodeAlone/autodev-marketplace`.

### Hook and workflow hardening

- Fixed hook JSON output to use host-compatible `hookSpecificOutput.additionalContext`.
- Added hook contract tests for SessionStart, UserPromptSubmit, PR reminders,
  PreCompact snapshots, Stop-hook phase continuation, compact state rows, and
  locked-plan design backports.
- Relaxed adversarial review loops so tangible issues continue driving
  revisions, while nitpicks no longer keep the loop alive.
- Changed scope locks to hash only the `## Scope Manifest` block, allowing
  design/backport notes without invalidating locked scope.
- Added phase-completion introspection and compressed phase-progress JSONL.

### Design pipeline additions

- Added `project-design-guidance` for durable project-wide design constraints.
- Added `condensed-pipeline-writing` for compact internal design/review/plan
  artifacts and compact JSONL state.
- Added required security, infrastructure, and multi-component validation
  checks across brainstorming, planning, adversarial review, and retros.
- Updated README and install docs with `npx skills add` commands for Claude
  Code and Codex.

## v5.6.0 (2026-05-01)

### Why this release exists

A user reported the agent going off the rails: told to "continue autonomously, create a PR, test locally, reorder as needed", the agent (a) reinterpreted "reorder as needed" as license to rescope, (b) collapsed a 6-PR plan into 1 PR, (c) shipped partial scope as a "demo". Each step looked plausible in isolation. Cumulatively, the contract was lost.

This release adds the gates that make each of those steps individually visible and individually blockable.

### New skill: `scope-lock`

Once `alignment-check` returns PASS, the plan's task list, PR count, and feature scope are **locked**. The lock is enforced by:

- A required `## Scope Manifest` section in every plan, declaring `**PR Count:**`, `**Tasks:**`, `**Out of scope:**`, and a `**PR Grouping:**` table mapping tasks → PRs → branches.
- A `Status:` line stamped `Locked <UTC ISO-8601 timestamp>` after alignment passes.
- A `<plan>.scope-lock` file containing the sha256 of the manifest section, committed alongside the locked plan.
- A re-check of the lock at every per-task checkpoint in `subagent-driven-development` and before any PR creation in `finishing-a-development-branch`.

Unlock is heavyweight and explicit: the user must approve the specific tasks/PRs being dropped, an ADR is written via `recording-decisions`, the manifest is updated, and `alignment-check` re-runs against the reduced plan. Cheap unlock = no lock at all.

There is no "demo mode". Either the locked manifest ships, or the unlock path runs.

### New test: `tests/plan-scope-check.sh`

Three modes:

- `--plan <path>` — manifest well-formedness: `**PR Count:**` matches the PR Grouping table row count; every Task ID in the table exists as a `### Task N:` heading in the body; every body task appears in exactly one PR row; `**Out of scope:**` is present (legacy plans without any manifest are grandfathered unless `--strict` is passed).
- `--verify-lock <path>` — verifies the manifest's current sha256 matches `<path>.scope-lock`. Catches post-lock tampering.
- `--against-branch <path>` — verifies every branch listed in the PR Grouping table exists locally or on origin. Catches the "collapsed N PRs into 1" failure mode at PR-creation time.

Exit codes: `0` clean / `1` failures / `3` usage error. Wirable into CI.

### New invariant: strict-interpretation rule (in `using-autodev`)

When the autonomous pipeline is running and a user instruction is ambiguous, the agent MUST pick the **most-faithful-to-the-locked-manifest** interpretation. A table mapping common ambiguous phrases to their forbidden-loose and mandated-strict readings:

| Phrase | ❌ Loose | ✅ Strict |
|---|---|---|
| "reorder as needed" | rescope, drop tasks | reorder tasks within the same PR |
| "create a PR" | one PR for whatever subset | the number of PRs in the manifest |
| "test locally" | skip CI | run every plan task's verification |
| "ship a demo" | partial scope, happy-path | no demo mode; ship locked manifest |
| "be efficient" | drop tests/reviews/tasks | speed comes from parallelism, not skipping |

When multiple strict interpretations remain plausible, the agent stops and asks. Picking one and proceeding is forbidden.

### Wired into existing skills

- **`writing-plans`** — every plan MUST start with the `## Scope Manifest` block; `**Base branch:**` added to the header. The PR Grouping table is the contract `scope-lock` enforces. Authoring rules added to prevent empty `Out of scope:` and orphan tasks.
- **`alignment-check`** — third trace added (manifest trace) on top of forward and reverse. Runs `tests/plan-scope-check.sh --plan` as part of the gate. After PASS, invokes `scope-lock` to stamp and hash. Drift items now include `MANIFEST DRIFT`, `UNSCOPED`, `COUNT MISMATCH`.
- **`subagent-driven-development`** — Sequential Mode adds Step 0 "scope-lock checkpoint" before each task dispatch. Red-flags expanded with explicit prohibitions on dropping/adding tasks, collapsing PRs, and skipping the per-task scope check.
- **`finishing-a-development-branch`** — new Step 1d "Scope Completeness Check" verifies every manifest task has implementing commits and that the manifest's PR count matches reality. Autonomous mode now creates one PR per row in the PR Grouping table; collapsing is a stop-the-line error. PR body template includes a Scope Manifest section.
- **`recording-decisions`** — fifth trigger condition added: user-approved scope reduction. ADR is cited from the manifest's `Status: Reduced …` line and from each PR body shipped under the reduced manifest.
- **`pr-monitoring`** — autonomous mode spawns one monitor per PR (manifest-driven), not one monitor per branch.
- **`using-autodev`** — pipeline auto-chain extended with explicit `scope-lock` step between alignment-check and subagent-driven-development. Strict-interpretation invariant added.

### Documentation

- `README.md` workflow extended to 14 stages (scope-lock inserted at 8); new "Strict-interpretation invariant" section.
- `tests/cross-llm-coverage.md` — row added for `scope-lock` (host-neutral; pure markdown + shell).

### Versioning

5.5.0 → 5.6.0 across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.cursor-plugin/plugin.json`.

### Backward compatibility

Plans created before v5.6.0 do not have a `## Scope Manifest` section. `tests/plan-scope-check.sh` grandfathers them by default; pass `--strict` to require the manifest on all plans (e.g., for CI on a fresh-start repo). New plans created via `writing-plans` from v5.6.0 onward always include the manifest.

## v5.5.0 (2026-05-01)

### New Features

Five items that v5.4.0 deferred into a roadmap have shipped as actual functionality:

**Decision log / ADRs (`skills/recording-decisions/`, `decisions/`)**

Architecture Decision Records for non-trivial trade-offs and rejected alternatives. Numbered sequentially in `decisions/`, using Michael Nygard's three-section format (Context / Decision / Consequences) with a "Reversibility" addendum. The skill is light by design: a numbering rule, a template, a four-condition trigger, and a commit convention. Wired into `brainstorming` (when designs make non-trivial choices) and `writing-plans` (when plans introduce a non-obvious choice not already covered by an ADR cited from the design). The template lives at `decisions/0000-template.md`.

**Post-merge retrospective (`skills/post-merge-retrospective/`, `docs/retros/`)**

Closes the autonomous-pipeline loop. After `pr-monitoring` exits successfully on a merged PR with green CI and a design + plan in `docs/plans/`, this skill:

- Scores each adversarial-review finding as Prescient / Resolved upfront / False positive / Inconclusive based on what showed up in code reviews and CI.
- Walks every code-review comment and CI failure and names the gate that *should* have caught it earlier (gate misses = the actionable signal).
- Verifies the expected pipeline gates fired using `tests/skill-activation-audit.sh`.
- Produces a one-page retro at `docs/retros/YYYY-MM-DD-<feature>-retro.md`.
- Surfaces plugin-level follow-ups when a gate miss recurs across multiple retros.

Wired into `pr-monitoring`'s exit conditions. The retro is intentionally short — long retros don't get read.

**Skill-usage telemetry (`tests/skill-activation-audit.sh`)**

Parses `.claude/autodev-state/in-progress.jsonl` (the activity log written by the existing `record-activity` PostToolUse hook) and reports which skills / agents fired during a session. Detects "expected but missing" pipeline gates by walking the canonical chain (brainstorming → adversarial-design-review → … → pr-monitoring). Strictly local; never transmits anything off the machine. Used directly by `post-merge-retrospective`. Exit code 2 when expected gates didn't fire so it can be wired into CI for automation runs.

**Brainstorming cost-control gate (`skills/brainstorming/SKILL.md`)**

Soft cap of 5 question-batches per brainstorming session. On exceed, the agent stops asking, presents a best-current-approximation design with confidence annotations, and gives the user three options: approve as-is, refine specific sections (one additional capped batch), or explicitly extend the budget. Convergence is now a feature, not an accident; question fatigue is a real failure mode and this cap addresses it without becoming a hard refusal.

**Cross-skill consistency invariants (`tests/skill-cross-refs.sh`)**

New test that scans `skills/**/SKILL.md` and `agents/*.md` for cross-references and verifies they resolve:

- `<skill>/SKILL.md` paths and `autodev:<name>` mentions resolve to either a skills directory or an `agents/<name>.md` file.
- `<skill> Step <N>[a-z]?` references resolve to a heading or bold-line label in the cited skill.
- Skips fenced code blocks (placeholder examples like `path/SKILL.md` inside ```code``` are not real references).

Catches a class of silent rot that became more likely as v5.4.0 added cross-skill citations between `runtime-launch-validation`, `writing-plans`, `adversarial-design-review`, and `finishing-a-development-branch` Step 1b/1c.

### Pipeline integration

The autonomous chain now extends through the post-merge stage:

```
brainstorming → adversarial-design-review (design)
              → writing-plans
              → adversarial-design-review (plan)
              → alignment-check
              → subagent-driven-development
              → finishing-a-development-branch
              → pr-monitoring
              → post-merge-retrospective
```

Cross-cutting: `recording-decisions` is invoked from inside brainstorming and writing-plans whenever a non-trivial choice is made.

### Documentation

- `docs/roadmap.md` rewritten — the previous "deferred" sections are now a "shipped as" mapping table; only the explicit "rejected" entries remain.
- `README.md` "Basic Workflow" extended through stage 13 (post-merge-retrospective) with a new "Auditing skill activations" section.
- `tests/cross-llm-coverage.md` adds rows for the two new skills.

## v5.4.0 (2026-04-30)

### New Features

**Adversarial design / plan review (`skills/adversarial-design-review/`)**

A new lifecycle stage that adversarially attacks the *ideas* in designs and plans — not just their structural coverage. Closes the only remaining gap in the review-gate stack: every other gate attacks code or structure; this one attacks ideas.

Two phases, one skill:

- **`--phase=design`** — invoked by `brainstorming` after the design doc is committed, before `writing-plans` runs.
- **`--phase=plan`** — invoked by `writing-plans` after the plan is committed, before `alignment-check` runs.

Mandatory bug-class checklist (design phase): unstated assumptions, repo-precedent conflicts, YAGNI violations, missing failure modes, security/privacy at architecture level, rollback story, simpler alternative not considered, user-intent drift. Plan phase adds: over/under-decomposition, verification-class mismatch, hidden serial dependencies, missing rollback wiring.

Adversarial framing reused verbatim from `requesting-code-review` (find ≥3 things wrong; reflexive approval forbidden; full bug-class scan transcript required even on Clean). Every report MUST include a non-empty "Options the author may not have considered" section so reviewers offer alternatives, not just objections.

PASS/FAIL with max 2 revision cycles per gate before user escalation, mirroring `alignment-check`. User overrides are recorded inline in the artifact.

**Brainstorming: explicit assumptions + self-challenge round**

`brainstorming` now requires:

- An explicit list of load-bearing assumptions in every design ("we assume the upstream API is idempotent"). The design doc gets an `## Assumptions` section.
- A lightweight self-challenge round before the design is presented to the user — five quick checks (laziest plausible solution? most fragile assumption? YAGNI? failure modes? repo-pattern conflicts?) that clean up obvious issues before the user sees the design.
- An `## Rollback` section in the design for change classes that affect runtime (build, deployment, version pins, startup config, migrations, plugin loading) — same trigger list as `runtime-launch-validation`.

The heavyweight pass remains `adversarial-design-review`; the self-challenge is intentionally lightweight.

**Writing-plans: rollback notes for runtime-affecting tasks**

For any task whose change class triggers `runtime-launch-validation`, the plan must now include a one-line rollback note in the task body ("Rollback: revert commit + re-run migration tool down + smoke check"). This makes the design's rollback story concretely traceable into the plan, so `adversarial-design-review --phase=plan` can verify it isn't an orphaned paragraph.

**Pipeline rewiring**

The autonomous pipeline now includes the new gates:

```
brainstorming → adversarial-design-review (design)
              → writing-plans
              → adversarial-design-review (plan)
              → alignment-check
              → subagent-driven-development
              → finishing-a-development-branch → pr-monitoring
```

`alignment-check` is now scoped to **structural** trace only — adversarial concerns are cleared by the time it runs, so it stays narrow and fast.

### Why

Every existing review gate attacks code (`requesting-code-review`, spec-reviewer, code-reviewer, `verification-before-completion`) or structure (`alignment-check`). Nothing attacked the **ideas** in the design or plan themselves. Misconceptions, unstated assumptions, YAGNI features, and over-engineered approaches survived all the way to implementation, where they were the most expensive to fix. `adversarial-design-review` catches them at the cheapest stage. Stacking it on top of `alignment-check` is additive, not redundant — they catch different bug classes.

### Roadmap

`docs/roadmap.md` was added in this release to track items considered during the holistic evaluation that did not land in this version: durable decision logs (ADRs), post-merge retrospective skill, skill-usage telemetry, brainstorming cost-control gate, and cross-skill consistency invariants. Each entry had a rationale and trigger condition.

**Update for v5.5.0:** all five of those items have shipped as actual functionality. See the v5.5.0 entry above.

## v5.3.0 (2026-04-29)

### New Features

**Compaction-recovery hooks (Claude Code, Cursor)**

Long autonomous runs are now resilient to context compaction. Two hooks ship in `hooks/hooks.json`:

- **`SessionStart` (matcher `compact|resume`)** — re-injects a `<autodev-resumption-context>` block into the resumed session containing the original task (extracted from the first user message in the transcript) and the last 30 autodev activity entries. This re-anchors a compacted **subagent** to its original assignment and re-anchors the **lead orchestrator** to its place in the pipeline. The hook fires inside each session against its own transcript, so subagents recover their own task context automatically.
- **`PostToolUse` (matcher `Skill|Agent|Task.*`)** — appends each `Skill`, `Agent`, and `Task*`-family (`Task`, `TaskCreate`, `TaskList`, `TaskGet`, `TaskUpdate`, etc.) invocation to `.claude/autodev-state/in-progress.jsonl` (capped at 200 lines; wiped on `startup|clear`, or when the session source can't be determined). Append+rotate is guarded by a `flock` when available so concurrent writes from the lead and subagents don't corrupt the JSONL. This is the activity log that the SessionStart hook replays.

The state file is project-local and in JSONL format. Both hooks no-op gracefully when `jq` is unavailable. On hosts without a documented hooks system (Codex, OpenCode), the same recovery pattern is described in prose as a manual discipline.

**Subagent watchdog cadence (every 5–10 minutes)**

`subagent-driven-development` now prescribes a 5–10 minute health-check cadence on background subagents: confirm still-active, output flowing, no API/rate-limit/transport errors, not flailing off-task. Includes corrective playbooks for stuck agents (send a redirecting message, or terminate and re-dispatch with a one-line note about what went wrong). Tools mentioned (`TaskList`, `TaskOutput`, `SendMessage`, `TaskStop`, `ScheduleWakeup`) are wrapped in `<host: claude-code>` blocks; Codex and OpenCode get host-conditional equivalents (scratch-context tracking, status pings via thread / `@mention`).

**Quality-based subagent rotation**

`subagent-driven-development` now prescribes replacing — not re-prompting — a `subagent_type` that is consistently low-quality. Track per-session quality signals (review rejections, corrective messages, attributable failures); rotate triggers are 2 consecutive review rejections on the same task, 3 cumulative quality issues across tasks, or 2 instances of ignored guidance. Rotation should be stated visibly in user-facing text so the user can redirect.

### Why

A subagent that compacts mid-flight, hits a transient API error, or quietly drifts off-task can burn 30+ minutes of autonomous run time before anyone notices. The hook automation handles compaction recovery deterministically; the watchdog and rotation patterns rely on the orchestrator applying them consistently. Together they close the most common silent-degradation paths in the autonomous pipeline.

## v5.0.0 (2026-03-04)

### New Features

**Agent Teams as default execution mode**

`subagent-driven-development` now uses Claude's Agent Teams API (TeamCreate, SendMessage, TaskCreate/Update/List) as the default execution model. A role-based team replaces the sequential single-subagent flow:

- **Team Lead (Opus)** — orchestration only, no implementation
- **Implementers (Sonnet)** — claim and implement tasks from shared task list
- **Spec Reviewer (Sonnet)** — verifies implementation matches spec before quality review
- **Code Reviewer (Sonnet)** — quality review after spec approval

Team sizing scales with plan size: 1 implementer (1-5 tasks), 2 implementers (6-15), 3 implementers (16+). All reviewers operate via DM-based handoffs, not polling. Sequential subagent fallback is preserved when Agent Teams is unavailable.

**Design-to-plan alignment check**

New `alignment-check` skill verifies that an implementation plan faithfully covers every design requirement — no missing coverage, no scope creep. Dispatches a Sonnet agent to forward-trace (design → plan) and reverse-trace (plan → design), then reports PASS/FAIL with a coverage table. On FAIL, feeds drift items back to `writing-plans` for revision (max 2 cycles before escalating to user).

**Full autonomy after design approval**

After a design is approved in brainstorming, the entire pipeline now runs without user interaction:

`brainstorming → writing-plans → alignment-check → subagent-driven-development → finishing-a-development-branch → pr-monitoring`

The design approval in brainstorming is the last user interaction point. Everything after is autonomous.

**Adaptive multi-question brainstorming**

`brainstorming` now uses AskUserQuestion's multi-question capability instead of single questions one at a time. First form groups 2-4 related questions covering purpose, constraints, scope, and tech choices. Follow-up forms are targeted singles based on interesting or ambiguous answers. Reduces round-trips while preserving thoroughness.

**PR monitoring with auto-fix**

New `pr-monitoring` skill spawns a background agent that monitors open PRs in a loop: checks CI status, reads failure logs, fixes root causes, commits and pushes fixes. Also monitors and addresses review comments. Safety limits prevent runaway fixes: max 5 CI fix attempts per unique failure, max 3 revision rounds per review comment, 30 min total duration. Invoked automatically by `finishing-a-development-branch` in autonomous mode.

### Changed

**`finishing-a-development-branch` autonomous path**

Added autonomous mode: when invoked from the pipeline (not by user), skips the 4-option menu and goes directly to push + PR creation with a structured body (summary, design link, plan link, per-task changes). Then spawns pr-monitoring as a background agent.

**`writing-plans` autonomous mode**

When invoked from the brainstorming pipeline, skips user plan review, invokes alignment-check, and on PASS invokes subagent-driven-development automatically. Manual mode (direct invocation) preserves the existing execution choice prompt.

**`using-autodev` pipeline documentation**

Updated Skill Priority section to document pipeline auto-chaining as item 3. "Let's build X" now explicitly routes through the autonomous pipeline after design approval.

## v4.3.1 (2026-02-21)

### Added

**Cursor support**

Autonomous Dev Kit now works with Cursor's plugin system. Includes a `.cursor-plugin/plugin.json` manifest and Cursor-specific installation instructions in the README. The SessionStart hook output now includes an `additional_context` field alongside the existing `hookSpecificOutput.additionalContext` for Cursor hook compatibility.

### Fixed

**Windows: Restored polyglot wrapper for reliable hook execution (#518, #504, #491, #487, #466, #440)**

Claude Code's `.sh` auto-detection on Windows was prepending `bash` to the hook command, breaking execution. The fix:

- Renamed `session-start.sh` to `session-start` (extensionless) so auto-detection doesn't interfere
- Restored `run-hook.cmd` polyglot wrapper with multi-location bash discovery (standard Git for Windows paths, then PATH fallback)
- Exits silently if no bash is found rather than erroring
- On Unix, the wrapper runs the script directly via `exec bash`
- Uses POSIX-safe `dirname "$0"` path resolution (works on dash/sh, not just bash)

This fixes SessionStart failures on Windows with spaces in paths, missing WSL, `set -euo pipefail` fragility on MSYS, and backslash mangling.

## v4.3.0 (2026-02-12)

This fix should dramatically improve autodev skills compliance and should reduce the chances of Claude entering its native plan mode unintentionally.

### Changed

**Brainstorming skill now enforces its workflow instead of describing it**

Models were skipping the design phase and jumping straight to implementation skills like frontend-design, or collapsing the entire brainstorming process into a single text block. The skill now uses hard gates, a mandatory checklist, and a graphviz process flow to enforce compliance:

- `<HARD-GATE>`: no implementation skills, code, or scaffolding until design is presented and user approves
- Explicit checklist (6 items) that must be created as tasks and completed in order
- Graphviz process flow with `writing-plans` as the only valid terminal state
- Anti-pattern callout for "this is too simple to need a design" — the exact rationalization models use to skip the process
- Design section sizing based on section complexity, not project complexity

**Using-autodev workflow graph intercepts EnterPlanMode**

Added an `EnterPlanMode` intercept to the skill flow graph. When the model is about to enter Claude's native plan mode, it checks whether brainstorming has happened and routes through the brainstorming skill instead. Plan mode is never entered.

### Fixed

**SessionStart hook now runs synchronously**

Changed `async: true` to `async: false` in hooks.json. When async, the hook could fail to complete before the model's first turn, meaning using-autodev instructions weren't in context for the first message.

## v4.2.0 (2026-02-05)

### Breaking Changes

**Codex: Replaced bootstrap CLI with native skill discovery**

The `autodev-codex` bootstrap CLI, Windows `.cmd` wrapper, and related bootstrap content file have been removed. Codex now uses native skill discovery via `~/.agents/skills/autodev/` symlink, so the old `use_skill`/`find_skills` CLI tools are no longer needed.

Installation is now just clone + symlink (documented in INSTALL.md). No Node.js dependency required. The old `~/.codex/skills/` path is deprecated.

### Fixes

**Windows: Fixed Claude Code 2.1.x hook execution (#331)**

Claude Code 2.1.x changed how hooks execute on Windows: it now auto-detects `.sh` files in commands and prepends `bash`. This broke the polyglot wrapper pattern because `bash "run-hook.cmd" session-start.sh` tries to execute the `.cmd` file as a bash script.

Fix: hooks.json now calls session-start.sh directly. Claude Code 2.1.x handles the bash invocation automatically. Also added .gitattributes to enforce LF line endings for shell scripts (fixes CRLF issues on Windows checkout).

**Windows: SessionStart hook runs async to prevent terminal freeze (#404, #413, #414, #419)**

The synchronous SessionStart hook blocked the TUI from entering raw mode on Windows, freezing all keyboard input. Running the hook async prevents the freeze while still injecting autodev context.

**Windows: Fixed O(n^2) `escape_for_json` performance**

The character-by-character loop using `${input:$i:1}` was O(n^2) in bash due to substring copy overhead. On Windows Git Bash this took 60+ seconds. Replaced with bash parameter substitution (`${s//old/new}`) which runs each pattern as a single C-level pass — 7x faster on macOS, dramatically faster on Windows.

**Codex: Fixed Windows/PowerShell invocation (#285, #243)**

- Windows doesn't respect shebangs, so directly invoking the extensionless `autodev-codex` script triggered an "Open with" dialog. All invocations now prefixed with `node`.
- Fixed `~/` path expansion on Windows — PowerShell doesn't expand `~` when passed as an argument to `node`. Changed to `$HOME` which expands correctly in both bash and PowerShell.

**Codex: Fixed path resolution in installer**

Used `fileURLToPath()` instead of manual URL pathname parsing to correctly handle paths with spaces and special characters on all platforms.

**Codex: Fixed stale skills path in writing-skills**

Updated `~/.codex/skills/` reference (deprecated) to `~/.agents/skills/` for native discovery.

### Improvements

**Worktree isolation now required before implementation**

Added `using-git-worktrees` as a required skill for both `subagent-driven-development` and `executing-plans`. Implementation workflows now explicitly require setting up an isolated worktree before starting work, preventing accidental work directly on main.

**Main branch protection softened to require explicit consent**

Instead of prohibiting main branch work entirely, the skills now allow it with explicit user consent. More flexible while still ensuring users are aware of the implications.

**Simplified installation verification**

Removed `/help` command check and specific slash command list from verification steps. Skills are primarily invoked by describing what you want to do, not by running specific commands.

**Codex: Clarified subagent tool mapping in bootstrap**

Improved documentation of how Codex tools map to Claude Code equivalents for subagent workflows.

### Tests

- Added worktree requirement test for subagent-driven-development
- Added main branch red flag warning test
- Fixed case sensitivity in skill recognition test assertions

---

## v4.1.1 (2026-01-23)

### Fixes

**OpenCode: Standardized on `plugins/` directory per official docs (#343)**

OpenCode's official documentation uses `~/.config/opencode/plugins/` (plural). Our docs previously used `plugin/` (singular). While OpenCode accepts both forms, we've standardized on the official convention to avoid confusion.

Changes:
- Renamed `.opencode/plugin/` to `.opencode/plugins/` in repo structure
- Updated all installation docs (INSTALL.md, README.opencode.md) across all platforms
- Updated test scripts to match

**OpenCode: Fixed symlink instructions (#339, #342)**

- Added explicit `rm` before `ln -s` (fixes "file already exists" errors on reinstall)
- Added missing skills symlink step that was absent from INSTALL.md
- Updated from deprecated `use_skill`/`find_skills` to native `skill` tool references

---

## v4.1.0 (2026-01-23)

### Breaking Changes

**OpenCode: Switched to native skills system**

Autonomous Dev Kit for OpenCode now uses OpenCode's native `skill` tool instead of custom `use_skill`/`find_skills` tools. This is a cleaner integration that works with OpenCode's built-in skill discovery.

**Migration required:** Skills must be symlinked to `~/.config/opencode/skills/autodev/` (see updated installation docs).

### Fixes

**OpenCode: Fixed agent reset on session start (#226)**

The previous bootstrap injection method using `session.prompt({ noReply: true })` caused OpenCode to reset the selected agent to "build" on first message. Now uses `experimental.chat.system.transform` hook which modifies the system prompt directly without side effects.

**OpenCode: Fixed Windows installation (#232)**

- Removed dependency on `skills-core.js` (eliminates broken relative imports when file is copied instead of symlinked)
- Added comprehensive Windows installation docs for cmd.exe, PowerShell, and Git Bash
- Documented proper symlink vs junction usage for each platform

**Claude Code: Fixed Windows hook execution for Claude Code 2.1.x**

Claude Code 2.1.x changed how hooks execute on Windows: it now auto-detects `.sh` files in commands and prepends `bash `. This broke the polyglot wrapper pattern because `bash "run-hook.cmd" session-start.sh` tries to execute the .cmd file as a bash script.

Fix: hooks.json now calls session-start.sh directly. Claude Code 2.1.x handles the bash invocation automatically. Also added .gitattributes to enforce LF line endings for shell scripts (fixes CRLF issues on Windows checkout).

---

## v4.0.3 (2025-12-26)

### Improvements

**Strengthened using-autodev skill for explicit skill requests**

Addressed a failure mode where Claude would skip invoking a skill even when the user explicitly requested it by name (e.g., "subagent-driven-development, please"). Claude would think "I know what that means" and start working directly instead of loading the skill.

Changes:
- Updated "The Rule" to say "Invoke relevant or requested skills" instead of "Check for skills" - emphasizing active invocation over passive checking
- Added "BEFORE any response or action" - the original wording only mentioned "response" but Claude would sometimes take action without responding first
- Added reassurance that invoking a wrong skill is okay - reduces hesitation
- Added new red flag: "I know what that means" → Knowing the concept ≠ using the skill

**Added explicit skill request tests**

New test suite in `tests/explicit-skill-requests/` that verifies Claude correctly invokes skills when users request them by name. Includes single-turn and multi-turn test scenarios.

## v4.0.2 (2025-12-23)

### Fixes

**Slash commands now user-only**

Added `disable-model-invocation: true` to all three slash commands (`/brainstorm`, `/execute-plan`, `/write-plan`). Claude can no longer invoke these commands via the Skill tool—they're restricted to manual user invocation only.

The underlying skills (`autodev:brainstorming`, `autodev:executing-plans`, `autodev:writing-plans`) remain available for Claude to invoke autonomously. This change prevents confusion when Claude would invoke a command that just redirects to a skill anyway.

## v4.0.1 (2025-12-23)

### Fixes

**Clarified how to access skills in Claude Code**

Fixed a confusing pattern where Claude would invoke a skill via the Skill tool, then try to Read the skill file separately. The `using-autodev` skill now explicitly states that the Skill tool loads skill content directly—no need to read files.

- Added "How to Access Skills" section to `using-autodev`
- Changed "read the skill" → "invoke the skill" in instructions
- Updated slash commands to use fully qualified skill names (e.g., `autodev:brainstorming`)

**Added GitHub thread reply guidance to receiving-code-review** (h/t @ralphbean)

Added a note about replying to inline review comments in the original thread rather than as top-level PR comments.

**Added automation-over-documentation guidance to writing-skills** (h/t @EthanJStark)

Added guidance that mechanical constraints should be automated, not documented—save skills for judgment calls.

## v4.0.0 (2025-12-17)

### New Features

**Two-stage code review in subagent-driven-development**

Subagent workflows now use two separate review stages after each task:

1. **Spec compliance review** - Skeptical reviewer verifies implementation matches spec exactly. Catches missing requirements AND over-building. Won't trust implementer's report—reads actual code.

2. **Code quality review** - Only runs after spec compliance passes. Reviews for clean code, test coverage, maintainability.

This catches the common failure mode where code is well-written but doesn't match what was requested. Reviews are loops, not one-shot: if reviewer finds issues, implementer fixes them, then reviewer checks again.

Other subagent workflow improvements:
- Controller provides full task text to workers (not file references)
- Workers can ask clarifying questions before AND during work
- Self-review checklist before reporting completion
- Plan read once at start, extracted to TodoWrite

New prompt templates in `skills/subagent-driven-development/`:
- `implementer-prompt.md` - Includes self-review checklist, encourages questions
- `spec-reviewer-prompt.md` - Skeptical verification against requirements
- `code-quality-reviewer-prompt.md` - Standard code review

**Debugging techniques consolidated with tools**

`systematic-debugging` now bundles supporting techniques and tools:
- `root-cause-tracing.md` - Trace bugs backward through call stack
- `defense-in-depth.md` - Add validation at multiple layers
- `condition-based-waiting.md` - Replace arbitrary timeouts with condition polling
- `find-polluter.sh` - Bisection script to find which test creates pollution
- `condition-based-waiting-example.ts` - Complete implementation from real debugging session

**Testing anti-patterns reference**

`test-driven-development` now includes `testing-anti-patterns.md` covering:
- Testing mock behavior instead of real behavior
- Adding test-only methods to production classes
- Mocking without understanding dependencies
- Incomplete mocks that hide structural assumptions

**Skill test infrastructure**

Three new test frameworks for validating skill behavior:

`tests/skill-triggering/` - Validates skills trigger from naive prompts without explicit naming. Tests 6 skills to ensure descriptions alone are sufficient.

`tests/claude-code/` - Integration tests using `claude -p` for headless testing. Verifies skill usage via session transcript (JSONL) analysis. Includes `analyze-token-usage.py` for cost tracking.

`tests/subagent-driven-dev/` - End-to-end workflow validation with two complete test projects:
- `go-fractals/` - CLI tool with Sierpinski/Mandelbrot (10 tasks)
- `svelte-todo/` - CRUD app with localStorage and Playwright (12 tasks)

### Major Changes

**DOT flowcharts as executable specifications**

Rewrote key skills using DOT/GraphViz flowcharts as the authoritative process definition. Prose becomes supporting content.

**The Description Trap** (documented in `writing-skills`): Discovered that skill descriptions override flowchart content when descriptions contain workflow summaries. Claude follows the short description instead of reading the detailed flowchart. Fix: descriptions must be trigger-only ("Use when X") with no process details.

**Skill priority in using-autodev**

When multiple skills apply, process skills (brainstorming, debugging) now explicitly come before implementation skills. "Build X" triggers brainstorming first, then domain skills.

**brainstorming trigger strengthened**

Description changed to imperative: "You MUST use this before any creative work—creating features, building components, adding functionality, or modifying behavior."

### Breaking Changes

**Skill consolidation** - Six standalone skills merged:
- `root-cause-tracing`, `defense-in-depth`, `condition-based-waiting` → bundled in `systematic-debugging/`
- `testing-skills-with-subagents` → bundled in `writing-skills/`
- `testing-anti-patterns` → bundled in `test-driven-development/`
- `sharing-skills` removed (obsolete)

### Other Improvements

- **render-graphs.js** - Tool to extract DOT diagrams from skills and render to SVG
- **Rationalizations table** in using-autodev - Scannable format including new entries: "I need more context first", "Let me explore first", "This feels productive"
- **docs/testing.md** - Guide to testing skills with Claude Code integration tests

---

## v3.6.2 (2025-12-03)

### Fixed

- **Linux Compatibility**: Fixed polyglot hook wrapper (`run-hook.cmd`) to use POSIX-compliant syntax
  - Replaced bash-specific `${BASH_SOURCE[0]:-$0}` with standard `$0` on line 16
  - Resolves "Bad substitution" error on Ubuntu/Debian systems where `/bin/sh` is dash
  - Fixes #141

---

## v3.5.1 (2025-11-24)

### Changed

- **OpenCode Bootstrap Refactor**: Switched from `chat.message` hook to `session.created` event for bootstrap injection
  - Bootstrap now injects at session creation via `session.prompt()` with `noReply: true`
  - Explicitly tells the model that using-autodev is already loaded to prevent redundant skill loading
  - Consolidated bootstrap content generation into shared `getBootstrapContent()` helper
  - Cleaner single-implementation approach (removed fallback pattern)

---

## v3.5.0 (2025-11-23)

### Added

- **OpenCode Support**: Native JavaScript plugin for OpenCode.ai
  - Custom tools: `use_skill` and `find_skills`
  - Message insertion pattern for skill persistence across context compaction
  - Automatic context injection via chat.message hook
  - Auto re-injection on session.compacted events
  - Three-tier skill priority: project > personal > autodev
  - Project-local skills support (`.opencode/skills/`)
  - Shared core module (`lib/skills-core.js`) for code reuse with Codex
  - Automated test suite with proper isolation (`tests/opencode/`)
  - Platform-specific documentation (`docs/README.opencode.md`, `docs/README.codex.md`)

### Changed

- **Refactored Codex Implementation**: Now uses shared `lib/skills-core.js` ES module
  - Eliminates code duplication between Codex and OpenCode
  - Single source of truth for skill discovery and parsing
  - Codex successfully loads ES modules via Node.js interop

- **Improved Documentation**: Rewrote README to explain problem/solution clearly
  - Removed duplicate sections and conflicting information
  - Added complete workflow description (brainstorm → plan → execute → finish)
  - Simplified platform installation instructions
  - Emphasized skill-checking protocol over automatic activation claims

---

## v3.4.1 (2025-10-31)

### Improvements

- Optimized autodev bootstrap to eliminate redundant skill execution. The `using-autodev` skill content is now provided directly in session context, with clear guidance to use the Skill tool only for other skills. This reduces overhead and prevents the confusing loop where agents would execute `using-autodev` manually despite already having the content from session start.

## v3.4.0 (2025-10-30)

### Improvements

- Simplified `brainstorming` skill to return to original conversational vision. Removed heavyweight 6-phase process with formal checklists in favor of natural dialogue: ask questions one at a time, then present design in 200-300 word sections with validation. Keeps documentation and implementation handoff features.

## v3.3.1 (2025-10-28)

### Improvements

- Updated `brainstorming` skill to require autonomous recon before questioning, encourage recommendation-driven decisions, and prevent agents from delegating prioritization back to humans.
- Applied writing clarity improvements to `brainstorming` skill following Strunk's "Elements of Style" principles (omitted needless words, converted negative to positive form, improved parallel construction).

### Bug Fixes

- Clarified `writing-skills` guidance so it points to the correct agent-specific personal skill directories (`~/.claude/skills` for Claude Code, `~/.codex/skills` for Codex).

## v3.3.0 (2025-10-28)

### New Features

**Experimental Codex Support**
- Added unified `autodev-codex` script with bootstrap/use-skill/find-skills commands
- Cross-platform Node.js implementation (works on Windows, macOS, Linux)
- Namespaced skills: `autodev:skill-name` for autodev skills, `skill-name` for personal
- Personal skills override autodev skills when names match
- Clean skill display: shows name/description without raw frontmatter
- Helpful context: shows supporting files directory for each skill
- Tool mapping for Codex: TodoWrite→update_plan, subagents→manual fallback, etc.
- Bootstrap integration with minimal AGENTS.md for automatic startup
- Complete installation guide and bootstrap instructions specific to Codex

**Key differences from Claude Code integration:**
- Single unified script instead of separate tools
- Tool substitution system for Codex-specific equivalents
- Simplified subagent handling (manual work instead of delegation)
- Updated terminology: "Autonomous Dev Kit skills" instead of "Core skills"

### Files Added
- `.codex/INSTALL.md` - Installation guide for Codex users
- `.codex/autodev-bootstrap.md` - Bootstrap instructions with Codex adaptations
- `.codex/autodev-codex` - Unified Node.js executable with all functionality

**Note:** Codex support is experimental. The integration provides core autodev functionality but may require refinement based on user feedback.

## v3.2.3 (2025-10-23)

### Improvements

**Updated using-autodev skill to use Skill tool instead of Read tool**
- Changed skill invocation instructions from Read tool to Skill tool
- Updated description: "using Read tool" → "using Skill tool"
- Updated step 3: "Use the Read tool" → "Use the Skill tool to read and run"
- Updated rationalization list: "Read the current version" → "Run the current version"

The Skill tool is the proper mechanism for invoking skills in Claude Code. This update corrects the bootstrap instructions to guide agents toward the correct tool.

### Files Changed
- Updated: `skills/using-autodev/SKILL.md` - Changed tool references from Read to Skill

## v3.2.2 (2025-10-21)

### Improvements

**Strengthened using-autodev skill against agent rationalization**
- Added EXTREMELY-IMPORTANT block with absolute language about mandatory skill checking
  - "If even 1% chance a skill applies, you MUST read it"
  - "You do not have a choice. You cannot rationalize your way out."
- Added MANDATORY FIRST RESPONSE PROTOCOL checklist
  - 5-step process agents must complete before any response
  - Explicit "responding without this = failure" consequence
- Added Common Rationalizations section with 8 specific evasion patterns
  - "This is just a simple question" → WRONG
  - "I can check files quickly" → WRONG
  - "Let me gather information first" → WRONG
  - Plus 5 more common patterns observed in agent behavior

These changes address observed agent behavior where they rationalize around skill usage despite clear instructions. The forceful language and pre-emptive counter-arguments aim to make non-compliance harder.

### Files Changed
- Updated: `skills/using-autodev/SKILL.md` - Added three layers of enforcement to prevent skill-skipping rationalization

## v3.2.1 (2025-10-20)

### New Features

**Code reviewer agent now included in plugin**
- Added `autodev:code-reviewer` agent to plugin's `agents/` directory
- Agent provides systematic code review against plans and coding standards
- Previously required users to have personal agent configuration
- All skill references updated to use namespaced `autodev:code-reviewer`
- Fixes #55

### Files Changed
- New: `agents/code-reviewer.md` - Agent definition with review checklist and output format
- Updated: `skills/requesting-code-review/SKILL.md` - References to `autodev:code-reviewer`
- Updated: `skills/subagent-driven-development/SKILL.md` - References to `autodev:code-reviewer`

## v3.2.0 (2025-10-18)

### New Features

**Design documentation in brainstorming workflow**
- Added Phase 4: Design Documentation to brainstorming skill
- Design documents now written to `docs/plans/YYYY-MM-DD-<topic>-design.md` before implementation
- Restores functionality from original brainstorming command that was lost during skill conversion
- Documents written before worktree setup and implementation planning
- Tested with subagent to verify compliance under time pressure

### Breaking Changes

**Skill reference namespace standardization**
- All internal skill references now use `autodev:` namespace prefix
- Updated format: `autodev:test-driven-development` (previously just `test-driven-development`)
- Affects all REQUIRED SUB-SKILL, RECOMMENDED SUB-SKILL, and REQUIRED BACKGROUND references
- Aligns with how skills are invoked using the Skill tool
- Files updated: brainstorming, executing-plans, subagent-driven-development, systematic-debugging, testing-skills-with-subagents, writing-plans, writing-skills

### Improvements

**Design vs implementation plan naming**
- Design documents use `-design.md` suffix to prevent filename collisions
- Implementation plans continue using existing `YYYY-MM-DD-<feature-name>.md` format
- Both stored in `docs/plans/` directory with clear naming distinction

## v3.1.1 (2025-10-17)

### Bug Fixes

- **Fixed command syntax in README** (#44) - Updated all command references to use correct namespaced syntax (`/autodev:brainstorm` instead of `/brainstorm`). Plugin-provided commands are automatically namespaced by Claude Code to avoid conflicts between plugins.

## v3.1.0 (2025-10-17)

### Breaking Changes

**Skill names standardized to lowercase**
- All skill frontmatter `name:` fields now use lowercase kebab-case matching directory names
- Examples: `brainstorming`, `test-driven-development`, `using-git-worktrees`
- All skill announcements and cross-references updated to lowercase format
- This ensures consistent naming across directory names, frontmatter, and documentation

### New Features

**Enhanced brainstorming skill**
- Added Quick Reference table showing phases, activities, and tool usage
- Added copyable workflow checklist for tracking progress
- Added decision flowchart for when to revisit earlier phases
- Added comprehensive AskUserQuestion tool guidance with concrete examples
- Added "Question Patterns" section explaining when to use structured vs open-ended questions
- Restructured Key Principles as scannable table

**Anthropic best practices integration**
- Added `skills/writing-skills/anthropic-best-practices.md` - Official Anthropic skill authoring guide
- Referenced in writing-skills SKILL.md for comprehensive guidance
- Provides patterns for progressive disclosure, workflows, and evaluation

### Improvements

**Skill cross-reference clarity**
- All skill references now use explicit requirement markers:
  - `**REQUIRED BACKGROUND:**` - Prerequisites you must understand
  - `**REQUIRED SUB-SKILL:**` - Skills that must be used in workflow
  - `**Complementary skills:**` - Optional but helpful related skills
- Removed old path format (`skills/collaboration/X` → just `X`)
- Updated Integration sections with categorized relationships (Required vs Complementary)
- Updated cross-reference documentation with best practices

**Alignment with Anthropic best practices**
- Fixed description grammar and voice (fully third-person)
- Added Quick Reference tables for scanning
- Added workflow checklists Claude can copy and track
- Appropriate use of flowcharts for non-obvious decision points
- Improved scannable table formats
- All skills well under 500-line recommendation

### Bug Fixes

- **Re-added missing command redirects** - Restored `commands/brainstorm.md` and `commands/write-plan.md` that were accidentally removed in v3.0 migration
- Fixed `defense-in-depth` name mismatch (was `Defense-in-Depth-Validation`)
- Fixed `receiving-code-review` name mismatch (was `Code-Review-Reception`)
- Fixed `commands/brainstorm.md` reference to correct skill name
- Removed references to non-existent related skills

### Documentation

**writing-skills improvements**
- Updated cross-referencing guidance with explicit requirement markers
- Added reference to Anthropic's official best practices
- Improved examples showing proper skill reference format

## v3.0.1 (2025-10-16)

### Changes

We now use Anthropic's first-party skills system!

## v2.0.2 (2025-10-12)

### Bug Fixes

- **Fixed false warning when local skills repo is ahead of upstream** - The initialization script was incorrectly warning "New skills available from upstream" when the local repository had commits ahead of upstream. The logic now correctly distinguishes between three git states: local behind (should update), local ahead (no warning), and diverged (should warn).

## v2.0.1 (2025-10-12)

### Bug Fixes

- **Fixed session-start hook execution in plugin context** (#8, PR #9) - The hook was failing silently with "Plugin hook error" preventing skills context from loading. Fixed by:
  - Using `${BASH_SOURCE[0]:-$0}` fallback when BASH_SOURCE is unbound in Claude Code's execution context
  - Adding `|| true` to handle empty grep results gracefully when filtering status flags

---

# Autonomous Dev Kit v2.0.0 Release Notes

## Overview

Autonomous Dev Kit v2.0 makes skills more accessible, maintainable, and community-driven through a major architectural shift.

The headline change is **skills repository separation**: all skills, scripts, and documentation have moved from the plugin into a dedicated repository ([GoCodeAlone/autonomous-dev-kit-skills](https://github.com/GoCodeAlone/autonomous-dev-kit-skills)). This transforms autodev from a monolithic plugin into a lightweight shim that manages a local clone of the skills repository. Skills auto-update on session start. Users fork and contribute improvements via standard git workflows. The skills library versions independently from the plugin.

Beyond infrastructure, this release adds nine new skills focused on problem-solving, research, and architecture. We rewrote the core **using-skills** documentation with imperative tone and clearer structure, making it easier for Claude to understand when and how to use skills. **find-skills** now outputs paths you can paste directly into the Read tool, eliminating friction in the skills discovery workflow.

Users experience seamless operation: the plugin handles cloning, forking, and updating automatically. Contributors find the new architecture makes improving and sharing skills trivial. This release lays the foundation for skills to evolve rapidly as a community resource.

## Breaking Changes

### Skills Repository Separation

**The biggest change:** Skills no longer live in the plugin. They've been moved to a separate repository at [GoCodeAlone/autonomous-dev-kit-skills](https://github.com/GoCodeAlone/autonomous-dev-kit-skills).

**What this means for you:**

- **First install:** Plugin automatically clones skills to `~/.config/autodev/skills/`
- **Forking:** During setup, you'll be offered the option to fork the skills repo (if `gh` is installed)
- **Updates:** Skills auto-update on session start (fast-forward when possible)
- **Contributing:** Work on branches, commit locally, submit PRs to upstream
- **No more shadowing:** Old two-tier system (personal/core) replaced with single-repo branch workflow

**Migration:**

If you have an existing installation:
1. Your old `~/.config/autodev/.git` will be backed up to `~/.config/autodev/.git.bak`
2. Old skills will be backed up to `~/.config/autodev/skills.bak`
3. Fresh clone of GoCodeAlone/autonomous-dev-kit-skills will be created at `~/.config/autodev/skills/`

### Removed Features

- **Personal autodev overlay system** - Replaced with git branch workflow
- **setup-personal-autodev hook** - Replaced by initialize-skills.sh

## New Features

### Skills Repository Infrastructure

**Automatic Clone & Setup** (`lib/initialize-skills.sh`)
- Clones GoCodeAlone/autonomous-dev-kit-skills on first run
- Offers fork creation if GitHub CLI is installed
- Sets up upstream/origin remotes correctly
- Handles migration from old installation

**Auto-Update**
- Fetches from tracking remote on every session start
- Auto-merges with fast-forward when possible
- Notifies when manual sync needed (branch diverged)
- Uses pulling-updates-from-skills-repository skill for manual sync

### New Skills

**Problem-Solving Skills** (`skills/problem-solving/`)
- **collision-zone-thinking** - Force unrelated concepts together for emergent insights
- **inversion-exercise** - Flip assumptions to reveal hidden constraints
- **meta-pattern-recognition** - Spot universal principles across domains
- **scale-game** - Test at extremes to expose fundamental truths
- **simplification-cascades** - Find insights that eliminate multiple components
- **when-stuck** - Dispatch to right problem-solving technique

**Research Skills** (`skills/research/`)
- **tracing-knowledge-lineages** - Understand how ideas evolved over time

**Architecture Skills** (`skills/architecture/`)
- **preserving-productive-tensions** - Keep multiple valid approaches instead of forcing premature resolution

### Skills Improvements

**using-skills (formerly getting-started)**
- Renamed from getting-started to using-skills
- Complete rewrite with imperative tone (v4.0.0)
- Front-loaded critical rules
- Added "Why" explanations for all workflows
- Always includes /SKILL.md suffix in references
- Clearer distinction between rigid rules and flexible patterns

**writing-skills**
- Cross-referencing guidance moved from using-skills
- Added token efficiency section (word count targets)
- Improved CSO (Claude Search Optimization) guidance

**sharing-skills**
- Updated for new branch-and-PR workflow (v2.0.0)
- Removed personal/core split references

**pulling-updates-from-skills-repository** (new)
- Complete workflow for syncing with upstream
- Replaces old "updating-skills" skill

### Tools Improvements

**find-skills**
- Now outputs full paths with /SKILL.md suffix
- Makes paths directly usable with Read tool
- Updated help text

**skill-run**
- Moved from scripts/ to skills/using-skills/
- Improved documentation

### Plugin Infrastructure

**Session Start Hook**
- Now loads from skills repository location
- Shows full skills list at session start
- Prints skills location info
- Shows update status (updated successfully / behind upstream)
- Moved "skills behind" warning to end of output

**Environment Variables**
- `SUPERPOWERS_SKILLS_ROOT` set to `~/.config/autodev/skills`
- Used consistently throughout all paths

## Bug Fixes

- Fixed duplicate upstream remote addition when forking
- Fixed find-skills double "skills/" prefix in output
- Removed obsolete setup-personal-autodev call from session-start
- Fixed path references throughout hooks and commands

## Documentation

### README
- Updated for new skills repository architecture
- Prominent link to autodev-skills repo
- Updated auto-update description
- Fixed skill names and references
- Updated Meta skills list

### Testing Documentation
- Added comprehensive testing checklist (`docs/TESTING-CHECKLIST.md`)
- Created local marketplace config for testing
- Documented manual testing scenarios

## Technical Details

### File Changes

**Added:**
- `lib/initialize-skills.sh` - Skills repo initialization and auto-update
- `docs/TESTING-CHECKLIST.md` - Manual testing scenarios
- `.claude-plugin/marketplace.json` - Local testing config

**Removed:**
- `skills/` directory (82 files) - Now in GoCodeAlone/autonomous-dev-kit-skills
- `scripts/` directory - Now in GoCodeAlone/autonomous-dev-kit-skills/skills/using-skills/
- `hooks/setup-personal-autodev.sh` - Obsolete

**Modified:**
- `hooks/session-start.sh` - Use skills from ~/.config/autodev/skills
- `commands/brainstorm.md` - Updated paths to SUPERPOWERS_SKILLS_ROOT
- `commands/write-plan.md` - Updated paths to SUPERPOWERS_SKILLS_ROOT
- `commands/execute-plan.md` - Updated paths to SUPERPOWERS_SKILLS_ROOT
- `README.md` - Complete rewrite for new architecture

### Commit History

This release includes:
- 20+ commits for skills repository separation
- PR #1: Amplifier-inspired problem-solving and research skills
- PR #2: Personal autodev overlay system (later replaced)
- Multiple skill refinements and documentation improvements

## Upgrade Instructions

### Fresh Install

```bash
# In Claude Code
/plugin marketplace add GoCodeAlone/autodev-marketplace
/plugin install autodev@autodev-marketplace
```

The plugin handles everything automatically.

### Upgrading from v1.x

1. **Backup your personal skills** (if you have any):
   ```bash
   cp -r ~/.config/autodev/skills ~/autodev-skills-backup
   ```

2. **Update the plugin:**
   ```bash
   /plugin update autodev
   ```

3. **On next session start:**
   - Old installation will be backed up automatically
   - Fresh skills repo will be cloned
   - If you have GitHub CLI, you'll be offered the option to fork

4. **Migrate personal skills** (if you had any):
   - Create a branch in your local skills repo
   - Copy your personal skills from backup
   - Commit and push to your fork
   - Consider contributing back via PR

## What's Next

### For Users

- Explore the new problem-solving skills
- Try the branch-based workflow for skill improvements
- Contribute skills back to the community

### For Contributors

- Skills repository is now at https://github.com/GoCodeAlone/autonomous-dev-kit-skills
- Fork → Branch → PR workflow
- See skills/meta/writing-skills/SKILL.md for TDD approach to documentation

## Known Issues

None at this time.

## Credits

- Problem-solving skills inspired by Amplifier patterns
- Community contributions and feedback
- Extensive testing and iteration on skill effectiveness

---

**Full Changelog:** https://github.com/GoCodeAlone/autonomous-dev-kit/compare/dd013f6...main
**Skills Repository:** https://github.com/GoCodeAlone/autonomous-dev-kit-skills
**Issues:** https://github.com/GoCodeAlone/autonomous-dev-kit/issues
