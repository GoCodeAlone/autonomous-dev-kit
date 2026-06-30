# Cross-LLM Skill Coverage

A snapshot of which skills have host-conditional content and which are
host-neutral. Updated whenever a skill changes.

| Skill | Claude Code | Codex | OpenCode | Cursor | Hermes Agent | Zed Agent | Notes |
|---|---|---|---|---|---|---|---|
| adversarial-design-review | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | host-neutral fallback | Agent dispatch block in `<host: claude-code>`; generic subagent-capable fallback applies where available |
| alignment-check | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | spawn block in `<host: claude-code>`; inline fallback includes `<host: codex, opencode, cursor, zed-agent>`; Hermes uses `delegate_task` |
| post-merge-retrospective | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | Inline-vs-subagent decision block in `<host: claude-code>`; inline-only prose includes Zed; Hermes inline block |
| recording-decisions | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | ADR storage protocol; no host-specific tooling |
| scope-lock | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | Pure markdown + shell-script invariant; no host-specific tooling |
| brainstorming | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | `AskUserQuestion` in `<host: claude-code>`; numbered-list fallback includes Zed; Hermes uses `clarify`; visual companion guidance is host-neutral and best-effort; browser/event capture is deferred |
| dispatching-parallel-agents | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | generic parallel-dispatch pattern; no tool-specific refs |
| executing-plans | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | tool-use block in `<host: claude-code>`; prose fallback includes Zed; Hermes uses `todo` |
| finishing-a-development-branch | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | audited clean — no forbidden tokens; bash-based throughout |
| pr-monitoring | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | Agent spawn block in `<host: claude-code>`; polling fallback includes Zed; Hermes uses background terminal |
| receiving-code-review | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | audited clean — pattern-based guidance, no tool refs |
| requesting-code-review | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| runtime-launch-validation | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| subagent-driven-development | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | Agent Teams setup in `<host: claude-code>`; Zed uses subagents or parallel Threads Sidebar; Hermes uses `delegate_task` |
| systematic-debugging | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| test-driven-development | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| using-git-worktrees | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| using-autodev | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | Zed block maps `autodev:<skill>` references to flat Zed skill names; no forbidden tokens |
| verification-before-completion | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | already portable (Group I) |
| demonstration-fidelity | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | pure markdown; no host-specific tooling. Advisory backstop is the separate `hooks/pretool-demo-fidelity-guard` where host hooks are installed |
| writing-plans | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | host-neutral | Native planning mode reference is host-neutral; no `<host:>` blocks needed |
| writing-skills | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | host-conditional | Host list includes `zed-agent`; Claude-only tokens remain wrapped in `<host: claude-code>` blocks |

## Audit cadence

Re-run `./tests/skill-content-grep.sh` and update this table whenever a skill
is added or rewritten. The grep guard catches forbidden tokens; this table
records intent.

## Related

- `docs/cross-llm-coverage.md` — host capability matrix (what each host supports natively)
