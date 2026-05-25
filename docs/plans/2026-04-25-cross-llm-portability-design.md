# Cross-LLM Portability Design

**Goal:** Make the autodev skills repo first-class on Claude Code, Codex, OpenCode, and Cursor without forking content per host.

**Status:** Design only. Implementation will be queued to a separate plan and dispatched to implementer agents.

**Date:** 2026-04-25

---

## Problem

The autodev repo currently ships installers for four hosts (Claude Code, Codex, OpenCode, Cursor) but the skill bodies are heavily Claude-specific. An audit of the 17 skills found:

- 11 of 17 skills (65%) reference Claude-only tool names: `TodoWrite`, `TaskCreate`, `TaskList`, `TeamCreate`, `SendMessage`, `Agent`, `Monitor`.
- 8 of 17 reference Claude model tier names (`Sonnet`, `Opus`, `Haiku`) that have no analogue in other hosts.
- Several skills assume Claude-specific UX features such as the `EnterPlanMode` tool / `Shift+Tab` gesture.
- One skill (`subagent-driven-development`) is built around a Claude experimental feature (Agent Teams + persistent named teammates + cross-agent chat) that has **no equivalent on any other host**.

The Codex install plumbing already symlinks `~/.agents/skills/autodev` — which is exactly the path Codex documents for user-scope skill discovery. The plumbing is correct; **the bleed is in the content**.

A non-Claude user installing these skills will read prose that references tools their host does not expose, model names their host does not understand, and gestures that don't exist. Skills with this content cannot reliably trigger their intended behavior on a non-Claude host.

## Constraints and non-goals

**Constraints (hard):**

- The existing install model (clone + symlink, `git pull` for updates) must keep working. No installer-time forking of skill content.
- Skills must remain a **single source of truth** on disk. Every host reads the same files.
- Frontmatter must remain `name` + `description` only. SKILL.md frontmatter is constrained to those two fields by Claude's spec; Codex follows the same convention. Adding new top-level fields breaks Claude's loader.
- Existing user-facing skill names (e.g. `autodev:brainstorming`) must remain stable. No renames.
- Branch protection on `main` is active; every change is a PR, no direct push.
- This repo is public — all content remains free of internal-project / company / version / incident references.

**Non-goals (intentionally deferred):**

- Adding Codex-only or OpenCode-only **new** skills. The scope is making the existing 17 portable, not expanding the catalog.
- Building a full Codex plugin (`.codex-plugin/plugin.json`) for marketplace listing. The symlink-based install is documented and works; marketplace listing is a follow-up once Codex's plugin directory opens for self-serve.
- Solving the Cursor install path (Cursor has a stub `.cursor-plugin/plugin.json`; full Cursor support is a separate workstream).
- Writing host-detection code that runs at runtime. We rely on per-host preamble files (`CLAUDE.md`, `AGENTS.md`, etc.) to set context.

## Research summary (informs every choice below)

Codex (April 2026) has matured significantly since the audit. Pasting the relevant facts so the design choices are legible:

- **Codex skills**: `SKILL.md` with `name` + `description` frontmatter. Discovery walks `.agents/skills` → `$HOME/.agents/skills` → `/etc/codex/skills`. **Frontmatter shape is identical to Claude.**
- **Codex subagents**: TOML files at `~/.codex/agents/<name>.toml` defining `name`, `description`, `developer_instructions`. Spawned via natural language ("spawn one agent per X"). No `Agent`-tool API surface; orchestration is internal.
- **Codex plugins**: `.codex-plugin/plugin.json` manifest. Marketplace at `~/.agents/plugins/marketplace.json`. Self-serve publish "coming soon".
- **Codex AGENTS.md**: same multi-tier hierarchy as Claude's CLAUDE.md, with `.override.md` precedence.
- **Codex MCP**: `[mcp_servers.<name>]` in `~/.codex/config.toml`. Identical MCP standard.
- **Codex slash commands**: ~30 built-ins including `/plan`, `/agent`, `/review`, `/diff`, `/model`. Codex **does** have plan mode, contrary to the audit's assumption.
- **Codex models**: version-numbered (`gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.3-codex`, etc). No tier vocabulary like Haiku/Sonnet/Opus.
- **Codex has no built-in for shared task list across subagents** and no built-in for cross-subagent chat. The Agent Teams pattern in `subagent-driven-development` does not have a direct port.

Full research notes: `/tmp/codex-research-notes.md`.

## Approach options considered

### Option A — installer-time substitution (audit's original recommendation)

Store host-specific tool aliases in skill frontmatter, then run a substitution pass at install time so each host gets a different on-disk copy of `SKILL.md`.

**Pros:** Each skill body reads natively to the model on each host.

**Cons (decisive):**
- Forks content per host — breaks the symlink-based install and `git pull` refresh.
- Substitution can't fix **semantic** mismatches (Codex has no `TaskCreate` analogue at all; renaming the tool doesn't make the workflow valid).
- Frontmatter is limited to `name` + `description`; adding tool-alias fields requires either schema extension (which Claude rejects) or stuffing aliases in the description (which collides with skill triggering).
- Requires a CLI tool to do the substitution; users currently install with two `git clone` + `ln -s` commands.

### Option B — host-conditional sections inline (recommended)

Single skill body per skill. Where a section depends on host capabilities, use **inline conditional blocks** keyed by host name. Use a **role-based vocabulary** for model tiers (`fast` / `balanced` / `frontier`) instead of brand names. Move the Agent-Teams pattern into a **conditionally-included Claude-only addendum** that the host-aware skill body links to but does not require.

The host context is established by a small preamble in each host's entry point file — `CLAUDE.md`, `~/.codex/AGENTS.md`, OpenCode plugin context — that names the host. Skills then read host-specific sections.

**Pros:**
- One source of truth on disk. Symlink install + `git pull` refresh keeps working.
- No installer changes required. Existing `.codex/INSTALL.md` and `.opencode/INSTALL.md` continue to work; minor updates only to record the new vocabulary.
- Semantic mismatches (e.g. "no Codex equivalent for cross-agent chat") become explicit fall-throughs in prose, not silent renames.
- Frontmatter stays `name` + `description`.
- Reviewers and skill authors can read every conditional path side by side.

**Cons:**
- Skill bodies grow somewhat (each conditional adds prose).
- Model has to read the right host section. Mitigated by (a) tagging sections with explicit `<host:claude>`-style markers, (b) putting the host-detection rule prominently in `using-autodev`.
- Requires discipline: every author touching a skill must keep all host paths in sync.

### Option C — top-level "tool alias" registry file

Add `agents/tool-aliases.md` (markdown table mapping role → tool name per host). Skills reference roles (`task_queue`, `agent_spawn`) instead of concrete tool names. Each host's preamble overrides the aliases.

**Pros:** Single source of truth for the mapping; skills read uniformly across hosts.

**Cons:**
- Same semantic-mismatch problem as Option A: an alias entry of `task_queue: codex=null` doesn't tell the skill how to behave on Codex; the **skill itself** still has to encode the fallback.
- Adds an indirection: model has to read `agents/tool-aliases.md` to know what `task_queue` resolves to. That's a load-time cost on every skill.
- Tool aliases can paper over name differences but cannot encode workflow differences (e.g. Claude does TeamCreate-then-monitor; Codex does sequential-spawn-and-collect).

### Recommendation: Option B + a small Option C component

Adopt **Option B (host-conditional sections + role-based vocabulary)** as the primary approach. Add **one targeted artifact from Option C**: a single `agents/model-tiers.md` table that resolves `fast` / `balanced` / `frontier` → host-specific model name. This is the only place the alias-table indirection is worth its cost, because model names appear in many skills and are pure identifiers (no workflow semantics).

For tool names and workflow patterns: handle inline. Specifically:

- Where a tool name has a direct cross-host equivalent, use a generic phrase plus a parenthetical: "shared task list (`TodoWrite` on Claude Code; `update_plan` on OpenCode; absent on Codex — see fallback below)".
- Where there is no cross-host equivalent, document the fallback workflow explicitly in the skill body, gated behind a host-conditional marker.

## Design

### 1. Host-detection preamble

Each host's existing entry point file gets a one-line declaration at the top:

| Host | Entry-point file | Declaration |
|---|---|---|
| Claude Code | `CLAUDE.md` | `Host: claude-code` |
| Codex | `~/.codex/AGENTS.md` | `Host: codex` |
| OpenCode | `~/.config/opencode/AGENTS.md` (Codex-compatible) | `Host: opencode` |
| Cursor | `.cursorrules` | `Host: cursor` |

Skills read this declaration when deciding which conditional sections to honor.

We do **not** edit the user's CLAUDE.md / AGENTS.md directly. We document the declaration in the host's INSTALL.md and provide a one-paragraph block users append. Existing users are not affected — skills behave correctly without the declaration too, defaulting to host-neutral language.

### 2. Host-conditional section markers

Skill bodies use these two markers inline:

```
<host: claude-code>
…content for Claude Code only…
</host>

<host: codex, opencode>
…content for Codex and OpenCode…
</host>
```

A section without a `<host:>` marker is host-neutral and applies to all.

These are **prose markers**, not parser directives. They use angle-bracket tag syntax that most markdown renderers treat as unknown HTML tags and render harmlessly, but the model reads them and skips non-matching sections. We document this convention in `skills/writing-skills/SKILL.md` so future authors follow it.

Example (excerpt from rewritten `subagent-driven-development`):

```markdown
## Spawning teammates

<host: claude-code>
Use the `Agent` tool with `team_name`, `name`, `subagent_type`, and `model` parameters.
The `TeamCreate` and `SendMessage` tools coordinate the team.
…
</host>

<host: codex, opencode, cursor>
Codex and OpenCode do not provide a persistent team-chat surface. Use sequential
sub-agent dispatch: spawn one sub-agent per task, wait for it to return, then dispatch
the next. The role assignments (implementer, spec-reviewer, code-reviewer) still apply;
review still happens between tasks; the difference is that there is no shared chat
between sub-agents — the orchestrator routes messages serially.
…
</host>
```

### 3. Role-based model-tier vocabulary

Skills refer to model tiers by **role** (`fast` / `balanced` / `frontier` / `coding-specialist`) rather than by brand name. A new `agents/model-tiers.md` defines the mapping per host:

| Role | Claude Code | Codex | OpenCode | Cursor |
|---|---|---|---|---|
| `fast` | `haiku` | `gpt-5.4-mini` | host-pass-through | host-pass-through |
| `balanced` | `sonnet` | `gpt-5.4` | host-pass-through | host-pass-through |
| `frontier` | `opus` | `gpt-5.5` | host-pass-through | host-pass-through |
| `coding-specialist` | `sonnet` | `gpt-5.3-codex` | host-pass-through | host-pass-through |

Skills cite this table once: "Use a `balanced`-tier model — see `agents/model-tiers.md` for the host-specific name."

OpenCode and Cursor use `host-pass-through` in the table, meaning the host uses whatever model the user has selected in its own configuration; the user's host config drives the choice.

### 4. Workflow patterns with semantic gaps

Three patterns in the current skills have no cross-host equivalent. Each gets a documented fallback:

#### 4.1 Persistent team chat (TeamCreate / SendMessage)

Used heavily in `subagent-driven-development`. **No equivalent on Codex / OpenCode / Cursor.**

**Fallback for non-Claude hosts:** sequential sub-agent dispatch. The orchestrator (a) spawns implementer-1, (b) waits for it to return with a summary, (c) spawns spec-reviewer with the implementer's output, (d) waits, (e) spawns code-reviewer, etc. No cross-agent chat — the orchestrator carries state.

This is precisely the "Legacy Mode (Sequential Subagents)" path already documented in `skills/subagent-driven-development/SKILL.md`. We rename "Legacy Mode" to **"Sequential Mode"** (which doesn't carry a "deprecated" connotation) and reverse the framing: Sequential Mode is the **default**; Agent Teams is a Claude-Code-only enhancement.

#### 4.2 Shared task list (TodoWrite / TaskCreate)

Used in `executing-plans`, `subagent-driven-development`, `using-autodev`. Claude has `TodoWrite` (single-agent) and `TaskCreate` (Agent Teams shared list). OpenCode has `update_plan`. Codex and Cursor have no built-in.

**Fallback for hosts without a task-list tool:** in-prose checklist in the conversation transcript. The orchestrator maintains a markdown checklist in chat output; sub-agents are passed a copy. Less ergonomic than a real task tool but functionally equivalent for a single session.

We document this fallback once in `using-autodev` and reference it from the skills that depend on the pattern.

#### 4.3 Plan Mode (`EnterPlanMode` + Shift-Tab)

Used in `writing-plans`. Claude has its native Plan Mode tool. **Codex has `/plan` slash command.** OpenCode and Cursor have no plan mode.

**Fix:** the skill currently says "If Plan Mode is not available (Cursor, Codex, OpenCode), use the Built-In Planning Process." That's wrong as of April 2026 — Codex now has `/plan`. Update to:

```
<host: claude-code>
Prefer Claude's native Plan Mode (Shift-Tab or EnterPlanMode tool).
</host>
<host: codex>
Use Codex's `/plan` slash command.
</host>
<host: opencode, cursor>
Use the Built-In Planning Process described below.
</host>
```

### 5. Per-skill changes

The 17 skills divide into three groups based on bleed level:

#### Group I — already portable (6 skills)

- `test-driven-development`
- `systematic-debugging`
- `verification-before-completion`
- `using-git-worktrees`
- `runtime-launch-validation`
- `requesting-code-review`

These reference no host-specific tools or model tiers. Audit pass: no changes.

#### Group II — moderate bleed: model tier names + minor tool refs (5 skills)

- `alignment-check`
- `pr-monitoring`
- `receiving-code-review`
- `finishing-a-development-branch`
- `brainstorming`

Changes per skill:

1. Replace brand model names (`sonnet`, `opus`, `haiku`) with role names (`balanced`, `frontier`, `fast`).
2. Add a one-line reference to `agents/model-tiers.md`.
3. Replace any tool-name reference (e.g. `Agent tool (general-purpose, model: sonnet)`) with the host-conditional pattern from §2.

Estimated: 5–15 line diff per skill.

#### Group III — heavy bleed: workflow patterns (6 skills)

- `subagent-driven-development` — heaviest; rewritten around Sequential Mode default with Agent Teams as Claude-only addendum.
- `dispatching-parallel-agents` — `Task("…")` examples need host-conditional rewrite.
- `writing-plans` — Plan Mode logic gets host-conditional update; Sonnet/Opus/Haiku → role names.
- `using-autodev` — Skill tool references already host-conditional; add explicit host-detection pointer + task-list fallback.
- `executing-plans` — `TodoWrite` references → "shared task list" + fallback.
- `writing-skills` — already mentions `~/.agents/skills/` for Codex; expand with host-conditional rewrite + the alias-marker convention.

Estimated: 30–80 line diff per skill, mostly additions for the conditional sections.

### 6. New shared file

**`agents/model-tiers.md`** — single source of truth for the role-name → host-specific-model-name mapping (table from §3). Cited by every skill that names a model tier. ~30 lines.

### 7. Documentation updates

- `README.md` — add a "Cross-LLM compatibility" section listing the four hosts, their install paths, what's natively supported, and what falls back to a Sequential workflow. Keep the section short (~15 lines).
- `docs/README.codex.md` — update the install instructions to mention the host declaration in `AGENTS.md` and the role-name vocabulary.
- `docs/README.opencode.md` — same updates for OpenCode.
- `.codex/INSTALL.md` and `.opencode/INSTALL.md` — already correct; add a one-paragraph note pointing to the host declaration.
- `agents/team-conventions.md` — already host-neutral; one paragraph added clarifying that team-conventions applies to both Sequential and Agent-Teams modes.

### 8. Tests / evidence

The repo currently has a `tests/` directory but no skills tests we can re-run for cross-host coverage. We add **two evidence artifacts** rather than executable tests:

1. **`tests/cross-llm-coverage.md`** — a manually-maintained table mapping every skill × host to "host-conditional?", "tested in baseline?", "documented fallback?". This is the alignment artifact for future audits.
2. **`tests/skill-content-grep.sh`** — a shell script that grep-fails the skills tree for forbidden tokens (`Sonnet`, `Opus`, `Haiku`, `TeamCreate`, etc.) **outside** of `<host: claude-code>` blocks. Run as part of CI / pre-commit. ~30 lines of bash.

This pairs the documentation discipline with a mechanical guard against regressions.

## Risks and trade-offs

**Risk: model ignores the host marker and reads the wrong section.**

Mitigation:
- The marker convention is documented in `using-autodev` (the entry-point skill the model loads first).
- Skills include short explicit cues like "On Codex, do X." inside the conditional block, so even a model that under-weighs the marker tends to do the right thing.
- The `tests/skill-content-grep.sh` guard catches the common error of authoring host-specific content outside a marker.

**Risk: skill bodies grow large.**

Mitigation: most conditionals are small (1–3 lines). The two skills with the largest expected growth (`subagent-driven-development`, `writing-plans`) already exceed 200 lines; another 30–50 lines is in line with their existing density. We accept this trade-off.

**Risk: future hosts (more than four) require N-way conditionals.**

Mitigation: we already have an "everything-else" pattern — sections without a marker apply to all hosts. New hosts default to host-neutral content and only need their own conditional block where they meaningfully diverge. This is exactly the pattern Codex documents for AGENTS.md hierarchy and we mirror it.

**Risk: drift between skills and `agents/model-tiers.md`.**

Mitigation: the grep guard from §8 flags direct mention of Claude-Code brand model names in skill bodies (`Sonnet`, `Opus`, `Haiku`, and their lowercase forms) outside the `agents/model-tiers.md` table itself. Skills must use role names (`fast`, `balanced`, `frontier`, `coding-specialist`). The guard does not currently flag Codex model identifiers; those are addressed by the `<host: ...>` marker convention rather than the grep guard.

**Risk: re-naming "Legacy Mode" to "Sequential Mode" in `subagent-driven-development` confuses existing users.**

Mitigation: the rename is paired with a clear "Migrating from earlier docs" note at the top of the skill; the new "Sequential Mode" section explicitly states it is the same workflow previously documented as "Legacy Mode (Sequential Subagents)". No behavior change, just naming.

## Acceptance criteria

A user installing this repo on Codex (or OpenCode, or Cursor) and reading any of the 17 skills must:

1. Encounter no Claude-only tool name presented as the only option.
2. Encounter no Claude-only model tier name (`Sonnet`, `Opus`, `Haiku`).
3. Find a documented fallback for any workflow pattern that Claude uniquely supports (Agent Teams, TodoWrite, EnterPlanMode).
4. Be able to follow each skill's recommended workflow on their host without external context.
5. Have the existing install model (`git clone` + symlink) continue to work unchanged.

A user installing on Claude Code reads the same skill files and gets the Claude-Code-specific path inside each `<host: claude-code>` block, plus all the host-neutral content. Existing Claude users see no degradation.

CI guard passes (the grep test from §8 finds no forbidden tokens outside markers).

The `tests/cross-llm-coverage.md` table shows every skill × host has either "host-conditional" or "host-neutral" status with no gaps.

## Decisions made during implementation planning

The following questions were open at design time and have since been resolved:

- **Grep-guard implementation.** Single-pass AWK script (`tests/skill-content-grep.sh`). AWK tracks line numbers while skipping exclusive `<host: claude-code>` blocks; grep runs per-token on the annotated output. Multi-host blocks such as `<host: codex, claude-code>` are NOT skipped — content there is shown to codex users and must not contain Claude-only tokens.

- **Host-marker syntax.** `<host: claude-code>` … `</host>` (angle-bracket form). Rationale: visible when reading the document, including in rendered Markdown — unlike HTML-comment form which renderers hide; most markdown renderers treat unknown tags harmlessly.

- **OpenCode plugin tool-mapping.** Rewritten skills use `update_plan` in `<host: opencode>` blocks where they previously used `TodoWrite`. The `.opencode/INSTALL.md` mapping is the source of truth.

- **Cursor support depth.** Cursor's `.cursor-plugin/plugin.json` remains a stub. Skills will include `<host: cursor>` blocks where they meaningfully diverge; the install path for Cursor is a separate follow-up outside this scope.

## Reference

- Research notes on Codex / GPT-5.5 / OpenCode capabilities: `/tmp/codex-research-notes.md`.
- Existing audit: 11 of 17 skills have Claude-tool bleed (provided by orchestrator).
- Existing install plumbing: `.codex/INSTALL.md`, `.opencode/INSTALL.md`, `.claude-plugin/`, `.cursor-plugin/`.

## Next step

Hand off to `autodev:writing-plans` in `--design-only` mode. The plan will halt at alignment-check PASS for orchestrator review; implementation will be dispatched separately.
