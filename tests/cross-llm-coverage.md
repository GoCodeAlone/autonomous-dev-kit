# Cross-LLM Skill Coverage

A snapshot of which skills have host-conditional content and which are
host-neutral. Updated whenever a skill changes.

| Skill | Claude Code | Codex | OpenCode | Cursor | Notes |
|---|---|---|---|---|---|
| adversarial-design-review | host-conditional | host-conditional | host-conditional | host-conditional | Agent dispatch block in `<host: claude-code>`; inline-execution prose in `<host: codex, opencode, cursor>` |
| alignment-check | host-conditional | host-conditional | host-conditional | host-conditional | spawn block in `<host: claude-code>`; prose fallback outside |
| post-merge-retrospective | host-conditional | host-conditional | host-conditional | host-conditional | Inline-vs-subagent decision block in `<host: claude-code>`; inline-only prose in `<host: codex, opencode, cursor>` |
| recording-decisions | host-neutral | host-neutral | host-neutral | host-neutral | ADR storage protocol; no host-specific tooling |
| scope-lock | host-neutral | host-neutral | host-neutral | host-neutral | Pure markdown + shell-script invariant; no host-specific tooling |
| brainstorming | host-conditional | host-conditional | host-conditional | host-conditional | `AskUserQuestion` in `<host: claude-code>`; numbered-list fallback in `<host: codex, opencode, cursor>` |
| dispatching-parallel-agents | host-neutral | host-neutral | host-neutral | host-neutral | generic parallel-dispatch pattern; no tool-specific refs |
| executing-plans | host-conditional | host-conditional | host-conditional | host-conditional | tool-use block in `<host: claude-code>`; prose fallback in `<host: codex, opencode, cursor>` |
| finishing-a-development-branch | host-neutral | host-neutral | host-neutral | host-neutral | audited clean — no forbidden tokens; bash-based throughout |
| pr-monitoring | host-conditional | host-conditional | host-conditional | host-conditional | Agent spawn block in `<host: claude-code>`; poll-loop prose outside |
| receiving-code-review | host-neutral | host-neutral | host-neutral | host-neutral | audited clean — pattern-based guidance, no tool refs |
| requesting-code-review | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| runtime-launch-validation | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| subagent-driven-development | host-conditional | host-conditional | host-conditional | host-conditional | Agent Teams setup in `<host: claude-code>`; Sequential Mode is host-neutral default |
| systematic-debugging | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| test-driven-development | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| using-git-worktrees | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| using-autodev | host-neutral | host-neutral | host-neutral | host-neutral | host-access phrasing is prose-based ("In Claude Code: … In other environments: …"); no forbidden tokens |
| verification-before-completion | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| demonstration-fidelity | host-neutral | host-neutral | host-neutral | host-neutral | pure markdown; no host-specific tooling. Advisory backstop is the separate `hooks/pretool-demo-fidelity-guard` (Claude+Codex+Cursor via hooks.json) |
| writing-plans | host-neutral | host-neutral | host-neutral | host-neutral | Plan Mode reference is prose-based ("If you are running in Claude Code…"); no `<host:>` blocks needed |
| writing-skills | host-conditional | host-conditional | host-conditional | host-conditional | `TodoWrite` checklist and tier-brand names wrapped in `<host: claude-code>` blocks |

## Audit cadence

Re-run `./tests/skill-content-grep.sh` and update this table whenever a skill
is added or rewritten. The grep guard catches forbidden tokens; this table
records intent.

## Related

- `docs/cross-llm-coverage.md` — host capability matrix (what each host supports natively)
