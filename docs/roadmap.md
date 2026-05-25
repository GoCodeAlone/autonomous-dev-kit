# Roadmap

This file used to track items that had been considered but deferred. Those items are now shipped (v5.5.0):

| Former roadmap item | Shipped as |
|---|---|
| Decision log / ADRs | `skills/recording-decisions/SKILL.md` + `decisions/` directory + `decisions/0000-template.md` |
| Post-merge retrospective | `skills/post-merge-retrospective/SKILL.md` + `docs/retros/` directory; wired into `pr-monitoring` exit |
| Skill-usage telemetry | `tests/skill-activation-audit.sh` (reads `.claude/autodev-state/in-progress.jsonl`) |
| Brainstorming cost-control gate | 5-batch soft cap section in `skills/brainstorming/SKILL.md` |
| Cross-skill consistency invariants | `tests/skill-cross-refs.sh` |

## Out of scope (rejected)

These were considered and explicitly rejected during plugin evaluation. They are recorded here so future contributors don't re-litigate the same paths:

- **Heavy adversarial debate during brainstorming** — risks turning the user's design conversation into a multi-agent debate they didn't ask for. The lightweight self-challenge round in `brainstorming` is the chosen alternative.
- **Hostile / steelman-the-rejection reviewer framing** — theatrical, low signal. The "find ≥3 things wrong" framing from `requesting-code-review` and `adversarial-design-review` is sharp enough.
- **Separate `pre-mortem` skill** — folded into `adversarial-design-review`'s "Missing failure modes" bug class instead of being a standalone skill. One artifact, one pass, less skill sprawl.

If a future contributor wants to revisit any of these, the bar is: explain what changed about the trade-off that wasn't true at evaluation time. Then write an ADR before adding the skill.
