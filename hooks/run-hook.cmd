: << 'CMDBLOCK'
@echo off
REM Cross-platform polyglot wrapper for hook scripts.
REM On Windows: cmd.exe runs the batch portion, which finds and calls bash.
REM On Unix: the shell interprets this as a script (: is a no-op in bash).
REM
REM Hook scripts use extensionless filenames (e.g. "session-start" not
REM "session-start.sh") so Claude Code's Windows auto-detection -- which
REM prepends "bash" to any command containing .sh -- doesn't interfere.
REM
REM Usage: run-hook.cmd <script-name> [args...]

if "%~1"=="" (
    echo run-hook.cmd: missing script name >&2
    exit /b 1
)

set "HOOK_DIR=%~dp0"

REM Try Git for Windows bash in standard locations
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

REM Try bash on PATH (e.g. user-installed Git Bash, MSYS2, Cygwin)
where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

REM No bash found - exit silently rather than error
REM (plugin still works, just without SessionStart context injection)
exit /b 0
CMDBLOCK

# Unix: run the named script directly
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift

# Some hosts start hooks with C.UTF-8 even on systems where that locale is not
# installed (notably macOS). Bash then writes a locale warning to stderr before
# the hook can emit its JSON response, which makes strict hook parsers reject the
# output. Preserve valid locales, but fall back to C when C.UTF-8 is unavailable.
if { [ "${LC_ALL:-}" = "C.UTF-8" ] || [ "${LC_CTYPE:-}" = "C.UTF-8" ] || [ "${LANG:-}" = "C.UTF-8" ]; } &&
   ! LC_ALL=C locale -a 2>/dev/null | grep -Eiq '^(C\.UTF-8|C\.utf8)$'; then
  [ "${LC_ALL:-}" = "C.UTF-8" ] && export LC_ALL=C
  [ "${LC_CTYPE:-}" = "C.UTF-8" ] && export LC_CTYPE=C
  [ "${LANG:-}" = "C.UTF-8" ] && export LANG=C
fi

exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
