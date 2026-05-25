#!/usr/bin/env bash
# tests/skill-activation-audit.sh
# Reads .claude/autodev-state/in-progress.jsonl and reports which
# autodev skills / agents fired during the recorded session(s),
# plus a heuristic check for "expected but not invoked" pipeline gates.
#
# This is strictly local — it never transmits anything off the machine.
# Use it post-hoc to confirm whether the autonomous pipeline ran as
# expected, or to identify where it stopped.
#
# Usage:
#   ./tests/skill-activation-audit.sh                  # default state file
#   ./tests/skill-activation-audit.sh /path/to/jsonl   # explicit path
#   ./tests/skill-activation-audit.sh --quiet          # only flag gaps
#
# Exit codes:
#   0 — audit completed; no expected-but-missing pipeline gates detected
#   2 — one or more expected pipeline gates did not fire
#   3 — state file unreadable or malformed
#   4 — usage error

set -euo pipefail

QUIET=0
STATE_FILE=""

for arg in "$@"; do
  case "$arg" in
    --quiet|-q) QUIET=1 ;;
    --help|-h)
      # Print the leading comment block (everything from line 2 up to the
      # first non-comment line). Marker-based so the help text stays in
      # sync if the header is edited.
      awk '
        NR==1 { next }                  # shebang
        /^#/  { sub(/^# ?/, ""); print; next }
        { exit }
      ' "$0"
      exit 0
      ;;
    -*)
      printf 'unknown option: %s\n' "$arg" >&2
      exit 4
      ;;
    *)
      if [ -n "$STATE_FILE" ]; then
        printf 'unexpected positional argument: %s\n' "$arg" >&2
        exit 4
      fi
      STATE_FILE="$arg"
      ;;
  esac
done

# Default: look up from CWD into .claude/autodev-state/in-progress.jsonl
if [ -z "$STATE_FILE" ]; then
  STATE_FILE="${PWD}/.claude/autodev-state/in-progress.jsonl"
fi

if [ ! -r "$STATE_FILE" ]; then
  printf 'No state file at %s\n' "$STATE_FILE" >&2
  printf '\nThis is normal if:\n' >&2
  printf '  - the PostToolUse activity hook is not installed in this checkout\n' >&2
  printf '  - the session has not invoked any Skill / Agent / Task* tool yet\n' >&2
  printf '  - this host does not write the state file (Codex / OpenCode / Cursor)\n' >&2
  exit 3
fi

# Pipeline gates we expect for an autonomous run, in order. The pipeline
# is the canonical chain documented in skills/using-autodev/SKILL.md:
#   brainstorming → adversarial-design-review (design) → writing-plans →
#   adversarial-design-review (plan) → alignment-check → scope-lock →
#   subagent-driven-development → finishing-a-development-branch →
#   pr-monitoring → post-merge-retrospective
# Note: adversarial-design-review appears twice (design and plan phases);
# this list de-dupes it — the audit reports the count seen so gaps can be
# identified but cannot distinguish the two phases without --phase= args.
PIPELINE_GATES=(
  brainstorming
  adversarial-design-review
  writing-plans
  alignment-check
  scope-lock
  subagent-driven-development
  finishing-a-development-branch
  pr-monitoring
  post-merge-retrospective
)

# Optional gates — present only when conditions trigger them. Reported
# but their absence is NOT a failure.
OPTIONAL_GATES=(
  recording-decisions
  post-merge-retrospective
  using-git-worktrees
  test-driven-development
  systematic-debugging
  receiving-code-review
  requesting-code-review
  runtime-launch-validation
)

# --- Parse JSONL ----------------------------------------------------------

# New rows are compressed: {"ts":"...","ev":"skill","sk":"foo"} or
# {"ts":"...","ev":"agent","ag":"general-purpose"}. Legacy rows used
# {"tool":"...","detail":"skill=foo ..."}; keep reading both during migration.
# We tolerate jq missing — fall back to grep if jq isn't installed.

extract_skills() {
  if command -v jq >/dev/null 2>&1; then
    jq -r 'if (.ev // "") == "skill" then (.sk // "") elif (.tool // "") == "Skill" then (.detail // "") else empty end' "$STATE_FILE" 2>/dev/null \
      | awk 'NF {print}' \
      | sed -nE '/^skill=/ s/.*skill=([A-Za-z0-9_:-]+).*/\1/p; /^[A-Za-z0-9_:-]+$/ p' \
      | sed -E 's/^autodev://'
  else
    grep -E '"ev":"skill"|"tool":"Skill"' "$STATE_FILE" 2>/dev/null \
      | sed -nE 's/.*"sk":"([^"]+)".*/\1/p; s/.*skill=([A-Za-z0-9_:-]+).*/\1/p' \
      | sed -E 's/^autodev://'
  fi
}

extract_agents() {
  if command -v jq >/dev/null 2>&1; then
    jq -r 'if (.ev // "") == "agent" then (.ag // "") elif (.ev // "") == "task" then (.ag // "") elif (.tool=="Agent" or ((.tool // "") | startswith("Task"))) then (.detail // "") else empty end' "$STATE_FILE" 2>/dev/null \
      | awk 'NF {print}' \
      | sed -nE '/^agent=/ s/.*agent=([A-Za-z0-9_-]+).*/\1/p; /^[A-Za-z0-9_-]+$/ p'
  else
    grep -E '"ev":"(agent|task)"|"tool":"(Agent|Task[^"]*)"' "$STATE_FILE" 2>/dev/null \
      | sed -nE 's/.*"ag":"([^"]+)".*/\1/p; s/.*agent=([A-Za-z0-9_-]+).*/\1/p'
  fi
}

skills_seen=$(extract_skills | sort | uniq -c | sort -rn || true)
agents_seen=$(extract_agents | sort | uniq -c | sort -rn || true)
all_seen_skills=$(extract_skills | sort -u || true)

if [ "$QUIET" -eq 0 ]; then
  printf '=== Skill activation audit ===\n'
  printf 'State file: %s\n' "$STATE_FILE"
  printf 'Total entries: %s\n' "$(wc -l < "$STATE_FILE" 2>/dev/null | tr -d ' ' || echo 0)"
  printf '\n--- Skill invocations (count, name) ---\n'
  if [ -n "$skills_seen" ]; then
    printf '%s\n' "$skills_seen"
  else
    printf '(none)\n'
  fi
  printf '\n--- Agent / Task dispatches (count, agent_type) ---\n'
  if [ -n "$agents_seen" ]; then
    printf '%s\n' "$agents_seen"
  else
    printf '(none)\n'
  fi
fi

# --- Pipeline gap check ---------------------------------------------------

# A gate is "expected" only if at least one preceding pipeline gate fired.
# Otherwise this run wasn't an autonomous pipeline run and we don't expect
# any of these gates to have fired.

any_pipeline_seen=0
for gate in "${PIPELINE_GATES[@]}"; do
  if printf '%s\n' "$all_seen_skills" | grep -qx "$gate"; then
    any_pipeline_seen=1
    break
  fi
done

missing_gates=()
if [ "$any_pipeline_seen" -eq 1 ]; then
  # We saw at least one pipeline gate; check what's missing AFTER the
  # earliest gate we saw. Reports gates that are "downstream of where
  # we got to" — the user can compare against where they expected to stop.
  earliest_idx=-1
  for i in "${!PIPELINE_GATES[@]}"; do
    gate="${PIPELINE_GATES[$i]}"
    if printf '%s\n' "$all_seen_skills" | grep -qx "$gate"; then
      earliest_idx="$i"
      break
    fi
  done

  for i in "${!PIPELINE_GATES[@]}"; do
    [ "$i" -lt "$earliest_idx" ] && continue
    gate="${PIPELINE_GATES[$i]}"
    if ! printf '%s\n' "$all_seen_skills" | grep -qx "$gate"; then
      missing_gates+=("$gate")
    fi
  done
fi

if [ "$QUIET" -eq 0 ]; then
  printf '\n--- Expected pipeline gates ---\n'
  if [ "$any_pipeline_seen" -eq 0 ]; then
    printf '(no autonomous-pipeline skills observed; nothing to check)\n'
  else
    for gate in "${PIPELINE_GATES[@]}"; do
      if printf '%s\n' "$all_seen_skills" | grep -qx "$gate"; then
        printf '  [x] %s\n' "$gate"
      else
        printf '  [ ] %s\n' "$gate"
      fi
    done
  fi

  printf '\n--- Optional gates (not failures if absent) ---\n'
  for gate in "${OPTIONAL_GATES[@]}"; do
    if printf '%s\n' "$all_seen_skills" | grep -qx "$gate"; then
      printf '  [x] %s\n' "$gate"
    else
      printf '  [ ] %s\n' "$gate"
    fi
  done
fi

if [ "${#missing_gates[@]}" -gt 0 ]; then
  printf '\nMISSING pipeline gates after first observed gate:\n' >&2
  for gate in "${missing_gates[@]}"; do
    printf '  - %s\n' "$gate" >&2
  done
  printf '\nIf the run intentionally stopped earlier (e.g., --design-only,\n' >&2
  printf 'manual interruption, or escalation to user), this is expected.\n' >&2
  printf 'Otherwise the pipeline did not complete; investigate.\n' >&2
  exit 2
fi

exit 0
