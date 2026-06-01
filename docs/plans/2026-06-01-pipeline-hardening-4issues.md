# Autodev Pipeline Hardening (v6.3.0) Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Ship 5 recurring-gate-miss / context-waste fixes (#41/#58/#59/#60/#61) as one v6.3.0 release.

**Architecture:** Skill-doc additions (#59 bug-class, #60 pr-monitoring pattern, #58 trust-boundary) + two hook changes through the choke-points (#41 `run-hook.cmd` stdout-JSON discipline; #61 `pretool-pr-review-reminder` session-dedup + `pre-compact-snapshot` marker-clear) + a CI workflow that runs the hook regression tests + a version bump that triggers `release-tag.yml`.

**Tech Stack:** Markdown skill files; bash hooks + `jq`; bash test harness (`tests/hook-contracts.sh`); GitHub Actions.

**Base branch:** main

---

## Scope Manifest

**PR Count:** 1
**Tasks:** 9
**Estimated Lines of Change:** ~340 (informational; not enforced)

**Out of scope:**
- A deterministic hook that *blocks* `TaskUpdate(status=completed)` on `Implement:*` (infeasible — ADR 0003).
- Any advisory `TaskUpdate` hook for #58 (rejected — noisy, can't identify Implement tasks).
- Extending the wrapper locale logic to unset/empty locales (#41 keeps existing locale handling).
- Any new pr-monitoring tool / Codex-specific background primitive (#60 documents host-scoped patterns only).
- Changing hook event registrations in `hooks.json` (the wrapper change is transparent; only the new `hooks-check.yml` workflow is added).

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | feat: v6.3.0 pipeline hardening (#41/#58/#59/#60/#61/#63/#64) | Task 1, Task 2, Task 3, Task 4, Task 5, Task 6, Task 7, Task 8, Task 9 | feat/pipeline-hardening-4issues-v6.3.0 |

**Status:** Amended 2026-06-01T06:00:00Z (user-approved scope expansion to #63 + #64; see Amendment note + decisions/0004)

---

## Project Design Guidance

`Guidance: none at docs/design-guidance.md; canon = README §Cross-LLM + ADRs 0001/0002/0003.` Mapping:
- Host-neutral → #41 wrapper + #59/#58/#61 are host-neutral; #60 explicitly host-scoped (verified by `tests/skill-content-grep.sh` host-token lint).
- Don't claim enforcement you can't deliver → #58 (ADR 0003) + #41 (a test that runs in CI, Task 6).
- Checklist is the floor → #59 joins the mandatory plan-phase scan.

---

### Task 1: #59 — auth/authz chain-composition bug-class (plan-phase)

**Files:**
- Modify: `skills/adversarial-design-review/SKILL.md` (plan-phase table, insert right after the `Verification-class mismatch` row)

**Step 1: Verify the insertion anchor**
Run: `grep -n "Verification-class mismatch" skills/adversarial-design-review/SKILL.md`
Expected: one match in the plan-phase table (lines ~104-113). The new row goes immediately after it.

**Step 2: Insert the row** (exact, after the `Verification-class mismatch` row):
```
| **Auth/authz chain composition** | When the design names an auth/authz chain ("behind the X auth filter", "RBAC-enforced", "admin-only"), walk that chain component-by-component against the plan's actual wiring. For each gate, verify it is enforced **server-side against an authenticated principal**, not shape-matched by a client-asserted value. Flag any gate where the plan's check reads from request/client-supplied input (`evidence.granted_permissions`, a header, a body field) instead of an authenticated subject (`authz.Enforce(authenticatedSubject, …)`). A plan that wires a weaker gate than the design's chain implies = finding. |
```

**Step 3: Verify placement + lint**
Run: `awk '/Bug-class checklist — plan phase/{p=1} p && /Auth\/authz chain composition/{print NR": ok"}' skills/adversarial-design-review/SKILL.md`
Expected: one line (row is in the plan-phase section).
Run: `bash tests/skill-content-grep.sh 2>&1 | tail -1`
Expected: `PASS: …`.

**Step 4: Commit**
```bash
git add skills/adversarial-design-review/SKILL.md
git commit -m "feat(adversarial-design-review): add auth/authz chain-composition plan-phase bug-class (#59)"
```
Rollback: revert commit (additive prose row).

---

### Task 2: #60 — pr-monitoring bash poll-loop sanctioned pattern

**Files:**
- Modify: `skills/pr-monitoring/SKILL.md` (add a "Waiting for CI: the sanctioned pattern" subsection near the top of the process, after the overview)

**Step 1: Add the section** (host-scoped, per design §#60). Insert after the "## When to Use" / before "## The Process" (or near the top of the process):

```markdown
## Waiting for CI: the sanctioned pattern

<host: claude-code>
**Recommended default — a bash poll-loop, not a long-lived monitor Agent.** Issue a
`Bash` tool call with `run_in_background: true` running a **bounded** sleep-loop that
polls `gh pr checks <pr>` until no check is `pending` (or a failure), prints a settle
line, and exits. The harness re-invokes the lead **once** on exit (≈0 tokens while it
sleeps); the lead then reads the result and admin-merges on `failures=0`.

Bound the loop so it can never spin forever, e.g.:
```bash
for i in $(seq 1 120); do            # 120 × 30s = 60 min cap
  raw=$(gh pr checks <pr> --json bucket 2>/dev/null)
  fail=$(echo "$raw" | jq '[.[]|select(.bucket=="fail")]|length')
  pend=$(echo "$raw" | jq '[.[]|select(.bucket=="pending")]|length')
  { [ "$fail" != 0 ] && [ -n "$fail" ]; } && { echo "FAILURES=$fail"; break; }
  { [ "$pend" = 0 ] || [ -z "$pend" ]; } && { echo "SETTLED"; break; }
  sleep 30
done
```
On the 120-iteration cap, print a timeout line and exit for the lead to restart.

**Why not a background Agent:** a `run_in_background` **Agent** told to sleep-loop
tends to return after ~1 cycle and re-complete repeatedly (the agent loop is not a
blocking sleep) — observed early-exiting ~6× in one run. The bash sleep-loop genuinely
blocks to completion.
</host>

<host: codex, cursor, opencode>
Use your host's equivalent poll mechanism. Where no blocking-background-bash exists,
the sanctioned fallback is **self-poll on each lead wakeup**: run `gh pr checks <pr>`
once per turn and re-check next turn. This loses fire-on-event but is reliable; do not
dispatch a background Agent expecting it to block on a sleep-loop.
</host>

**Fallback (all hosts):** the background-Agent monitor below remains documented for
multi-PR review-comment handling needing active fix-and-push; note its early-exit
failure mode and prefer the poll-loop / self-poll for pure CI-wait.
```

**Step 2: Verify lint + cross-refs**
Run: `bash tests/skill-content-grep.sh 2>&1 | tail -1` → `PASS`
Run: `bash tests/skill-cross-refs.sh 2>&1 | tail -1` → `PASS: all cross-skill references resolve.`

**Step 3: Commit**
```bash
git add skills/pr-monitoring/SKILL.md
git commit -m "docs(pr-monitoring): sanction the bash poll-loop CI-wait pattern, host-scoped (#60)"
```
Rollback: revert commit.

---

### Task 3: #58 — Implement-N completion trust boundary

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md` (add a "Completion is not trusted until lead-verified" rule)
- Modify: `agents/team-conventions.md` (restate the implementer/code-reviewer rules + the lead trust-boundary)
- (ADR `decisions/0003-implement-n-completion-trust-boundary.md` already committed with the design.)

**Step 1: Add the trust-boundary rule to subagent-driven-development** — near the "Red Flags"/completion section, add:
```markdown
### Completion is not trusted until lead-verified

A green `Implement: N` checkbox is a **claim, not evidence**. Regardless of who or
what flips an `Implement: N` task to `completed` (implementer, a blockedBy-clear, or
the code-reviewer), the lead MUST run `autodev:verification-before-completion` —
build + test from a clean tree, CI green — before treating that task as truly done or
invoking `finishing-a-development-branch`. The team-conventions "only code-reviewer
flips Implement-N" rule remains team discipline, but correctness rests on lead
verification, which does not depend on who flipped the bit. (A deterministic hook that
blocks the flip is infeasible — the PreToolUse payload lacks the task subject and
caller identity; see decisions/0003-implement-n-completion-trust-boundary.md.)
```

**Step 2: Add the rules to team-conventions.md** — under the Implementer + a Code-reviewer/Lead section:
- Implementer: "Never self-complete an `Implement: N` task. DM the spec-reviewer when ready; the code-reviewer is the sole flipper."
- Lead: "Treat any `completed` Implement-N as a claim; run `verification-before-completion` (clean build + tests + CI green) before accepting it or finishing the branch."

**Step 3: Verify lint + cross-refs**
Run: `bash tests/skill-content-grep.sh 2>&1 | tail -1` → `PASS`
Run: `bash tests/skill-cross-refs.sh 2>&1 | tail -1` → `PASS`

**Step 4: Commit**
```bash
git add skills/subagent-driven-development/SKILL.md agents/team-conventions.md
git commit -m "docs(subagent-driven-development): completion trust-boundary for Implement-N (#58, ADR 0003)"
```
Rollback: revert commit.

---

### Task 4: #41 — run-hook.cmd stdout-JSON discipline + test

**Files:**
- Modify: `hooks/run-hook.cmd` (Unix portion — replace the final `exec bash …` with a capture-then-discipline block; keep the locale logic unchanged)
- Create: `tests/hook-stdout-discipline.sh`

**Step 1: Write the failing test** (`tests/hook-stdout-discipline.sh`) — runs the REAL `run-hook.cmd` against fixture hooks:
```bash
#!/usr/bin/env bash
# tests/hook-stdout-discipline.sh — verify run-hook.cmd enforces stdout JSON discipline.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="$REPO_ROOT/hooks/run-hook.cmd"
failures=0
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures+1)); }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq required"; exit 0; }

tmp="$(mktemp -d)"
# Cleanup trap set BEFORE any fixture is copied into hooks/ (rm -f on absent files is safe).
trap 'rm -f "$REPO_ROOT"/hooks/fix-warn-then-json "$REPO_ROOT"/hooks/fix-noise "$REPO_ROOT"/hooks/fix-clean; rm -rf "$tmp"' EXIT
mkfix() { printf '%s\n' "$1" > "$tmp/$2"; chmod +x "$tmp/$2"; }

# Fixture A: locale warning to stderr-or-stdout then a block JSON on stdout.
mkfix '#!/usr/bin/env bash
echo "perl: warning: Setting locale failed."   # leaks to stdout
printf "%s\n" "{\"decision\":\"block\",\"reason\":\"x\"}"' fix-warn-then-json
# Fixture B: only noise, no JSON.
mkfix '#!/usr/bin/env bash
echo "just a diagnostic line"' fix-noise
# Fixture C: clean single-line JSON.
mkfix '#!/usr/bin/env bash
printf "%s\n" "{\"hookSpecificOutput\":{\"hookEventName\":\"X\"}}"' fix-clean

run() { local out err rc; out="$("$WRAPPER" "$1" 2>"$tmp/err")"; rc=$?; printf '%s' "$out" > "$tmp/out"; err="$(cat "$tmp/err")"; OUT="$out"; ERR="$err"; RC=$rc; }

# Point the wrapper at the tmp fixtures by copying them next to run-hook.cmd is
# heavy; instead invoke the wrapper with a fixture in hooks/ via a temp symlink dir.
# Simplest: call the wrapper with HOOK_DIR override is not supported, so copy fixtures
# into hooks/ under a unique prefix and clean up.
for f in fix-warn-then-json fix-noise fix-clean; do cp "$tmp/$f" "$REPO_ROOT/hooks/$f"; done

# (a) warning + block JSON → stdout is ONLY the block JSON; warning ON stderr (m1).
run fix-warn-then-json
if printf '%s' "$OUT" | jq -e '.decision=="block"' >/dev/null 2>&1 \
   && ! printf '%s' "$OUT" | grep -q 'perl: warning' \
   && printf '%s' "$ERR" | grep -q 'perl: warning'; then
  pass "(a) block JSON on stdout, warning routed to stderr"
else fail "(a) expected block JSON on stdout + warning on stderr, got OUT=[$OUT] ERR=[$ERR]"; fi

# (b) only noise → stdout empty, noise on stderr.
run fix-noise
{ [ -z "$OUT" ] && printf '%s' "$ERR" | grep -q 'diagnostic'; } \
  && pass "(b) noise suppressed from stdout, routed to stderr" || fail "(b) expected empty stdout, got: $OUT"

# (c) clean JSON → unchanged + valid.
run fix-clean
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName=="X"' >/dev/null 2>&1 \
  && pass "(c) clean JSON passthrough" || fail "(c) clean JSON broke, got: $OUT"

# (d) jq-absent (I2) → wrapper passes stdout through VERBATIM (warning + JSON both present).
# Stub PATH so the wrapper's `command -v jq` fails; assert via grep (no jq needed here).
nojq="$tmp/nojq"; mkdir -p "$nojq"
OUTD="$(PATH="$nojq" "$WRAPPER" fix-warn-then-json 2>/dev/null)"
{ printf '%s' "$OUTD" | grep -q 'perl: warning' && printf '%s' "$OUTD" | grep -q '"decision":"block"'; } \
  && pass "(d) jq-absent → verbatim passthrough (no discipline applied)" \
  || fail "(d) expected verbatim passthrough with jq absent, got: $OUTD"

echo ""; echo "Results: $failures failure(s)"; [ "$failures" -eq 0 ]
```

> Implementation note: fixtures are copied into `hooks/` (the wrapper resolves
> scripts relative to its own dir) and cleaned up in the trap (set BEFORE the copy so
> a mid-test failure still cleans up). The top `command -v jq` guard SKIPs only when
> the **test machine** has no jq (can't run a/b/c); on CI (jq present) all four cases
> run — case (d) stubs PATH so the **wrapper** sees no jq and asserts verbatim
> passthrough via grep (no jq needed for that assertion).

**Step 2: Run → FAIL** (wrapper still `exec bash`, doesn't strip the warning):
Run: `bash tests/hook-stdout-discipline.sh 2>&1 | tail -6`
Expected: `(a)` FAILs (stdout contains the perl warning + JSON).

**Step 3: Implement the wrapper discipline** — replace the final `exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"` line of `hooks/run-hook.cmd` with:
```bash
# Run the hook with stdout captured (stderr + stdin pass through untouched).
# Enforce stdout JSON discipline: only valid-JSON-or-empty reaches the host's hook
# parser; diagnostics that leak onto stdout (locale/perl/git warnings) are routed to
# stderr. A block decision preceded by a warning is recovered, not dropped (#41).
if command -v jq >/dev/null 2>&1; then
  hook_out="$(bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@")"
  hook_rc=$?
  if [ -z "$hook_out" ]; then
    : # nothing to emit
  elif printf '%s' "$hook_out" | jq -e . >/dev/null 2>&1; then
    printf '%s\n' "$hook_out"                       # valid JSON as a whole
  else
    json_line="$(printf '%s\n' "$hook_out" | grep -E '^\{' | tail -1)"
    if [ -n "$json_line" ] && printf '%s' "$json_line" | jq -e . >/dev/null 2>&1; then
      printf '%s\n' "$hook_out" | grep -vF "$json_line" >&2   # diagnostics → stderr
      printf '%s\n' "$json_line"                              # recovered JSON → stdout
    else
      printf '%s\n' "$hook_out" >&2                           # all noise → stderr
    fi
  fi
  exit "$hook_rc"
else
  exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"     # jq absent: pass through unchanged
fi
```

**Step 4: Run → PASS**
Run: `bash tests/hook-stdout-discipline.sh 2>&1 | tail -6`
Expected: `Results: 0 failure(s)` (all of a/b/c pass).
Run: `bash tests/hook-contracts.sh 2>&1 | tail -3`
Expected: existing hook contracts still pass (no regression to real hooks through the wrapper).

**Step 5: Commit**
```bash
git add hooks/run-hook.cmd tests/hook-stdout-discipline.sh
git commit -m "fix(run-hook.cmd): enforce stdout JSON discipline, recover block decisions behind warnings (#41)"
```
Rollback: revert `run-hook.cmd` to the `exec bash` form + re-run `tests/hook-contracts.sh`. Hook-path change — verified by the regression test (Task 6 CI-gates it).

---

### Task 5: #61 — pr-review reminder dedup + pre-compact clear

**Files:**
- Modify: `hooks/pretool-pr-review-reminder` (session-dedup + tighter match)
- Modify: `hooks/pre-compact-snapshot` (clear the marker, unconditionally, before the early-exit)
- Modify: `tests/hook-contracts.sh` (dedup + post-compact-reset cases)

**Step 1: Add the dedup + post-compact tests to `tests/hook-contracts.sh`** (reuse `run_hook` + a tmp cwd):
```bash
test_pr_reminder_dedup() {
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN                       # I3: repo-convention cleanup
  local sess='/x/transcripts/sess-abc.jsonl'
  local payload='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title t --body b"},"cwd":"'"$tmp"'","transcript_path":"'"$sess"'"}'
  # first call emits
  local out1; out1="$(run_hook pretool-pr-review-reminder "$payload")"
  printf '%s' "$out1" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
    || fail "pr-reminder: first call should emit"
  # second call (same session) is silent
  local out2; out2="$(run_hook pretool-pr-review-reminder "$payload")"
  [ -z "$out2" ] && pass "pr-reminder: deduped within session" \
    || fail "pr-reminder: second call should be silent, got: $out2"
  # a PreCompact run with NO locked plans must still clear the marker
  run_hook pre-compact-snapshot '{"cwd":"'"$tmp"'","transcript_path":"'"$sess"'"}' >/dev/null 2>&1 || true
  local out3; out3="$(run_hook pretool-pr-review-reminder "$payload")"
  printf '%s' "$out3" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
    && pass "pr-reminder: re-emits after PreCompact reset" \
    || fail "pr-reminder: should re-emit after compaction, got: $out3"
  # I1: a quoted body that merely mentions 'gh pr create' must NOT emit
  local fp='{"tool_name":"Bash","tool_input":{"command":"gh issue create --title t --body \"see gh pr create docs\""},"cwd":"'"$tmp"'","transcript_path":"'"$sess"'"}'
  local outfp; outfp="$(run_hook pretool-pr-review-reminder "$fp")"
  [ -z "$outfp" ] && pass "pr-reminder: not tripped by 'gh pr create' inside a quoted body" \
    || fail "pr-reminder: false-positive on quoted body, got: $outfp"
  # degrade gracefully: no transcript_path → emits every time (no marker write)
  local tmp2; tmp2="$(mktemp -d)"
  local np='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title t"},"cwd":"'"$tmp2"'"}'
  local na; na="$(run_hook pretool-pr-review-reminder "$np")"
  local nb; nb="$(run_hook pretool-pr-review-reminder "$np")"
  { printf '%s' "$na" | jq -e '.hookSpecificOutput' >/dev/null 2>&1 && printf '%s' "$nb" | jq -e '.hookSpecificOutput' >/dev/null 2>&1; } \
    && pass "pr-reminder: no transcript_path → emits every time" \
    || fail "pr-reminder: should emit each time without transcript_path"
  rm -rf "$tmp2"
}
# (call test_pr_reminder_dedup in the main run sequence)
```

**Step 2: Run → FAIL** (reminder has no dedup yet):
Run: `bash tests/hook-contracts.sh 2>&1 | grep -i "pr-reminder" | head`
Expected: the "deduped within session" case FAILs (second call still emits).

**Step 3: Implement dedup in `pretool-pr-review-reminder`** — after computing `cmd` and confirming `gh pr create`, before emitting:
- **Tighten the match via quote-stripping (I1 — mirror `pre-tool-scope-guard`'s precedent), NOT a boundary regex.** A boundary regex still matches `gh pr create` inside a quoted `--body`. Strip quoted segments first, then match on the stripped command:
  ```bash
  cmd_unquoted=$(printf '%s' "$cmd" | sed "s/\"[^\"]*\"//g; s/'[^']*'//g")  # double-first, matching pre-tool-scope-guard
  printf '%s' "$cmd_unquoted" | grep -q 'gh pr create' || exit 0
  ```
  So `gh issue create --body "… gh pr create …"` → stripped → `gh issue create --body ` → no match → no emit; a real `gh pr create --title t --body b` → stripped → `gh pr create --title t --body ` → matches.
- Compute `session_key`: `transcript_path=$(… jq -r .transcript_path …); session_key=""; [ -n "$transcript_path" ] && session_key=$(basename "$transcript_path")`.
- Marker: `marker="${cwd_dir}/.claude/autodev-state/pr-reminder-seen"`.
- If `[ -n "$session_key" ]` and `grep -qxF "$session_key" "$marker" 2>/dev/null` → `exit 0` (already reminded). Else emit, and if `[ -n "$session_key" ]` append: `mkdir -p "$(dirname "$marker")"; printf '%s\n' "$session_key" >> "$marker"`.
- No `session_key` (no transcript) → emit every time (current behavior).

**Step 4: Implement the clear in `pre-compact-snapshot`** — UNCONDITIONALLY, immediately after `session_key` is computed (≈ line 30) and BEFORE the `[ -z "$state_section" ] && exit 0` early-exit:
```bash
# #61: clear this session's pr-review-reminder marker so the reminder re-emits once
# after compaction (the post-compaction context lost the earlier reminder). Must run
# before the no-locked-plans early-exit. Guard on a non-empty session key.
if [ -n "${session_key:-}" ]; then
  reminder_marker="${cwd_dir}/.claude/autodev-state/pr-reminder-seen"
  if [ -f "$reminder_marker" ]; then
    grep -vxF "$session_key" "$reminder_marker" > "${reminder_marker}.tmp" 2>/dev/null \
      && mv "${reminder_marker}.tmp" "$reminder_marker" || rm -f "${reminder_marker}.tmp"
  fi
fi
```

**Step 5: Run → PASS**
Run: `bash tests/hook-contracts.sh 2>&1 | tail -4`
Expected: all pass, including `pr-reminder: deduped within session` + `pr-reminder: re-emits after PreCompact reset`.

**Step 6: Commit**
```bash
git add hooks/pretool-pr-review-reminder hooks/pre-compact-snapshot tests/hook-contracts.sh
git commit -m "fix(hooks): pr-review reminder once-per-session + PreCompact reset (#61)"
```
Rollback: revert commit (hooks restore prior emit-every-time behavior).

---

### Task 6: CI-gate the hook regression tests

**Files:**
- Create: `.github/workflows/hooks-check.yml`

**Rationale:** #41 is a hook-reliability fix; its regression test must actually run in CI (a test that never runs is theater — the existence/runtime-validity discipline). No workflow currently runs the hook tests.

**Step 1: Add the workflow**
```yaml
name: Hooks Check
on:
  push:
    paths:
      - 'hooks/**'
      - 'tests/hook-contracts.sh'
      - 'tests/hook-stdout-discipline.sh'
      - '.github/workflows/hooks-check.yml'
  pull_request:
    paths:
      - 'hooks/**'
      - 'tests/hook-contracts.sh'
      - 'tests/hook-stdout-discipline.sh'
jobs:
  hooks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq
      - name: Hook contract tests
        run: bash tests/hook-contracts.sh
      - name: Hook stdout discipline tests
        run: bash tests/hook-stdout-discipline.sh
```

**Step 2: Verify both test scripts currently pass locally (the gate is real)**
Run: `bash tests/hook-contracts.sh 2>&1 | tail -2 && bash tests/hook-stdout-discipline.sh 2>&1 | tail -2`
Expected: both report 0 failures (after Tasks 4+5).

**Step 3: Lint the workflow YAML**
Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/hooks-check.yml'))" && echo "YAML OK"`
Expected: `YAML OK`.

**Step 4: Commit**
```bash
git add .github/workflows/hooks-check.yml
git commit -m "ci: run hook contract + stdout-discipline tests on hooks/tests changes (#41/#61)"
```
Rollback: revert commit (removes the workflow).

---

### Task 7: Version bump → v6.3.0 + RELEASE-NOTES

**Files:**
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.cursor-plugin/plugin.json` (via `scripts/bump-version.sh`)
- Modify: `RELEASE-NOTES.md`

**Step 1: Confirm start version + the tag is free**
Run: `grep -m1 '"version"' .claude-plugin/plugin.json; git ls-remote --tags origin refs/tags/v6.3.0`
Expected: `6.2.2`; `git ls-remote` prints nothing (v6.3.0 free).

**Step 2: Bump**
Run: `scripts/bump-version.sh 6.3.0`
Expected: `Bumping version: 6.2.2 → 6.3.0` across the 3 manifests.

**Step 3: Consistency gate (the exact check `release-tag.yml` runs)**
Run: `bash tests/version-check.sh`
Expected: `OK: All version files agree on version 6.3.0`.

**Step 4: Add RELEASE-NOTES entry** — a `## v6.3.0 — 2026-06-01` section at the top (below the title), summarizing the 5 fixes (#41/#58/#59/#60/#61).

**Step 5: Commit**
```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .cursor-plugin/plugin.json RELEASE-NOTES.md
git commit -m "chore: bump version to 6.3.0 (#41/#58/#59/#60/#61)"
```
Rollback: `scripts/bump-version.sh 6.3.0 6.2.2` + revert; pre-merge revert prevents the v6.3.0 tag (release fires only on merge-to-main touching plugin.json).

> After merge: `release-tag.yml` auto-tags v6.3.0 + dispatches the marketplace. Create the GH Release from the RELEASE-NOTES v6.3.0 section (tag-only is the workflow's behavior; v6.2.0/6.2.2 precedent).

---

### Task 8: #64 — session-start time-dedup Linux portability (amendment)

**Discovered at execution:** Task 6's new `hooks-check.yml` ran `hook-contracts.sh` on
ubuntu for the first time and surfaced a **pre-existing** Linux bug:
`hooks/session-start` computes the last-emit mtime with BSD `stat -f %m` **before** GNU
`stat -c %Y`. On Linux `stat -f` means "file system status", succeeds (exit 0), and
prints fs info instead of the mtime → `[ "$last" -gt 0 ]` errors and the time-dedup
never suppresses re-fires. User-approved amendment (#64).

**Files:**
- Modify: `hooks/session-start` (the `stat` ordering + numeric guard)
- Modify: `.github/workflows/hooks-check.yml` (re-enable `hook-contracts.sh` once fixed)

**Step 1: Fix the `stat` ordering** — GNU first, then BSD, then guard numeric:
```bash
last=$(stat -c %Y "$LAST_EMIT_FILE" 2>/dev/null || stat -f %m "$LAST_EMIT_FILE" 2>/dev/null || echo 0)
case "$last" in (*[!0-9]*|'') last=0 ;; esac
```
**Step 2: Re-enable `hook-contracts.sh` in `hooks-check.yml`** (the CI gate is now real on Linux).
**Step 3: Verify** — `bash tests/hook-contracts.sh` → `All hook contract tests passed.`
(macOS: `stat -c %Y` fails → falls to BSD `stat -f %m`; Linux: `stat -c %Y` works.) CI on
ubuntu confirms the time-dedup case now passes.
**Step 4: Commit** — `fix(session-start): GNU stat -c %Y before BSD -f %m … (#64)`.
Rollback: revert commit.

### Task 9: #63 — Artifact-class precedent design-phase bug-class (amendment)

**User-approved amendment (#63).** A design can pass mechanism-correctness review yet put
an artifact in the wrong *place/shape* (v1.1: a scenario test fixture inside the
production engine repo, when sibling scenarios own a `cmd/server/main.go`).

**Files:**
- Modify: `skills/adversarial-design-review/SKILL.md` (design-phase table, after `Repo-precedent conflicts`)

**Step 1: Insert the row** (after `Repo-precedent conflicts`):
```
| **Artifact-class precedent** | Survey how the codebase already implements this *artifact class* — not just the *mechanism*. … Grep for sibling instances (`ls scenarios/*/cmd/server/main.go`, sibling plugins, migrations, CLI commands, fixtures) and confirm the design follows the established shape — or explicitly justifies divergence. … Run the decisive `ls`/`grep` for the artifact class, not just for the mechanism. |
```
**Step 2: Verify** — awk confirms the row is in the **design-phase** section; `bash tests/skill-content-grep.sh` PASS.
**Step 3: Commit** — `feat(adversarial-design-review): add Artifact-class precedent design-phase bug-class (#63)`.
Rollback: revert commit (additive prose row).

## Verification summary (change-class mapping)

| Task | Change class | Verification | Expected |
|---|---|---|---|
| 1 | Documentation (skill) | skill-content-grep + awk placement | PASS; row in plan-phase section |
| 2 | Documentation (skill) | skill-content-grep + skill-cross-refs | PASS |
| 3 | Documentation (skill+agent) | skill-content-grep + skill-cross-refs | PASS |
| 4 | Hook (wrapper) | `tests/hook-stdout-discipline.sh` + `tests/hook-contracts.sh` | 0 failures; block JSON recovered behind warning |
| 5 | Hook (reminder+precompact) | `tests/hook-contracts.sh` dedup+reset cases | 0 failures; deduped + re-emits post-compact |
| 6 | CI workflow | YAML lint + both hook test scripts pass locally | YAML OK; 0 failures |
| 7 | Version pin | `tests/version-check.sh` | all 3 manifests agree on 6.3.0 |

## Multi-Component / Integration proof

The real boundaries: (a) wrapper↔hook — Task 4's `hook-stdout-discipline.sh` runs the
**real** `run-hook.cmd` against fixture hooks (warning+JSON, noise, clean) and asserts
stdout/stderr; `hook-contracts.sh` runs the real registered hooks through the wrapper
(no regression). (b) reminder↔state↔pre-compact — Task 5's tests run the **real**
`pretool-pr-review-reminder` + `pre-compact-snapshot` against a shared tmp
`.claude/autodev-state`, asserting dedup + post-compact reset. (c) Task 6 CI-gates both
so the hook fixes can't silently regress.
