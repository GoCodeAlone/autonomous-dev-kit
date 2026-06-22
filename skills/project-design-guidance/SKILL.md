---
name: project-design-guidance
description: Use before brainstorming, design docs, implementation plans, or retros when project-wide design constraints may exist or need to be created
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Project Design Guidance

Global guidance = durable constraints every design inherits: product direction, architecture boundaries, UX/domain rules, security/ops posture, infra/deploy limits, non-goals. No isolated design.

## Canon

Prefer `docs/design-guidance.md`.

If equivalent exists, use + cite it instead of duplicating: `docs/product-guidance.md`, `docs/architecture.md`, `docs/technical-strategy.md`, repo `AGENTS.md`/`CLAUDE.md`, ADRs with cross-cutting direction. Add pointer file only if discoverability is poor.

## Portfolio Inventory (reuse before building)

If the project keeps a portfolio catalog (commonly `docs/PORTFOLIO.md` per the workspace's `docs/design-guidance.md`), consult its tooling-inventory section BEFORE designing or building a feature. The goal is to avoid rebuilding capability an existing plugin/tool already provides — cite the existing tool in the design instead of proposing a parallel one.

Record any follow-ups the inventory surfaces (a gap, a needed capability, a doc-lag) in the follow-up queue (commonly `docs/FOLLOWUPS.md`) so they are not lost.

## Pre-Design Gate

1. Search:
   ```bash
   rg -n "design guidance|product direction|architecture principles|non-goals|constraints|strategy" AGENTS.md CLAUDE.md README.md docs decisions 2>/dev/null
   ```
2. If found: read, cite under design `## Global Design Guidance`.
3. If absent: ask Q&A before final design; save to `docs/design-guidance.md` unless human declines.
4. Every design states either `Guidance: docs/design-guidance.md` or `Guidance: none found; Q&A captured here`.

## Q&A

Ask max 2 batches.

Batch 1:
- Product: optimize for what across project? speed, reliability, low ops, rich UX, portability, cost, local-first?
- Architecture: preferred/forbidden languages, frameworks, stores, integrations, hosts, boundaries?
- Quality/security/release: must preserve what? compat, audit logs, no PII logs, rollback, offline, flags, prod approval?

Batch 2 if unclear:
- User/domain principles?
- Non-goals?
- Evolution triggers: language/runtime change, new product line, deploy model change, enterprise/compliance need, repeated retro miss?

## File Shape

```markdown
# Design Guidance

**Status:** Active
**Last updated:** YYYY-MM-DD
**Source:** human Q&A | retro <path> | ADR <path>

## Product Direction
- ...

## Architecture Constraints
- ...

## UX / Domain Principles
- ...

## Quality / Security / Operations
- ...

## Infrastructure / Integration Impact
- cloud resources, network paths, secrets, migrations, queues, storage, cost,
  scaling, env differences, deploy approval

## Multi-Component Validation
- proof across real boundaries: app+DB, API+worker, plugin+host, frontend+backend,
  CLI+service, IaC+runtime

## Non-Goals
- ...

## Evolution Triggers
- ...

## Change Log
| Date | Source | Change |
|---|---|---|
```

## Apply

Design must include:

```markdown
## Global Design Guidance

Source: `docs/design-guidance.md`

| guidance | design response |
|---|---|
| <constraint> | <how design follows it> |
```

Plan must turn relevant guidance into tasks/verification: code, tests, deploy wiring, rollback, privacy, UX, ops. Intentional guidance violation → ADR before plan.

Every non-trivial design answers:

- Security review: auth/authz, secrets, PII/logging, abuse case, deps/trust boundary, least privilege.
- Infra impact: resources create/change/destroy, migrations, network exposure, cost/scale, deploy/rollback, prod approval.
- Multi-component validation: smallest real integration/e2e proof; no mock-only boundary proof.

## Retro Backfeed

During `post-merge-retrospective`, update guidance only for durable future-design lessons:
- language/runtime/framework direction changed
- app/product/user segment evolved
- deploy/compliance/privacy/ops constraints changed
- repeated gate miss needs explicit principle
- guidance assumption proved false

Append dated `Change Log` row + edit relevant section. If file missing, create only when lesson affects future designs. One-off implementation trivia stays in retro.

## Smells

- Treating guidance as optional for "small" features.
- Copying all guidance into every design; cite + summarize touched constraints.
- Retro noise that would not change next design.
- Silent guidance violation.
