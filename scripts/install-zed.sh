#!/usr/bin/env bash
# install-zed.sh — install Autonomous Dev Kit skills for Zed Agent.
#
# Zed discovers skills only as direct children of ~/.agents/skills or
# <worktree>/.agents/skills. This installer links each skills/<name>/ directory
# directly into the chosen skills root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_ROOT="$REPO_ROOT/skills"
SCOPE="global"
SKILLS_ROOT=""
MODE="symlink"
FORCE=false
UNINSTALL=false
PROJECT_ROOT=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/install-zed.sh [options]

Options:
  --scope global|project   Install globally (default) or into a project's .agents/skills
  --project-root PATH      Project root for --scope project (default: current directory)
  --skills-root PATH       Explicit skills root; overrides --scope
  --copy                   Copy skill directories instead of symlinking
  --force                  Replace existing autodev-managed skill links/directories
  --uninstall              Remove autodev-managed skill links/directories
  -h, --help               Show this help

Examples:
  scripts/install-zed.sh
  scripts/install-zed.sh --scope project --project-root /path/to/project
  scripts/install-zed.sh --skills-root /tmp/skills --copy --force
USAGE
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --scope)
      [ "$#" -ge 2 ] || usage
      SCOPE="$2"
      shift 2
      ;;
    --project-root)
      [ "$#" -ge 2 ] || usage
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --skills-root)
      [ "$#" -ge 2 ] || usage
      SKILLS_ROOT="$2"
      shift 2
      ;;
    --copy)
      MODE="copy"
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --uninstall)
      UNINSTALL=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      ;;
  esac
done

case "$SCOPE" in
  global|project) ;;
  *) echo "ERROR: --scope must be global or project" >&2; exit 1 ;;
esac

if [ -z "$SKILLS_ROOT" ]; then
  if [ "$SCOPE" = "global" ]; then
    SKILLS_ROOT="$HOME/.agents/skills"
  else
    if [ -z "$PROJECT_ROOT" ]; then
      PROJECT_ROOT="$(pwd)"
    fi
    SKILLS_ROOT="$PROJECT_ROOT/.agents/skills"
  fi
fi

mkdir -p "$SKILLS_ROOT"

is_autodev_managed() {
  target="$1"
  marker="$target/.autodev-zed-install"
  [ -f "$marker" ] && return 0
  if [ -L "$target" ]; then
    link_target="$(readlink "$target" 2>/dev/null || true)"
    case "$link_target" in
      "$SRC_ROOT"/*) return 0 ;;
    esac
  fi
  return 1
}

install_one() {
  src="$1"
  name="$(basename "$src")"
  dest="$SKILLS_ROOT/$name"

  if [ "$UNINSTALL" = true ]; then
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      if is_autodev_managed "$dest"; then
        rm -rf "$dest"
        echo "Removed $dest"
      else
        echo "Skipped unmanaged existing skill: $dest" >&2
      fi
    fi
    return
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$FORCE" = true ] && is_autodev_managed "$dest"; then
      rm -rf "$dest"
    else
      echo "ERROR: $dest already exists. Use --force to replace autodev-managed installs, or remove/rename it manually." >&2
      return 1
    fi
  fi

  if [ "$MODE" = "copy" ]; then
    cp -R "$src" "$dest"
    printf 'installed-by=autodev\nsource=%s\n' "$src" > "$dest/.autodev-zed-install"
    echo "Copied $name"
  else
    ln -s "$src" "$dest"
    echo "Linked $name"
  fi
}

failures=0
for src in "$SRC_ROOT"/*; do
  [ -d "$src" ] || continue
  if [ ! -f "$src/SKILL.md" ]; then
    continue
  fi
  install_one "$src" || failures=$((failures + 1))
done

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures skill(s) could not be installed." >&2
  exit 1
fi

if [ "$UNINSTALL" = true ]; then
  echo "Autonomous Dev Kit Zed skills removed from $SKILLS_ROOT"
else
  echo "Autonomous Dev Kit Zed skills installed in $SKILLS_ROOT"
  echo "Open Zed's AI > Skills page or start a new Zed Agent thread to verify discovery."
fi
