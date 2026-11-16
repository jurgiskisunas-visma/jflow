# JTI completion gate (SubagentStop hook, matcher: j-the-implementer).
#
# Blocks j-the-implementer from finishing when its verification receipt is
# red, when new warnings are unjustified, when the worktree changed after the last
# green run, or when it is stopping with a dirty tree and no receipt at all.
# Silent no-op for every other agent.
#
# Contract: JTI writes a receipt via jti-receipt.ps1 after a passing gate, or a
# hand-back receipt before returning work to JTPS. Receipts live under
# $TEMP/claude/jti-gate keyed by worktree root and expire after MaxAgeMinutes.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$MaxAgeMinutes = 120
$MaxBlocks = 3

. (Join-Path $PSScriptRoot 'jti-common.ps1')

$script:BlockCountPath = $null

function Exit-Allow { exit 0 }

function Exit-Block([string]$Message) {
    # Loop guard: count the blocks per receipt and let the agent through after
    # MaxBlocks rather than trapping it in a stop-block-stop cycle.
    $count = 0
    if ($script:BlockCountPath -and (Test-Path -LiteralPath $script:BlockCountPath)) {
        # A counter older than the receipt window is from an earlier run; start over.
        if ((Get-Item -LiteralPath $script:BlockCountPath).LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddMinutes(-$MaxAgeMinutes)) {
            Remove-Item -LiteralPath $script:BlockCountPath -Force -ErrorAction SilentlyContinue
        } else {
            [int]::TryParse((Get-Content -LiteralPath $script:BlockCountPath -Raw).Trim(), [ref]$count) | Out-Null
        }
    }
    if ($count -ge $MaxBlocks) {
        [Console]::Error.WriteLine("JTI GATE: blocked $count times already; letting the stop through. The gate is still red -- say so explicitly in the report instead of claiming completion.")
        exit 0
    }
    if ($script:BlockCountPath) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:BlockCountPath) | Out-Null
        Set-Content -LiteralPath $script:BlockCountPath -Value ($count + 1) -NoNewline
    }
    [Console]::Error.WriteLine($Message)
    exit 2
}

function Read-FreshReceipt([string]$Path) {
    try {
        $receipt = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
    $written = 0L
    if (-not [long]::TryParse([string]$receipt.writtenEpoch, [ref]$written)) { return $null }
    $ageMinutes = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $written) / 60
    if ($ageMinutes -gt $MaxAgeMinutes) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ([IO.Path]::ChangeExtension($Path, '.blocks')) -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $receipt
}

function Test-Receipt($Receipt, [string]$ReceiptPath) {
    $script:BlockCountPath = [IO.Path]::ChangeExtension($ReceiptPath, '.blocks')
    $where = "worktree $($Receipt.worktreeRoot), branch $($Receipt.branch)"

    if ($Receipt.status -eq 'handback') { return }

    $failed = @($Receipt.gates | Where-Object { $_.exitCode -ne 0 })
    if ($failed.Count -gt 0) {
        $names = ($failed | ForEach-Object { "$($_.name) (exit $($_.exitCode))" }) -join ', '
        Exit-Block @"
JTI GATE: you are stopping with a red verification gate ($where).

Failing: $names

Fix the failure and re-run the full Phase 3 gate (build, lint, tests, no new
warnings, end-to-end, feature flag off), then write a fresh receipt. If the same
check has now failed three times, stop and report the failing output instead of
looking for another way to make it pass.
"@
    }

    $unjustified = [int]$Receipt.newWarnings - [int]$Receipt.justifiedWarnings
    if ($unjustified -gt 0) {
        Exit-Block @"
JTI GATE: $unjustified unjustified new warning(s) in the last verification run ($where).

Pristine output is part of the gate. Fix them, or -- only if they are genuinely
out of scope -- re-write the receipt with -JustifiedWarnings <n> and a -Note
saying what they are and why they stay, and repeat that note in the final report.
"@
    }

    $root = [string]$Receipt.worktreeRoot
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { return }
    if ($Receipt.treeSha -and $Receipt.treeSha -ne (Get-TreeFingerprint $root)) {
        Exit-Block @"
JTI GATE: the worktree changed after your last green verification run ($where).

Every edit, new file or commit after the last passing gate is unverified. Re-run
the full Phase 3 gate over the current tree and write a fresh receipt before
reporting "done implementing". If you are handing the work back to JTPS instead,
run jti-receipt.ps1 -HandBack -WorktreeRoot <path> first.
"@
    }
}

try {
    $raw = [Console]::In.ReadToEnd()
    $payload = if ([string]::IsNullOrWhiteSpace($raw)) { $null } else { $raw | ConvertFrom-Json }
} catch {
    Exit-Allow
}

# Defensive: the settings.json matcher already scopes this to JTI, but a
# mis-scoped matcher must never gate an unrelated agent.
if ($payload -and $payload.agent_type -and $payload.agent_type -ne 'j-the-implementer') { Exit-Allow }

$receiptDir = Get-StateDir 'jti-gate'

# Preferred: the receipt for the worktree the hook's cwd points at. Fallback: when
# the subagent worked in its own worktree the hook may report the parent session's
# cwd instead, so every fresh receipt is checked -- there is at most a handful, all
# written by JTI runs within the last MaxAgeMinutes.
$cwdRoot = $null
$candidates = @()
$cwd = if ($payload -and $payload.cwd) { $payload.cwd } else { (Get-Location).Path }
if (Test-Path -LiteralPath $cwd) {
    $top = & git -C $cwd rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($top)) {
        $cwdRoot = (Resolve-Path -LiteralPath $top.Trim()).Path
        $keyed = Get-ReceiptPath $cwdRoot
        if (Test-Path -LiteralPath $keyed) { $candidates += $keyed }
    }
}
if ($candidates.Count -eq 0 -and (Test-Path -LiteralPath $receiptDir)) {
    $candidates = @(Get-ChildItem -LiteralPath $receiptDir -Filter '*.json' -File | ForEach-Object { $_.FullName })
}

$checked = 0
foreach ($path in $candidates) {
    $receipt = Read-FreshReceipt $path
    if ($receipt) { $checked++; Test-Receipt $receipt $path }
}

# No receipt anywhere, but JTI is stopping with uncommitted work in the cwd repo:
# it skipped the gate or forgot the receipt. Tracked changes only -- the session
# cwd is usually the main checkout, where untracked .claude/worktrees/ and local
# .env files are normal and would make every stop look dirty.
if ($checked -eq 0 -and $cwdRoot) {
    $dirty = @(& git -C $cwdRoot status --porcelain --untracked-files=no 2>$null | Where-Object { $_ })
    if ($dirty.Count -gt 0) {
        $script:BlockCountPath = [IO.Path]::ChangeExtension((Get-ReceiptPath $cwdRoot), '.blocks')
        Exit-Block @"
JTI GATE: you are stopping with $($dirty.Count) changed file(s) in $cwdRoot and no verification receipt.

Every path -- including trivial fixes -- ends with the Phase 3 gate and a receipt:
  pwsh -NoProfile -File $PSScriptRoot/jti-receipt.ps1 -WorktreeRoot "$cwdRoot" -Gates "build=0,lint=0,test=0" -NewWarnings 0
or, if you are handing the work back to JTPS:
  pwsh -NoProfile -File $PSScriptRoot/jti-receipt.ps1 -WorktreeRoot "$cwdRoot" -HandBack
"@
    }
}

Exit-Allow
