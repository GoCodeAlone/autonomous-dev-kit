#!/usr/bin/env bash
# tests/cascade-preflight.sh
# Pre-cascade gate: verify each plugin repo's most-recent Release
# workflow run was SUCCESS. Catches release-pipeline-class gaps
# (e.g., ManifestProvider missing) before scope-lock + dispatch.
#
# Usage:
#   tests/cascade-preflight.sh <repo1> <repo2> ...
#   tests/cascade-preflight.sh GoCodeAlone/workflow-plugin-cloudflare GoCodeAlone/workflow-plugin-namecheap
#
# Note: Release workflows typically trigger on tag-push (push: tags: 'v*'),
# not branch-push. headBranch for tag-triggered runs is the tag name (e.g.,
# 'v1.0.0'), not 'main'. Don't filter --branch.
set -euo pipefail

[ "$#" -ge 1 ] || { printf 'Usage: %s <owner/repo> [...]\n' "$0" >&2; exit 2; }

failed=0
for repo in "$@"; do
    conclusion=""
    for wf in release.yml Release.yml; do
        result=$(gh run list --repo "$repo" --workflow "$wf" --limit 1 \
            --json conclusion --jq '.[0].conclusion // ""' 2>/dev/null || echo "")
        if [ -n "$result" ]; then
            conclusion="$result"
            break
        fi
    done
    conclusion="${conclusion:-not-found}"

    if [ "$conclusion" = "success" ]; then
        printf '  ✓ %s: Release workflow last run = success\n' "$repo"
    else
        printf '  ✗ %s: Release workflow last run = %s — FIX BEFORE CASCADE\n' "$repo" "$conclusion" >&2
        failed=$((failed+1))
    fi
done

[ "$failed" -eq 0 ] || { printf '\nPreflight FAIL: %d repo(s) have broken Release pipelines\n' "$failed" >&2; exit 1; }
printf '\nPreflight PASS: all %d repo(s) have green Release workflows\n' "$#"
