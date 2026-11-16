# Shared by jti-receipt.ps1 (writer), jti-gate.ps1 (checker) and jcrew-ui-lock.ps1. Writer and
# checker must compute the receipt path and the tree fingerprint identically.

# State lives under the user's own ~/.claude, never the shared temp folder: on Linux and macOS
# another user could plant a receipt, a lock or a symlink in /tmp.
function Get-StateDir([string]$Name) {
    $dir = Join-Path $HOME ".claude/state/$Name"
    $created = New-Item -ItemType Directory -Force -Path $dir
    foreach ($item in $created, $created.Parent) {
        if ($item.LinkType) { throw "refusing to use $($item.FullName): it is a link" }
        if (-not $IsWindows) { chmod 700 $item.FullName }
    }
    $dir
}

function Get-Sha256Hex([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    ([Security.Cryptography.SHA256]::Create().ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-ReceiptPath([string]$WorktreeRoot) {
    $normalized = $WorktreeRoot.ToLowerInvariant().Replace('\', '/').TrimEnd('/')
    $key = Get-Sha256Hex $normalized
    Join-Path (Get-StateDir 'jti-gate') "$key.json"
}

# HEAD commit + tracked diff + untracked files (path and content hash), so that a
# commit, an edit, or a new file after the receipt all change the fingerprint.
function Get-TreeFingerprint([string]$WorktreeRoot) {
    $head = (& git -C $WorktreeRoot rev-parse HEAD 2>$null)
    $diff = (& git -C $WorktreeRoot diff HEAD 2>$null) -join "`n"
    $untracked = @(& git -C $WorktreeRoot ls-files --others --exclude-standard 2>$null | Where-Object { $_ })
    $untrackedPart = foreach ($relative in ($untracked | Sort-Object)) {
        $full = Join-Path $WorktreeRoot $relative
        $contentHash = if (Test-Path -LiteralPath $full -PathType Leaf) { (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash } else { 'missing' }
        "$relative=$contentHash"
    }
    Get-Sha256Hex (@([string]$head, $diff) + @($untrackedPart) -join "`n")
}
