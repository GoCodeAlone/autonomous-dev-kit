# Installing Autonomous Dev Kit for Codex

Enable autodev skills in Codex via native skill discovery. Prefer the
`skills` CLI when Node is available; clone and symlink manually as a fallback.

## Prerequisites

- Git
- Node.js 18+ for `npx skills add` install

## Installation

### Recommended: Skills CLI

From your project root:

```bash
npx skills add GoCodeAlone/autonomous-dev-kit -a codex --skill '*' -y
```

For user/global install:

```bash
npx skills add GoCodeAlone/autonomous-dev-kit -a codex --skill '*' -g -y
```

Restart Codex after install.

### Manual fallback

1. **Clone the autodev repository:**
   ```bash
   git clone https://github.com/GoCodeAlone/autonomous-dev-kit.git ~/.codex/autodev
   ```

2. **Create the skills symlink:**
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.codex/autodev/skills ~/.agents/skills/autodev
   ```

   **Windows (PowerShell):**
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.agents\skills"
   cmd /c mklink /J "$env:USERPROFILE\.agents\skills\autodev" "$env:USERPROFILE\.codex\autodev\skills"
   ```

3. **Restart Codex** (quit and relaunch the CLI) to discover the skills.

## Migrating from old bootstrap

If you installed autodev before native skill discovery, you need to:

1. **Update the repo:**
   ```bash
   cd ~/.codex/autodev && git pull
   ```

2. **Create the skills symlink** (step 2 above) — this is the new discovery mechanism.

3. **Remove the old bootstrap block** from `~/.codex/AGENTS.md` — any block referencing `autodev-codex bootstrap` is no longer needed.

4. **Restart Codex.**

## Verify

```bash
ls -la ~/.agents/skills/autodev
```

You should see a symlink (or junction on Windows) pointing to your autodev skills directory.

## Updating

```bash
cd ~/.codex/autodev && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.agents/skills/autodev
```

Optionally delete the clone: `rm -rf ~/.codex/autodev`.

## Cross-LLM Behavior

Autonomous Dev Kit skills use `<host: claude-code>` blocks to gate Claude Code-only content. Codex skips those blocks automatically; no configuration needed.

To enable host-conditional logic inside skills (so skills can adapt behavior per host), declare your host in `~/.codex/AGENTS.md`:

```markdown
# Autonomous Dev Kit host declaration
Host: codex
```

Add this block once. Skills that inspect the host context will use it to pick the right execution path.
