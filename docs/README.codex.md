# Autonomous Dev Kit for Codex

Guide for using Autonomous Dev Kit with OpenAI Codex via native skill discovery.

## Quick Install

From your project root:

```bash
npx skills add GoCodeAlone/autonomous-dev-kit -a codex --skill '*' -y
```

For user/global install:

```bash
npx skills add GoCodeAlone/autonomous-dev-kit -a codex --skill '*' -g -y
```

Restart Codex after install.

Manual fallback: tell Codex:

```
Fetch and follow instructions from https://raw.githubusercontent.com/GoCodeAlone/autonomous-dev-kit/refs/heads/main/.codex/INSTALL.md
```

## Manual Installation

### Prerequisites

- OpenAI Codex CLI
- Git
- Node.js 18+ if using `npx skills add`

### Steps

1. Clone the repo:
   ```bash
   git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git ~/.codex/autodev
   ```

2. Create the skills symlink:
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.codex/autodev/skills ~/.agents/skills/autodev
   ```

3. Restart Codex.

### Windows

Use a junction instead of a symlink (works without Developer Mode):

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.agents\skills"
cmd /c mklink /J "$env:USERPROFILE\.agents\skills\autodev" "$env:USERPROFILE\.codex\autodev\skills"
```

## How It Works

Codex has native skill discovery — it scans `~/.agents/skills/` at startup, parses SKILL.md frontmatter, and loads skills on demand. Autonomous Dev Kit skills are made visible through a single symlink:

```
~/.agents/skills/autodev/ → ~/.codex/autodev/skills/
```

The `using-autodev` skill is discovered automatically and enforces skill usage discipline — no additional configuration needed.

## Usage

Skills are discovered automatically. Codex activates them when:
- You mention a skill by name (e.g., "use brainstorming")
- The task matches a skill's description
- The `using-autodev` skill directs Codex to use one

### Personal Skills

Create your own skills in `~/.agents/skills/`:

```bash
mkdir -p ~/.agents/skills/my-skill
```

Create `~/.agents/skills/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Use when [condition] - [what it does]
---

# My Skill

[Your skill content here]
```

The `description` field is how Codex decides when to activate a skill automatically — write it as a clear trigger condition.

## Updating

```bash
cd ~/.codex/autodev && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.agents/skills/autodev
```

**Windows (PowerShell):**
```powershell
Remove-Item "$env:USERPROFILE\.agents\skills\autodev"
```

Optionally delete the clone: `rm -rf ~/.codex/autodev` (Windows: `Remove-Item -Recurse -Force "$env:USERPROFILE\.codex\autodev"`).

## Troubleshooting

### Skills not showing up

1. Verify the symlink: `ls -la ~/.agents/skills/autodev`
2. Check skills exist: `ls ~/.codex/autodev/skills`
3. Restart Codex — skills are discovered at startup

### Windows junction issues

Junctions normally work without special permissions. If creation fails, try running PowerShell as administrator.

## Cross-LLM Behavior

Autonomous Dev Kit skills use `<host: claude-code>` blocks to gate content that only applies to Claude Code (Agent Teams, specific tool names, etc.). On Codex, those blocks are skipped — the rest of the skill runs as-is.

To let skills detect that they are running on Codex, add a host declaration to your `~/.codex/AGENTS.md`:

```markdown
Host: codex
```

This single line enables host-conditional skill logic. See `.codex/INSTALL.md` for the full declaration snippet.

## Getting Help

- Report issues: https://github.com/GoCodeAlone/autonomous-dev-kit/issues
- Main documentation: https://github.com/GoCodeAlone/autonomous-dev-kit
