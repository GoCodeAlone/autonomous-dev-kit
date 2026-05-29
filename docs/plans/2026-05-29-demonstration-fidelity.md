# Demonstration Fidelity Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Add a harness-agnostic `demonstration-fidelity` skill + advisory write-time hook + pipeline wiring so agents stop shipping fake demos (reimplementation / hard-coded output / artifact-stub) that don't execute the real code.

**Architecture:** Skill markdown is the universal load-bearing layer (all harnesses). An advisory, never-blocking PreToolUse hook is a best-effort write-time nudge (Claude/Codex/Cursor). Cross-refs wire it into RLV, verification-before-completion, finishing, using-autodev, README, coverage table. Design: `docs/plans/2026-05-29-demonstration-fidelity-design.md` (adversarial-review PASS rev3).

**Tech Stack:** Bash hooks (jq), Markdown skills, existing `tests/*.sh` harness.

**Base branch:** main

---

## Scope Manifest

**PR Count:** 1
**Tasks:** 8
**Estimated Lines of Change:** ~420 (informational)

**Out of scope:**
- A general "anti-fabrication / fake-evidence" skill beyond demonstrations (YAGNI; the reported failure is demos).
- A blocking Stop-hook interceptor on completion claims (Option D — user chose advisory-only; a non-blocking Stop hook is a no-op).
- OpenCode per-tool hook port (OpenCode has no PreToolUse equivalent today; skill markdown still covers it).
- Editing user CLAUDE.md/AGENTS.md.

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | feat: demonstration-fidelity skill + advisory hook + wiring (v6.2.0) | Task 1, Task 2, Task 3, Task 4, Task 5, Task 6, Task 7, Task 8 | feat/demonstration-fidelity-2026-05-29T1128 |

**Status:** Locked 2026-05-29T11:52:19Z

---

### Task 1: RED baseline gate (Iron Law — already satisfied)

writing-skills Iron Law: no skill without a failing test first. The RED baseline
is already run + documented in the design (2 subagent scenarios + production
report). This task is the gate that proves it before any skill text is written.

**Files:**
- Read: `docs/plans/2026-05-29-demonstration-fidelity-design.md` (§ "RED baseline")

**Step 1:** Verify the baseline is recorded.
Run: `grep -c "Baseline #" docs/plans/2026-05-29-demonstration-fidelity-design.md`
Expected: `>= 2` (two baseline scenarios documented).

**Step 2:** Confirm learnings shaped the invariant (seam-substitution carve-out traces to Baseline #2).
Run: `grep -n "dependency seam\|seam-substitution\|Baseline #2" docs/plans/2026-05-29-demonstration-fidelity-design.md`
Expected: non-empty.

No commit (gate only). Proceed only if both pass.

---

### Task 2: Advisory hook `hooks/pretool-demo-fidelity-guard` (TDD)

**Change class:** Hook/trigger/event-handler + plugin-loading path. Verify by
firing the real hook via stdin (hook-contracts.sh) AND a manual stdin invocation
(runtime-launch-validation of the loading path). **Rollback:** revert commit +
remove the `hooks.json` entry (Task 3); or `SUPERPOWERS_HOOKS_DISABLE=1`.

**Files:**
- Create: `hooks/pretool-demo-fidelity-guard`
- Test: `tests/hook-contracts.sh` (add a `demo-fidelity` case block)

**Step 1 (RED): add failing contract cases to `tests/hook-contracts.sh`.** Cases:
- demo path `examples/foo-demo.py` (+ `transcript_path` set) → stdout JSON has `hookSpecificOutput.additionalContext` matching `demonstration-fidelity`; exit 0; no `decision`/`block`.
- excluded `pkg/example_test.go` → empty stdout (silent); exit 0.
- excluded `testdata/example.json` → silent.
- excluded `examples/testdata/demo.py` → silent (excluded segment `testdata` wins over trigger segment `examples`).
- kept `examples/latest-feature-demo.py` → fires (rev2-regression guard: basename has substring `test`/`spec`? no — `latest` contains `test` but exclusion is segment/suffix-anchored, not substring).
- kept `examples/Showcase.go` (capitalized) → fires (path lowercased before matching).
- non-demo `internal/server.go` → silent.
- `SUPERPOWERS_HOOKS_DISABLE=1` + demo path → silent.
- malformed/empty stdin → exit 0, no crash.
- dedup: same demo path twice with the **same** `transcript_path` → fires once (second is suppressed).
- fail-open: state file path forced unwritable (e.g. point `cwd` at a dir where `.claude/autodev-state` cannot be created) → still **fires** (fail-open = fire, never silent).

**Step 2 (RED run):** `bash tests/hook-contracts.sh 2>&1 | tail -20`
Expected: FAIL (hook script does not exist yet).

**Step 3 (GREEN): implement `hooks/pretool-demo-fidelity-guard`.** Model on
`hooks/pretool-pr-review-reminder` (same `emit_additional_context` shape). Logic:
- `set -euo pipefail`; `[ "${SUPERPOWERS_HOOKS_DISABLE:-}" = "1" ] && exit 0`.
- `[ -t 0 ] && exit 0`; require `jq`; read stdin; empty → exit 0.
- `tool_name` ∈ {`Write`,`Edit`,`MultiEdit`} else exit 0.
- path = `.tool_input.file_path`; empty → exit 0.
- **lowercase** path for matching (handles `Examples/`, `Demo*`).
- Split on `/`. Trigger iff: a segment == `demos`|`examples`, OR basename starts with `demo`|`example`|`showcase`|`quickstart`.
- Exclude iff: a segment ∈ {`test`,`tests`,`spec`,`specs`,`testdata`,`fixtures`,`vendor`,`node_modules`,`.git`}, OR basename matches `*_test.*`|`*.test.*`|`*.spec.*`. Excluded → exit 0.
- **Session key (NOT `session_id`):** `transcript_path=$(printf '%s' "$hook_input" | jq -r '.transcript_path // empty')`; `session_key=$(basename "$transcript_path" 2>/dev/null || echo "")`. PreToolUse payloads carry `transcript_path`, **not** `session_id` — verified at `hooks/pre-tool-scope-guard:39-41`, which uses exactly this idiom. Empty `transcript_path` → `session_key=""` (degrades to per-path dedup for that harness; acceptable for an advisory nudge).
- Dedup: `key=$(printf '%s' "${session_key}:${file_path}" | sha256sum | cut -d" " -f1)` (or `shasum -a 256` fallback); state file `${cwd}/.claude/autodev-state/demo-fidelity-seen` (one key per line). If `grep -qxF "$key" "$state" 2>/dev/null` → exit 0 (already nudged this session). Else append + emit.
- **Fail-open guard (critical with `set -euo pipefail`):** wrap every state I/O so a failure CANNOT fail-closed — `mkdir -p "$dir" 2>/dev/null || true`, `grep ... || true`, `printf '%s\n' "$key" >> "$state" 2>/dev/null || true`. A read/write failure must fall through to **emit** (fire), never to a silent exit. (A naive unguarded `>>` under `errexit` would fail-CLOSED — the bug this guard prevents.)
- Emit static `additionalContext` reminder (no file contents) via `emit_additional_context "PreToolUse" "$reminder"`; exit 0.
- Any unexpected error path → exit 0 silently (cannot wedge a session). Note: "fail-open = fire" applies specifically to *state I/O* failures; a malformed-payload parse failure still exits 0 silent.

Reminder string (static):
```
<IMPORTANT>
You appear to be writing a demonstration/example artifact. A demo MUST execute the
real artifact and show its actual output. Do NOT reimplement the logic, hard-code
the output, or stub the thing being demonstrated. Substituting a *dependency* at a
real interface seam is allowed only if disclosed. See autodev:demonstration-fidelity.
</IMPORTANT>
```
`chmod +x hooks/pretool-demo-fidelity-guard`.

**Step 4 (GREEN run):** `bash tests/hook-contracts.sh 2>&1 | tail -20`
Expected: PASS (all cases).

**Step 5:** Manual runtime-launch-validation (plugin-loading path):
Run: `printf '{"tool_name":"Write","tool_input":{"file_path":"examples/demo_main.go"},"cwd":"'$PWD'"}' | bash hooks/pretool-demo-fidelity-guard`
Expected: JSON with `additionalContext` containing `demonstration-fidelity`; capture for PR body.

**Step 6:** Commit. `git add hooks/pretool-demo-fidelity-guard tests/hook-contracts.sh && git commit -m "feat(hooks): advisory demo-fidelity write-time guard"`

---

### Task 3: Register hook in `hooks/hooks.json`

**Change class:** plugin-loading path. **Rollback:** revert commit (hook becomes inert).

**Files:** Modify: `hooks/hooks.json` (PreToolUse array).

**Step 1:** Add a **new, separate** element to the `PreToolUse` array (do NOT merge into the existing `Bash|Write|Edit|MultiEdit` scope-guard block — that would alter scope-guard's matcher). Exact element:
```json
{
  "matcher": "Write|Edit|MultiEdit",
  "hooks": [
    {
      "type": "command",
      "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" pretool-demo-fidelity-guard",
      "timeout": 10
    }
  ]
}
```

**Step 2 (verify):** `jq . hooks/hooks.json >/dev/null && echo VALID`
Expected: `VALID`.

**Step 3 (verify registration via contracts):** `bash tests/hook-contracts.sh 2>&1 | tail -5`
Expected: PASS (includes hooks.json well-formedness + new hook wiring).

**Step 4:** Commit. `git add hooks/hooks.json && git commit -m "feat(hooks): register pretool-demo-fidelity-guard"`

---

### Task 4: Write `skills/demonstration-fidelity/SKILL.md` (GREEN)

**Change class:** Documentation (skill). Verify: host-neutral grep + word count + cross-refs.

**Files:** Create: `skills/demonstration-fidelity/SKILL.md`.

**Step 1:** Write the skill. Frontmatter `name: demonstration-fidelity`, symptom-first description (from design). Body (host-neutral, no forbidden tokens):
- Overview + the Invariant (execute the real artifact; output produced by that run).
- Forbidden-regardless-of-language list (reimplementation, hard-coded output, artifact-stub, detached prototype).
- Allowed-with-disclosure: dependency-seam substitution (cite RLV DB-migration + Fall-back).
- Fidelity-not-language-sameness nuance (valid cross-language client demo).
- 3-question fidelity test.
- One fake-vs-faithful example pair (single language, no multi-language dilution).
- Rationalization table (seeded from RED baseline — "tooling finicky so I'll just print expected output", "looks identical on screen", "no time to stand up the DB").
- Red flags + Common mistakes.
- Cross-refs: runtime-launch-validation, verification-before-completion, scope-lock (skill-name form, no `@`).

**Step 2 (verify host-neutral):** `bash tests/skill-content-grep.sh 2>&1 | tail -5`
Expected: PASS (no Claude-only tokens).

**Step 3 (verify cross-refs resolve):** `bash tests/skill-cross-refs.sh 2>&1 | tail -5`
Expected: PASS.

**Step 4 (token budget):** `wc -w skills/demonstration-fidelity/SKILL.md`
Expected: < 800 words (lean; target ~500 core).

**Step 5:** Commit. `git add skills/demonstration-fidelity && git commit -m "feat(skills): demonstration-fidelity skill"`

---

### Task 5: Wire cross-refs into existing skills + README + coverage

**Change class:** Documentation. Verify: cross-refs resolve + grep each edit.

**Files:**
- Modify: `skills/runtime-launch-validation/SKILL.md` (add the exact Demonstration change-class row from design §2 + a "See also" line).
- Modify: `skills/verification-before-completion/SKILL.md` (claim-matrix row `demo/example works | real artifact executed via the demo produced the shown output | hand-written/hard-coded output, a reimplementation`).
- Modify: `skills/finishing-a-development-branch/SKILL.md` (Step 1b: note — if the diff ships a demo/example artifact, `demonstration-fidelity` applies).
- Modify: `skills/using-autodev/SKILL.md` (add to skill discovery / red-flags so it loads at demo time).
- Modify: `README.md` (Skills Library → Testing group: `demonstration-fidelity`).
- Modify: `tests/cross-llm-coverage.md` (host-neutral row).

**Step 1:** Apply all six edits.

**Step 2 (verify):** `bash tests/skill-cross-refs.sh && bash tests/skill-content-grep.sh 2>&1 | tail -8`
Expected: both PASS.

**Step 3 (verify RLV/VBC rows present):**
Run: `grep -n "demonstration-fidelity" skills/runtime-launch-validation/SKILL.md skills/verification-before-completion/SKILL.md skills/finishing-a-development-branch/SKILL.md README.md tests/cross-llm-coverage.md`
Expected: a hit in each file.

**Step 4:** Commit. `git commit -am "feat(wiring): cross-ref demonstration-fidelity into RLV/VBC/finishing/using-autodev/README/coverage"`

---

### Task 6: GREEN behavioral verification (writing-skills) + discoverability

**Change class:** Skill test (behavioral; best-effort, not CI-gating).

**Step 1:** Dispatch a subagent WITH the skill available, given the same fake-demo
pressure scenario as RED Baseline #2 (hard-to-run artifact), and the skill named.
Expected: agent applies fidelity — runs the real artifact (or substitutes only a
disclosed dependency seam), never hard-codes output. Capture summary.

**Step 2 (discoverability):** Dispatch a second subagent given "build a demo of X,"
skill present but NOT named, autodev loaded. Observe whether the symptom-first
description triggers a skill load / fidelity behavior.
Expected: skill loads or fidelity behavior emerges (best-effort; record outcome).

**Step 3:** Record both outcomes in the PR body. No commit (verification only).

**GATE (writing-skills Iron Law GREEN — blocks Task 7):** Step 1 MUST show fidelity
behavior — the agent runs the real artifact (or substitutes only a disclosed
dependency seam) and does NOT hard-code output or reimplement. If the agent still
fakes the demo with the skill present, the skill's GREEN test FAILED: return to
Task 4, revise the skill to close the rationalization, re-run Step 1. Do NOT
proceed to Task 7 (version bump / release) on a failing GREEN. A skill whose GREEN
test fails is an untested skill and must not ship. (Step 2 discoverability is
best-effort and non-gating; only Step 1 fidelity gates.)

---

### Task 7: Version bump + release notes

**Change class:** Version pin (plugin manifest). **Rollback:** revert commit.

**Files:**
- Modify: `.claude-plugin/plugin.json` (`"version": "6.1.5"` → `"6.2.0"`).
- Modify: `.cursor-plugin/plugin.json` (`6.1.5`→`6.2.0` — it carries a version; `tests/version-check.sh` requires all manifests agree, so this bump is mandatory, not conditional).
- Modify: `RELEASE-NOTES.md` (prepend v6.2.0 entry: new skill + advisory hook + wiring).

**Step 1:** Apply bumps. (New feature → minor bump 6.1.5→6.2.0.)

**Step 2 (verify):** `jq -r .version .claude-plugin/plugin.json` → `6.2.0`; `bash tests/version-check.sh 2>&1 | tail -5` → PASS.

**Step 3:** Commit. `git commit -am "chore: bump version to 6.2.0"`

---

### Task 8: Full suite + scope-lock verify (pre-PR gate)

> **Lock ordering:** the `.scope-lock` sidecar is written by `scope-lock-apply`
> at lock time — i.e. after `alignment-check` PASS and **before** Task-1
> execution begins (`alignment-check` invokes `scope-lock`). By the time Task 8
> runs, `docs/plans/2026-05-29-demonstration-fidelity.md.scope-lock` exists, so
> `--verify-lock` below is valid. If the lock file is missing here, scope-lock
> was skipped — stop and run `bash hooks/scope-lock-apply <plan>` before the PR.

**Step 1:** Run the full local suite:
```
bash tests/hook-contracts.sh && bash tests/skill-content-grep.sh && \
bash tests/skill-cross-refs.sh && bash tests/version-check.sh && \
bash tests/plan-scope-check.sh --plan docs/plans/2026-05-29-demonstration-fidelity.md
```
Expected: all PASS.

**Step 2:** Verify scope-lock hash still matches:
`bash tests/plan-scope-check.sh --verify-lock docs/plans/2026-05-29-demonstration-fidelity.md`
Expected: PASS (manifest unchanged since lock).

**Step 3:** Hand off to `finishing-a-development-branch` (Step 1b runtime-launch transcript already captured in Task 2 Step 5).

---

## Global Design Guidance

Inherits the design's `## Global Design Guidance` (cited canon: README §Cross-LLM,
cross-llm-portability design, writing-skills). Mapped to tasks: host-neutrality →
Task 4/5 grep gate; TDD Iron Law → Task 1 gate + Task 2/4 RED→GREEN; one-example
rule → Task 4; scope discipline → Scope Manifest + Task 8 verify.

## Rollback summary

Single-step PR revert removes skill + hook + hooks.json entry + wiring + version
bump. Hook independently neutralizable (drop `hooks.json` entry or
`SUPERPOWERS_HOOKS_DISABLE=1`) without reverting the skill. Dedup jsonl untracked
+ benign.
