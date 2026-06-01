#!/usr/bin/env bash
# tests/hook-stdout-discipline.sh — verify run-hook.cmd enforces stdout JSON discipline.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="$REPO_ROOT/hooks/run-hook.cmd"
failures=0
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures+1)); }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq required for a/b/c"; exit 0; }

tmp="$(mktemp -d)"
# Cleanup trap set BEFORE any fixture is copied into hooks/ (rm -f on absent files is safe).
trap 'rm -f "$REPO_ROOT"/hooks/fix-warn-then-json "$REPO_ROOT"/hooks/fix-noise "$REPO_ROOT"/hooks/fix-clean; rm -rf "$tmp"' EXIT
mkfix() { printf '%s\n' "$1" > "$tmp/$2"; chmod +x "$tmp/$2"; }

# Fixture A: a warning leaks to stdout, then a block JSON on stdout.
mkfix '#!/usr/bin/env bash
echo "perl: warning: Setting locale failed."
printf "%s\n" "{\"decision\":\"block\",\"reason\":\"x\"}"' fix-warn-then-json
# Fixture B: only noise, no JSON.
mkfix '#!/usr/bin/env bash
echo "just a diagnostic line"' fix-noise
# Fixture C: clean single-line JSON.
mkfix '#!/usr/bin/env bash
printf "%s\n" "{\"hookSpecificOutput\":{\"hookEventName\":\"X\"}}"' fix-clean

for f in fix-warn-then-json fix-noise fix-clean; do cp "$tmp/$f" "$REPO_ROOT/hooks/$f"; done

run() { OUT="$("$WRAPPER" "$1" 2>"$tmp/err")"; RC=$?; ERR="$(cat "$tmp/err")"; }

# (a) warning + block JSON → stdout ONLY the block JSON; warning ON stderr.
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

# (d) jq-absent → wrapper passes stdout through VERBATIM (warning + JSON both present).
# Stub PATH so the wrapper's `command -v jq` fails, but `bash` is still resolvable
# (the wrapper's jq-absent branch `exec bash`s the fixture). assert via grep (no jq).
nojq="$tmp/nojq"; mkdir -p "$nojq"
# Symlink the externals the wrapper's jq-absent path needs (bash for `exec bash`,
# dirname for SCRIPT_DIR) but NOT jq, so `command -v jq` fails.
for bin in bash dirname; do ln -sf "$(command -v "$bin")" "$nojq/$bin"; done
OUTD="$(PATH="$nojq" "$WRAPPER" fix-warn-then-json 2>/dev/null)"
{ printf '%s' "$OUTD" | grep -q 'perl: warning' && printf '%s' "$OUTD" | grep -q '"decision":"block"'; } \
  && pass "(d) jq-absent → verbatim passthrough (no discipline applied)" \
  || fail "(d) expected verbatim passthrough with jq absent, got: $OUTD"

echo ""; echo "Results: $failures failure(s)"; [ "$failures" -eq 0 ]
