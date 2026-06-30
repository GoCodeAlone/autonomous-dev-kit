# Cross-LLM Capability Coverage

Host-by-host capability matrix for the Autonomous Dev Kit skills system.

`✅` = fully supported  `⚠️` = partial / workaround required  `❌` = not supported

| Capability | Claude Code | Codex CLI | OpenCode | Cursor | Hermes Agent | Zed Agent |
|---|---|---|---|---|---|---|
| SKILL.md import | ✅ native | ✅ native | ✅ native | ✅ plugin manifest defines skills/agents/commands/hooks; install via `/plugin-add autodev` | ✅ native via `~/.hermes/skills/` symlink or `hermes skills install` | ✅ native via flat direct children under `~/.agents/skills/` or `<worktree>/.agents/skills/` |
| Sub-agent dispatch | ✅ `Agent` tool | ✅ natural language | ⚠️ `@mention` to peer sessions | ❌ not documented | ✅ `delegate_task` tool | ⚠️ native subagent tool when available; otherwise parallel Zed Agent threads |
| Agent Teams (persistent multi-agent DM) | ✅ experimental flag | ❌ | ❌ | ❌ | ❌ (uses sequential `delegate_task`) | ❌ (use Threads Sidebar / worktree isolation) |
| Background agents | ✅ `run_in_background` | ⚠️ thread-based; no explicit background flag | ❌ not documented | ❌ not documented | ✅ `terminal(background=true)` | ⚠️ multiple threads; no ADK lifecycle hook reinvocation |
| MCP servers | ✅ | ✅ `config.toml` | ✅ | ⚠️ partial | ✅ `hermes mcp` | ✅ Zed Agent Settings / `context_servers` |
| Slash commands | ✅ | ✅ 30+ built-ins incl. `/plan`, `/agent`, `/review` | ✅ | ✅ | ✅ 40+ built-ins | ✅ skill slash commands and @-mentions |
| Plan mode | ✅ `EnterPlanMode` + Shift-Tab | ✅ `/plan` slash | ⚠️ not documented; use prose planning | ⚠️ built-in Composer; not slash-invokable | ⚠️ prose planning in chat | ⚠️ prose planning / Agent Panel workflow |
| Task list / TodoWrite | ✅ built-in | ❌ no documented equivalent | ⚠️ `update_plan` mapping (see `.opencode/INSTALL.md`) | ⚠️ unknown | ✅ `todo` tool (built-in) | ⚠️ orchestrator checklist; no ADK shared queue |
| AGENTS.md / project context | CLAUDE.md | AGENTS.md (+ `.override.md`) | AGENTS.md | n/a | AGENTS.md (cwd only), `.hermes.md` (parent walk) | `~/.config/zed/AGENTS.md`; project `AGENTS.md` and compatible instruction files |
| Host declaration for skill conditionals | `Host: claude-code` in CLAUDE.md | `Host: codex` in `~/.codex/AGENTS.md` | `Host: opencode` in `~/.config/opencode/AGENTS.md` | n/a | Auto-detected as `hermes-agent` | `Host: zed-agent` in `~/.config/zed/AGENTS.md` or `%APPDATA%\\Zed\\AGENTS.md` |
| Skill discovery path (user scope) | `~/.claude/skills/` (personal skills); autodev installed to `~/.claude/plugins/marketplace/autodev/` via marketplace | `~/.agents/skills/` | `~/.config/opencode/skills/` | via plugin (no manual symlink) | `~/.hermes/skills/` (symlink or `hermes skills install`) | `~/.agents/skills/<skill-name>/` (flat; no namespace folder) |
| Model tier vocabulary | role names → `haiku`/`sonnet`/`opus` (see `agents/model-tiers.md`) | role names → `gpt-5.4-mini`/`gpt-5.4`/`gpt-5.5` | role names → host-pass-through | role names → host-pass-through | role names → host-pass-through | role names → host-pass-through |

## Notes

**Sub-agent dispatch (Codex):** Codex uses natural-language spawn ("spawn one agent per X") rather than an explicit `Agent` tool call. The `<host: codex>` blocks in skills provide the correct phrasing.

**Agent Teams:** The `TeamCreate` / `SendMessage` persistent-chat pattern is exclusive to Claude Code (experimental flag). Skills fall back to **Sequential Mode** (one sub-agent at a time) on all other hosts — see `skills/subagent-driven-development/SKILL.md`.

**Task list (Codex):** No built-in task-tracking tool is documented in Codex CLI. Skills that reference `TodoWrite` wrap those references in `<host: claude-code>` blocks; the host-neutral path uses prose checklists.

**Cursor:** The `.cursor-plugin/plugin.json` manifest defines `skills`, `agents`, `commands`, and `hooks`. Installation is via `/plugin-add autodev` in the Cursor agent chat (same marketplace mechanism as Claude Code). Skill discovery path (user scope) is managed through the plugin; no manual symlink required.

**Zed Agent:** Zed Skills apply only to Zed Agent, not ACP External Agents or Terminal Threads. Zed requires a flat skills layout, so ADK installs each `skills/<name>/` directory directly under `~/.agents/skills/` or `<worktree>/.agents/skills/`; project-local skills require a trusted worktree. Zed does not expose the Claude/Codex lifecycle hook contract for skill packages. Current Zed task hooks are narrower (`create_worktree` is the documented event), so ADK hook-driven reminders use manual skill fallbacks and optional Zed Tool Permissions on Zed.

## Related files

- `tests/cross-llm-coverage.md` — per-skill host-conditional vs host-neutral audit
- `tests/skill-content-grep.sh` — CI guard: fails if forbidden tokens appear outside `<host: claude-code>` blocks
- `.codex/INSTALL.md` — Codex setup instructions
- `.opencode/INSTALL.md` — OpenCode setup instructions
- `.zed/INSTALL.md` — Zed Agent setup instructions
- `agents/model-tiers.md` — role-to-model-name resolution table (fast / balanced / frontier / coding-specialist)
