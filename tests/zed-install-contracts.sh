#!/usr/bin/env bash
# zed-install-contracts.sh — Validate the Zed installer creates flat skill installs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bash scripts/install-zed.sh --skills-root "$tmp/skills" --copy >/dev/null
bash scripts/install-zed.sh --skills-root "$tmp/links" >/dev/null
bash scripts/install-zed.sh --scope project --project-root "$tmp/project" --copy >/dev/null

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
pass() {
  printf 'PASS: %s\n' "$1"
}

if [ -d "$tmp/skills/autodev" ]; then
  fail "installer created nested autodev namespace; Zed requires flat direct children"
else
  pass "no nested autodev namespace created"
fi

for src in skills/*; do
  [ -d "$src" ] || continue
  [ -f "$src/SKILL.md" ] || continue
  name="$(basename "$src")"
  if [ ! -f "$tmp/skills/$name/SKILL.md" ]; then
    fail "missing flat skill install: $name"
  elif [ ! -f "$tmp/skills/$name/.autodev-zed-install" ]; then
    fail "missing autodev management marker: $name"
  else
    pass "flat skill installed: $name"
  fi
  if [ ! -L "$tmp/links/$name" ]; then
    fail "missing symlink skill install: $name"
  fi
  if [ ! -f "$tmp/project/.agents/skills/$name/SKILL.md" ]; then
    fail "missing project-local skill install: $name"
  fi
done

if [ -L "$tmp/links/using-autodev" ]; then
  pass "symlink mode installs flat skills"
else
  fail "symlink mode did not install flat skills"
fi

if [ -f "$tmp/project/.agents/skills/using-autodev/SKILL.md" ]; then
  pass "project scope installs to <worktree>/.agents/skills"
else
  fail "project scope did not install to <worktree>/.agents/skills"
fi

bash scripts/install-zed.sh --skills-root "$tmp/skills" --uninstall >/dev/null
bash scripts/install-zed.sh --skills-root "$tmp/links" --uninstall >/dev/null

remaining="$(find "$tmp/skills" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')"
link_remaining="$(find "$tmp/links" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')"
if [ "$remaining" = "0" ] && [ "$link_remaining" = "0" ]; then
  pass "uninstall removes autodev-managed flat skills"
else
  fail "uninstall left copy=$remaining link=$link_remaining entries"
fi

[ "$failures" -eq 0 ]
