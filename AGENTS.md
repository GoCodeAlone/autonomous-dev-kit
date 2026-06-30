# Autonomous Dev Kit

This repository contains the Autonomous Dev Kit — a plugin bundling skills, hooks, agents, and commands for coding agents (Claude Code, Codex, OpenCode, Cursor, and Hermes Agent).

## Project Structure

- `skills/` — SKILL.md files (the core reusable workflows)
- `hooks/` — Shell scripts that fire at session/tool lifecycle events
- `agents/` — Agent role definitions and team conventions
- `commands/` — Slash command definitions
- `tests/` — Test scripts for skill content, hooks, and contracts
- `.claude-plugin/` — Claude Code plugin manifest
- `.cursor-plugin/` — Cursor plugin manifest
- `.codex/` — Codex installation instructions
- `.opencode/` — OpenCode installation instructions
- `.hermes/` — Hermes Agent installation instructions
- `.github/workflows/` — CI pipelines

## Building and Testing

Run the test scripts before committing:

```bash
# Skill content checks (host-neutrality, path canonicalization, cross-refs)
bash tests/skill-content-grep.sh
bash tests/adk-path-canonicalization.sh
bash tests/pipeline-evidence-doc-sync.sh
bash tests/skill-cross-refs.sh
bash tests/brainstorm-visual-companion.sh

# Hook contract tests
bash tests/hook-contracts.sh
bash tests/hook-stdout-discipline.sh
bash tests/plan-scope-check-contracts.sh

# Version consistency
bash tests/version-check.sh
```

## Adding Skills

Follow `skills/writing-skills/SKILL.md` for the complete guide. Key rules:
- Skills use `<host: ...>` blocks to gate host-specific content
- Forbidden tokens (TodoWrite, TeamCreate, Sonnet, etc.) must only appear inside `<host: claude-code>` blocks
- Recognized hosts: `claude-code`, `codex`, `opencode`, `cursor`, `hermes-agent`, `zed-agent`

## Versioning

All plugin manifests must declare the same version. Use `scripts/bump-version.sh <new-version>` to update all manifests at once.
