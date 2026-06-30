# Autonomous Dev Kit for Zed

Guide for using Autonomous Dev Kit with Zed Agent via native Zed Skills.

## Quick Install

Global install on macOS/Linux:

```bash
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git ~/.agents/autodev
~/.agents/autodev/scripts/install-zed.sh
```

WSL2 with Windows-native Zed: use the same Bash installer. It detects WSL and
copies skills to `/mnt/c/Users/<linux-user>/.agents/skills`, the Windows path
Zed sees as `C:\Users\<user>\.agents\skills`. If your Windows username differs
from your WSL username, pass it explicitly:

```bash
~/.agents/autodev/scripts/install-zed.sh --skills-root /mnt/c/Users/<WindowsUser>/.agents/skills --copy --force
```

Global install on Windows PowerShell:

```powershell
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git "$env:USERPROFILE\.agents\autodev"
& "$env:USERPROFILE\.agents\autodev\scripts\install-zed.ps1"
```

Then add the Zed host declaration to your personal Zed instructions:

```markdown
# Autonomous Dev Kit host declaration
Host: zed-agent
When reading ADK skills, follow host-neutral instructions and `<host: zed-agent>`
blocks. Ignore host blocks for claude-code, codex, opencode, cursor, and
hermes-agent unless explicitly running that External Agent instead of Zed Agent.
```

Personal Zed instructions live at `~/.config/zed/AGENTS.md` on macOS/Linux and
`%APPDATA%\Zed\AGENTS.md` on Windows.

## Why Zed Uses a Different Layout

Zed discovers skills from `~/.agents/skills/` and `<worktree>/.agents/skills/`,
but each skill must be a direct child of the skills root. ADK's other hosts can
use a namespace symlink such as `autodev/skills`; Zed cannot. The ADK installer
therefore creates this flat layout:

```text
~/.agents/skills/brainstorming/SKILL.md
~/.agents/skills/writing-plans/SKILL.md
~/.agents/skills/using-autodev/SKILL.md
```

## Project-local Install

```bash
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git .autodev-kit
.autodev-kit/scripts/install-zed.sh --scope project --project-root .
```

Project-local skills load only in trusted Zed worktrees.

## Verify

1. Open Zed's **AI > Skills** page or the Agent Panel Skills manager.
2. Confirm ADK skills are listed.
3. Start a new Zed Agent thread and ask `help me plan this feature`.
4. The agent should invoke `brainstorming`; manual invocation also works with
   `/brainstorming` or an `@skill` mention.

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

## Uninstalling

```bash
~/.agents/autodev/scripts/install-zed.sh --uninstall
```

Windows:

```powershell
& "$env:USERPROFILE\.agents\autodev\scripts\install-zed.ps1" -Uninstall
```

## Zed Agent vs External Agents

Zed Skills apply to Zed Agent. If you install Claude, Codex, OpenCode, Cursor, or
another ACP External Agent inside Zed, that agent usually uses its own native
skills/instructions. Use ADK's install docs for that harness in addition to, or
instead of, this Zed Agent install path.

## Capability Notes

- Zed Agent supports skills, personal/project `AGENTS.md`, Agent Profiles, Tool
  Permissions, MCP servers, the Threads Sidebar, and worktree isolation.
- ADK's Claude/Codex lifecycle hook bundle is not installed for Zed Agent.
  Current Zed task hooks are not equivalent: documented Zed hooks run task
  templates, with `create_worktree` as the supported event, so they cannot
  implement ADK prompt/tool/session/compaction guards.
- For hook-like safety, use ADK's Zed skill fallbacks plus Zed Tool Permissions
  (`agent.tool_permissions`) where a command/path deny or confirm rule can
  approximate a guard. See [`zed-hook-equivalents.md`](zed-hook-equivalents.md)
  for concrete "run script X at checkpoint Y" mappings.
- ADK skills include Zed host-specific fallbacks for task tracking, subagent
  coordination, compaction recovery, and PR monitoring where Zed differs from
  other harnesses.

Detailed docs: [`.zed/INSTALL.md`](../.zed/INSTALL.md)
