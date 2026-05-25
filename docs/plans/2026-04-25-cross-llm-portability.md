# Cross-LLM Portability Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Make the 17 autodev skills first-class on Claude Code, Codex, OpenCode, and Cursor by replacing brand-specific tool names + model tiers with host-conditional sections + a role-based vocabulary, with a CI guard against regression.

**Architecture:** Single-source skills on disk. Inline `<host: …>` markers gate host-specific paragraphs. Model tiers expressed by role (`fast` / `balanced` / `frontier` / `coding-specialist`) and resolved through `agents/model-tiers.md`. Workflow patterns with no cross-host equivalent (Agent Teams, shared task list, EnterPlanMode) get explicit fallbacks. A grep guard keeps Claude-only tokens out of host-neutral text.

**Tech Stack:** Markdown skill files; YAML frontmatter; bash/POSIX grep guard; existing symlink-based install (no installer changes).

---

## Mode

**Design-only mode is active** (orchestrator passed `--design-only`).

After alignment-check PASS, **STOP**. Do not invoke `autodev:subagent-driven-development`. The plan + design sit in `docs/plans/` for the team's persistent implementer agents to execute.

## Reading order for the implementer

1. The design doc: `docs/plans/2026-04-25-cross-llm-portability-design.md`. Mandatory; this plan does not duplicate the rationale.
2. Research notes (context only): `/tmp/codex-research-notes.md`. Optional but recommended.
3. The 17 skills under `skills/` for current state.

## Conventions for every task

- Branch off `main`. Each task or coherent group of tasks is a separate PR. Direct push to `main` is rejected by branch protection.
- Generic phrasing only — this is a public repo. No internal-project, company, version, or incident references.
- Commit messages describe **what changed**, not which review round.
- Run the grep guard from Task 1 before opening every PR.

## Group I — already portable (no rewrite needed)

The following six skills were audited and contain no Claude-only tool names or model-tier brand names. They should stay clean once the grep guard from Task 1 lands:

- `test-driven-development`
- `systematic-debugging`
- `verification-before-completion`
- `using-git-worktrees`
- `runtime-launch-validation`
- `requesting-code-review`

The grep guard (Task 1) and the cross-LLM coverage table (Task 18) verify these remain clean. No rewrite tasks are scheduled for them. If the guard reports a finding in any of these files, escalate before patching — it indicates an unintended regression in another in-flight PR.

## Group structure (suggested PR boundaries)

The plan is grouped so an orchestrator can dispatch each group as a self-contained PR. The implementation team can choose to combine adjacent groups if review bandwidth allows.

| Group | Tasks | Rough size | Suggested PR |
|---|---|---|---|
| A. Infrastructure | 1, 2, 3 | small | PR-A: shared infra (model tiers + grep guard + writing-skills marker convention) |
| B. Group II rewrites | 4, 5, 6, 7, 8 | small × 5 | PR-B: moderate-bleed skills (alignment-check, pr-monitoring, receiving-code-review, finishing-a-development-branch, brainstorming) |
| C. Group III rewrites | 9, 10, 11, 12, 13, 14 | medium × 6 | PR-C: heavy-bleed skills (subagent-driven-development, dispatching-parallel-agents, writing-plans, using-autodev, executing-plans, writing-skills extension) |
| D. Documentation | 15, 15b, 15c, 16, 17 | small | PR-D: README + INSTALL.md updates |
| E. Coverage table | 18 | small | PR-E: tests/cross-llm-coverage.md |

PRs A and E are the bookend infrastructure work. B, C, D are content edits and can run in parallel after A lands.

---

## Task 1: Add the grep guard test

**Files:**
- Create: `tests/skill-content-grep.sh`

**Goal:** A repeatable check that fails if a forbidden Claude-only token appears in a skill body **outside** an allowed context (a `<host: claude-code>` block, the model-tiers table, or a known-allowed file).

**Forbidden tokens (full word, matched in both title-case and lowercase):**

```
TodoWrite TaskCreate TaskUpdate TaskList TaskGet
TeamCreate TeamDelete SendMessage EnterPlanMode
Sonnet Opus Haiku
sonnet opus haiku
```

Model-brand names are flagged in both cases because skills may reference them
in YAML config (`model: sonnet`) as well as prose. Claude-specific tool names
that appear in existing skill files (`AskUserQuestion`, `Agent`) are not in the
initial token list; they will be added once those skills are migrated in PRs B–D.

**Step 1: Write the failing test**

The test is the script itself. Save as `tests/skill-content-grep.sh`:

```bash
#!/usr/bin/env bash
# tests/skill-content-grep.sh
# Fails if forbidden Claude-only tokens appear in skills/ or agents/ outside allowed contexts.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Tokens that must not appear in host-neutral skill text.
# Tool names below are Claude-Code-specific. Model-brand names are listed in
# both title-case and lowercase because skills may reference them in YAML
# (model: sonnet) as well as in prose. Skills must use role names instead
# (fast / balanced / frontier / coding-specialist) per agents/model-tiers.md.
# Note: Claude-specific tool names like AskUserQuestion and Agent are not in
# this list yet — they will be addressed as skills migrate in PRs B–D.
# Once migration is complete, add them here to prevent future bleed.
TOKENS=(
  TodoWrite TaskCreate TaskUpdate TaskList TaskGet
  TeamCreate TeamDelete SendMessage EnterPlanMode
  Sonnet Opus Haiku
  sonnet opus haiku
)

# Allowed files: tokens may appear here without restriction.
# Keep paths to files under skills/ or agents/ only — those are the
# directories that the find command below actually scans.
ALLOWED_FILES=(
  "agents/model-tiers.md"
)

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Find all markdown files under skills/ and agents/.
find skills agents -type f -name '*.md' -print0 \
  | while IFS= read -r -d '' file; do
      # Skip allowed files.
      for allowed in "${ALLOWED_FILES[@]}"; do
        if [ "$file" = "$allowed" ]; then
          continue 2
        fi
      done

      # Single-pass AWK: emit "LINENO:content" for lines outside exclusive
      # <host: claude-code> blocks. Only blocks tagged EXCLUSIVELY with
      # claude-code are skipped — a multi-host block like
      # <host: codex, claude-code> is NOT skipped because its content is also
      # shown to codex users who must not see Claude-only tokens.
      # Markers must appear at the start of a line (after optional whitespace).
      annotated="$(awk '
        BEGIN { skip = 0; ln = 0 }
        {
          ln++
          if (/^[[:space:]]*<host:[[:space:]]*claude-code[[:space:]]*>[[:space:]]*$/) { skip = 1; next }
          if (/^[[:space:]]*<\/host>/) { skip = 0; next }
          if (!skip) { print ln ":" $0 }
        }
      ' "$file")"

      for token in "${TOKENS[@]}"; do
        # grep -w for whole-word match; || true prevents non-zero exit on no matches.
        matches="$(printf '%s\n' "$annotated" | grep -w "$token" || true)"
        if [ -n "$matches" ]; then
          printf '%s\n' "$matches" | sed "s|^|$file:|" >> "$tmp"
        fi
      done
    done

if [ -s "$tmp" ]; then
  echo "FAIL: forbidden Claude-only tokens found outside <host: claude-code> blocks:"
  cat "$tmp"
  exit 1
fi

echo "PASS: skill content is host-neutral or properly conditional."
exit 0
```

**Step 2: Make it executable and run against the current tree**

```bash
chmod +x tests/skill-content-grep.sh
./tests/skill-content-grep.sh
```

**Expected:** FAIL — current skills have many forbidden tokens. Capture the output for reference; it confirms the guard finds the bleed the audit identified.

**Step 3: Commit the guard**

```bash
git add tests/skill-content-grep.sh
git commit -m "test: add AWK-based grep guard for Claude-only tokens in skill text"
```

The guard will go from FAIL → PASS as Tasks 4–14 land. We do **not** add it to CI in this task; that's Task 17 once content is clean.

**Verification class:** CLI command + representative invocation. Expected output: script runs, exits non-zero on the current tree, and lists token occurrences. Capture transcript in PR body.

---

## Task 2: Add the model-tier vocabulary table

**Files:**
- Create: `agents/model-tiers.md`

**Step 1: Write the table**

```markdown
# Model Tiers

Skills refer to model tiers by role rather than brand name so they read correctly
on every supported host. This file resolves each role to the host-specific model
identifier.

| Role | Claude Code | Codex | OpenCode | Cursor |
|---|---|---|---|---|
| `fast` | `haiku` | `gpt-5.4-mini` | host-pass-through | host-pass-through |
| `balanced` | `sonnet` | `gpt-5.4` | host-pass-through | host-pass-through |
| `frontier` | `opus` | `gpt-5.5` | host-pass-through | host-pass-through |
| `coding-specialist` | `sonnet` | `gpt-5.3-codex` | host-pass-through | host-pass-through |

`host-pass-through` means the host uses whatever model the user has selected in
its own configuration; skill prose should not name a specific model on those
hosts.

## How skills cite this table

Skill bodies refer to roles, not brand names:

> Use a `balanced`-tier model for spec review.

When the model is following the skill on a specific host, it resolves the role
through this table. Authors maintaining a skill must use role names, not
`Sonnet` / `Opus` / `Haiku`. The grep guard
(`tests/skill-content-grep.sh`) enforces the Claude-brand-name portion of this rule.

## Updating

When a host's model lineup changes, edit only this file. No skill body should
need to change for a model rename.
```

**Step 2: Verify file renders**

```bash
ls -l agents/model-tiers.md
head -1 agents/model-tiers.md
```

Expected: file exists; first line is `# Model Tiers`.

**Step 3: Commit**

```bash
git add agents/model-tiers.md
git commit -m "docs(agents): add model-tier role vocabulary table"
```

**Verification class:** Documentation. Expected: file present, table renders, no broken anchors.

---

## Task 3: Document the host-marker convention in writing-skills

**Files:**
- Modify: `skills/writing-skills/SKILL.md`

**Goal:** Future skill authors must know how to write host-conditional sections. Add a short section to `writing-skills` and the `<host:>` marker spec.

**Step 1: Add the section**

Insert after the existing "Directory Structure" section (around current line 90), a new section:

```markdown
## Host-Conditional Sections

Skills may need different content per host (Claude Code, Codex, OpenCode,
Cursor). Use inline `<host: …>` markers to gate host-specific prose. Sections
without a marker apply to every host.

### Syntax

```
<host: claude-code>
…content for Claude Code only…
</host>

<host: codex, opencode>
…content shared between Codex and OpenCode…
</host>
```

Markers are angle-bracket-shaped so they read like markdown elements. Comma-
separated host lists are allowed inside the opening tag. Nested markers are not
allowed.

**Why angle-bracket form, not HTML-comment form?** We considered
`<!-- host: claude-code -->` and rejected it. The angle-bracket form is
shorter, visible in PR diffs and skill author reviews, and renders in any
markdown viewer as plain text or an unknown element without breaking layout.
The HTML-comment form would render fully invisibly, which is a footgun:
authors can write host-conditional content and not notice the marker is
mis-spelled or unclosed. Visibility is the safer trade-off.

### Recognised host names

- `claude-code` — Anthropic Claude Code
- `codex` — OpenAI Codex CLI
- `opencode` — OpenCode.ai
- `cursor` — Cursor

Use exactly these strings. Adding a new host means updating this list, the
grep guard's allowed-context handling, and `agents/model-tiers.md`.

### When to use a marker vs host-neutral phrasing

Prefer host-neutral phrasing wherever possible:

> Use the shared task list to coordinate sub-agents.

Use a marker only when the prose has to name a host-specific tool, gesture, or
slash command:

> <host: claude-code>
> Use the `Agent` tool with `team_name` and `name` parameters.
> </host>
> <host: codex>
> Spawn a sub-agent by asking Codex in natural language ("spawn a worker
> sub-agent for task X"). Codex's `/agent` slash command switches between
> active threads.
> </host>

### Forbidden tokens outside markers

The grep guard at `tests/skill-content-grep.sh` rejects these tokens outside
a `<host: claude-code>` block:

`TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`,
`TeamCreate`, `TeamDelete`, `SendMessage`, `EnterPlanMode`,
`Sonnet`, `Opus`, `Haiku`.

Use role names (`fast` / `balanced` / `frontier`) for model tiers and resolve
them through `agents/model-tiers.md`.
```

**Step 2: Verify the file still parses (frontmatter intact)**

```bash
head -5 skills/writing-skills/SKILL.md
```

Expected: starts with `---`, ends frontmatter at line 4, no syntax issues.

**Step 3: Commit**

```bash
git add skills/writing-skills/SKILL.md
git commit -m "docs(writing-skills): document host-conditional marker convention"
```

**Verification class:** Documentation. Expected: section renders, frontmatter unchanged.

---

## Task 4: Rewrite `alignment-check` to use role names + host-conditional agent spawn

**Files:**
- Modify: `skills/alignment-check/SKILL.md`

**Current bleed (audit):**
- Line 28: "Dispatch a Sonnet agent to perform the comparison:"
- Lines 30–33: example uses `Agent tool (general-purpose, model: sonnet)`.

**Step 1: Replace the model-tier reference**

Change line 28 from:

```
Dispatch a Sonnet agent to perform the comparison:
```

to:

```
Dispatch a `balanced`-tier sub-agent (see `agents/model-tiers.md`) to perform
the comparison:
```

**Step 2: Replace the Agent-tool snippet with a host-conditional block**

Replace the code block (lines 30–73 in the current file) with:

````markdown
<host: claude-code>
```
Agent tool (general-purpose, model: balanced):
  description: "Check alignment: design vs plan"
  prompt: |
    [prompt body unchanged]
```
</host>

<host: codex, opencode, cursor>
Spawn a sub-agent in your host's native way (natural-language request on Codex,
`@mention` on OpenCode, equivalent on Cursor) with the same prompt body.
The sub-agent reads the design doc, reads the plan doc, and produces the same
report format.
</host>
````

Keep the prompt body itself unchanged — that text is host-neutral.

**Step 3: Run the grep guard scoped to this file**

```bash
guard_out="$(./tests/skill-content-grep.sh 2>&1)"; printf '%s\n' "$guard_out" | grep alignment-check || true
```

Expected: no output for `skills/alignment-check/SKILL.md` (no matches = PASS for this file; the overall script may still exit non-zero until other tasks land).

**Step 4: Commit**

```bash
git add skills/alignment-check/SKILL.md
git commit -m "skill(alignment-check): role-based model tier + host-conditional spawn"
```

**Verification class:** Skill content (CLI command). Expected output: grep guard reports no occurrences in this file.

---

## Task 5: Rewrite `pr-monitoring` model references

**Files:**
- Modify: `skills/pr-monitoring/SKILL.md`

**Step 1: Identify forbidden tokens**

```bash
grep -nE 'Sonnet|Opus|Haiku|TodoWrite|TaskCreate|TeamCreate|SendMessage|EnterPlanMode' \
  skills/pr-monitoring/SKILL.md || echo "no matches"
```

**Step 2: Replace each match with a role name or host-conditional block**

For tier names: replace `Sonnet` with `balanced`, `Opus` with `frontier`, `Haiku` with `fast`. Add a `(see agents/model-tiers.md)` parenthetical the first time a role appears in the file.

For tool names: wrap the surrounding paragraph in a `<host: claude-code>` block and add a corresponding `<host: codex, opencode, cursor>` block describing the equivalent in those hosts (typically: same workflow, host's native task tracker or in-prose checklist).

**Step 3: Run the grep guard**

```bash
guard_out="$(./tests/skill-content-grep.sh 2>&1)"; printf '%s\n' "$guard_out" | grep pr-monitoring || true
```

Expected: no matches.

**Step 4: Commit**

```bash
git add skills/pr-monitoring/SKILL.md
git commit -m "skill(pr-monitoring): role-based tiers + host-conditional tool refs"
```

**Verification class:** Skill content. Expected: grep guard clean for this file.

---

## Task 6: Rewrite `receiving-code-review`

**Files:**
- Modify: `skills/receiving-code-review/SKILL.md`

**Step 1: Identify forbidden tokens** (same grep as Task 5, scoped to this file).

**Step 2: Apply the same replacement pattern** as Task 5: role names for tiers, host-conditional blocks for tool calls.

**Step 3: Run the grep guard scoped to this file**, expect no matches.

**Step 4: Commit**

```bash
git add skills/receiving-code-review/SKILL.md
git commit -m "skill(receiving-code-review): role-based tiers + host-conditional refs"
```

**Verification class:** Skill content.

---

## Task 7: Rewrite `finishing-a-development-branch`

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md`

**Step 1–4:** identical pattern to Task 5. Identify, replace, grep-clean, commit.

```bash
git add skills/finishing-a-development-branch/SKILL.md
git commit -m "skill(finishing-a-development-branch): role-based tiers + conditionals"
```

**Verification class:** Skill content.

---

## Task 8: Rewrite `brainstorming`

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

The current file references `AskUserQuestion` (a Claude-Code tool) — wrap that in a `<host: claude-code>` block, and document the cross-host fallback (just ask in chat).

**Step 1: Identify references**

```bash
grep -n 'AskUserQuestion\|Sonnet\|Opus\|Haiku' skills/brainstorming/SKILL.md
```

**Step 2: Apply the wrapping**

Wrap the `AskUserQuestion` paragraph(s) in `<host: claude-code>`. Add `<host: codex, opencode, cursor>` block: ask one or two grouped questions per turn in plain prose; multi-choice options can be presented as a numbered list and the user replies with the chosen number.

**Step 3: Grep-clean**

```bash
guard_out="$(./tests/skill-content-grep.sh 2>&1)"; printf '%s\n' "$guard_out" | grep brainstorming || true
```

Expect no matches.

**Step 4: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "skill(brainstorming): host-conditional question UI + role tiers"
```

**Verification class:** Skill content.

---

## Task 9: Rewrite `subagent-driven-development` (heaviest)

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`
- Modify: `skills/subagent-driven-development/implementer-prompt.md`
- Modify: `skills/subagent-driven-development/spec-reviewer-prompt.md`
- Modify: `skills/subagent-driven-development/code-quality-reviewer-prompt.md`

**Goal:** Reframe the skill so **Sequential Mode** is the default and **Agent Teams** is a Claude-Code-only enhancement. The current file already documents both, but presents Agent Teams as default and Sequential as "Legacy". We invert.

**Step 1: Restructure the SKILL.md sections**

The new structure for `skills/subagent-driven-development/SKILL.md`:

```markdown
---
name: subagent-driven-development
description: Use when executing implementation plans with independent tasks in the current session
---

# Subagent-Driven Development

Execute a plan by dispatching role-specialised sub-agents (implementer, spec
reviewer, code reviewer) and applying two-stage review (spec compliance, then
code quality).

**Core principle:** Role separation + two-stage review = high quality.

## Mode Selection

This skill has two modes:

- **Sequential Mode (default, all hosts):** orchestrator dispatches one
  sub-agent at a time, waits for it to return, then dispatches the next. No
  shared chat surface; the orchestrator carries state.
- **Agent Teams Mode (Claude Code only, opt-in):** persistent named teammates
  in a shared chat surface, parallel implementer threads. Requires the
  experimental Agent Teams feature flag.

If you don't know which to use, use Sequential Mode.

<host: claude-code>
### When to choose Agent Teams

Use Agent Teams Mode when:
- The `TeamCreate` tool is available in your tool list, and
- The `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag is set, and
- The plan has 6+ independent implementer tasks (parallelism is worth the
  setup cost).

Otherwise stay in Sequential Mode.
</host>

## Sequential Mode

[Promote the current "Legacy Mode (Sequential Subagents)" content to here.
Expand each step with the concrete sub-agent prompt files referenced below.
Use role names (`balanced`-tier model) instead of brand model names.]

…

## Agent Teams Mode (Claude Code)

<host: claude-code>
[Move the current Agent Teams section here, intact except for tier-name
renames: `Opus` → `frontier`, `Sonnet` → `balanced`. Keep the digraph,
the team-sizing table, and the spawn snippets.]
</host>

## Red Flags

[Keep current section, drop the line "In Agent Teams mode: let the lead
implement (orchestration only)" out of the host-neutral block and put it
inside the Agent-Teams section instead.]

## Integration

[Keep current section.]
```

**Step 2: Update the three sub-agent prompt files**

For `implementer-prompt.md`, `spec-reviewer-prompt.md`, `code-quality-reviewer-prompt.md`:

- Replace any `Sonnet`/`Opus`/`Haiku` with role names.
- Replace any `TaskCreate`/`TaskList`/`TaskGet`/`TaskUpdate` mention with a host-conditional block:
  - `<host: claude-code>` paragraph using the original tool names;
  - `<host: codex, opencode, cursor>` paragraph: "the orchestrator passes the task description in your prompt; report status by returning a summary."
- Replace `SendMessage` with `<host: claude-code>` block (existing) + `<host: codex, opencode, cursor>` block ("return your summary; the orchestrator routes it.").

**Step 3: Grep-clean**

```bash
guard_out="$(./tests/skill-content-grep.sh 2>&1)"; printf '%s\n' "$guard_out" | grep subagent-driven-development || true
```

Expect no matches outside `<host: claude-code>` blocks.

**Step 4: Commit**

```bash
git add skills/subagent-driven-development/
git commit -m "skill(subagent-driven-development): Sequential Mode default, Agent Teams Claude-only"
```

**Verification class:** Skill content (CLI command). Expected: grep guard clean for these files; the file's structure preserves both modes; the existing Agent Teams content is intact under the Claude-Code block.

---

## Task 10: Rewrite `dispatching-parallel-agents`

**Files:**
- Modify: `skills/dispatching-parallel-agents/SKILL.md`

**Bleed:** lines 67–73 use `Task("…")` syntax which is OpenCode-conditional and Claude-Code-conditional in different ways.

**Step 1: Wrap the example block**

Replace the current code block (around line 67):

```typescript
// In Claude Code / AI environment
Task("Fix agent-tool-abort.test.ts failures")
Task("Fix batch-completion-behavior.test.ts failures")
Task("Fix tool-approval-race-conditions.test.ts failures")
// All three run concurrently
```

with a host-neutral lead and conditional examples:

```markdown
Spawn one sub-agent per problem domain, in parallel where the host supports it.

<host: claude-code>
```typescript
Task("Fix agent-tool-abort.test.ts failures")
Task("Fix batch-completion-behavior.test.ts failures")
Task("Fix tool-approval-race-conditions.test.ts failures")
// All three run concurrently
```
</host>

<host: codex>
Ask Codex to spawn one worker per problem ("spawn three workers, one for each
test file"). Codex's `[agents].max_threads` (default 6) caps concurrency.
</host>

<host: opencode>
@mention three sub-agent personas, one per problem domain. OpenCode runs them
concurrently up to its configured limit.
</host>

<host: cursor>
Cursor does not currently expose a parallel sub-agent surface. Run problems
sequentially, or open multiple Cursor windows for true parallelism.
</host>
```

**Step 2: Grep-clean**

```bash
guard_out="$(./tests/skill-content-grep.sh 2>&1)"; printf '%s\n' "$guard_out" | grep dispatching-parallel-agents || true
```

Expect no matches.

**Step 3: Commit**

```bash
git add skills/dispatching-parallel-agents/SKILL.md
git commit -m "skill(dispatching-parallel-agents): host-conditional spawn examples"
```

**Verification class:** Skill content.

---

## Task 11: Rewrite `writing-plans` (Plan Mode + tier names)

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

**Bleed:**
- "Plan Mode Detection" section (current lines 21–37) says Codex has no Plan Mode. **Outdated as of April 2026** — Codex has `/plan`.
- "Sonnet" / "Opus" / "Haiku" appear in any task tier examples.

**Step 1: Replace the Plan Mode section**

Replace lines 21–37 with:

```markdown
## Plan Mode Detection

Each host has a different mechanism for entering an interactive planning state.
Use whichever your host supports.

<host: claude-code>
Prefer Claude's native Plan Mode (Shift-Tab, or the `EnterPlanMode` tool, or
`/plan` slash command). Once Plan Mode is active, draft the implementation plan
following the format below, then exit Plan Mode and save the plan to disk.
</host>

<host: codex>
Use Codex's `/plan` slash command. Draft the plan in the planning thread, then
save it to `docs/plans/YYYY-MM-DD-<feature-name>.md`.
</host>

<host: opencode, cursor>
Neither host exposes a dedicated plan mode. Use the Built-In Planning Process
described below: draft the plan as ordinary chat output, then save to the
canonical path.
</host>

The plan document you save MUST follow the same format described in the
Plan Document Header and Task Structure sections below, regardless of which
mode you used to draft it.
```

**Step 2: Replace tier-name references**

Search and replace within this file:

```bash
grep -n 'Sonnet\|Opus\|Haiku' skills/writing-plans/SKILL.md
```

Replace each with the matching role name.

**Step 3: Grep-clean**

```bash
guard_out="$(./tests/skill-content-grep.sh 2>&1)"; printf '%s\n' "$guard_out" | grep writing-plans || true
```

Expect no matches.

**Step 4: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "skill(writing-plans): host-conditional plan mode + role tiers"
```

**Verification class:** Skill content.

---

## Task 12: Rewrite `using-autodev` (entry-point skill — important)

**Files:**
- Modify: `skills/using-autodev/SKILL.md`

**Bleed:** mentions `Skill` tool; mentions `TodoWrite`; entire file structure assumes Claude tooling.

**Step 1: Add a host-detection cue at top of the body**

After the `<EXTREMELY-IMPORTANT>` block and before the existing content, insert:

```markdown
## Host

Skills in this repo support Claude Code, Codex, OpenCode, and Cursor. Sections
marked `<host: …>` apply only to the named host(s); unmarked sections apply
everywhere. Your host is declared in your host's preamble file (CLAUDE.md for
Claude Code, AGENTS.md for Codex/OpenCode, .cursorrules for Cursor).

Model tiers are referred to by role (`fast` / `balanced` / `frontier` /
`coding-specialist`). See `agents/model-tiers.md` for the host-specific
resolution.
```

**Step 2: Wrap the "How to Access Skills" block**

The existing block at lines 14–18 references "the `Skill` tool" (Claude Code) and "other environments" loosely. Replace with explicit host blocks:

```markdown
## How to Access Skills

<host: claude-code>
Use the `Skill` tool. When you invoke a skill, its content is loaded; follow
it directly. Never use the `Read` tool on skill files.
</host>

<host: codex>
Skills are auto-discovered from `~/.agents/skills/`. Use `/skills` to list
them or `$skillname` shorthand to invoke one.
</host>

<host: opencode>
Use OpenCode's native `skill` tool to list and load skills.
</host>

<host: cursor>
Skills are read as plain markdown context. Reference them by name; the
host loads the file when you cite it.
</host>
```

**Step 3: Replace `TodoWrite` references**

The "Has checklist?" branch in the digraph and the "Create TodoWrite todo per item" instruction need conditional treatment:

- Inside `<host: claude-code>`: keep the original `TodoWrite` reference.
- Inside `<host: opencode>`: substitute `update_plan`.
- Inside `<host: codex, cursor>`: substitute "an inline checklist in chat".

Restructure the surrounding paragraph so the rule "create one tracking entry per checklist item" is host-neutral, and only the tool name varies per host.

**Step 4: Grep-clean**

```bash
guard_out="$(./tests/skill-content-grep.sh 2>&1)"; printf '%s\n' "$guard_out" | grep using-autodev || true
```

Expect no matches.

**Step 5: Commit**

```bash
git add skills/using-autodev/SKILL.md
git commit -m "skill(using-autodev): host-aware skill access + checklist tool"
```

**Verification class:** Skill content.

---

## Task 13: Rewrite `executing-plans`

**Files:**
- Modify: `skills/executing-plans/SKILL.md`

**Bleed:** "If no concerns: Create TodoWrite and proceed" (line 23).

**Step 1: Wrap the TodoWrite reference**

Replace line 23 area with:

```markdown
4. If no concerns:
   <host: claude-code>
   Create a `TodoWrite` checklist with one entry per plan task and proceed.
   </host>
   <host: opencode>
   Use `update_plan` to record one entry per plan task and proceed.
   </host>
   <host: codex, cursor>
   Maintain an inline markdown checklist in chat with one entry per plan
   task. Update entries as you complete them.
   </host>
```

**Step 2: Grep-clean**

```bash
guard_out="$(./tests/skill-content-grep.sh 2>&1)"; printf '%s\n' "$guard_out" | grep executing-plans || true
```

Expect no matches.

**Step 3: Commit**

```bash
git add skills/executing-plans/SKILL.md
git commit -m "skill(executing-plans): host-conditional checklist tool"
```

**Verification class:** Skill content.

---

## Task 14: Audit and clean `writing-skills` supporting files

**Files:**
- Modify: `skills/writing-skills/persuasion-principles.md`
- Modify: `skills/writing-skills/anthropic-best-practices.md`

**Bleed:** these supporting files mention Claude/Sonnet/Opus prose context.

**Step 1: Identify**

```bash
grep -n 'Sonnet\|Opus\|Haiku\|TodoWrite\|TaskCreate\|TeamCreate' \
  skills/writing-skills/persuasion-principles.md \
  skills/writing-skills/anthropic-best-practices.md
```

**Step 2: Apply replacements**

For these reference docs, the bleed is mostly **Anthropic-attributed sources** (acceptable; they're citations) and tier names in examples (replace with role names where the example is generic).

Where a sentence is genuinely about Anthropic guidance, leave the brand reference intact (it's a citation, not a tool reference) — but wrap the surrounding paragraph in `<host: claude-code>` if the prescriptive guidance applies only to Claude Code authoring.

The grep guard is line-based and would catch these, so add the file paths to the **`ALLOWED_FILES`** list in `tests/skill-content-grep.sh` if and only if their references are unambiguous citations. Document the rationale in a comment.

**Step 3: Grep-clean (after either editing or allowlisting)**

```bash
./tests/skill-content-grep.sh
```

Expect: full pass.

**Step 4: Commit**

```bash
git add skills/writing-skills/ tests/skill-content-grep.sh
git commit -m "skill(writing-skills): clean supporting files; allowlist citations if needed"
```

**Verification class:** Skill content.

---

## Task 15: Update `README.md` — cross-LLM compatibility section

**Files:**
- Modify: `README.md`

**Step 1: Add a "Cross-LLM compatibility" section**

After the existing introduction / installation section, add:

```markdown
## Cross-LLM compatibility

Skills are designed to work on Claude Code, Codex, OpenCode, and Cursor. A
skill body may include host-conditional sections marked `<host: …>` that
apply only to the named host(s); unmarked content applies to every host.

| Host | Install path | Native skill discovery | Notes |
|---|---|---|---|
| Claude Code | `~/.claude/plugins/marketplace/autodev/` | yes | Full Agent Teams support (experimental flag) |
| Codex | `~/.agents/skills/autodev/` | yes | Sequential sub-agent dispatch; `/plan` slash; `/agent` switching |
| OpenCode | `~/.config/opencode/skills/autodev/` | yes | Tool mapping documented in `.opencode/INSTALL.md` |
| Cursor | manual reference | partial | Plugin manifest stub; install path TBD |

See `agents/model-tiers.md` for the role-based model vocabulary used across
hosts, and `tests/skill-content-grep.sh` for the regression guard.
```

**Step 2: Verify README still renders**

```bash
head -30 README.md
```

Expected: original heading intact; new section integrates cleanly.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add cross-LLM compatibility matrix to README"
```

**Verification class:** Documentation.

---

## Task 15b: Update host-specific READMEs (`docs/README.codex.md`, `docs/README.opencode.md`)

**Files:**
- Modify: `docs/README.codex.md`
- Modify: `docs/README.opencode.md`

**Step 1: `docs/README.codex.md` — host declaration + role vocabulary**

After the existing install section, append a "Cross-LLM behavior" subsection:

```markdown
## Cross-LLM behavior

Skills in this repo are written to work across hosts. To make Codex-specific
sections resolve correctly, add to your `~/.codex/AGENTS.md`:

```
Host: codex
```

Model tiers cited in skills (`fast`, `balanced`, `frontier`,
`coding-specialist`) resolve to Codex models per `agents/model-tiers.md`.
The grep guard at `tests/skill-content-grep.sh` keeps host-neutral skill text
free of Claude-specific tokens.
```

**Step 2: `docs/README.opencode.md` — same**

Append the equivalent section, with `Host: opencode` and a note that OpenCode
uses host-pass-through model selection (i.e. whichever model the user has
configured).

**Step 3: Commit**

```bash
git add docs/README.codex.md docs/README.opencode.md
git commit -m "docs: cross-LLM behavior notes for Codex + OpenCode READMEs"
```

**Verification class:** Documentation.

---

## Task 15c: Update `agents/team-conventions.md`

**Files:**
- Modify: `agents/team-conventions.md`

**Step 1: Add a "Modes" paragraph**

After the file's introduction (around current line 6), insert:

```markdown
## Modes

Team conventions apply identically in both execution modes:

- **Sequential Mode** (all hosts): orchestrator dispatches one sub-agent at
  a time; reviewers run between tasks.
- **Agent Teams Mode** (Claude Code only, opt-in): persistent named teammates
  in a shared chat surface; reviewers run in parallel after each task.

Implementer, spec-reviewer, and code-reviewer roles are the same in both
modes. The conventions below apply to both.
```

**Step 2: Commit**

```bash
git add agents/team-conventions.md
git commit -m "docs(team-conventions): note Sequential and Agent Teams mode applicability"
```

**Verification class:** Documentation.

---

## Task 16: Update INSTALL.md files for host declaration

**Files:**
- Modify: `.codex/INSTALL.md`
- Modify: `.opencode/INSTALL.md`

**Step 1: Add a "Host declaration (recommended)" subsection**

To `.codex/INSTALL.md`, after the "Verify" section, append:

```markdown
## Host declaration (recommended)

To make host-conditional sections in skills resolve correctly, add this line
to your `~/.codex/AGENTS.md`:

```
Host: codex
```

If you don't add this declaration, skills still work; they default to host-
neutral content. The declaration sharpens host-specific guidance.
```

To `.opencode/INSTALL.md`, after the verification section, append:

```markdown
## Host declaration (recommended)

Add this line to your OpenCode `AGENTS.md` (or equivalent context file):

```
Host: opencode
```

If you don't add this declaration, skills still work; they default to host-
neutral content. The declaration sharpens host-specific guidance.
```

**Step 2: Commit**

```bash
git add .codex/INSTALL.md .opencode/INSTALL.md
git commit -m "docs(install): add host declaration step for Codex + OpenCode"
```

**Verification class:** Documentation.

---

## Task 17: Wire the grep guard into pre-commit / CI

**Files:**
- Create: `.github/workflows/skill-content-check.yml` (if `.github/workflows/` is the repo's CI surface; otherwise check the existing CI config)
- Modify: existing CI config if a GitHub Actions workflow already runs.

**Step 1: Check current CI surface**

```bash
ls -la .github/workflows/ 2>/dev/null || echo "no workflows directory"
ls -la lib/hooks/ hooks/ 2>/dev/null
```

If a `.github/workflows/` exists, add a job; if not, create the directory and a minimal workflow.

**Step 2: Minimal workflow**

```yaml
name: Skill content check

on:
  pull_request:
    paths:
      - 'skills/**'
      - 'agents/**'
      - 'tests/skill-content-grep.sh'

jobs:
  grep-guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run grep guard
        run: ./tests/skill-content-grep.sh
```

**Step 3: Verify locally**

```bash
./tests/skill-content-grep.sh
```

Expected: PASS (after Tasks 4–14 land).

**Step 4: Commit**

```bash
git add .github/workflows/skill-content-check.yml
git commit -m "ci: enforce skill-content grep guard on PRs touching skills"
```

**Verification class:** Hook / trigger / event handler — fire the event (push branch / open PR), observe the workflow runs.

---

## Task 18: Create the cross-LLM coverage table

**Files:**
- Create: `tests/cross-llm-coverage.md`

**Step 1: Write the table**

```markdown
# Cross-LLM Skill Coverage

A snapshot of which skills have host-conditional content and which are
host-neutral. Updated whenever a skill changes.

| Skill | Claude Code | Codex | OpenCode | Cursor | Notes |
|---|---|---|---|---|---|
| alignment-check | host-conditional | host-conditional | host-conditional | host-conditional | role tiers; spawn block |
| brainstorming | host-conditional | host-conditional | host-conditional | host-conditional | AskUserQuestion fallback |
| dispatching-parallel-agents | host-conditional | host-conditional | host-conditional | host-conditional | spawn examples per host |
| executing-plans | host-conditional | host-conditional | host-conditional | host-conditional | TodoWrite fallback |
| finishing-a-development-branch | host-conditional | host-conditional | host-conditional | host-conditional | role tiers |
| pr-monitoring | host-conditional | host-conditional | host-conditional | host-conditional | role tiers + tool refs |
| receiving-code-review | host-conditional | host-conditional | host-conditional | host-conditional | role tiers |
| requesting-code-review | host-neutral | host-neutral | host-neutral | host-neutral | already portable |
| runtime-launch-validation | host-neutral | host-neutral | host-neutral | host-neutral | already portable |
| subagent-driven-development | host-conditional | host-conditional | host-conditional | host-conditional | Sequential default; Agent Teams Claude-only |
| systematic-debugging | host-neutral | host-neutral | host-neutral | host-neutral | already portable |
| test-driven-development | host-neutral | host-neutral | host-neutral | host-neutral | already portable |
| using-git-worktrees | host-neutral | host-neutral | host-neutral | host-neutral | already portable |
| using-autodev | host-conditional | host-conditional | host-conditional | host-conditional | entry-point host detection |
| verification-before-completion | host-neutral | host-neutral | host-neutral | host-neutral | already portable |
| writing-plans | host-conditional | host-conditional | host-conditional | host-conditional | plan-mode block + role tiers |
| writing-skills | host-conditional | host-conditional | host-conditional | host-conditional | marker convention |

## Audit cadence

Re-run `./tests/skill-content-grep.sh` and update this table whenever a skill
is added or rewritten. The grep guard catches forbidden tokens; this table
records intent.
```

**Step 2: Commit**

```bash
git add tests/cross-llm-coverage.md
git commit -m "docs(tests): add cross-LLM skill coverage table"
```

**Verification class:** Documentation.

---

## Risks called out in the plan

- **Sub-agent prompt files (Task 9) duplicate content the orchestrator already passes.** The implementer must check whether the prompts are still cited verbatim by `subagent-driven-development/SKILL.md` (Sequential Mode section) — if so, ensure prompt edits and skill body stay in sync.

- **Allowlisting in Task 14** is a judgment call. If the writing-skills supporting files contain a Claude tier name in an Anthropic-attributed quote, allowlisting that file is acceptable; if it's prescriptive guidance, rewrite is preferred. Document the choice in the commit message.

- **Task 17 needs the actual CI surface** — verify `.github/workflows/` is the right directory before creating the workflow. The repo may use a different CI; adjust accordingly.

- **Coordination with the existing PR queue.** Branch protection means each task PR must rebase on `main`; if multiple PRs are in flight at once, expect rebase conflicts in the grep guard or the coverage table. Stagger merges (Group A first, then B/C/D in parallel after, then E last).

## Done criteria

The full plan is done when:

1. `./tests/skill-content-grep.sh` exits 0 on the working tree.
2. `tests/cross-llm-coverage.md` shows every skill row populated.
3. README, `.codex/INSTALL.md`, `.opencode/INSTALL.md` all reference the host declaration and the role vocabulary.
4. CI workflow runs on every PR touching `skills/`, `agents/`, or the guard itself.
5. Each PR has received at least one clean Copilot review pass before merge (recommended: two distinct clean passes at the same HEAD to guard against false positives).

## Execution Handoff

**Design-only mode active.** The orchestrator passed `--design-only`.

After alignment-check PASS:

1. Save the plan ✅ (this document).
2. Commit the plan.
3. Invoke `autodev:alignment-check`.
4. **On PASS: STOP.** Do NOT invoke `autodev:subagent-driven-development`. Return summary to orchestrator.
5. **On FAIL:** revise based on drift items; re-run alignment-check (max 2 cycles); STOP regardless.
