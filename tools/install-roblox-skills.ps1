# Project skills are vendored in .claude/skills; AGENTS.md routes Codex to the same files.
[CmdletBinding()]
param(
    [ValidateSet('Codex', 'Claude', 'Both')]
    [string]$Agent = 'Both',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'AGENTS.md'))) {
    throw 'Project routing is missing: AGENTS.md'
}
& python -X utf8 (Join-Path $PSScriptRoot 'audit-project-skills.py')
if ($LASTEXITCODE -ne 0) { throw 'Project skill validation failed.' }
if (-not $CheckOnly) {
    $skillLock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'roblox-skills.lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Output "Ready for ${Agent}: $($skillLock.requested_skills -join ', ')"
    Write-Output 'Both agents use the shared project directory .claude/skills through AGENTS.md and CLAUDE.md.'
}
