<#
.SYNOPSIS
Install Autonomous Dev Kit skills for Zed Agent on Windows.

.DESCRIPTION
Zed discovers skills only as direct children of %USERPROFILE%\.agents\skills
or <worktree>\.agents\skills. This script creates one junction or copy per
ADK skill directory.
#>

param(
    [ValidateSet("Global", "Project")]
    [string]$Scope = "Global",

    [string]$ProjectRoot = (Get-Location).Path,

    [string]$SkillsRoot,

    [switch]$Copy,

    [switch]$Force,

    [switch]$Uninstall
)

<#
If Zed's AI > Skills page says no global skills are installed, open Create
Skill in Zed's User tab and note the directory Zed says it will write to.
Then rerun this installer with -SkillsRoot set to that exact skills root.
#>

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$SourceRoot = Join-Path $RepoRoot "skills"

if (-not $SkillsRoot) {
    if ($Scope -eq "Global") {
        $SkillsRoot = Join-Path $env:USERPROFILE ".agents\skills"
    } else {
        $SkillsRoot = Join-Path $ProjectRoot ".agents\skills"
    }
}

New-Item -ItemType Directory -Force -Path $SkillsRoot | Out-Null

function Test-AutodevManaged {
    param([string]$Path)

    $marker = Join-Path $Path ".autodev-zed-install"
    if (Test-Path -LiteralPath $marker) { return $true }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $target = $item.Target
        if ($target -is [array]) { $target = $target[0] }
        if ($target -and $target.StartsWith($SourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

$failures = 0
Get-ChildItem -LiteralPath $SourceRoot -Directory | ForEach-Object {
    $src = $_.FullName
    $name = $_.Name
    $skillFile = Join-Path $src "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillFile)) { return }

    $dest = Join-Path $SkillsRoot $name

    if ($Uninstall) {
        if (Test-Path -LiteralPath $dest) {
            if (Test-AutodevManaged -Path $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force
                Write-Host "Removed $dest"
            } else {
                Write-Warning "Skipped unmanaged existing skill: $dest"
            }
        }
        return
    }

    if (Test-Path -LiteralPath $dest) {
        if ($Force -and (Test-AutodevManaged -Path $dest)) {
            Remove-Item -LiteralPath $dest -Recurse -Force
        } else {
            Write-Error "$dest already exists. Use -Force to replace autodev-managed installs, or remove/rename it manually."
            $script:failures += 1
            return
        }
    }

    if ($Copy) {
        Copy-Item -LiteralPath $src -Destination $dest -Recurse
        "installed-by=autodev`nsource=$src" | Set-Content -LiteralPath (Join-Path $dest ".autodev-zed-install") -NoNewline
        Write-Host "Copied $name"
    } else {
        cmd /c mklink /J "$dest" "$src" | Out-Null
        Write-Host "Linked $name"
    }
}

if ($failures -gt 0) {
    throw "FAIL: $failures skill(s) could not be installed."
}

if ($Uninstall) {
    Write-Host "Autonomous Dev Kit Zed skills removed from $SkillsRoot"
} else {
    $installedSkillFiles = @(Get-ChildItem -LiteralPath $SkillsRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md")
    })

    Write-Host "Autonomous Dev Kit Zed skills installed in $SkillsRoot"
    if ($installedSkillFiles.Count -gt 0) {
        $example = Join-Path $installedSkillFiles[0].FullName "SKILL.md"
        Write-Host "Verified $($installedSkillFiles.Count) direct child SKILL.md file(s); for example: $example"
    } else {
        Write-Warning "No direct child SKILL.md files found under $SkillsRoot"
    }
    Write-Host "Open Zed's AI > Skills page or start a new Zed Agent thread to verify discovery."
    Write-Host "If Zed still reports no global skills, rerun with -Copy -Force and/or -SkillsRoot set to the exact path shown by Zed's User-scope skill creator."
}
