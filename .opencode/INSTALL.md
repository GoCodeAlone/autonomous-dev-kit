# Installing Autonomous Dev Kit for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed
- Git installed

## Installation Steps

### 1. Clone Autonomous Dev Kit

```bash
git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git ~/.config/opencode/autodev
```

### 2. Register the Plugin

Create a symlink so OpenCode discovers the plugin:

```bash
mkdir -p ~/.config/opencode/plugins
rm -f ~/.config/opencode/plugins/autodev.js
ln -s ~/.config/opencode/autodev/.opencode/plugins/autodev.js ~/.config/opencode/plugins/autodev.js
```

### 3. Symlink Skills

Create a symlink so OpenCode's native skill tool discovers autodev skills:

```bash
mkdir -p ~/.config/opencode/skills
rm -rf ~/.config/opencode/skills/autodev
ln -s ~/.config/opencode/autodev/skills ~/.config/opencode/skills/autodev
```

### 4. Restart OpenCode

Restart OpenCode. The plugin will automatically inject autodev context.

Verify by asking: "do you have autodev?"

## Usage

### Finding Skills

Use OpenCode's native `skill` tool to list available skills:

```
use skill tool to list skills
```

### Loading a Skill

Use OpenCode's native `skill` tool to load a specific skill:

```
use skill tool to load autodev/brainstorming
```

### Personal Skills

Create your own skills in `~/.config/opencode/skills/`:

```bash
mkdir -p ~/.config/opencode/skills/my-skill
```

Create `~/.config/opencode/skills/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Use when [condition] - [what it does]
---

# My Skill

[Your skill content here]
```

### Project Skills

Create project-specific skills in `.opencode/skills/` within your project.

**Skill Priority:** Project skills > Personal skills > Autonomous Dev Kit skills

## Updating

```bash
cd ~/.config/opencode/autodev
git pull
```

## Troubleshooting

### Plugin not loading

1. Check plugin symlink: `ls -l ~/.config/opencode/plugins/autodev.js`
2. Check source exists: `ls ~/.config/opencode/autodev/.opencode/plugins/autodev.js`
3. Check OpenCode logs for errors

### Skills not found

1. Check skills symlink: `ls -l ~/.config/opencode/skills/autodev`
2. Verify it points to: `~/.config/opencode/autodev/skills`
3. Use `skill` tool to list what's discovered

### Tool mapping

When skills reference Claude Code tools:
- `TodoWrite` → `update_plan`
- `Task` with subagents → `@mention` syntax
- `Skill` tool → OpenCode's native `skill` tool
- File operations → your native tools

## Cross-LLM Behavior

Autonomous Dev Kit skills use `<host: claude-code>` blocks to gate Claude Code-only content. OpenCode skips those blocks automatically; no configuration needed.

To enable host-conditional logic inside skills (so skills can adapt behavior per host), declare your host in `~/.config/opencode/AGENTS.md`:

```markdown
# Autonomous Dev Kit host declaration
Host: opencode
```

Add this block once. Skills that inspect the host context will use it to pick the right execution path.

## Getting Help

- Report issues: https://github.com/GoCodeAlone/autonomous-dev-kit/issues
- Full documentation: https://github.com/GoCodeAlone/autonomous-dev-kit/blob/main/docs/README.opencode.md
