#!/usr/bin/env bash
# Regression guard for issue #78 brainstorm visualization companion.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRAIN="$ROOT/skills/brainstorming/SKILL.md"
GUIDE="$ROOT/skills/brainstorming/visual-companion.md"
FIXTURE="$ROOT/skills/brainstorming/test-fixtures/visual-companion/expected-behavior.md"
AGENTS="$ROOT/AGENTS.md"
CAPS="$ROOT/docs/cross-llm-coverage.md"
SKILL_COVERAGE="$ROOT/tests/cross-llm-coverage.md"
fail=0
pass(){ printf 'PASS: %s\n' "$1"; }
bad(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
has(){ grep -qiF "$2" "$1"; }
hasE(){ grep -qiE "$2" "$1"; }

has "$BRAIN" "Visual Companion" && pass "brainstorming has Visual Companion section" || bad "brainstorming missing Visual Companion section"
has "$BRAIN" "just-in-time" && pass "visual companion offer is just-in-time" || bad "visual companion offer is not just-in-time"
hasE "$BRAIN" 'not[ -]upfront|never[ -]upfront|NOT upfront' && pass "visual companion is not offered upfront" || bad "visual companion upfront prohibition missing"
has "$BRAIN" "per-question" && pass "visual decision is per-question" || bad "per-question decision rule missing"
has "$BRAIN" "text remains the source of truth" && pass "text source-of-truth rule present" || bad "text source-of-truth rule missing"
has "$BRAIN" "question batch" && pass "visual offer batch-budget rule present" || bad "visual offer batch-budget rule missing"
has "$BRAIN" "lazy-load" && pass "guide lazy-load rule present" || bad "guide lazy-load rule missing"
has "$BRAIN" "visual-companion.md" && pass "guide reference present" || bad "guide reference missing"

[ -f "$GUIDE" ] && pass "visual companion guide exists" || bad "visual companion guide missing"
if [ -f "$GUIDE" ]; then
  has "$GUIDE" "Mermaid" && pass "guide mentions Mermaid" || bad "guide missing Mermaid guidance"
  has "$GUIDE" "accessibility" && pass "guide mentions accessibility" || bad "guide missing accessibility guidance"
  has "$GUIDE" "fallback" && pass "guide mentions fallback" || bad "guide missing fallback guidance"
  has "$GUIDE" "secrets" && pass "guide forbids secrets" || bad "guide missing secrets guidance"
  has "$GUIDE" "SKILL.md remains authoritative" && pass "guide is bounded by SKILL.md authority" || bad "guide authority boundary missing"
fi

[ -f "$FIXTURE" ] && pass "behavior fixture exists" || bad "behavior fixture missing"
if [ -f "$FIXTURE" ]; then
  for marker in "conceptual text-only" "visual offer" "declines" "accepts" "stale visual" "RED baseline"; do
    has "$FIXTURE" "$marker" && pass "fixture covers $marker" || bad "fixture missing $marker"
  done
fi

has "$AGENTS" "tests/brainstorm-visual-companion.sh" && pass "AGENTS documents visual companion test" || bad "AGENTS missing visual companion test"
has "$CAPS" "Visual companion" && pass "capability matrix includes visual companion" || bad "capability matrix missing visual companion"
has "$CAPS" "browser deferred" && pass "capability matrix tracks browser deferral" || bad "capability matrix missing browser deferral"
has "$SKILL_COVERAGE" "visual companion" && pass "skill coverage notes visual companion" || bad "skill coverage missing visual companion note"

echo ""; echo "Results: $fail failure(s)"; [ "$fail" -eq 0 ]
