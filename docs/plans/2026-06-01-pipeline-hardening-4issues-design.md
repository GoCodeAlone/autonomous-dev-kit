# Autodev Pipeline Hardening (v6.3.0) — 5 Recurring Gate-Miss / Context-Waste Fixes — Design

**Status:** Approved (autonomous — user pre-authorized full-pipeline execution; trigger v6.3.0 release after merge)
**Date:** 2026-06-01
**Issues:** #41, #58, #59, #60, #61 (GoCodeAlone/autonomous-dev-kit)
**ADR:** decisions/0003-implement-n-completion-trust-boundary.md (#58)
**Adversarial review:** design cycle 1 = FAIL (1C/3I/3m) → all resolved this revision; #61 added (user-reported same session).

## Problem

Four open issues, all recurring gate-misses observed across infra-admin v1/v1.1
autonomous runs + Codex compaction:

- **#59** — plan-phase reviews can pass a design that says "behind X auth filter"/
  "RBAC enforced" while the plan wires a *weaker*, shape-matching gate (v1.1:
  client-supplied `evidence.granted_permissions` made write-tier RBAC theater;
  caught only on plan-review cycle 2).
- **#60** — a `run_in_background` pr-monitoring **Agent** told to poll-loop-with-
  sleep instead returns after ~1 cycle and re-completes repeatedly without the
  conclusive report (early-exited ~6× in v1.1). The lead fell back to self-polling
  `gh pr checks`, which worked but lost fire-on-event semantics.
- **#41** — the PreCompact hook (via Codex) is reported as emitting invalid hook
  JSON ("hook returned invalid PreCompact hook JSON output"), interrupting
  compaction-time state handling. Root cause class: locale warnings / diagnostics
  leaking onto the hook's stdout before/around its JSON.
- **#58** — `Implement: N` tasks get flipped to `completed` by implementers or via
  blockedBy-clear *before* the code-reviewer's quality gate, violating the
  team-conventions contract. In v1.1 this masked a non-compiling tree + a
  CI-failing hash regression both reported "done"; only the lead's
  verification-before-completion caught them.
- **#61** — the `pretool-pr-review-reminder` hook injects its ~12-line gh-version
  + Copilot-reviewer `<IMPORTANT>` block on **every** `gh pr create` (observed 7×
  in one session) — wasted context for advice the agent already has.

## Goals

One coherent v6.3.0 release hardening the autonomous pipeline against these four.

1. **#59** — add a plan-phase bug-class that walks the design's auth/authz chain
   component-by-component vs the plan's wiring; flag any gate that is
   client-asserted rather than server-enforced against an authenticated principal.
2. **#60** — make the **bash poll-loop** the sanctioned pr-monitoring wait pattern
   (a `run_in_background` Bash sleep-loop that *blocks to completion* and
   re-invokes the lead once on settle), documenting the subagent early-exit
   failure mode. Keep the subagent monitor as a documented fallback.
3. **#41** — harden the **`run-hook.cmd` wrapper** (the single choke-point all
   hooks run through) to (a) export a deterministic locale with portable fallback
   and (b) enforce **stdout JSON discipline**: only valid-JSON-or-empty reaches
   the host's hook parser; non-JSON noise is routed to stderr. Plus a regression
   test for noisy/locale-warning output.
4. **#58** — fix the *real* harm via a **trust boundary**, since a hard hook-block
   is infeasible (see Design): a flipped `Implement: N` is NOT trusted-done until
   the lead runs `verification-before-completion` (build + test from a clean
   tree). Strengthen `subagent-driven-development` + `team-conventions` + ADR.
5. **#61** — emit the pr-review reminder **once per session** (deduped via a
   `.claude/autodev-state` marker like `session-start`), reset by the PreCompact
   hook so it re-emits once after a compaction.

## Non-Goals

- No deterministic hook that *blocks* `TaskUpdate(status=completed)` on `Implement:*`
  — infeasible (see #58 design). No fragile heuristic that pretends to.
- No change to the hook event registrations in `hooks.json` (the wrapper change is
  transparent to all of them).
- No new pr-monitoring tool; reuse the existing `Bash run_in_background` primitive.
- No change to GHA/other-platform behavior; these are skill-doc + hook + version
  changes within the plugin.

## Global Design Guidance

`Guidance: none at docs/design-guidance.md; canon = README §Cross-LLM,
docs/plans/2026-04-25-cross-llm-portability-design.md, ADRs 0001/0002.`

| guidance | response |
|---|---|
| Host-neutral / cross-LLM first | The wrapper fix (#41) is the host-neutral choke-point. #60 is explicitly **host-scoped**: bash poll-loop under `<host: claude-code>`, self-poll fallback documented for `<host: codex,cursor>` (no false cross-LLM claim). #58 trust-boundary + #59 bug-class + #61 dedup-marker are host-neutral prose/state. #61 degrades to emit-every-time on identity-less hosts. |
| Checklist is the floor | #59 row joins the mandatory-scan plan-phase set. |
| Don't claim enforcement you can't deliver | #58 explicitly rejects the infeasible hard-block and documents why (ADR) — directly applies the Existence/runtime-validity discipline (#55). |
| Strict stdout discipline for hooks | #41 centralizes it in the wrapper, not per-hook. |

## Design

### #59 — Auth/authz chain-composition bug-class (plan phase)

Add one row to the **plan-phase** checklist of `skills/adversarial-design-review/
SKILL.md`. Place it **near the top** of the plan-phase table (right after
`Verification-class mismatch`), not after the plugin-layout/config-schema rows —
auth/authz is a security-class finding and ordering signals priority (m2):

```
| **Auth/authz chain composition** | When the design names an auth/authz chain ("behind the X auth filter", "RBAC-enforced", "admin-only"), walk that chain component-by-component against the plan's actual wiring. For each gate, verify it is enforced **server-side against an authenticated principal**, not shape-matched by a client-asserted value. Flag any gate where the plan's check reads from request/client-supplied input (`evidence.granted_permissions`, a header, a body field) instead of an authenticated subject (`authz.Enforce(authenticatedSubject, …)`). A plan that wires a weaker gate than the design's chain implies = finding. |
```

(Plan-phase, not design-phase: chain *composition* is a plan-wiring concern — the
design states the intent; the plan is where a weaker gate slips in.)

### #60 — Bash poll-loop as the sanctioned pr-monitoring pattern

In `skills/pr-monitoring/SKILL.md`, add a **"Waiting for CI: the sanctioned
pattern"** section near the top of the process. The recommendation is **host-scoped**
(the bash poll-loop is a Claude-Code Bash-`run_in_background` construct; Codex/Cursor
don't expose it identically):

- **`<host: claude-code>` — Recommended default:** a `Bash` tool call with
  `run_in_background: true` running a bounded sleep-loop that polls `gh pr checks`
  until no check is `pending` (or a failure), then prints a settle line and exits.
  The harness re-invokes the lead once on exit (≈0 tokens while sleeping). On
  settle the lead reads the result and admin-merges on `failures=0`. **Concrete
  cap (m3):** bound the loop (e.g. `for i in $(seq 1 120)` × `sleep 30` = 60 min)
  so it can never spin forever; on cap, print a timeout line and exit for the lead
  to restart.
- **Why:** a `run_in_background` **Agent** instructed to sleep-loop tends to return
  after ~1 cycle and re-complete repeatedly (the agent loop is not a blocking
  sleep) — observed early-exiting ~6× (#60). The bash sleep-loop genuinely blocks
  to completion.
- **`<host: codex, cursor>`:** these hosts keep the existing `<host: codex,
  opencode, cursor>` guidance (host's equivalent poll mechanism). Where no
  blocking-background-bash exists, the sanctioned fallback is **self-poll on each
  lead wakeup** — the lead runs `gh pr checks` once per turn and re-checks on the
  next turn — which loses fire-on-event but is reliable. Document this explicitly
  so the Codex path isn't left undefined.
- **Fallback (all hosts):** the existing background-Agent monitor stays documented
  for multi-PR review-comment handling needing active fix-and-push; note its
  early-exit failure mode.

### #41 — Wrapper-level stdout-JSON discipline (+ keep existing locale logic)

Harden `hooks/run-hook.cmd` (Unix portion — the choke-point every hook runs
through). The **primary** fix is stdout discipline; the existing locale handling
is already correct and stays.

1. **Locale (UNCHANGED):** the wrapper already falls back `C.UTF-8 → C` (covering
   `LC_ALL`/`LC_CTYPE`/`LANG`) when `C.UTF-8` is inherited but not installed —
   keep it as-is. We do **not** extend it to unset/empty locales (no evidence the
   Codex failure is an unset locale, and forcing `C` on an otherwise-working
   UTF-8 default could corrupt multibyte hook output). The real #41 cause is
   diagnostics leaking onto stdout, addressed below — the locale fallback already
   prevents the *bash* locale warning; stdout discipline catches whatever else
   (perl/git/jq diagnostics, shell tracing) leaks.

2. **Stdout JSON discipline (the fix):** run the hook with stdout captured (stderr
   passes through untouched; stdin still flows from host → hook). Then, when `jq`
   is available:
   - **empty** stdout → emit nothing.
   - stdout is **valid JSON as a whole** → emit it verbatim.
   - otherwise → **extract** the hook's JSON rather than suppress it: take the last
     line beginning with `{` (`printf '%s\n' "$out" | grep -E '^\{' | tail -1`);
     if that line is valid JSON (`jq -e .`), emit **that** on stdout and route the
     rest (the leading warning/diagnostic prefix) to **stderr**. If no JSON line is
     found, route the whole capture to stderr and emit nothing.
   - This is the C1 correction: a `decision:block` JSON preceded by a locale/perl
     warning (`warning\n{"decision":"block"}`) is **not** valid-as-a-whole, so the
     extraction path delivers the block instead of dropping it.
   - Preserve the hook's exit code. When `jq` is **absent**, pass stdout through
     unchanged (don't break hooks on minimal hosts).
   - **Trailing-newline note (I3):** capturing via `out=$(…)` strips trailing
     newlines; re-emitting via `printf '%s\n' "$out"` restores exactly one. JSON
     parsers accept one trailing newline — a regression case asserts this.

3. **Regression test** (`tests/hook-stdout-discipline.sh`, runs the real
   `run-hook.cmd` against fixture hooks): (a) warning-then-`{"decision":"block"}`
   → wrapper emits **only** the block JSON on stdout, warning on stderr, exit code
   preserved; (b) only-noise → stdout empty, noise on stderr; (c) clean valid JSON
   → unchanged, exactly one trailing newline; (d) jq-absent (PATH stub) →
   pass-through verbatim. Also run `tests/hook-contracts.sh` for no real-hook
   regression.

### #58 — Implement-N completion trust boundary (hard-block is infeasible)

**Investigation (the key finding):** a deterministic plugin hook that *blocks*
`TaskUpdate(status=completed)` on `Implement:*` tasks unless `owner ==
code-reviewer` is **not feasible**:
- The PreToolUse payload for a `TaskUpdate` call carries the *tool input*
  (`taskId`, `status`, `owner`) but **not the task's current subject** ("Implement:
  N") nor the calling subagent's identity. The task store is harness state the
  hook cannot read (no `TaskList` from a bash hook).
- So the hook cannot reliably determine "is taskId an Implement task?" or "is the
  caller the code-reviewer?" — the two facts the block needs. A heuristic (e.g.
  block all `completed`) would break legitimate completions.
- **Closest feasible hook approach, also rejected (m1):** a `SubagentStop` hook
  *does* receive `transcript_path` (used by `subagent-scope-guard` /
  `completion-claim-guard`), so it could parse the transcript for `TaskCreate`
  calls to map `taskId → "Implement: N"` subject and flag a matching
  `TaskUpdate(status=completed)`. Rejected as too unreliable: it only sees
  *subagent* completions (not a lead-level `TaskUpdate`), the transcript JSONL
  shape is not a stable API surface, and event ordering across subagents is racy.
  It would also only *warn after the fact* (SubagentStop fires post-completion),
  not block. So it does not deliver the asked-for enforcement and adds a fragile
  transcript-format dependency for marginal value.

**Feasible fix — shift the trust boundary (ADR 0003):** the harm in v1.1 was not
*who flipped the bit* but that a flipped `Implement: N` was **trusted as done**
while the tree didn't compile / CI failed. So:
- `skills/subagent-driven-development/SKILL.md`: add an explicit **"Completion is
  not trusted until lead-verified"** rule — regardless of who/what flips an
  `Implement: N` to `completed`, the lead MUST run
  `autodev:verification-before-completion` (build + test from a clean tree, CI
  green) before treating that task as truly done or proceeding to
  `finishing-a-development-branch`. A green checkbox is a *claim*, not *evidence*.
- `agents/team-conventions.md`: restate the code-reviewer-sole-flipper convention
  AND add the implementer rule "never self-complete an `Implement: N`; DM the
  reviewer instead" + the lead's trust-boundary gate.
- ADR 0003 records: rejected the infeasible hard-block; chose the verification
  trust-boundary; documented the hook-payload limitation so it isn't re-proposed.

### #61 — pr-review reminder: once per session, reset on compaction

`hooks/pretool-pr-review-reminder` currently emits its `<IMPORTANT>` block on every
`gh pr create`. Add session-dedup mirroring `hooks/session-start`'s
`session-start-seen` precedent:

- Derive a session key from `transcript_path` basename (the same key
  `pre-compact-snapshot`/`session-start` use). Marker file:
  `${cwd}/.claude/autodev-state/pr-reminder-seen` containing the session key(s)
  already reminded.
- On a matched `gh pr create`: if the current session key is already in the marker
  → `exit 0` silently (no emit). Else → emit the reminder once and append the
  session key to the marker.
- **Reset on compaction:** `hooks/pre-compact-snapshot` (PreCompact) removes the
  current session's key from `pr-reminder-seen` (or deletes the marker) so the
  next `gh pr create` after a compaction re-emits exactly once — the
  post-compaction context lost the earlier reminder.
- Degrade gracefully: no `transcript_path` (hookless/identity-less host) → fall
  back to current behavior (emit every time) rather than suppress, so a host that
  can't dedup still gets the advice.
- **Match precision (minor, in-scope):** tighten the trigger so it matches an
  actual `gh pr create` invocation, not the literal substring inside a quoted
  argument (e.g. an issue/PR *body* that mentions `gh pr create`) — anchor on a
  word boundary / command position. (Observed: this design's own tracking-issue
  body tripped the hook.)
- **Regression test:** two `gh pr create` payloads with the same session key →
  emitted once; a `pre-compact-snapshot` run between them → emitted again
  (post-compact reset); no `transcript_path` → emits each time.

- **#41** is security-adjacent: a hook that leaks non-JSON to stdout can corrupt
  the host's view of a *block* decision (e.g. a scope-guard `{"decision":"block"}`
  preceded by a locale warning could be ignored → a guarded action proceeds).
  Centralizing JSON discipline in the wrapper makes every block decision reliably
  delivered. No secrets touched; no network; the wrapper reads only the hook's own
  stdout.
- **#59** *is* an auth/authz review-quality improvement — it strengthens detection
  of client-asserted-permission theater in plans.
- **#58/#60** are process/doc; no runtime security surface.

## Infrastructure Impact

None at runtime. Plugin skill/hook/doc changes + a version bump. Release path is
the existing `release-tag.yml` (push to main touching `.claude-plugin/plugin.json`
→ version-check → tag → marketplace dispatch).

## Multi-Component Validation

- **#41 wrapper × hooks:** `tests/hook-stdout-discipline.sh` runs the **real**
  `run-hook.cmd` against fixture hook scripts (noisy + clean + jq-absent) and
  asserts stdout/stderr/exit-code — the real wrapper↔hook boundary, not a mock.
  Also run the existing `tests/hook-contracts.sh` to confirm no regression to the
  real hooks (session-start, scope-guard, completion-claim-guard, pre-compact).
- **#61 reminder dedup:** the regression test runs the real
  `pretool-pr-review-reminder` against two same-session `gh pr create` payloads
  (emit once) + a `pre-compact-snapshot` between them (re-emit once) + a
  no-`transcript_path` payload (emit each time) — the real hook↔state boundary.
- **#59/#60/#58:** `tests/skill-content-grep.sh` (host-neutral lint) +
  `tests/skill-cross-refs.sh` pass on the edited skills; plan-phase reviewers will
  enumerate the new class because the plan-phase checklist is embedded in their
  dispatch prompt.

## Assumptions

| id | assumption | challenge | fallback |
|---|---|---|---|
| A1 | All autodev hooks emit JSON-or-nothing on stdout (Claude-Code/Codex protocol) | A hook might emit intentional plain-text stdout | Verified: every registered hook emits `{…}` JSON or nothing. If a future hook needs plain-text stdout it must opt out — but none do today. |
| A2 | The PreToolUse payload lacks task subject + caller identity | Harness could add it later | Verified against the documented hook payload; if it ever exposes both, the hard-block becomes feasible and ADR 0003 should be revisited. |
| A3 | A `run_in_background` Bash sleep-loop genuinely blocks + re-invokes the lead once on exit (Claude Code) | Codex/Cursor lack this primitive | Directly observed working across this session's many CI waits ([[feedback_ci_wait_use_bash_poll_loop]]); scoped to `<host: claude-code>`, with the self-poll fallback documented for other hosts. |
| A6 | #41 last-JSON-line extraction recovers a block decision behind a warning | A hook could emit multi-line pretty-printed JSON (not single-line) | autodev hooks all emit single-line `jq -n` JSON (one object, one line); the `grep '^{' | tail -1` extraction matches. If a future hook pretty-prints, the whole-blob `jq .` path still handles the no-warning case; the test covers the warning-prefixed single-line case. |
| A4 | The wrapper can capture stdout without breaking hooks that read stdin | Hooks read the harness JSON from stdin, not the wrapper | The wrapper only redirects the hook's *stdout*; stdin still flows from the host to the hook unchanged. |
| A5 | v6.3.0 is the right bump + the tag is free | Could collide (the #804 lesson) | Verified `git ls-remote --tags` shows v6.3.0 free; current 6.2.2 → 6.3.0 minor. |

## Rollback

- Revert the PR(s). #59/#60/#58 are additive prose; #41 reverts the wrapper to its
  prior conditional-locale form (no migration). The version bump reverts with the
  same commit; do not push the v6.3.0 tag if reverted pre-merge.
- **#41 runtime note:** the wrapper is on the hook hot-path. If the captured-stdout
  change regresses a hook, rollback = revert `run-hook.cmd` to the `exec bash` form
  + re-run `tests/hook-contracts.sh`. The regression test gates this pre-merge.

## Self-Challenge

- **Simplest alternative:** fix the PreCompact hook script alone (#41) instead of
  the wrapper. Rejected — the issue explicitly wants the wrapper-level fix so
  *every* hook gets stdout discipline, not just one.
- **Most fragile assumption:** A1 (hooks emit JSON-or-nothing). Mitigated by the
  jq-absent pass-through + the fact that all current hooks comply.
- **YAGNI sweep:** no advisory `TaskUpdate` hook for #58 (it can't block, fires on
  every completion → noise); no new monitor tool for #60; no per-hook locale edits
  (#41 is wrapper-only). All rejected as surface the issues didn't ask for.
