# Writes the JTI verification receipt that jti-gate.ps1 checks on stop.
#
# Run this immediately after a full, passing Phase 3 gate. The receipt records
# what was run, what it returned, and a fingerprint of the worktree at that
# moment (HEAD + tracked diff + untracked files), so any later edit or commit
# invalidates it.
#
# Usage after a green gate:
#   pwsh -NoProfile -File ~/.claude/hooks/jti-receipt.ps1 -WorktreeRoot <path> `
#       -Gates "build=0,lint=0,test=0" -NewWarnings 0
#
# New warnings that are genuinely out of scope pass the gate only when justified:
#   ... -NewWarnings 2 -JustifiedWarnings 2 -Note "CS0618 from upstream package, tracked in PROJ-123"
#
# Before reporting a hand-back to JTPS (tree may be partial or reverted):
#   pwsh -NoProfile -File ~/.claude/hooks/jti-receipt.ps1 -WorktreeRoot <path> -HandBack

[CmdletBinding()]
param(
    [string]$WorktreeRoot,
    [string]$Gates,
    [int]$NewWarnings = 0,
    [int]$JustifiedWarnings = 0,
    [string]$Note = '',
    [switch]$HandBack
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'jti-common.ps1')

if (-not $WorktreeRoot) {
    $WorktreeRoot = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($WorktreeRoot)) {
        throw 'Not inside a git worktree. Pass -WorktreeRoot <path to the worktree you verified>.'
    }
}
$WorktreeRoot = (Resolve-Path -LiteralPath $WorktreeRoot.Trim()).Path

if (-not $HandBack) {
    if (-not $Gates) { throw 'Pass -Gates "build=0,lint=0,test=0" (name=exitCode, comma separated), or -HandBack.' }
    if ($NewWarnings -gt 0 -and $JustifiedWarnings -ge $NewWarnings -and -not $Note) {
        throw 'Justified warnings need a -Note saying what they are and why they stay.'
    }
}

# Deliberately not named $gates: PowerShell variable names are case-insensitive,
# so that would overwrite the $Gates parameter before it is read.
$gateList = @()
if ($Gates) {
    foreach ($entry in ($Gates.Split(',') | Where-Object { $_.Trim() })) {
        $parts = $entry.Split('=', 2)
        if ($parts.Count -ne 2) { throw "Bad -Gates entry '$entry'. Expected name=exitCode, for example 'build=0,lint=0,test=0'." }
        $gateList += @{ name = $parts[0].Trim(); exitCode = [int]$parts[1].Trim() }
    }
    if ($gateList.Count -eq 0) { throw "No gates parsed from '$Gates'." }
}

$receipt = [ordered]@{
    agent             = 'j-the-implementer'
    status            = if ($HandBack) { 'handback' } else { 'verified' }
    worktreeRoot      = $WorktreeRoot
    branch            = (& git -C $WorktreeRoot rev-parse --abbrev-ref HEAD 2>$null)
    gates             = @($gateList)
    newWarnings       = $NewWarnings
    justifiedWarnings = $JustifiedWarnings
    note              = $Note
    treeSha           = Get-TreeFingerprint $WorktreeRoot
    writtenEpoch      = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

$path = Get-ReceiptPath $WorktreeRoot
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding utf8
Remove-Item -LiteralPath ([IO.Path]::ChangeExtension($path, '.blocks')) -Force -ErrorAction SilentlyContinue

Write-Output "Receipt written ($($receipt.status)): $path"
