# Autonomous Dev Kit

Autonomous Dev Kit is a complete software development workflow for your coding agents, built on top of a set of composable "skills" and some initial instructions that make sure your agent uses them.

## How it works

It starts from the moment you fire up your coding agent. As soon as it sees that you're building something, it *doesn't* just jump into trying to write code. Instead, it steps back and asks you what you're really trying to do. 

Once it's teased a spec out of the conversation, it shows it to you in chunks short enough to actually read and digest. 

After you've signed off on the design, your agent puts together an implementation plan that's clear enough for an enthusiastic junior engineer with poor taste, no judgement, no project context, and an aversion to testing to follow. It emphasizes true red/green TDD, YAGNI (You Aren't Gonna Need It), and DRY. 

Next up, once you say "go", it launches a *subagent-driven-development* process, having agents work through each engineering task, inspecting and reviewing their work, and continuing forward. In capable hosts, agents can work autonomously for long stretches without deviating from the plan you put together.

There's a bunch more to it, but that's the core of the system. And because the skills trigger automatically, you don't need to do anything special. Your coding agent just has Autonomous Dev Kit.

Autonomous Dev Kit originated as a fork of Jesse Vincent's [Superpowers](https://github.com/obra/superpowers) repo.


## Installation

**Note:** Installation differs by platform. Claude Code or Cursor have built-in plugin marketplaces. Codex can use the open `skills` CLI (`npx skills add`) or manual setup. OpenCode currently uses manual setup.

### Claude Code (via Plugin Marketplace)

If you have the old `superpowers` plugin installed, **uninstall it first** before installing `autodev`:

```bash
# 1. Remove existing superpowers plugin (if installed)
/plugin uninstall superpowers

# 2. Remove the old marketplace (if registered)
/plugin marketplace remove superpowers-marketplace

# 3. Restart Claude Code to apply removals
/exit
```

Then in a fresh session, add the GoCodeAlone marketplace and install:

```bash
# 4. Register the GoCodeAlone marketplace
/plugin marketplace add GoCodeAlone/autodev-marketplace

# 5. Install the plugin
/plugin install autodev@autodev-marketplace
```

Alternatively, install the skills directly with the open Skills CLI:

```bash
npx skills add GoCodeAlone/autonomous-dev-kit -a claude-code --skill '*' -y
```

For user/global install:

```bash
npx skills add GoCodeAlone/autonomous-dev-kit -a claude-code --skill '*' -g -y
```

### Cursor (via Plugin Marketplace)

In Cursor Agent chat, install from marketplace:

```text
/plugin-add autodev
```

### Codex

From your project root, install the skills with the open Skills CLI:

```bash
npx skills add GoCodeAlone/autonomous-dev-kit -a codex --skill '*' -y
```

For user/global install instead of project-local install:

```bash
npx skills add GoCodeAlone/autonomous-dev-kit -a codex --skill '*' -g -y
```

Then restart Codex so it discovers the skills.

The Skills CLI path installs `SKILL.md` files only. It does not install the
Codex plugin wrapper, hooks, plugin trust state, or marketplace config. For the
full Codex plugin install, use Codex's native plugin commands:

```bash
codex plugin marketplace add GoCodeAlone/autodev-marketplace
codex plugin add autodev@autodev-marketplace
```

To remove the old plugin first:

```bash
codex plugin remove superpowers@superpowers-marketplace
codex plugin marketplace remove superpowers-marketplace
```

Manual fallback: tell Codex:

```
Fetch and follow instructions from https://raw.githubusercontent.com/GoCodeAlone/autonomous-dev-kit/refs/heads/main/.codex/INSTALL.md
```

**Detailed docs:** [docs/README.codex.md](docs/README.codex.md)

### OpenCode

Tell OpenCode:

```
Fetch and follow instructions from https://raw.githubusercontent.com/GoCodeAlone/autonomous-dev-kit/refs/heads/main/.opencode/INSTALL.md
```

**Detailed docs:** [docs/README.opencode.md](docs/README.opencode.md)

### Verify Installation

Start a new session in your chosen platform and ask for something that should trigger a skill (for example, "help me plan this feature" or "let's debug this issue"). The agent should automatically invoke the relevant autodev skill.

## Cross-LLM Compatibility

Autonomous Dev Kit skills run on any host that supports the SKILL.md format. Host-specific tools (like Agent Teams) are conditioned with `<host: claude-code>` blocks so other hosts skip them gracefully.

| Host | Install path | Native skill discovery | Notes |
|---|---|---|---|
| Claude Code | `~/.claude/plugins/marketplace/autodev/` | yes | Full Agent Teams support (experimental flag) |
| Codex | `~/.agents/skills/autodev/` | yes | Sequential sub-agent dispatch; `/plan` slash; `/agent` switching |
| OpenCode | `~/.config/opencode/skills/autodev/` | yes | Tool mapping documented in `.opencode/INSTALL.md` |
| Cursor | `/plugin-add autodev` | yes (via plugin) | Plugin manifest defines skills/agents/commands/hooks |

Full capability matrix: [docs/cross-llm-coverage.md](docs/cross-llm-coverage.md)  
Per-skill host-conditional audit: [tests/cross-llm-coverage.md](tests/cross-llm-coverage.md)

## The Basic Workflow

1. **brainstorming** - Activates before writing code. Refines rough ideas through questions, explores alternatives, applies project-wide design guidance, lists load-bearing assumptions, runs a self-challenge round, presents design in sections for validation. Designs now explicitly cover global guidance fit, security review, infrastructure impact, multi-component validation, assumptions, and rollback. Soft cap of 5 question-batches; on exceed, agent presents best-current-approximation and asks user to approve / refine / extend the budget. Saves design document.

2. **adversarial-design-review (design phase)** - Activates after design doc is committed. Adversarially attacks the *ideas* in the design (not just structure): project-guidance conflicts, assumptions under attack, repo-precedent conflicts, YAGNI violations, missing failure modes, security/privacy gaps, infrastructure impact, multi-component validation, rollback story, simpler alternatives, user-intent drift. PASS/FAIL cycles continue while tangible issues appear; the loop stops when only nitpicks remain.

3. **recording-decisions** - Activates inside brainstorming and writing-plans whenever a non-trivial choice is made (divergence from precedent, trade-off between ≥2 plausible approaches, adversarial-review override, cross-skill structural change). Adds a numbered ADR in `decisions/` so the *why* survives renames and refactors.

4. **using-git-worktrees** - Activates after design approval. Creates isolated workspace on new branch, runs project setup, verifies clean test baseline.

5. **writing-plans** - Activates with approved design. Breaks work into bite-sized tasks (2-5 minutes each). Every task has exact file paths, complete code, verification steps. Plans must map project guidance into tasks, wire security-sensitive behavior into verification, prove multi-component boundaries with integration/E2E checks where feasible, and validate infrastructure changes with render/plan/dry-run or safe-env apply. Runtime-affecting tasks include rollback notes. Plan MUST contain a `## Scope Manifest` block declaring PR Count, Tasks, Out-of-scope items, and a per-PR grouping table — this is the contract `scope-lock` enforces.

6. **adversarial-design-review (plan phase)** - Activates after plan doc is committed. Inherits the design checklist plus plan-specific scans: task granularity, verification-class match, hidden serial dependencies, rollback wiring, missing integration proof, and infrastructure verification mismatch.

7. **alignment-check** - Activates after adversarial review of plan passes. Narrowly structural: every design requirement maps to a plan task; every plan task traces to a design requirement; the Scope Manifest is well-formed (forward + reverse + manifest trace via `tests/plan-scope-check.sh`).

8. **scope-lock** - Activates immediately after `alignment-check` PASS. Stamps the plan with `Locked <timestamp>`, computes the manifest's sha256 into `<plan>.scope-lock`, commits both. From this point until completion (or an explicit user-approved amendment), the task list, PR count, and feature scope are immutable. Design backports that do not change the manifest are allowed; manifest changes go through ADR + alignment. The lock hash covers only the `## Scope Manifest` block, so explanatory design/task notes can evolve without invalidating scope. `subagent-driven-development` re-checks the lock between tasks; `finishing-a-development-branch` re-checks before any PR is created. When the design is fully complete, `hooks/scope-lock-complete <plan> --evidence "<verification>"` marks it `Complete`, removes the lock file, and prunes session reminder traces.

9. **subagent-driven-development** or **executing-plans** - Activates with a locked plan. Dispatches fresh subagent per task with two-stage review (spec compliance, then code quality). Between tasks, re-runs the scope-lock check; on lock drift, stops the line and surfaces the discrepancy. Phase/task completions are logged in compressed JSONL to `.autodev/state/phase-progress.jsonl` when a locked plan continues.

10. **test-driven-development** - Activates during implementation. Enforces RED-GREEN-REFACTOR: write failing test, watch it fail, write minimal code, watch it pass, commit. Deletes code written before tests.

11. **requesting-code-review** - Activates between tasks. Reviews against plan, reports issues by severity. Critical issues block progress.

12. **finishing-a-development-branch** - Activates when tasks complete. Step 1d (Scope Completeness Check) verifies every manifest task has implementing commits and that the autonomous run produces the planned number of PRs (no silent collapse). Verifies tests, presents options (merge/PR/keep/discard), cleans up worktree.

13. **pr-monitoring** - Activates after autonomous PR creation (one monitor per PR in the manifest). Watches CI and review comments; fixes failures and responds to feedback until green.

14. **post-merge-retrospective** - Activates after `pr-monitoring` exits successfully on a merged PR with green CI. Reads the design, plan, adversarial-review reports, code-review threads, and CI history; produces a short retro in `docs/retros/` scoring each adversarial finding (Prescient / Resolved upfront / False positive / Inconclusive), naming gate misses, and surfacing plugin-level follow-ups when patterns emerge across retros. If the retro reveals durable project-wide guidance, it updates `docs/design-guidance.md` in the same loop.

**The agent checks for relevant skills before any task.** Mandatory workflows, not suggestions.

## Auditing skill activations

`tests/skill-activation-audit.sh` reads `.claude/autodev-state/in-progress.jsonl` (the compressed activity log written by the `record-activity` hook) and reports which pipeline gates fired during a session. Use it post-hoc when you want to confirm whether the autonomous pipeline ran end-to-end or stopped earlier than expected. Strictly local — never transmits anything.

`tests/skill-cross-refs.sh` verifies that cross-skill references inside `skills/` and `agents/` markdown resolve (skill names, `Step N` references, `autodev:<name>` mentions). Run it before committing any skill edit that renames a skill or renumbers a step.

`tests/plan-scope-check.sh` verifies the Scope Manifest invariant. Three modes: `--plan <path>` (well-formedness — PR Count matches the grouping table; every task in the body appears in the table; etc.), `--verify-lock <path>` (manifest sha256 matches the `.scope-lock` file written at alignment time), and `--against-branch <plan>` (planned branches in the manifest exist locally or on origin). The autonomous pipeline runs all three at the appropriate gates; CI can run `--plan` against every plan in `docs/plans/`.

`tests/hook-contracts.sh` verifies hook JSON and guard behavior without requiring Claude Code or Codex to be installed. It checks the host-neutral `hookSpecificOutput.additionalContext` schema, Stop-hook phase-continuation behavior, hard-blocker stops, compact JSONL state rows, and locked-plan backports that do not change the Scope Manifest.

## Strict-interpretation invariant

Once a plan is locked, ambiguous user phrases — "reorder as needed", "create a PR", "test locally", "ship a demo", "be quick" — do NOT authorize rescoping, PR collapse, or partial-scope shipping. The agent picks the most-faithful-to-the-locked-manifest interpretation; if multiple strict readings remain plausible, it stops and asks. See the table in `skills/using-autodev/SKILL.md` § "Strict-interpretation invariant" for the full mapping and the amendment path.

## Bug Backpropagation Invariants

When a bug is fixed, `systematic-debugging` now requires a backpropagation check:
what invariant would have caught this before it shipped? Durable invariants are
recorded as tests, design/plan backports, project guidance, scope-manifest
amendments, CI/hooks, runtime validation, or deployment checks. The invariant
should be stated as a one-line "System must always/never ..." rule. If the bug
proved an assumption false, that assumption is backported so the next
adversarial review challenges it explicitly.

## What's Inside

### Skills Library

**Testing**
- **test-driven-development** - RED-GREEN-REFACTOR cycle (includes testing anti-patterns reference)

**Debugging**
- **systematic-debugging** - 4-phase root cause process (includes root-cause-tracing, defense-in-depth, condition-based-waiting techniques)
- **verification-before-completion** - Ensure it's actually fixed

**Collaboration** 
- **brainstorming** - Socratic design refinement (with assumption-listing, self-challenge round, and a 5-batch question budget)
- **project-design-guidance** - Reads or creates durable project-wide constraints before designs/plans and backfeeds durable lessons from retros
- **adversarial-design-review** - Adversarial attack on design and plan ideas before execution (two phases: design, plan), including project-guidance conflicts, security/privacy, infrastructure impact, and multi-component validation
- **recording-decisions** - ADRs in `decisions/` for non-trivial trade-offs, rejected alternatives, and user-approved manifest amendments
- **writing-plans** - Detailed implementation plans (with mandatory Scope Manifest)
- **executing-plans** - Batch execution with checkpoints
- **alignment-check** - Structural design ↔ plan trace (forward + reverse + manifest)
- **scope-lock** - Once a plan passes alignment, the task list, PR count, and feature scope are immutable until completion or explicit user-approved amendment
- **condensed-pipeline-writing** - Compact internal format for design, review, planning, backport, and phase-progress artifacts
- **dispatching-parallel-agents** - Concurrent subagent workflows
- **requesting-code-review** - Pre-review checklist
- **receiving-code-review** - Responding to feedback
- **using-git-worktrees** - Parallel development branches
- **finishing-a-development-branch** - Merge/PR decision workflow (with Step 1d Scope Completeness Check)
- **pr-monitoring** - Watches CI and reviews after autonomous PR creation
- **post-merge-retrospective** - Closes the loop on merged PRs; scores each adversarial finding and surfaces gate misses
- **subagent-driven-development** - Fast iteration with two-stage review (spec compliance, then code quality)

**Meta**
- **writing-skills** - Create new skills following best practices (includes testing methodology)
- **using-autodev** - Introduction to the skills system

## Philosophy

- **Test-Driven Development** - Write tests first, always
- **Systematic over ad-hoc** - Process over guessing
- **Complexity reduction** - Simplicity as primary goal
- **Evidence over claims** - Verify before declaring success

## Contributing

Skills live directly in this repository. To contribute:

1. Fork the repository
2. Create a branch for your skill
3. Follow the `writing-skills` skill for creating and testing new skills
4. Submit a PR

See `skills/writing-skills/SKILL.md` for the complete guide.

## Updating

Skills update automatically when you update the plugin:

```bash
/plugin update autodev
```

## License

MIT License - see LICENSE file for details

## Support

- **Issues**: https://github.com/GoCodeAlone/autonomous-dev-kit/issues
- **Marketplace**: https://github.com/GoCodeAlone/autodev-marketplace
