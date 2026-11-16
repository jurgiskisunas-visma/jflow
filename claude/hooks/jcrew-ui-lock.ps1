# One UI-validation slot per project root (the folder that holds the project's main checkout).
#
# The main checkout, its build, its running services and the browser are one
# shared unit per project. Whoever holds the lock may touch them; everyone else
# waits. Locks live under $TEMP/claude/jcrew-locks, one file per project root.
#
#   -Acquire  blocks (polling, one status line per poll) until the slot is free,
#             then takes it. Exit 0 = held. Exit 3 = gave up after -TimeoutMinutes.
#   -Release  frees the slot if this task holds it. Always exit 0.
#   -Status   prints who holds it, or "free". Exit 0.
#
# Usage:
#   pwsh -NoProfile -File ~/.claude/hooks/jcrew-ui-lock.ps1 -Acquire -ProjectRoot <project root> -Task PROJ-123
#   pwsh -NoProfile -File ~/.claude/hooks/jcrew-ui-lock.ps1 -Release -ProjectRoot <project root> -Task PROJ-123

[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [string]$Task = '',
    [Parameter(ParameterSetName = 'Acquire')][switch]$Acquire,
    [Parameter(ParameterSetName = 'Release')][switch]$Release,
    [Parameter(ParameterSetName = 'Status')][switch]$Status,
    [int]$PollSeconds = 30,
    [int]$TimeoutMinutes = 180,
    [int]$StaleMinutes = 150
)

$ErrorActionPreference = 'Stop'

function Get-Sha256Hex([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    ([Security.Cryptography.SHA256]::Create().ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
}

$normalized = (Resolve-Path -LiteralPath $ProjectRoot).Path.ToLowerInvariant().Replace('\', '/').TrimEnd('/')
$lockDir = Join-Path ([IO.Path]::GetTempPath()) 'claude/jcrew-locks'
$lockPath = Join-Path $lockDir "$(Get-Sha256Hex $normalized).lock"
New-Item -ItemType Directory -Force -Path $lockDir | Out-Null

function Read-Lock {
    if (-not (Test-Path -LiteralPath $lockPath)) { return $null }
    try { return Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json } catch { return $null }
}

function Lock-AgeMinutes($lock) {
    ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$lock.acquiredEpoch) / 60
}

function Try-Acquire {
    # New-Item without -Force fails when the file exists: an atomic create.
    try {
        $content = [ordered]@{
            task          = $Task
            projectRoot   = $normalized
            acquiredEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            pid           = $PID
        } | ConvertTo-Json
        New-Item -ItemType File -Path $lockPath -Value $content -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

if ($Release) {
    $lock = Read-Lock
    if ($lock -and $lock.task -eq $Task) {
        Remove-Item -LiteralPath $lockPath -Force
        Write-Output "released: $Task ($normalized)"
    } elseif ($lock) {
        Write-Output "not released: slot held by $($lock.task), not $Task"
    } else {
        Write-Output "released: slot was already free"
    }
    exit 0
}

if ($Acquire) {
    if (-not $Task) { throw 'Pass -Task <key> with -Acquire.' }
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    # Check, takeover and create run under one mutex: two waiters that both saw a stale lock used to both get in.
    $mutex = [Threading.Mutex]::new($false, "Global\jcrew-ui-lock-$(Get-Sha256Hex $normalized)")
    while ($true) {
        try { [void]$mutex.WaitOne() } catch [Threading.AbandonedMutexException] { }
        try {
            $lock = Read-Lock
            if ($lock -and $lock.task -eq $Task) { Write-Output "held: $Task already holds the slot"; exit 0 }
            if ($lock -and (Lock-AgeMinutes $lock) -gt $StaleMinutes) {
                Write-Output "stale: $($lock.task) held the slot for $([int](Lock-AgeMinutes $lock)) min; taking it over"
                Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
            }
            # An empty or unreadable lock file has no holder to wait for.
            $file = Get-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue
            if (-not $lock -and $file -and $file.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddMinutes(-2)) {
                Write-Output 'stale: unreadable lock file; removing it'
                Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
            }
            if (Try-Acquire) { Write-Output "acquired: $Task ($normalized)"; exit 0 }
        } finally {
            $mutex.ReleaseMutex()
        }
        $lock = Read-Lock
        $holder = if ($lock) { "$($lock.task), $([int](Lock-AgeMinutes $lock)) min" } else { 'unknown' }
        Write-Output "waiting: slot held by $holder; retry in ${PollSeconds}s"
        if ((Get-Date) -gt $deadline) { Write-Output "timeout: gave up after $TimeoutMinutes min"; exit 3 }
        Start-Sleep -Seconds $PollSeconds
    }
}

$lock = Read-Lock
if ($lock) { Write-Output "held by $($lock.task) for $([int](Lock-AgeMinutes $lock)) min ($normalized)" } else { Write-Output "free ($normalized)" }
exit 0
