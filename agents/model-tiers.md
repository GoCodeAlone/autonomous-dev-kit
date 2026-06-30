# Model Tiers

Skills refer to model tiers by **role** rather than by brand name so they read
correctly on every supported host. This file resolves each role to the
host-specific model identifier.

| Role | Claude Code | Codex | OpenCode | Cursor | Hermes Agent | Zed Agent |
|---|---|---|---|---|---|---|
| `fast` | `haiku` | `gpt-5.4-mini` | host-pass-through | host-pass-through | host-pass-through | host-pass-through |
| `balanced` | `sonnet` | `gpt-5.4` | host-pass-through | host-pass-through | host-pass-through | host-pass-through |
| `frontier` | `opus` | `gpt-5.5` | host-pass-through | host-pass-through | host-pass-through | host-pass-through |
| `coding-specialist` | `sonnet` | `gpt-5.3-codex` | host-pass-through | host-pass-through | host-pass-through | host-pass-through |

`host-pass-through` means the host uses whatever model the user has selected in
its own configuration. Skill prose must not name a specific model on those hosts.

## How skills cite this table

Skill bodies refer to roles, not brand names:

> Use a `balanced`-tier model for spec review.

When the model is following a skill on a specific host, it resolves the role
through this table. Authors maintaining a skill must use role names, not
host-specific model identifiers. The grep guard (`tests/skill-content-grep.sh`)
enforces this for Claude-Code-specific names.

## Updating

When a host's model lineup changes, edit only this file. No skill body should
need to change for a model rename.
