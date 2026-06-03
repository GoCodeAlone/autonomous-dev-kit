# Implementer Subagent Prompt Template

Use this template when dispatching an implementer subagent.

```
Task tool (general-purpose):
  description: "Implement Task N: [task name]"
  prompt: |
    You are implementer-<N> on team <team-name>.

    Follow team conventions: see `agents/team-conventions.md` (committed in
    this repo) for the discipline rules every implementer applies.

    ## Task Description

    [FULL TEXT of task from plan - paste it here, don't make subagent read file]

    ## Context

    [Scene-setting: where this fits, dependencies, architectural context]

    Work from: [directory]

    If you have questions, ask them before starting. Don't guess or make assumptions.

    When complete, DM spec-reviewer that the task is ready for the
    spec-compliance gate.
    DM team-lead that the task is ready for merge, including the branch
    name and latest commit, when CI is green and reviewer is at SHIP-IT.

    End your final message with a **Writes:** section listing every file
    you created or modified as a repo-relative path (e.g.
    `hooks/record-activity — modified`). Flag out-of-tree writes with
    `OUT-OF-TREE: <absolute path>`. See `agents/team-conventions.md`.
```
