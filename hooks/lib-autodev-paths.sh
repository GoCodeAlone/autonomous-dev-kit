#!/usr/bin/env bash
# lib-autodev-paths.sh — canonical ADK state-root resolver, sourced by state-writing hooks.
# autodev_repo_root <cwd> -> canonical repo root (shared across worktrees, survives worktree removal).
# set -u safe: every var is assigned before any read. Sourced; uses `local` (all callers are bash).
autodev_repo_root() {
  local cwd="${1:-$PWD}" _gcd="" _root=""
  if [ -n "${AUTODEV_STATE_ROOT:-}" ]; then printf '%s\n' "$AUTODEV_STATE_ROOT"; return 0; fi
  _gcd="$(cd "$cwd" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null || true)"
  # pwd -P (physical): git returns an ABSOLUTE common-dir for a linked worktree but a RELATIVE
  # `.git` for a main checkout; on macOS the tmp/cwd is a /var->/private symlink. `pwd -P`
  # normalizes both to the same physical path so a main-checkout and a worktree invocation
  # resolve to the IDENTICAL root string (and the same inode) — C-2 fix.
  [ -n "$_gcd" ] && _root="$(cd "$cwd" 2>/dev/null && cd "$_gcd/.." 2>/dev/null && pwd -P || true)"
  if [ -n "$_root" ]; then printf '%s\n' "$_root"; else printf '%s\n' "$cwd"; fi
}
