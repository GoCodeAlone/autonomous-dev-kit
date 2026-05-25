#!/usr/bin/env bash
# tests/skill-cross-refs.sh
# Verifies that cross-skill references in skills/ and agents/ markdown
# resolve to existing targets. Catches silent-rot when a skill is renamed
# or a step is renumbered.
#
# Two classes of references are checked:
#   1. Skill / agent references — `<name>/SKILL.md` paths and
#      `autodev:<name>` strings. Verifies the target exists either as
#      skills/<name>/SKILL.md or as agents/<name>.md.
#   2. Step references — `<skill> Step N[a-z]?` mentions in prose.
#      Verifies that the cited skill's SKILL.md contains a heading or
#      bold-line whose label is `Step <N>` / `Step <N><letter>`.
#
# Fenced code blocks (``` … ```) are skipped, mirroring the discipline of
# tests/skill-content-grep.sh — placeholder examples like `path/SKILL.md`
# inside ```code``` are not real references.
#
# Exit codes:
#   0 — no broken references
#   1 — one or more broken references
#   3 — script error (missing tools, etc.)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

failures=0
tmp_failures="$(mktemp)" || { echo "ERROR: mktemp failed" >&2; exit 3; }
trap 'rm -f "$tmp_failures"' EXIT

# Build the set of known skill names and agent names from the filesystem.
known_skills="$(find skills -mindepth 1 -maxdepth 1 -type d | sed -E 's|.*/||' | sort -u)"
known_agents="$(find agents -mindepth 1 -maxdepth 1 -type f -name '*.md' | sed -E 's|.*/||; s|\.md$||' | sort -u)"

# Helper: is the name a known skill or agent?
is_known_target() {
  local name="$1"
  printf '%s\n' "$known_skills" | grep -qx "$name" && return 0
  printf '%s\n' "$known_agents" | grep -qx "$name" && return 0
  return 1
}

# Strip fenced code blocks from a file, emitting "LINENO:CONTENT" for
# every non-fenced line. Mirrors the AWK in tests/skill-content-grep.sh.
strip_fences() {
  awk '
    BEGIN { fence_width = 0; ln = 0 }
    {
      ln++
      stripped = $0
      sub(/^[[:space:]]*/, "", stripped)
      if (stripped ~ /^```/) {
        n = 0
        s = stripped
        while (length(s) > 0 && substr(s, 1, 1) == "`") { n++; s = substr(s, 2) }
        if (s ~ /^[a-zA-Z0-9_+-]*[[:space:]]*$/) {
          if (fence_width == 0) { fence_width = n; next }
          if (n == fence_width)  { fence_width = 0; next }
        }
      }
      if (fence_width > 0) { next }
      print ln ":" $0
    }
  ' "$1"
}

# Files to scan. Exclude *creation-log* / changelog-style files where the
# point is to record historical names that no longer exist.
# Use a newline-separated string for portability (no mapfile / Bash 4+).
scan_files_list="$(find skills agents -type f -name '*.md' \
  ! -iname 'CREATION-LOG.md' | sort)"

# --- 1. Skill / agent references ----------------------------------------

while IFS= read -r f; do
  [ -z "$f" ] && continue
  annotated="$(strip_fences "$f")"

  # Pattern 1: bare `<slug>/SKILL.md` references
  while IFS=: read -r line_no line; do
    [ -z "${line_no:-}" ] && continue
    name="$(printf '%s' "$line" | grep -oE '[a-z][a-z0-9-]+/SKILL\.md' \
              | head -1 | sed -E 's|/SKILL\.md$||' || true)"
    [ -z "$name" ] && continue
    case "$line" in
      *"skills/${name}/SKILL.md"*) ;;
      *)
        if [ ! -f "skills/${name}/SKILL.md" ]; then
          printf '%s:%s: skill reference "%s/SKILL.md" — no such skill\n' \
            "$f" "$line_no" "$name" >> "$tmp_failures"
        fi
        ;;
    esac
  done < <(printf '%s\n' "$annotated" | grep -E '[a-z][a-z0-9-]+/SKILL\.md' || true)

  # Pattern 2: `skills/<name>/SKILL.md` paths
  while IFS=: read -r line_no line; do
    [ -z "${line_no:-}" ] && continue
    name="$(printf '%s' "$line" | grep -oE 'skills/[a-z][a-z0-9-]+/SKILL\.md' \
              | head -1 | sed -E 's|^skills/||; s|/SKILL\.md$||' || true)"
    [ -z "$name" ] && continue
    if [ ! -f "skills/${name}/SKILL.md" ]; then
      printf '%s:%s: path reference "skills/%s/SKILL.md" — file missing\n' \
        "$f" "$line_no" "$name" >> "$tmp_failures"
    fi
  done < <(printf '%s\n' "$annotated" | grep -E 'skills/[a-z][a-z0-9-]+/SKILL\.md' || true)

  # Pattern 3: `autodev:<name>` mentions — must resolve to a skill OR agent
  while IFS=: read -r line_no line; do
    [ -z "${line_no:-}" ] && continue
    # A line may have multiple autodev:<name> mentions; check each.
    for name in $(printf '%s' "$line" \
                    | grep -oE 'autodev:[a-z][a-z0-9-]+' \
                    | sed -E 's|^autodev:||' | sort -u); do
      if ! is_known_target "$name"; then
        printf '%s:%s: "autodev:%s" — no such skill or agent\n' \
          "$f" "$line_no" "$name" >> "$tmp_failures"
      fi
    done
  done < <(printf '%s\n' "$annotated" | grep -E 'autodev:[a-z][a-z0-9-]+' || true)
done <<< "$scan_files_list"

# --- 2. Step references --------------------------------------------------

# Match patterns like "<skill-name> Step 1b" or "<skill-name>'s Step 1b".
# Reference is valid if the cited SKILL.md contains a markdown heading or
# bold-line whose label starts with "Step <N>" / "Step <N><letter>".

# Helper: does skills/<skill>/SKILL.md contain a "Step <id>" heading or
# bold-line?
has_step() {
  local skill="$1" step="$2"
  local file="skills/${skill}/SKILL.md"
  [ -f "$file" ] || return 1
  # Match contexts where "Step N" is a label, not just prose:
  #   - markdown heading: lines starting with #'s
  #   - bold: **Step N...** or **Step N:**
  #   - list-item label: `- Step N:`
  # Word-boundary on the trailing side prevents "Step 1" matching "Step 11".
  grep -qE "(^#|^\*\*|\*\*Step|^- )(\*\*)?Step[[:space:]]+${step}([^0-9a-zA-Z]|$)" "$file" \
    || grep -qE "Step[[:space:]]+${step}[[:space:]]*[:.]" "$file"
}

while IFS= read -r f; do
  [ -z "$f" ] && continue
  annotated="$(strip_fences "$f")"

  while IFS=: read -r line_no line; do
    [ -z "${line_no:-}" ] && continue
    while read -r skill step; do
      [ -z "${skill:-}" ] && continue
      [ -z "${step:-}" ]  && continue
      # Only check known skills — ignores false positives like "Project Step 1"
      if ! printf '%s\n' "$known_skills" | grep -qx "$skill"; then
        continue
      fi
      if ! has_step "$skill" "$step"; then
        printf '%s:%s: "%s Step %s" — label not found in skills/%s/SKILL.md\n' \
          "$f" "$line_no" "$skill" "$step" "$skill" >> "$tmp_failures"
      fi
    done < <(printf '%s\n' "$line" \
              | grep -oE "[a-z][a-z0-9-]+(['s]*)?[[:space:]]+Step[[:space:]]+[0-9]+[a-z]?" \
              | sed -E "s/^([a-z][a-z0-9-]+)[a-z']*[[:space:]]+Step[[:space:]]+([0-9]+[a-z]?).*/\1 \2/")
  done < <(printf '%s\n' "$annotated" \
            | grep -E "[a-z][a-z0-9-]+[a-z']*[[:space:]]+Step[[:space:]]+[0-9]+[a-z]?" || true)
done <<< "$scan_files_list"

# --- Report --------------------------------------------------------------

if [ -s "$tmp_failures" ]; then
  echo "FAIL: broken cross-skill references:"
  sort -u "$tmp_failures"
  exit 1
fi

echo "PASS: all cross-skill references resolve."
exit 0
