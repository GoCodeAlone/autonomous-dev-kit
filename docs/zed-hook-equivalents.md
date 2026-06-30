# Zed Hook Equivalents for Autonomous Dev Kit

Zed Agent does not expose the Claude/Codex-style agent lifecycle hooks that ADK
uses on other hosts. Current Zed docs expose task-template hooks, with
`create_worktree` as the documented event. That means ADK cannot automatically
run scripts before every prompt, tool call, stop, subagent stop, or compaction in
Zed Agent.

Use this table as the Zed Agent replacement: explicit skill/script checkpoints at
the moments where the hook would have fired.

| ADK lifecycle hook | Other-host behavior | Zed Agent checkpoint |
|---|---|---|
| `SessionStart` (`startup`, `resume`, `clear`, `compact`) | Injects resumption context and recent ADK activity | At the first reply after opening/resuming/compaction, re-state the current objective, repo, branch, active plan, and next step. If resuming a locked plan, run `bash hooks/scope-lock-claim <plan-path>` from the ADK checkout/plugin root before editing. Use `--confirmed` only after the user explicitly confirms a handoff. |
| `UserPromptSubmit` / `prompt-strict-interpretation` | Warns when ambiguous user wording conflicts with a locked manifest | Before acting on ambiguous phrases like "continue", "create a PR", "be quick", "reorder as needed", or "ship a demo" while a plan is locked, load `using-autodev` and `scope-lock`; pick the strictest interpretation or ask. |
| `UserPromptSubmit` / `portfolio-inventory-reminder` | Reminds once per compaction window to consult portfolio inventory | Before designing new tooling, load `project-design-guidance` and inspect the project/portfolio guidance it names. |
| `PreToolUse` / `pre-tool-scope-guard` | Blocks edits/commands that drift a locked plan | Before each task, PR split, or scope-affecting edit in a locked plan, run `bash tests/plan-scope-check.sh --plan <plan-path> --verify-lock <plan-path>` from the project root. Stop on any non-zero exit. |
| `PreToolUse` / `pretool-demo-fidelity-guard` | Reminds before writing demo/example/quickstart/showcase files | Before creating or editing demo/example/quickstart/showcase/sample proof artifacts, load `demonstration-fidelity` and then run the real artifact to capture output. |
| `PreToolUse` / `pretool-pr-review-reminder` | Reminds before `gh pr create` | Before `gh pr create`, load `requesting-code-review` and `verification-before-completion`; run the declared verification and address Critical/Important review findings. |
| `PostToolUse` / `record-activity` | Writes compact skill/subagent/task activity rows | After each locked-plan task completes, append or update progress in the orchestrator checklist. When useful, append a compact row to `.autodev/state/phase-progress.jsonl` with the plan, phase/task, status, evidence, and next step. |
| `PostToolUse` / `posttool-pr-created` | Records PR creation and triggers monitor context | Immediately after creating a PR, load `pr-monitoring` and start the monitor loop/thread for every PR row in the Scope Manifest. |
| `Stop` / `completion-claim-guard` | Blocks completion claims without progress evidence | Before any "done", "complete", "fixed", "passes", or PR-ready claim, load `verification-before-completion`, run the proof fresh, and read the output. |
| `SubagentStop` / `subagent-scope-guard` | Blocks subagent completion when manifest drift is detected | When a Zed subagent or parallel thread finishes, inspect its `Writes:` ledger, review the diff, and run `bash tests/plan-scope-check.sh --plan <plan-path> --verify-lock <plan-path>` before accepting the result. |
| `PreCompact` / `pre-compact-snapshot` | Snapshots locked plan state before compaction | Before manually running `/compact` or starting a new thread from summary, write a short checkpoint in the thread: objective, repo, branch, active plan, completed task, next task, and open blockers. Zed auto-compaction cannot be intercepted, so re-orient on the next turn. |

## Optional Zed Task Hook

Zed's documented `create_worktree` task hook can approximate one setup behavior:
installing project-local ADK skills into a new linked worktree. Add this to a
project's `.zed/tasks.json` only if the project has an ADK checkout at
`.autodev-kit`:

```json
[
  {
    "label": "install autodev skills in new Zed worktree",
    "command": ".autodev-kit/scripts/install-zed.sh",
    "args": ["--scope", "project", "--project-root", "$ZED_WORKTREE_ROOT", "--copy", "--force"],
    "cwd": "$ZED_MAIN_GIT_WORKTREE",
    "hooks": ["create_worktree"],
    "reveal": "no_focus",
    "hide": "on_success"
  }
]
```

This does not observe agent prompts or tool calls. It only runs after Zed creates
a linked worktree.

## Tool Permissions as Guardrails

Some ADK hook behavior can be partially approximated with Zed Tool Permissions:

- Require confirmation for `terminal` commands matching `gh\s+pr\s+create`.
- Require confirmation for edits/writes matching demo paths such as
  `(^|/)(demo|demos|examples|quickstart|showcase|samples?)(/|\.)`.
- Require confirmation for `terminal` commands matching force-push or destructive
  git operations.

Tool Permissions are guardrails, not workflow gates: they can prompt or deny a
command/path, but they do not run ADK review or scope-lock scripts for you.
