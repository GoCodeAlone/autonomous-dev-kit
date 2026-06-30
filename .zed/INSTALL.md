# Installing Autonomous Dev Kit for Zed

Enable Autonomous Dev Kit skills in Zed Agent via Zed's native Skills system.

This install path targets **Zed Agent**. Zed External Agents such as Claude, Codex,
OpenCode, or Cursor run through ACP and generally use their own native skill or
instruction configuration; use the ADK install path for that external harness when
running those agents inside Zed.

## Prerequisites

- [Zed](https://zed.dev/) with Agent Panel support
- Git
- Bash on macOS/Linux, or PowerShell on Windows

## What Zed Discovers

As of Zed's June 2026 docs, Zed loads skills from:

| Scope | Path |
|---|---|
| Global | `~/.agents/skills/` |
| Project-local | `<worktree>/.agents/skills/` |

Each skill must be a **direct child** of the skills root. Nested layouts such as
`~/.agents/skills/autodev/brainstorming/SKILL.md` are not discovered by Zed.
The ADK Zed installer therefore links or copies each `skills/<name>/` directory
straight into the selected Zed skills root.

## Recommended: Global Install

macOS/Linux:

```bash
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git ~/.agents/autodev
~/.agents/autodev/scripts/install-zed.sh
```

WSL2 with Windows-native Zed:

```bash
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git ~/.agents/autodev
~/.agents/autodev/scripts/install-zed.sh
```

When run under WSL, the Bash installer detects a matching Windows profile at
`/mnt/c/Users/<linux-user>` and copies the skills to
`/mnt/c/Users/<linux-user>/.agents/skills`, which is
`C:\Users\<user>\.agents\skills` from Windows Zed's perspective. If your
Windows username differs from your WSL username, pass the path explicitly:

```bash
~/.agents/autodev/scripts/install-zed.sh --skills-root /mnt/c/Users/<WindowsUser>/.agents/skills --copy --force
```

Windows PowerShell:

```powershell
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git "$env:USERPROFILE\.agents\autodev"
& "$env:USERPROFILE\.agents\autodev\scripts\install-zed.ps1"
```

The installer creates one link per skill under `~/.agents/skills/`, for example:

```text
~/.agents/skills/brainstorming/SKILL.md
~/.agents/skills/writing-plans/SKILL.md
~/.agents/skills/using-autodev/SKILL.md
```

## Project-local Install

Use this when you want ADK enabled only for a single trusted worktree.

macOS/Linux:

```bash
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git .autodev-kit
.autodev-kit/scripts/install-zed.sh --scope project --project-root .
```

Windows PowerShell:

```powershell
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git .autodev-kit
& ".\.autodev-kit\scripts\install-zed.ps1" -Scope Project -ProjectRoot .
```

Project-local skills load only from trusted worktrees. If Zed has not yet marked
the project trusted, review the checked-in skills and grant trust before expecting
these skills to appear in the catalog or slash-command list.

## Copy Mode

If symlinks or junctions are unavailable, install copies instead:

```bash
~/.agents/autodev/scripts/install-zed.sh --copy
```

```powershell
& "$env:USERPROFILE\.agents\autodev\scripts\install-zed.ps1" -Copy
```

Copy mode does not update automatically when the ADK checkout changes; rerun the
installer with `--force` / `-Force` after pulling updates.

## Host Declaration

Add this to Zed personal instructions so ADK skills select Zed-specific host
blocks and ignore other host-only blocks:

macOS/Linux:

```bash
mkdir -p ~/.config/zed
cat >> ~/.config/zed/AGENTS.md <<'EOF'

# Autonomous Dev Kit host declaration
Host: zed-agent
When reading ADK skills, follow host-neutral instructions and `<host: zed-agent>`
blocks. Ignore host blocks for claude-code, codex, opencode, cursor, and
hermes-agent unless explicitly running that External Agent instead of Zed Agent.
EOF
```

Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force -Path "$env:APPDATA\Zed" | Out-Null
Add-Content -Path "$env:APPDATA\Zed\AGENTS.md" -Value @'

# Autonomous Dev Kit host declaration
Host: zed-agent
When reading ADK skills, follow host-neutral instructions and `<host: zed-agent>`
blocks. Ignore host blocks for claude-code, codex, opencode, cursor, and
hermes-agent unless explicitly running that External Agent instead of Zed Agent.
'@
```

## Verify Installation

In Zed:

1. Open **AI > Skills** or run `agent: open skill creator` / the Skills manager.
2. Confirm ADK skills such as `using-autodev`, `brainstorming`, and
   `writing-plans` appear.
3. Start a new Zed Agent thread and ask: `help me plan this feature`.
4. The agent should load the relevant ADK skill. You can also manually invoke a
   skill with `/brainstorming` or by @-mentioning it.

Zed live-reloads skill edits. Restart is usually unnecessary, but starting a fresh
thread can make catalog changes clearer to the model.

## Troubleshooting: Zed says no global skills are installed

If the installer reports success but **AI > Skills** shows no User/global skills,
Zed is probably reading a different home directory than the shell that ran the
installer. This is common when installing from MSYS, Git Bash, a remote shell,
or another sandbox while running a different Zed binary. WSL2 with
Windows-native Zed is handled automatically when the Windows profile matches
the WSL username; otherwise pass the `/mnt/c/Users/<WindowsUser>/.agents/skills`
path explicitly.

Use Zed as the source of truth for the path:

1. Open **AI > Skills**.
2. Select the **User** tab.
3. Click **Create Skill**.
4. Note the folder Zed says it will save the skill under. Use the parent
   `skills` directory as the installer target.

Then rerun ADK's installer with that exact skills root. Prefer copy mode for
troubleshooting so filesystem links are not another variable:

```bash
~/.agents/autodev/scripts/install-zed.sh --skills-root /exact/path/from/zed --copy --force
```

```powershell
& "$env:USERPROFILE\.agents\autodev\scripts\install-zed.ps1" -SkillsRoot "C:\exact\path\from\zed" -Copy -Force
```

The target must contain direct child skill folders like:

```text
<skills-root>/brainstorming/SKILL.md
<skills-root>/writing-plans/SKILL.md
<skills-root>/using-autodev/SKILL.md
```

Do not point Zed at `~/.agents/autodev`, `~/.agents/autodev/skills`, or a nested
`~/.agents/skills/autodev/` folder; Zed only discovers skills that are direct
children of the skills root.

## Updating

Symlink/junction install:

```bash
cd ~/.agents/autodev && git pull
```

Copy install:

```bash
cd ~/.agents/autodev && git pull
scripts/install-zed.sh --copy --force
```

Windows copy install:

```powershell
Set-Location "$env:USERPROFILE\.agents\autodev"
git pull
& ".\scripts\install-zed.ps1" -Copy -Force
```

## Uninstalling

macOS/Linux:

```bash
~/.agents/autodev/scripts/install-zed.sh --uninstall
```

Windows PowerShell:

```powershell
& "$env:USERPROFILE\.agents\autodev\scripts\install-zed.ps1" -Uninstall
```

Optionally delete the clone after uninstalling the links/copies.

## Capability Notes

- **Skills:** Supported natively by Zed Agent.
- **Always-on instructions:** Zed loads personal `~/.config/zed/AGENTS.md` (or
  `%APPDATA%\Zed\AGENTS.md`) and project instruction files including `AGENTS.md`.
- **Hooks:** ADK's Claude/Codex lifecycle hook bundle is not installed into Zed
  Agent. Current Zed docs expose task-template hooks, not agent lifecycle hooks,
  and the documented task hook event is `create_worktree`. That is useful for
  per-worktree setup but cannot implement ADK's `SessionStart`,
  `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, or `PreCompact` guards.
  Where ADK skills mention hook-provided reminders or blockers, Zed uses the
  manual fallback guidance in the skill text plus Zed Tool Permissions where a
  permission rule can approximate a guard.
- **Parallel work:** Use Zed's Threads Sidebar and worktree isolation for
  concurrent agent threads. ADK's subagent-driven workflow maps to sequential
  Zed Agent subagents or separate Zed Agent threads, depending on what the active
  profile/model exposes.
- **MCP:** Configure MCP servers in Zed Agent Settings if a workflow needs tools
  beyond Zed's built-ins.

For concrete "at this point, run this script or invoke this skill" mappings,
see [`docs/zed-hook-equivalents.md`](../docs/zed-hook-equivalents.md).

## Optional Zed Task Hook Approximation

Zed task hooks can help with one ADK-adjacent case: keeping project-local skills
available in linked worktrees that Zed creates. Add this to a project's
`.zed/tasks.json` only if the project has an ADK checkout at `.autodev-kit`:

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

This is intentionally narrow. It only runs after Zed creates a linked worktree;
it does not observe agent prompts, tool calls, compaction, or session lifecycle.
