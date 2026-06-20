---
name: runtime-launch-validation
description: Use after unit tests pass, before merge, when a change affects runtime behavior — launch the built artifact under realistic conditions and observe its behavior
---

> Condensed format: load `autodev:condensed-pipeline-writing` to expand shorthand.

# Runtime Launch Validation

## Iron Law

**Unit-test green ≠ launch green.** Engines fail at startup. Build pipelines fail at first run. Migrations fail mid-apply. The only proof a runtime artifact works is launching it.

After unit tests pass and before merge, for any change affecting runtime behavior, the implementer launches the built artifact under the closest-to-production conditions feasible locally, observes its behavior, and captures the transcript.

This skill complements `verification-before-completion` (general principle: evidence before assertion). `runtime-launch-validation` is the operationalization for runtime artifacts.

## When this applies

Triggered by changes to any of:

- Build configuration (Dockerfile, build script, CI build steps)
- Deployment configuration (compose, Kubernetes manifests, deployment workflows)
- Version pins on runtime, libraries, or build/launch-affecting tooling (images, CI build tools, language runtimes) — excludes dev-only tooling such as linters and formatters
- Application-startup configuration (config files read at boot)
- Database migrations
- Plugin / extension loading paths
- Modular UI/plugin contribution wiring (a plugin registers pages, panels,
  widgets, admin modules, or navigation into a host shell)
- Interface boundary changes (new method, field, event type, or hook crossing any of the boundary classes in `agents/boundary-classes.md`: producer→consumer, caller→callee, sender→handler, or plugin→host)

Triggered NOT by:

- Pure refactors of internal logic
- Documentation
- Test-only changes
- Dev-only tooling pin upgrades (linters, formatters) that cannot affect startup or launch behavior
- Library version bumps where the upgraded package has no runtime configuration impact AND existing tests already cover the new behavior

## Per-change-class instructions

| Change class | What to launch | What to observe |
|---|---|---|
| Application binary (server, CLI) | Build, run with production-equivalent config, exercise primary entry point (HTTP healthcheck, CLI `--version` plus a representative subcommand) | Stdout/stderr capture; exit code; healthcheck status |
| Container image | Build, `docker run` with production-equivalent env, hit `/healthz` (or equivalent) | Container logs, exit code, healthcheck status |
| Database migration | Apply against ephemeral DB instance; revert (down migration, if applicable); re-apply | Idempotent? No orphaned schema objects? |
| Library / SDK | Import into a tiny consumer program, exercise the new public surface | Output, behavior matches docs |
| Plugin / extension | Load it into the host application, exercise a representative call | Host doesn't crash on load; representative call returns |
| Modular UI/plugin contribution (admin page, panel, widget, nav item, or shell contribution) | Launch the host with the provider plugin installed; authenticate as a real principal if required; enumerate contributions from the host; open each new contribution route through the host shell, not the provider directly | Provider metadata exists; host lists and authorizes it; shell navigation includes it; route returns non-empty contribution-specific content; unauthorized principal is rejected; representative JS-backed contribution renders without blank/stub output |
| Interface boundary change (new method, field, event type, or hook — see `agents/boundary-classes.md` for the canonical boundary-class list) | Launch both sides/participants as applicable; exercise a real interaction across the boundary — not a mock or stub on either end | The receiving side correctly processes the new data/method/event/hook; no fallback silently swallows the new path; failure-signature scrape clean on all participating sides |
| Demonstration / example / showcase artifact (anything built to show a change working) | The real artifact, invoked through its real entry point; capture output from that run | Output is produced by the real code path, not literals; the artifact-under-demonstration is NOT stubbed; any substituted *dependency* sits behind a real interface seam and is disclosed. See `autodev:demonstration-fidelity`. |

When a demonstration *also* exercises a new boundary, both this row and the "Interface boundary change" row apply: stub neither the artifact nor the boundary under test — only a disclosed *dependency* behind the artifact may be substituted.

## Failure-signature scrape

While watching the artifact run, scan output for these patterns. Any hit is a fail.

- Panics / uncaught exceptions / crash dumps
- "fetch from remote: lookup ... no such host" — DNS failure (common for missing version pins)
- "module not found" / "import error"
- "version mismatch" / "incompatible API version"
- "schema drift" / "missing column" / "constraint violation"
- "permission denied" on resources the artifact should be able to access
- Stack traces (any language)
- "address already in use" — port collision (often from prior runs not cleaned)

If any pattern hits, the launch validation fails. Capture the exact line + 5 lines of context.

## Transcript format for PR body

Include in the PR description:

```
## Runtime launch transcript

Build:
$ <build command>
<relevant lines, not full dump>

Launch:
$ <launch command>
<startup lines until ready>
<healthcheck observation>

Failure-signature scrape: clean (or: list of hits with context)

Verdict: PASS / FAIL
```

## Fall-back when local launch is infeasible

If the change touches runtime behavior but the implementer's local environment can't realistically launch (no Docker, no target OS, no required external service), they must:

1. State the constraint explicitly in the PR body.
2. Propose how the launch will happen (e.g., "CI image-launch job runs on every PR; this PR enables that path") OR
3. Ask the orchestrator to launch on a capable host before merge.

The constraint is not an excuse to skip; it's a request for help.

## See also

- `skills/verification-before-completion/SKILL.md` — general evidence-before-assertion principle
- `autodev:demonstration-fidelity` — demo/example/showcase artifacts must execute the real artifact (the "Demonstration" change-class row above)
- `skills/finishing-a-development-branch/SKILL.md` — Step 1b invokes this skill
- `skills/writing-plans/SKILL.md` — related planning guidance for per-change-class verification
- `agents/boundary-classes.md` — canonical definition of interface boundary classes (producer→consumer, caller→callee, sender→handler, plugin→host)
