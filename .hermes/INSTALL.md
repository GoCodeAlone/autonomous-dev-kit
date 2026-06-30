# Installing Autonomous Dev Kit for Hermes Agent

Enable autodev skills in Hermes Agent via native skill discovery.

## Prerequisites

- [Hermes Agent](https://hermes-agent.nousresearch.com/docs) installed
- Git installed

## Installation

### Option 1: Clone and Symlink (Recommended)

```bash
# Clone the autodev repository
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git ~/.hermes/autodev

# Create the skills symlink so Hermes discovers autodev skills
mkdir -p ~/.hermes/skills
ln -s ~/.hermes/autodev/skills ~/.hermes/skills/autodev
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git "$env:USERPROFILE\.hermes\autodev"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.hermes\skills"
cmd /c mklink /J "$env:USERPROFILE\.hermes\skills\autodev" "$env:USERPROFILE\.hermes\autodev\skills"
```

### Option 2: Skills CLI (if available)

```bash
npx skills add GoCodeAlone/autonomous-dev-kit -a hermes-agent --skill '*' -y
```

### Option 3: Direct SKILL.md install via Hermes CLI

```bash
# Install individual skills from the repository
hermes skills install https://raw.githubusercontent.com/GoCodeAlone/autonomous-dev-kit/main/skills/brainstorming/SKILL.md
hermes skills install https://raw.githubusercontent.com/GoCodeAlone/autonomous-dev-kit/main/skills/writing-plans/SKILL.md
# ... repeat for each skill you want
```

## Verify Installation

Start a new Hermes session and ask for something that should trigger a skill:

```
help me plan this feature
```

Hermes should automatically invoke the `autodev/brainstorming` skill.

Verify skills are discovered:

```bash
ls -la ~/.hermes/skills/autodev
```

You should see the skills directory symlinked to your autodev checkout.

## Updating

```bash
cd ~/.hermes/autodev && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.hermes/skills/autodev
```

Optionally delete the clone: `rm -rf ~/.hermes/autodev`.

## Cross-LLM Behavior

Autonomous Dev Kit skills use `<host: claude-code>` blocks to gate Claude Code-only content. Hermes Agent skips those blocks automatically; no configuration needed.

To enable host-conditional logic inside skills (so skills can adapt behavior per host), Hermes Agent auto-detects itself as the host. Skills that inspect the host context will use it to pick the right execution path.

## Tool Mapping

When skills reference Claude Code tools, Hermes Agent maps them as follows:

| Claude Code Tool | Hermes Agent Equivalent |
|---|---|
| `TodoWrite` | `todo` tool (built-in) |
| `Agent` (subagent) | `delegate_task` tool |
| `Task` with subagents | `delegate_task` with `goal` + `context` |
| `TeamCreate` / `TeamDelete` | Not applicable — Hermes uses sequential `delegate_task` |
| `SendMessage` (team DM) | Not applicable — Hermes returns subagent results directly |
| `EnterPlanMode` | Prose planning in chat |
| `Skill` tool | `skill_view` / `skills_list` |
| File operations | `read_file`, `write_file`, `patch`, `search_files` |
| `Bash` | `terminal` tool |
| `AskUserQuestion` | `clarify` tool |

## Host Declaration

Hermes Agent identifies itself automatically. No manual host declaration is needed.
