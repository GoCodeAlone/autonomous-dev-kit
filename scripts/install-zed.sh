#!/usr/bin/env bash
# install-zed.sh — install Autonomous Dev Kit skills for Zed Agent.
#
# Zed discovers skills only as direct children of ~/.agents/skills or
# <worktree>/.agents/skills. This installer links or copies each skills/<name>/
# directory directly into the chosen skills root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_ROOT="$REPO_ROOT/skills"
SCOPE="global"
SKILLS_ROOT=""
SKILLS_ROOT_EXPLICIT=false
MODE="symlink"
MODE_EXPLICIT=false
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

If Zed's AI > Skills page says no global skills are installed, open Create
Skill in Zed's User tab and note the directory Zed says it will write to.
Then rerun this installer with --skills-root set to that exact skills root.

Examples:
  scripts/install-zed.sh
  scripts/install-zed.sh --scope project --project-root /path/to/project
  scripts/install-zed.sh --skills-root /tmp/skills --copy --force

On WSL with Windows-native Zed, the global default targets
/mnt/c/Users/<linux-user>/.agents/skills when that Windows profile exists and
uses copy mode. Otherwise pass --skills-root /mnt/c/Users/<WindowsUser>/.agents/skills --copy.
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
      SKILLS_ROOT_EXPLICIT=true
      shift 2
      ;;
    --copy)
      MODE="copy"
      MODE_EXPLICIT=true
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

is_wsl() {
  uname_text="$(uname -a 2>/dev/null || true)"
  case "$uname_text" in
    *Microsoft*|*microsoft*|*WSL*|*wsl*) return 0 ;;
  esac
  return 1
}

windows_profile_for_wsl_user() {
  linux_user="$(id -un 2>/dev/null || basename "$HOME")"
  candidate="/mnt/c/Users/$linux_user"
  if [ -d "$candidate" ]; then
    printf '%s\n' "$candidate"
  fi
}

if [ -z "$SKILLS_ROOT" ]; then
  if [ "$SCOPE" = "global" ]; then
    if is_wsl; then
      windows_profile="$(windows_profile_for_wsl_user)"
      if [ -n "$windows_profile" ]; then
        SKILLS_ROOT="$windows_profile/.agents/skills"
        if [ "$MODE_EXPLICIT" = false ]; then
          MODE="copy"
        fi
      else
        SKILLS_ROOT="$HOME/.agents/skills"
      fi
    else
      SKILLS_ROOT="$HOME/.agents/skills"
    fi
  else
    if [ -z "$PROJECT_ROOT" ]; then
      PROJECT_ROOT="$(pwd)"
    fi
    SKILLS_ROOT="$PROJECT_ROOT/.agents/skills"
  fi
fi

mkdir -p "$SKILLS_ROOT"

warn_if_home_may_differ_from_zed() {
  if [ "$SCOPE" != "global" ]; then
    return
  fi

  if ! is_wsl; then
    return
  fi

  if [ "$SKILLS_ROOT_EXPLICIT" = true ]; then
    case "$SKILLS_ROOT" in
      /mnt/c/Users/*) ;;
      *) return ;;
    esac
  fi

  case "$SKILLS_ROOT" in
    /mnt/c/Users/*)
      cat >&2 <<EOF
NOTE: This installer is running inside WSL and installed to the Windows profile
      path for Windows-native Zed: $SKILLS_ROOT
EOF
      ;;
    *)
      cat >&2 <<'EOF'
NOTE: This installer is running inside WSL. Windows-native Zed will not read
      WSL's /home/.../.agents/skills path. If you use Windows Zed, run
      scripts/install-zed.ps1 from Windows PowerShell instead, or pass the
      exact User skills path shown by Zed's AI > Skills > Create Skill page
      with --skills-root /mnt/c/Users/<WindowsUser>/.agents/skills --copy.
EOF
      ;;
  esac
}

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
  installed_count=0
  first_example=""
  for skill_file in "$SKILLS_ROOT"/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    installed_count=$((installed_count + 1))
    if [ -z "$first_example" ]; then
      first_example="$skill_file"
    fi
  done

  echo "Autonomous Dev Kit Zed skills installed in $SKILLS_ROOT"
  if [ "$installed_count" -gt 0 ]; then
    echo "Verified $installed_count direct child SKILL.md file(s); for example: $first_example"
  else
    echo "WARNING: no direct child SKILL.md files found under $SKILLS_ROOT" >&2
  fi
  warn_if_home_may_differ_from_zed
  echo "Open Zed's AI > Skills page or start a new Zed Agent thread to verify discovery."
  echo "If Zed still reports no global skills, rerun with --copy --force and/or --skills-root set to the exact path shown by Zed's User-scope skill creator."
fi
