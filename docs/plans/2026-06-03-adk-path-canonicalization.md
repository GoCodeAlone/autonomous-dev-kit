# ADK Path Canonicalization Implementation Plan

> **For the implementing agent:** REQUIRED SUB-SKILL: Use autodev:executing-plans to implement this plan task-by-task.

**Goal:** Make all ADK state writes resolve to one canonical per-repo location (worktree-safe), have subagents report where they wrote, and forbid operator-home paths in committed artifacts — fixing the #70 worktree-fragmentation residual.

**Architecture:** One shared bash resolver (`hooks/lib-autodev-paths.sh`, git-common-dir-anchored with cwd fallback + lib-missing degradation) sourced by the 12 state-writing hooks; a subagent `Writes:` ledger convention; a placeholder-aware path-hygiene CI gate in its own always-run workflow. TDD via a real temp `git worktree` fixture proving the resolver. v6.5.0 version bump.

**Tech Stack:** Bash (hooks + tests), Markdown (skills/agents), GitHub Actions, `scripts/bump-version.sh` + `tests/version-check.sh`.

**Base branch:** main

---

## Scope Manifest

**PR Count:** 1
**Tasks:** 10
**Estimated Lines of Change:** ~420 (1 lib + 12 hook retrofits + 2 tests + 1 workflow + 6 skill/agent edits + version bump)

**Out of scope:**
- Heuristic/ML path detection — the gate is a narrow home-rooted-path grep (placeholder-aware), nothing more.
- A CI validator that subagents actually emit the `Writes:` ledger (C2 is a soft convention by design; m-4).
- Gitignoring `.autodev/state/phase-progress.jsonl` (intentionally tracked; kept repo-relative).
- Bootstrapping `docs/design-guidance.md` (recurring follow-up; not this PR).
- Retrofitting `scope-lock-apply` / `scope-lock-publish` / `posttool-pr-created` (verified: no state-dir reference).
- Migrating the 2026-05-31 / 2026-06-03 pre-existing review reports.

**PR Grouping:**

| PR # | Title | Tasks | Branch |
|------|-------|-------|--------|
| 1 | ADK path canonicalization + write-location transparency + artifact hygiene (v6.5.0) | Task 1, Task 2, Task 3, Task 4, Task 5, Task 6, Task 7, Task 8, Task 9, Task 10 | feat/adk-path-canonicalization |

**Status:** Draft

---

### Task 1: Failing tests — resolver behavior + hook-wiring + degradation

**Change class:** Hook/test. Verification: the test (RED now; GREEN after Tasks 2–3).

**Files:**
- Create: `tests/adk-path-canonicalization.sh`

**Step 1: Write the failing test.** Mirror `tests/hook-contracts.sh` style (`pass()/fail()`, `failures` counter, non-zero exit). Three groups:

```bash
#!/usr/bin/env bash
# tests/adk-path-canonicalization.sh — proves the canonical ADK state-path resolver
# and that all 12 state-writing hooks adopt it. (#70 residual; v6.5.0)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
LIB="$ROOT/hooks/lib-autodev-paths.sh"
failures=0
pass(){ printf 'PASS: %s\n' "$1"; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; failures=$((failures+1)); }

# --- Group A: resolver behavior against a REAL temp git + linked worktree ---
if [ -f "$LIB" ]; then
  . "$LIB"
  tmp="$(mktemp -d)"
  ( cd "$tmp" && git init -q main && cd main && git -c user.email=a@b -c user.name=x commit -q --allow-empty -m init \
      && git worktree add -q ../wt >/dev/null 2>&1 )
  main_root="$(cd "$tmp/main" && pwd)"
  # (a) from main checkout -> main root
  [ "$(autodev_repo_root "$tmp/main")" = "$main_root" ] \
    && pass "resolver: main checkout -> main root" || fail "resolver main: got $(autodev_repo_root "$tmp/main")"
  # (b) from linked worktree -> SAME main root (the load-bearing claim)
  [ "$(autodev_repo_root "$tmp/wt")" = "$main_root" ] \
    && pass "resolver: linked worktree -> main root (shared)" || fail "resolver worktree: got $(autodev_repo_root "$tmp/wt")"
  # (c) non-git dir -> cwd fallback (C-1: NOT '/')
  ngt="$(mktemp -d)"; [ "$(autodev_repo_root "$ngt")" = "$ngt" ] \
    && pass "resolver: non-git dir -> cwd fallback" || fail "resolver non-git: got $(autodev_repo_root "$ngt") (want $ngt)"
  # (d) env override wins
  [ "$(AUTODEV_STATE_ROOT=/tmp/override autodev_repo_root "$tmp/main")" = "/tmp/override" ] \
    && pass "resolver: AUTODEV_STATE_ROOT override" || fail "resolver override broken"
  rm -rf "$tmp" "$ngt"
else
  fail "lib missing: $LIB"
fi

# --- Group B: all 12 state-writing hooks source the lib + guard the function ---
HOOKS="completion-claim-guard pre-compact-snapshot pre-tool-scope-guard pretool-demo-fidelity-guard pretool-pr-review-reminder prompt-strict-interpretation record-activity scope-lock-abandon scope-lock-claim scope-lock-complete session-start subagent-scope-guard"
for h in $HOOKS; do
  f="$ROOT/hooks/$h"
  if grep -q "lib-autodev-paths.sh" "$f" && grep -q "declare -f autodev_repo_root" "$f"; then
    pass "hook wired: $h"
  else
    fail "hook NOT wired (no lib source + declare -f guard): $h"
  fi
done

# --- Group C: lib-missing degradation — a hook with the lib hidden still emits valid output ---
# record-activity is the simplest writer: feed it a Skill payload with a bogus cwd, lib hidden,
# and assert it does NOT crash (exit !=2/127) and writes under the cwd fallback.
tmpd="$(mktemp -d)"; mkdir -p "$tmpd/.git"  # make it look git-less enough to fallback
payload='{"tool_name":"Skill","tool_input":{"skill":"autodev:x"},"cwd":"'"$tmpd"'"}'
LIBBAK=""; if [ -f "$LIB" ]; then LIBBAK="$(mktemp)"; cp "$LIB" "$LIBBAK"; fi
# Don't actually delete the real lib; instead run the hook with a PATH/source that can't find it:
# simulate by copying record-activity to a temp dir WITHOUT the sibling lib.
sandbox="$(mktemp -d)"; cp "$ROOT/hooks/record-activity" "$sandbox/record-activity"
out_rc=0; printf '%s' "$payload" | bash "$sandbox/record-activity" >/dev/null 2>&1 || out_rc=$?
# 127/2 would indicate the missing-function crash; 0 or 1 (benign) is acceptable degradation.
if [ "$out_rc" != "127" ] && [ "$out_rc" != "2" ]; then
  pass "degradation: record-activity survives missing lib (rc=$out_rc)"
else
  fail "degradation: record-activity crashed without lib (rc=$out_rc)"
fi
rm -rf "$tmpd" "$sandbox"; [ -n "$LIBBAK" ] && rm -f "$LIBBAK"

echo ""; echo "Results: $failures failure(s)"; [ "$failures" -eq 0 ]
```

**Step 2: Run, verify RED.** `bash tests/adk-path-canonicalization.sh` → FAILs (lib missing, hooks unwired), exit 1.

**Step 3: Commit (red).** `chmod +x` + `git add` + commit `test: ADK path canonicalization resolver+wiring guard [red]`.

---

### Task 2: Canonical resolver lib

**Change class:** Hook/library. Verification: Task-1 Group A (resolver) passes.

**Files:**
- Create: `hooks/lib-autodev-paths.sh`

**Step 1:** Write the resolver exactly as the design's C1 block (with the C-1 null-guard). Use `local` for `cwd`/`_gcd`/`_root` (all consumers are bash) to avoid scope leakage, with a header comment that the function must stay `set -u`-safe (assign before read):

```sh
#!/usr/bin/env bash
# lib-autodev-paths.sh — canonical ADK state-root resolver, sourced by state-writing hooks.
# autodev_repo_root <cwd> -> canonical repo root (shared across worktrees, survives worktree removal).
# set -u safe: every var is assigned before any read. Sourced; uses `local` (all callers are bash).
autodev_repo_root() {
  local cwd="${1:-$PWD}" _gcd="" _root=""
  if [ -n "${AUTODEV_STATE_ROOT:-}" ]; then printf '%s\n' "$AUTODEV_STATE_ROOT"; return 0; fi
  _gcd="$(cd "$cwd" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null || true)"
  [ -n "$_gcd" ] && _root="$(cd "$cwd" 2>/dev/null && cd "$_gcd/.." 2>/dev/null && pwd || true)"
  if [ -n "$_root" ]; then printf '%s\n' "$_root"; else printf '%s\n' "$cwd"; fi
}
```

**Step 2: Run** `bash tests/adk-path-canonicalization.sh` → Group A PASS (main, worktree, non-git, override).

**Step 3: Commit.** `git add hooks/lib-autodev-paths.sh tests/adk-path-canonicalization.sh && git commit -m "feat(hooks): canonical ADK state-root resolver (git-common-dir anchored)"`

---

### Task 3: Retrofit the 12 state-writing hooks

**Change class:** Hook. Verification: Task-1 Group B (all 12 wired) + Group C (degradation) pass; `tests/hook-contracts.sh` still green (no behavior regression).

**Files (Modify, all in `hooks/`):** `completion-claim-guard`, `pre-compact-snapshot`, `pre-tool-scope-guard`, `pretool-demo-fidelity-guard`, `pretool-pr-review-reminder`, `prompt-strict-interpretation`, `record-activity`, `scope-lock-abandon`, `scope-lock-claim`, `scope-lock-complete`, `session-start`, `subagent-scope-guard`.

**Step 0 (guard against list drift):** run `grep -rlE 'autodev-state|\.autodev/state' hooks/ | sort` — confirm it returns exactly these 12. If it differs, STOP and reconcile before editing.

**Step 1:** In each hook, immediately after its `cwd_dir` is determined (the line `[ -z "$cwd_dir" ] && cwd_dir="${PWD}"` or equivalent), insert:
```sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/lib-autodev-paths.sh" 2>/dev/null || true
declare -f autodev_repo_root >/dev/null 2>&1 || autodev_repo_root() { printf '%s\n' "${1:-$PWD}"; }
ADK_ROOT="$(autodev_repo_root "$cwd_dir")"
```
Then replace every `${cwd_dir}/.claude/autodev-state` → `${ADK_ROOT}/.claude/autodev-state` and every `${cwd_dir}/.autodev/state` → `${ADK_ROOT}/.autodev/state` **in that hook**. Leave non-state uses of `cwd_dir` (e.g. `${cwd_dir}/docs/plans`, repo-content reads) UNCHANGED — those legitimately want the working dir, not the canonical root.

**Special cases (per design m-3 / cycle-2 minors):**
- `scope-lock-complete`, `scope-lock-abandon`: they compute `repo_root` from the plan path and take `$PWD`. Replace that `repo_root=$(cd "${plan_dir}/../.." && pwd)` derivation with `ADK_ROOT="$(autodev_repo_root "$PWD")"` (source the lib first). This intentionally switches worktree→main root for state pruning.
- `scope-lock-claim`: it only **reads** `session-locks.jsonl` for verification (write is delegated to `pre-tool-scope-guard`). Anchor the read path to `ADK_ROOT` too (so it reads the same canonical file), but do not add an unused `STATE_DIR` (cycle-2 minor).

**Step 2: Verify.** `bash tests/adk-path-canonicalization.sh` → Group B + C PASS. `bash tests/hook-contracts.sh` → exit 0 (no contract regression). `bash tests/hook-stdout-discipline.sh` → exit 0.

**Step 3: Commit.** `git add hooks/ && git commit -m "refactor(hooks): all 12 state writers resolve canonical root via shared lib (#70 residual)"`

**Rollback:** revert this commit → hooks fall back to per-hook cwd-scoping (prior behavior); no state migration needed.

---

### Task 4: Retro reads the canonical activation log

**Change class:** Documentation/skill-content. Verification: content assertion + `skill-content-grep.sh`.

**Files:** Modify `skills/post-merge-retrospective/SKILL.md` (Step 5 + Reads bullet).

**Step 1:** Add a sentence to Step 5 + the `**Reads:**` bullet: the activation log lives at the **canonical repo root** (`git rev-parse --git-common-dir`'s parent — shared across worktrees, survives worktree cleanup), not the cwd; a worktree-executed pipeline writes there. If reading from a worktree checkout, resolve the same root. This closes the v6.4.0 retro's #70 residual (the retro that *surfaced* this).

**Step 2: Verify.** `bash tests/skill-content-grep.sh` → exit 0. `grep -q "git-common-dir\|canonical repo root" skills/post-merge-retrospective/SKILL.md`.

**Step 3: Commit.** `git commit -m "docs(retro): read activation log from canonical repo root (#70 residual)"`

---

### Task 5: Subagent write-location ledger (C2)

**Change class:** Documentation/skill-content. Verification: content assertion + `skill-content-grep.sh`.

**Files:** Modify `agents/team-conventions.md`, `skills/subagent-driven-development/implementer-prompt.md`, `spec-reviewer-prompt.md`, `code-quality-reviewer-prompt.md`, and `skills/subagent-driven-development/SKILL.md`.

**Step 1:** Add a `Writes:` ledger convention: every subagent ends its final message with a `Writes:` section — one line per file created/modified as a **repo-relative path**, plus `OUT-OF-TREE: <absolute path>` for any write outside the expected repo/worktree, so the orchestrator can verify and relocate. Add the matching instruction line to each of the 3 prompt templates and a short subsection in team-conventions.md + a pointer in the SKILL.

**Step 2: Verify.** `bash tests/skill-content-grep.sh` → exit 0. `grep -lq "Writes:" agents/team-conventions.md skills/subagent-driven-development/implementer-prompt.md`.

**Step 3: Commit.** `git commit -m "docs(subagents): require a repo-relative Writes: ledger from every subagent (C2)"`

---

### Task 6: Path-hygiene gate + fix existing leak (C3)

**Change class:** Test/Documentation. Verification: the gate is RED on a seeded leak, GREEN on placeholders + the real tree (after the testing.md fix).

**Files:**
- Create: `tests/no-machine-paths.sh`
- Modify: `docs/testing.md` (fix the existing operator-home leak → placeholder)

**Step 1: Write the gate** (placeholder-aware, per design C3):
```bash
#!/usr/bin/env bash
# tests/no-machine-paths.sh — forbid operator-home absolute paths in committed artifacts.
# Catches a real leak (/Users/<realuser>/x) but IGNORES <placeholder> segments and ellipsis,
# so artifacts that DOCUMENT the pattern (this feature's own docs) pass. Lines containing the
# sentinel `path-hygiene-allow` are skipped. Scans docs/ and decisions/.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
pattern='(/Users/|/home/)[A-Za-z0-9][A-Za-z0-9._-]*'
hits=0
while IFS= read -r f; do
  while IFS=: read -r line content; do
    case "$content" in (*path-hygiene-allow*) continue ;; esac
    printf 'LEAK: %s:%s: %s\n' "${f#$ROOT/}" "$line" "$content" >&2
    hits=$((hits+1))
  done < <(grep -nE "$pattern" "$f" 2>/dev/null || true)
done < <(find "$ROOT/docs" "$ROOT/decisions" -type f \( -name '*.md' -o -name '*.txt' \) 2>/dev/null)
if [ "$hits" -eq 0 ]; then echo "PASS: no operator-home machine paths in committed artifacts."; else
  echo "FAIL: $hits machine-path leak(s) in committed artifacts." >&2; fi
[ "$hits" -eq 0 ]
```

**Step 2: Prove RED on a seeded leak + GREEN on placeholder (revert-restore).** Build the probe
path with `printf` so this plan file itself stays gate-clean (the literal never appears here):
```bash
printf '/Users/%s/secret\n' realuser > docs/_leak_probe.md   # real-looking at runtime
bash tests/no-machine-paths.sh; test $? -ne 0 && echo "OK: catches real leak"
printf '/Users/<name>/x\n' > docs/_leak_probe.md             # angle-bracket placeholder
bash tests/no-machine-paths.sh; echo "placeholder rc=$?"     # probe line itself is ignored
rm -f docs/_leak_probe.md
```
Expected: real-path probe → FAIL (exit 1); placeholder probe → ignored (not a leak).

**Step 3: Fix the existing leak.** Edit `docs/testing.md` (the `/Users/<name>/...` example line) → replace the operator-home segment with `/Users/<name>/...` placeholder (angle-bracket) or `<repo-root>/...`.

**Step 4: Verify GREEN on the real tree.** `bash tests/no-machine-paths.sh` → `PASS` (exit 0). (The design + plan + review docs already use placeholders.)

**Step 5: Commit.** `git add tests/no-machine-paths.sh docs/testing.md && git commit -m "test(hygiene): forbid operator-home paths in artifacts; fix docs/testing.md leak (C3)"`

---

### Task 7: Dedicated path-hygiene CI workflow (C3 / I-2)

**Change class:** Hook/trigger (CI). Verification: YAML valid; runs the gate with no `paths:` filter.

**Files:** Create `.github/workflows/path-hygiene.yml`.

**Step 1:**
```yaml
name: Path Hygiene
on:
  push:
  pull_request:
permissions:
  contents: read
jobs:
  path-hygiene:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: No operator-home paths in committed artifacts
        run: bash tests/no-machine-paths.sh
```
(No `paths:` filter — always runs, so a docs-only leak PR can't bypass it; I-2.)

**Step 2: Verify.** `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/path-hygiene.yml'))"` → no error. `bash tests/no-machine-paths.sh` → exit 0.

**Step 3: Commit.** `git commit -m "ci: dedicated always-on path-hygiene workflow (C3)"`

---

### Task 8: Artifact path-hygiene skill rule (C3)

**Change class:** Documentation/skill-content. Verification: content assertion + `skill-content-grep.sh`.

**Files:** Modify `skills/brainstorming/SKILL.md`, `skills/writing-plans/SKILL.md`, `skills/post-merge-retrospective/SKILL.md`, `skills/adversarial-design-review/SKILL.md`, `skills/recording-decisions/SKILL.md`.

**Step 1:** Add ONE concise rule line to each (in the artifact-writing/documentation section): "Committed artifacts use repo-relative paths; illustrate machine paths only with `<placeholder>` segments (e.g. `/Users/<name>/…`); never a literal operator-home path. Enforced by `tests/no-machine-paths.sh`." Keep it to one line per skill (anti-bloat).

**Step 2: Verify.** `bash tests/skill-content-grep.sh` → exit 0. `bash tests/skill-cross-refs.sh` → exit 0. Confirm each of the 5 skills contains "repo-relative".

**Step 3: Commit.** `git commit -m "docs(skills): repo-relative-paths rule for committed artifacts (C3)"`

---

### Task 9: Full verification + wire resolver test into CI

**Change class:** Hook/trigger (CI) + verification.

**Files:** Modify `.github/workflows/skill-content-check.yml` (add `tests/adk-path-canonicalization.sh` step + `hooks/**` path so hook changes trigger it).

**Step 1:** Add `hooks/**` and `tests/adk-path-canonicalization.sh` to the workflow `paths` (push + PR), and a step `run: bash tests/adk-path-canonicalization.sh`.

**Step 2: Run the FULL local gate — all exit 0:**
```bash
bash tests/adk-path-canonicalization.sh   # Results: 0 failure(s)
bash tests/no-machine-paths.sh            # PASS
bash tests/hook-contracts.sh              # exit 0 (no hook regression)
bash tests/hook-stdout-discipline.sh      # exit 0
bash tests/skill-content-grep.sh          # exit 0
bash tests/skill-cross-refs.sh            # exit 0
```
Expected: every command exits 0. If any hook emits a host-token leak, fix it (`<host:>` block).

**Step 3: Commit.** `git commit -m "ci: run ADK path canonicalization test on hook changes"`

---

### Task 10: Version bump → v6.5.0

**Change class:** Version pin (release). Verification: `tests/version-check.sh`. **Rollback: revert merge + re-tag v6.4.0; resolver computed at runtime, no migration.**

**Files (via script):** `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.cursor-plugin/plugin.json`.

**Step 1:** `bash scripts/bump-version.sh 6.5.0`
**Step 2:** `bash tests/version-check.sh` → exit 0 (all three = 6.5.0).
**Step 3:** `git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .cursor-plugin/plugin.json && git commit -m "chore(release): bump to v6.5.0"`

---

## Verification Summary (whole-PR)
All green before PR: `adk-path-canonicalization.sh`, `no-machine-paths.sh`, `hook-contracts.sh`, `hook-stdout-discipline.sh`, `skill-content-grep.sh`, `skill-cross-refs.sh`, `version-check.sh`, `plan-scope-check --verify-lock`. Step 1e dogfood: this PR commits design/plan/review/skill docs → emit `Doc-reconciliation:` line in the PR body (and confirm no real machine paths — `no-machine-paths.sh` is the mechanical proof).

## Rollback (whole-PR)
Revert the squash-merge commit + re-tag v6.4.0. The canonical root is computed at runtime; reverting restores cwd-scoping. No data/state migration; any state already at a canonical path is harmless. Per-task rollback notes on Task 3 (hooks) + Task 10 (version).
