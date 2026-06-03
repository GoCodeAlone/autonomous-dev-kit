#!/usr/bin/env bash
# tests/pipeline-evidence-doc-sync.sh
# Regression guard for issues #69/#70/#71/#72 (v6.4.0). Asserts the skill
# contracts these issues fixed remain present, so they cannot silently regress.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADR="$ROOT/skills/adversarial-design-review/SKILL.md"
RETRO="$ROOT/skills/post-merge-retrospective/SKILL.md"
FIN="$ROOT/skills/finishing-a-development-branch/SKILL.md"
fail=0
pass(){ printf 'PASS: %s\n' "$1"; }
bad(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
has(){ grep -qiF "$2" "$1"; }       # literal substring
hasE(){ grep -qiE "$2" "$1"; }      # regex

# --- #69 (D1): adversarial-design-review mandates committing the report ---
hasE "$ADR" '(-design-review\.md|-plan-review\.md)' \
  && pass "#69 ADR cites the <stem>-design-review.md/-plan-review.md convention" \
  || bad  "#69 ADR missing committed-report convention path"
# P1: assert the SPECIFIC new mandate wording, not the ambient word "commit"
has "$ADR" "Write AND commit the report" \
  && pass "#69 ADR mandates writing+committing the report" \
  || bad  "#69 ADR does not mandate writing+committing the report"
hasE "$ADR" 'stable finding ID|stable .*ID' \
  && pass "#69 ADR defines stable finding IDs" \
  || bad  "#69 ADR missing stable finding IDs"
# P4/M1: guard the load-bearing D1<->D2 path contract -- retro must cite the SAME derivation.
# Assert the specific load-bearing phrase only (dropping the broad '-plan-review.md' OR branch,
# which is ambient vocabulary that could false-pass on an incidental path mention).
has "$RETRO" "same deterministic rule" \
  && pass "#69/#70 retro derives the report path by the same rule (D1<->D2 contract)" \
  || bad  "#69/#70 retro missing the shared path-derivation rule"

# --- #70 (D2): retro reads the jsonl as PRIMARY; script demoted, NOT a hard dep ---
# P1: assert the jsonl is the PRIMARY source (only true after Task 4), not merely mentioned
hasE "$RETRO" 'primary source.*in-progress\.jsonl|in-progress\.jsonl.*primary' \
  && pass "#70 retro makes in-progress.jsonl the primary activation source" \
  || bad  "#70 retro does not promote in-progress.jsonl to primary"
# The format template must NOT instruct 'Pull from tests/skill-activation-audit.sh'
grep -qiE 'Pull from .*skill-activation-audit\.sh' "$RETRO" \
  && bad  "#70 retro STILL instructs 'Pull from tests/skill-activation-audit.sh' (line ~99 not demoted)" \
  || pass "#70 retro format template no longer hard-depends on the kit-local script"
has "$RETRO" "kit-dev" \
  && pass "#70 retro marks the audit script kit-dev-only" \
  || bad  "#70 retro does not demote the audit script to kit-dev-only"

# --- #71/#72 (D3): finishing has Step 1e in BOTH body and autonomous list ---
hasE "$FIN" 'Step 1e' \
  && pass "#71/#72 finishing has Step 1e body" \
  || bad  "#71/#72 finishing missing Step 1e body"
has "$FIN" "Doc-reconciliation" \
  && pass "#71/#72 finishing emits Doc-reconciliation token" \
  || bad  "#71/#72 finishing missing Doc-reconciliation accountability token"
# Step 1e must be referenced in the Autonomous Mode numbered list region (top of file, before '### Step 1:')
auto_region="$(awk '/^## Autonomous Mode/{f=1} /^### Step 1: Verify Tests/{f=0} f' "$FIN")"
printf '%s' "$auto_region" | grep -qiE 'Step 1e' \
  && pass "#71/#72 Step 1e wired into Autonomous Mode list" \
  || bad  "#71/#72 Step 1e NOT in Autonomous Mode list (would never fire autonomously)"

# --- #72 (D4): plan-phase naming-convention checklist row ---
hasE "$ADR" 'naming.convention match|Identifier / naming' \
  && pass "#72 ADR plan-phase has Identifier/naming-convention row" \
  || bad  "#72 ADR plan-phase missing naming-convention row"

echo ""; echo "Results: $fail failure(s)"; [ "$fail" -eq 0 ]
