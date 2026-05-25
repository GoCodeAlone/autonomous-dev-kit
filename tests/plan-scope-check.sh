#!/usr/bin/env bash
# tests/plan-scope-check.sh
# Verifies the Scope Manifest invariant defined by skills/scope-lock/SKILL.md.
#
# Modes:
#   --plan <path>            Verify the manifest is well-formed (required block
#                            present, PR Count consistent with PR Grouping table,
#                            every Task ID appears in the body of the plan).
#                            Plans without any "## Scope Manifest" section are
#                            grandfathered (pre-scope-lock plans); pass --strict
#                            to require the manifest on all plans.
#   --verify-lock <path>     Verify the manifest section's sha256 matches
#                            <path>.scope-lock (only meaningful after the plan is
#                            in Locked status).
#   --against-branch <plan>  Verify the actual git branch layout matches the
#                            PR Grouping table: every branch listed in the
#                            table exists locally or on origin.
#
# Multiple modes can be combined. With no flags, runs --plan on every plan in
# docs/plans/*.md (skipping *-design.md and *.scope-lock).
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed
#   3 — usage error or environment problem
#
# This script is intentionally conservative: when something is ambiguous, it
# reports it and exits non-zero. The Scope Manifest is the contract; ambiguity
# in the contract is a failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

# --- Helpers --------------------------------------------------------------

# Extract the Scope Manifest section from a plan file. Prints lines from the
# `## Scope Manifest` heading through (but not including) the next H2 heading
# or first `### Task` heading at start of line. Empty output if absent.
extract_manifest() {
  awk '
    /^## Scope Manifest[[:space:]]*$/ { in_section = 1; print; next }
    in_section && /^## / { in_section = 0 }
    in_section && /^### Task [0-9]+[A-Za-z]*([: ]|$)/ { in_section = 0 }
    in_section { print }
  ' "$1"
}

# Compute sha256 of stdin in a portable way (sha256sum on Linux, shasum -a 256
# on macOS). Outputs only the hex digest.
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    echo "error: need sha256sum or shasum installed" >&2
    return 3
  fi
}

# Check the manifest is well-formed. Args: plan path. Echoes problems to stdout.
# Legacy plans (no manifest section) are skipped — only plans that opt into the
# format are enforced. New plans created by writing-plans always include the
# section, so this only matters for grandfathering historical plans pre-dating
# the scope-lock skill.
check_manifest_wellformed() {
  local plan="$1"
  local manifest
  manifest="$(extract_manifest "$plan")"

  if [ -z "$manifest" ]; then
    # Legacy / pre-scope-lock plan. Skip silently unless --strict is set.
    if [ "${STRICT:-0}" = "1" ]; then
      printf '%s: missing "## Scope Manifest" section (--strict)\n' "$plan"
      return 1
    fi
    return 0
  fi

  local pr_count tasks_count status_line
  pr_count="$(printf '%s\n' "$manifest" \
              | grep -E '^\*\*PR Count:\*\*[[:space:]]*[0-9]+' \
              | head -1 \
              | sed -E 's/.*\*\*PR Count:\*\*[[:space:]]*([0-9]+).*/\1/' || true)"
  tasks_count="$(printf '%s\n' "$manifest" \
              | grep -E '^\*\*Tasks:\*\*[[:space:]]*[0-9]+' \
              | head -1 \
              | sed -E 's/.*\*\*Tasks:\*\*[[:space:]]*([0-9]+).*/\1/' || true)"
  status_line="$(printf '%s\n' "$manifest" \
              | grep -E '^\*\*Status:\*\*' \
              | head -1 || true)"

  local rc=0

  if [ -z "$pr_count" ]; then
    printf '%s: manifest missing **PR Count:** N\n' "$plan"
    rc=1
  fi
  if [ -z "$tasks_count" ]; then
    printf '%s: manifest missing **Tasks:** N\n' "$plan"
    rc=1
  fi
  if [ -z "$status_line" ]; then
    printf '%s: manifest missing **Status:** field\n' "$plan"
    rc=1
  fi

  # Out of scope MUST appear, even if it's "(none)".
  if ! printf '%s\n' "$manifest" | grep -qE '^\*\*Out of scope:\*\*'; then
    printf '%s: manifest missing **Out of scope:** section\n' "$plan"
    rc=1
  fi

  # PR Grouping table: a markdown table whose header includes "PR #" and
  # "Tasks". Count the data rows (lines starting with `|` followed by an
  # integer-only first column).
  local grouping_rows
  grouping_rows="$(printf '%s\n' "$manifest" \
              | awk '
                  /^\| *PR *# *\|/ { in_table = 1; next }
                  in_table && /^\|[- :|]+$/ { next }   # separator row (only -, :, space, |)
                  in_table && /^\| *[0-9]+ *\|/ { print; next }
                  in_table && /^[^|]/ { in_table = 0 }
                ' || true)"
  local grouping_count
  grouping_count="$(printf '%s\n' "$grouping_rows" | grep -cE '^\| *[0-9]+ *\|' || true)"

  if [ -z "$grouping_count" ] || [ "$grouping_count" -eq 0 ]; then
    printf '%s: manifest missing or empty **PR Grouping** table\n' "$plan"
    rc=1
  elif [ -n "$pr_count" ] && [ "$grouping_count" -ne "$pr_count" ]; then
    printf '%s: PR Count (%s) disagrees with PR Grouping table rows (%s)\n' \
      "$plan" "$pr_count" "$grouping_count"
    rc=1
  fi

  # Verify every Task ID referenced in the grouping table appears in the body
  # of the plan as a `### Task N:` heading.
  if [ -n "$grouping_rows" ]; then
    # Extract all `Task N` mentions from column 3 of the table (the Tasks col).
    # Robust split: take everything between the 3rd and 4th `|`, then grep
    # `Task N` substrings from it. The optional `[A-Za-z]*` suffix captures
    # split-task ids like `Task 17a` and `Task 17b` as distinct from
    # `Task 17`. Without the suffix the substring `Task 17` would alias
    # both — a real failure mode observed when authors split tasks for
    # parallel dispatch.
    local task_ids
    task_ids="$(printf '%s\n' "$grouping_rows" \
              | awk -F'|' '{print $4}' \
              | grep -oE 'Task[[:space:]]+[0-9]+[A-Za-z]*' \
              | sed -E 's/[[:space:]]+/ /g' \
              | sort -u || true)"
    while read -r task_ref; do
      [ -z "$task_ref" ] && continue
      local n
      n="$(printf '%s\n' "$task_ref" | sed -E 's/Task +//')"
      if ! grep -qE "^### Task ${n}([: ]|\$)" "$plan"; then
        printf '%s: PR Grouping references "%s" but plan body has no "### Task %s:" heading\n' \
          "$plan" "$task_ref" "$n"
        rc=1
      fi
    done < <(printf '%s\n' "$task_ids")

    # Also: verify every `### Task N:` heading in the body appears in the
    # grouping table (no orphan tasks that ship without a PR home).
    # Same alpha-suffix capture as task_ids extraction so `### Task 17a:` is
    # treated as a distinct task from `### Task 17:`.
    local body_tasks
    body_tasks="$(grep -oE '^### Task [0-9]+[A-Za-z]*' "$plan" \
                 | sed -E 's/^### //' \
                 | sort -u || true)"
    while read -r task_ref; do
      [ -z "$task_ref" ] && continue
      if ! printf '%s\n' "$task_ids" | grep -qx "$task_ref"; then
        printf '%s: plan body has "%s" but the PR Grouping table does not include it\n' \
          "$plan" "$task_ref"
        rc=1
      fi
    done < <(printf '%s\n' "$body_tasks")

    # Tasks count consistency
    local body_task_count
    body_task_count="$(printf '%s\n' "$body_tasks" | grep -cE '^Task [0-9]+' || true)"
    if [ -n "$tasks_count" ] && [ "$body_task_count" -ne "$tasks_count" ]; then
      printf '%s: **Tasks:** %s disagrees with body task count (%s "### Task N:" headings)\n' \
        "$plan" "$tasks_count" "$body_task_count"
      rc=1
    fi
  fi

  return "$rc"
}

# Verify the manifest's sha256 matches <plan>.scope-lock. Args: plan path.
check_lock_hash() {
  local plan="$1"
  local lock="${plan}.scope-lock"
  if [ ! -f "$lock" ]; then
    printf '%s: lock file %s not found (manifest is not locked)\n' "$plan" "$lock"
    return 1
  fi
  local expected actual
  expected="$(awk 'NF && !/^#/ {print; exit}' "$lock")"
  actual="$(extract_manifest "$plan" | sha256_stdin)"
  if [ "$expected" != "$actual" ]; then
    printf '%s: manifest hash mismatch (lock=%s, current=%s)\n' \
      "$plan" "${expected:0:12}…" "${actual:0:12}…"
    return 1
  fi
  return 0
}

# Compare actual git branch layout vs. the PR Grouping table. Args: plan path.
# The plan-relative base branch is read from the line `**Base branch:** main`
# in the plan header (defaults to `main` if absent).
check_against_branch() {
  local plan="$1"
  local base
  base="$(grep -E '^\*\*Base branch:\*\*' "$plan" | head -1 \
            | sed -E 's/.*\*\*Base branch:\*\*[[:space:]]*([A-Za-z0-9._/-]+).*/\1/' || true)"
  [ -z "$base" ] && base="main"

  local rc=0

  # Grouping branch column = 5th `|`-delimited field.
  local manifest
  manifest="$(extract_manifest "$plan")"
  local branches
  branches="$(printf '%s\n' "$manifest" \
            | awk -F'|' '
                /^\| *PR *# *\|/ { in_table = 1; next }
                in_table && /^\|[- :|]+$/ { next }
                in_table && /^\| *[0-9]+ *\|/ {
                  gsub(/^ +| +$/, "", $5)
                  if ($5 != "") print $5
                  next
                }
                in_table && /^[^|]/ { in_table = 0 }
              ' \
            | sort -u || true)"

  if [ -z "$branches" ]; then
    printf '%s: PR Grouping table has no Branch column entries\n' "$plan"
    return 1
  fi

  while read -r br; do
    [ -z "$br" ] && continue
    if ! git rev-parse --verify "refs/heads/${br}" >/dev/null 2>&1 \
      && ! git rev-parse --verify "refs/remotes/origin/${br}" >/dev/null 2>&1; then
      printf '%s: planned branch %s does not exist locally or on origin\n' "$plan" "$br"
      rc=1
    fi
  done < <(printf '%s\n' "$branches")

  return "$rc"
}

# --- Argument parsing -----------------------------------------------------

MODE_PLAN=()
MODE_VERIFY_LOCK=()
MODE_AGAINST_BRANCH=()
STRICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)
      [ -n "${2:-}" ] || { usage; exit 3; }
      MODE_PLAN+=("$2"); shift 2 ;;
    --verify-lock)
      [ -n "${2:-}" ] || { usage; exit 3; }
      MODE_VERIFY_LOCK+=("$2"); shift 2 ;;
    --against-branch)
      [ -n "${2:-}" ] || { usage; exit 3; }
      MODE_AGAINST_BRANCH+=("$2"); shift 2 ;;
    --strict)
      STRICT=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      printf 'unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 3 ;;
  esac
done
export STRICT

# If no explicit --plan/--verify-lock/--against-branch was given, default
# to scanning all plans in docs/plans/ for well-formedness.
if [ "${#MODE_PLAN[@]}" -eq 0 ] \
   && [ "${#MODE_VERIFY_LOCK[@]}" -eq 0 ] \
   && [ "${#MODE_AGAINST_BRANCH[@]}" -eq 0 ]; then
  while IFS= read -r f; do
    MODE_PLAN+=("$f")
  done < <(find docs/plans -maxdepth 1 -name '*.md' \
              ! -name '*-design.md' ! -name 'README.md' 2>/dev/null | sort)
  if [ "${#MODE_PLAN[@]}" -eq 0 ]; then
    echo "No plans found in docs/plans/. Nothing to check."
    exit 0
  fi
fi

# --- Run ------------------------------------------------------------------

failures=0

for plan in "${MODE_PLAN[@]:-}"; do
  [ -z "$plan" ] && continue
  if [ ! -f "$plan" ]; then
    printf '%s: file not found\n' "$plan" >&2
    failures=$((failures + 1))
    continue
  fi
  if ! check_manifest_wellformed "$plan"; then
    failures=$((failures + 1))
  fi
done

for plan in "${MODE_VERIFY_LOCK[@]:-}"; do
  [ -z "$plan" ] && continue
  if ! check_lock_hash "$plan"; then
    failures=$((failures + 1))
  fi
done

for plan in "${MODE_AGAINST_BRANCH[@]:-}"; do
  [ -z "$plan" ] && continue
  if ! check_against_branch "$plan"; then
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  printf '\nFAIL: %s scope-manifest check(s) failed.\n' "$failures" >&2
  exit 1
fi

echo "PASS: scope-manifest checks succeeded."
exit 0
