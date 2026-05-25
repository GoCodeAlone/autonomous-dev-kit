---
name: condensed-pipeline-writing
description: Use when producing design docs, adversarial review reports, implementation plans, progress logs, or phase handoffs where token efficiency matters and precision must be preserved
---

# Condensed Pipeline Writing

## Overview

Use compact, structured writing for internal pipeline artifacts. The goal is
lower token use without losing decisions, evidence, assumptions, constraints,
or file paths.

This skill applies to:
- design docs in `docs/plans/*-design.md`
- implementation plans in `docs/plans/*.md`
- adversarial review reports
- scope/backport notes
- phase-progress logs and handoffs

It does not apply to user-facing explanations, PR descriptions, commit
messages, code comments, or public documentation unless the user asks for terse
format.

## Core Rules

- Prefer tables, tagged bullets, and short fragments over paragraphs.
- Keep every fact that affects implementation, review, rollback, or scope.
- Remove throat-clearing, restated goals, apologies, and generic process prose.
- Use stable labels so later agents can grep and cite sections.
- Preserve code, commands, paths, URLs, identifiers, versions, error strings,
  regex, SQL, JSON, YAML, and quoted user requirements verbatim.

## Symbols

Use these only in internal artifacts:

| Symbol | Meaning |
|---|---|
| `→` | leads to / becomes / then |
| `∴` | therefore / conclusion |
| `!` | required / must |
| `?` | unknown / needs validation |
| `⊥` | forbidden / impossible |
| `≠` | not equal / conflicts |
| `≤` / `≥` | at most / at least |
| `&` | and |
| `|` | or, except inside Markdown tables |

Avoid clever notation. If a symbol makes a sentence ambiguous, use words.

## Artifact Shapes

**Assumption row**

```markdown
| id | assumption | challenge | fallback |
|---|---|---|---|
| A1 | Codex parses hook stdout as JSON when non-empty | invalid JSON blocks hook | emit schema JSON via `jq -n`; no encoder → no output |
```

**Finding row**

```markdown
| sev | class | loc | issue | fix |
|---|---|---|---|---|
| Important | hook schema | `hooks/session-start` | top-level `additional_context` risks host mismatch | emit `hookSpecificOutput.additionalContext` only |
```

**Plan task**

```markdown
T3 hook JSON tests
Files: `tests/hook-contracts.sh`
Steps:
1. payload → `hooks/session-start`
2. parse via `jq -e`
3. assert `.hookSpecificOutput.additionalContext`
Verify: `tests/hook-contracts.sh` → PASS
```

**Compressed JSONL state row**

```json
{"ts":"2026-05-25T20:01:51Z","ev":"phase","pl":"docs/plans/x.md","ph":"T3","st":"done","e":"tests/hook-contracts.sh PASS","nx":"T4"}
```

## Compressed State

JSON/JSONL state is internal pipeline data. Use compact stable keys:

| key | meaning |
|---|---|
| `ts` | UTC timestamp |
| `ev` | event enum: `skill`, `agent`, `task`, `lock`, `phase`, `blk` |
| `sk` | skill name |
| `args` | truncated skill args |
| `ag` | agent/subagent type |
| `tt` | task tool name |
| `id` | task/agent id |
| `pl` | plan path/name |
| `ph` | phase/task id |
| `st` | status enum |
| `h` | lock/hash prefix or digest |
| `e` | evidence |
| `nx` | next action |
| `blk` | blocker |
| `d` | short fallback detail; avoid unless no structured key fits |

Prefer enums and path/id references over prose. Keep old parsers tolerant during
migration (`tool/detail` legacy rows may exist). Do not store long prompts,
transcripts, or review bodies in state; state should re-anchor agents, not
duplicate artifacts.

## Density Targets

- Design section: 3-7 bullets or one table, not a long essay.
- Adversarial report: one row per finding; one row per clean bug class.
- Plan task: exact files, exact commands, exact expected output; no motivational prose.
- Handoff/state: current state, evidence, next action, blockers. Nothing else.

## Backport Notes

When execution disproves an assumption or reveals a bug in the design, write a
small backport note:

```markdown
### Backport YYYY-MM-DD: <short title>

Cause: <assumption or design claim that failed>
Change: <design/plan correction>
Scope: no manifest change | manifest change requires re-lock
Evidence: `<command>` → <result>
```

Keep backports factual. Do not rewrite history; append the correction.

## Common Mistakes

- Cutting a caveat that changes behavior.
- Replacing exact expected output with "works."
- Compressing public/user-facing text until it sounds cryptic.
- Using symbols inside code, commands, JSON, YAML, or quoted strings.
- Hiding uncertainty. Mark it with `?` and state how to resolve it.
