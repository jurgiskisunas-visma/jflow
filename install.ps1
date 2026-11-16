# Sets up a machine for jflow: tools, Claude Code plugins, Claude files, the jplan tool and the
# planning root. Runs on Windows, macOS and Linux under PowerShell 7 (pwsh). Safe to re-run;
# existing files that differ are backed up first.
#
#   pwsh -File install.ps1                      core setup: the flow, jplan, hooks and the plugins the flow needs
#   pwsh -File install.ps1 -PluginSets ato      also the plugins, marketplaces, skills and tools of a set
#   pwsh -File install.ps1 -Personal            the owner's machine: all sets, and personal/CLAUDE.md replaces ~/.claude/CLAUDE.md
#   pwsh -File install.ps1 -PlanningRoot ~/plans     put the task ledger somewhere else (remembered for later runs)
#   pwsh -File install.ps1 -SkipTools -SkipPlugins   only sync the repo's files into ~/.claude and rebuild jplan
#   pwsh -File install.ps1 -WhatIf              show what would change

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PlanningRoot,
    [string[]]$PluginSets = @(),
    [switch]$Personal,
    [switch]$SkipTools,
    [switch]$SkipPlugins
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$claudeHome = Join-Path $HOME '.claude'
$configPath = Join-Path $claudeHome 'jflow.json'

function Step([string]$text) { Write-Host "== $text" }
function Get-UserEnv([string]$name) { if ($IsWindows) { [Environment]::GetEnvironmentVariable($name, 'User') } else { [Environment]::GetEnvironmentVariable($name) } }

# Same order as jplan: environment, then the config file, then the home folder.
if (-not $PlanningRoot) { $PlanningRoot = Get-UserEnv 'JPLAN_ROOT' }
if (-not $PlanningRoot -and (Test-Path $configPath)) { $PlanningRoot = (Get-Content $configPath -Raw | ConvertFrom-Json).planningRoot }
if (-not $PlanningRoot) { $PlanningRoot = Join-Path $HOME 'project-planning' }
if ($PlanningRoot -match '^~[\\/]') { $PlanningRoot = Join-Path $HOME $PlanningRoot.Substring(2) }
$PlanningRoot = [IO.Path]::GetFullPath($PlanningRoot)
$manifest = Get-Content (Join-Path $repo 'plugins.json') -Raw | ConvertFrom-Json
$problems = [Collections.Generic.List[string]]::new()
$sets = @('core') + @($PluginSets | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Personal) { $sets = @($manifest.plugins.PSObject.Properties.Name) }

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw 'Claude Code is not installed. Install it first (https://claude.com/claude-code), sign in, then re-run.'
}

# Returns $true when the tool was installed. Windows uses winget, macOS uses Homebrew; Linux has no
# single package manager, so a missing tool is reported with its name.
function Install-Tool($tool) {
    if ($IsWindows -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        winget install --id $tool.winget --silent --accept-package-agreements --accept-source-agreements | Out-Null
        return $LASTEXITCODE -eq 0
    }
    if ($IsMacOS -and $tool.brew -and (Get-Command brew -ErrorAction SilentlyContinue)) {
        brew install $tool.brew | Out-Null
        return $LASTEXITCODE -eq 0
    }
    return $false
}

function Update-SessionPath {
    if ($IsWindows) { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }
}

# Go is only needed to build jplan, so on macOS and Linux a private copy under ~/.claude/tools is enough.
function Install-GoLocal {
    $os = if ($IsMacOS) { 'darwin' } else { 'linux' }
    $arch = if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'amd64' }
    $release = (Invoke-RestMethod 'https://go.dev/dl/?mode=json')[0].files | Where-Object { $_.os -eq $os -and $_.arch -eq $arch -and $_.kind -eq 'archive' } | Select-Object -First 1
    if (-not $release) { return $null }
    $tools = Join-Path $claudeHome 'tools'
    $archive = Join-Path ([IO.Path]::GetTempPath()) $release.filename
    New-Item -ItemType Directory -Force $tools | Out-Null
    Invoke-WebRequest "https://go.dev/dl/$($release.filename)" -OutFile $archive
    if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $release.sha256) { Remove-Item $archive; throw "checksum mismatch for $($release.filename)" }
    tar -xzf $archive -C $tools
    Remove-Item $archive
    Join-Path $tools 'go/bin/go'
}

function Find-Go {
    $candidates = @((Get-Command go -ErrorAction SilentlyContinue)?.Source, 'C:\Program Files\Go\bin\go.exe', '/usr/local/go/bin/go', '/opt/homebrew/bin/go', (Join-Path $claudeHome 'tools/go/bin/go'))
    $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

if (-not $SkipTools) {
    Step 'Tools'
    foreach ($tool in $manifest.tools | Where-Object { $sets -contains $_.set -and $_.command -ne 'go' }) {
        if (Get-Command $tool.command -ErrorAction SilentlyContinue) { Write-Host "ok       $($tool.command)"; continue }
        if ($PSCmdlet.ShouldProcess($tool.command, 'install')) {
            if (Install-Tool $tool) { Write-Host "installed $($tool.command)" } else { $problems.Add("$($tool.command) is missing and could not be installed automatically; install it and re-run") }
        }
    }
    Update-SessionPath
    if ($sets -contains 'personal') { foreach ($cmd in $manifest.languageServers) { Write-Host "manual   $cmd" } }
}

if (-not $SkipPlugins) {
    Step 'Marketplaces and plugins'
    $known = (claude plugin marketplace list 2>&1) -join "`n"
    foreach ($m in $manifest.marketplaces | Where-Object { $sets -contains $_.set }) {
        if ($known -match [regex]::Escape($m.name)) { Write-Host "ok       marketplace $($m.name)"; continue }
        if ($PSCmdlet.ShouldProcess($m.source, 'claude plugin marketplace add')) {
            claude plugin marketplace add $m.source 2>&1 | Select-Object -Last 1 | Write-Host
            if ($LASTEXITCODE -ne 0) { $problems.Add("marketplace $($m.name) not added") }
        }
    }
    $installed = (claude plugin list 2>&1) -join "`n"
    foreach ($p in $sets | ForEach-Object { $manifest.plugins.$_ }) {
        if ($installed -match [regex]::Escape($p)) { Write-Host "ok       $p"; continue }
        if ($PSCmdlet.ShouldProcess($p, 'claude plugin install')) {
            claude plugin install $p 2>&1 | Select-Object -Last 1 | Write-Host
            if ($LASTEXITCODE -ne 0) { $problems.Add("plugin $p not installed") }
        }
    }
}

Step 'Claude files'
$backup = Join-Path $claudeHome ('backups/jflow-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
# A set's own files (sets/<set>/claude) are installed only when that set is selected.
$sources = @(Join-Path $repo 'claude') + @($sets | ForEach-Object { Join-Path $repo "sets/$_/claude" } | Where-Object { Test-Path $_ })
foreach ($source in $sources) {
    $sourceRoot = (Resolve-Path $source).Path
    foreach ($file in Get-ChildItem $sourceRoot -Recurse -File) {
        $relative = $file.FullName.Substring($sourceRoot.Length + 1)
        $target = Join-Path $claudeHome $relative
        if (Test-Path $target) {
            if ((Get-FileHash $target).Hash -eq (Get-FileHash $file.FullName).Hash) { continue }
            if ($PSCmdlet.ShouldProcess($target, 'back up and replace')) {
                $kept = Join-Path $backup $relative
                New-Item -ItemType Directory -Force (Split-Path $kept) | Out-Null
                Copy-Item $target $kept
            }
        }
        if ($PSCmdlet.ShouldProcess($target, 'copy')) {
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item $file.FullName $target -Force
            Write-Host "copied   $relative"
        }
    }
}

Step 'CLAUDE.md'
$claudeMd = Join-Path $claudeHome 'CLAUDE.md'
$import = '@~/.claude/jflow-rules.md'
if ($Personal) {
    $mine = Join-Path $repo 'personal/CLAUDE.md'
    if (-not (Test-Path $claudeMd) -or (Get-FileHash $claudeMd).Hash -ne (Get-FileHash $mine).Hash) {
        if ($PSCmdlet.ShouldProcess($claudeMd, 'back up and replace with personal/CLAUDE.md')) {
            if (Test-Path $claudeMd) { New-Item -ItemType Directory -Force $backup | Out-Null; Copy-Item $claudeMd (Join-Path $backup 'CLAUDE.md') }
            Copy-Item $mine $claudeMd -Force
            Write-Host 'copied   personal/CLAUDE.md'
        }
    }
} elseif ((Test-Path $claudeMd) -and (Get-Content $claudeMd -Raw) -match [regex]::Escape($import)) {
    Write-Host 'ok       CLAUDE.md imports jflow-rules.md'
} elseif ($PSCmdlet.ShouldProcess($claudeMd, 'add the jflow-rules.md import')) {
    Add-Content $claudeMd "`n$import" -Encoding utf8
    Write-Host 'added the jflow-rules.md import to CLAUDE.md (your own rules are untouched)'
}

Step 'Old names'
$renames = @{ 'agents/jurgis-the-implementer.md' = 'agents/j-the-implementer.md'; 'agents/jurgis-the-problem-solver.md' = 'agents/j-the-problem-solver.md'; 'skills/jurgis-crew' = 'skills/j-crew' }
foreach ($old in $renames.Keys) {
    $oldPath = Join-Path $claudeHome $old
    if ((Test-Path $oldPath) -and (Test-Path (Join-Path $claudeHome $renames[$old])) -and $PSCmdlet.ShouldProcess($oldPath, 'move to backup')) {
        $kept = Join-Path $backup $old
        New-Item -ItemType Directory -Force (Split-Path $kept) | Out-Null
        Move-Item $oldPath $kept
        Write-Host "retired  $old"
    }
}
$oldPlans = Join-Path $claudeHome 'jurgis'
if ((Test-Path $oldPlans) -and -not (Test-Path (Join-Path $claudeHome 'j')) -and $PSCmdlet.ShouldProcess($oldPlans, 'rename to j')) {
    Rename-Item $oldPlans 'j'
    Write-Host 'renamed  ~/.claude/jurgis to ~/.claude/j'
}

Step 'Hooks in settings.json'
$settingsPath = Join-Path $claudeHome 'settings.json'
$claudeHomeSlash = $claudeHome -replace '\\', '/'
$settingsText = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw } else { '{}' }
if ($settingsText -match 'user-guard\.ps1' -and $settingsText -match 'jti-gate\.ps1' -and $settingsText -match '\[Jj\]ira' -and $settingsText -match '"j-the-implementer"') {
    Write-Host 'ok       hooks already registered'
} elseif ($PSCmdlet.ShouldProcess($settingsPath, 'register hooks')) {
    $settings = $settingsText | ConvertFrom-Json -AsHashtable
    if (-not $settings.hooks) { $settings.hooks = @{} }
    $guard = @{ matcher = 'Bash|PowerShell|mcp__.*([Jj]ira|[Aa]tlassian|[Ss]lack).*'; hooks = @(@{ type = 'command'; command = "pwsh -NoProfile -File $claudeHomeSlash/hooks/user-guard.ps1" }) }
    $gate = @{ matcher = 'j-the-implementer'; hooks = @(@{ type = 'command'; command = "pwsh -NoProfile -File $claudeHomeSlash/hooks/jti-gate.ps1" }) }
    $settings.hooks.PreToolUse = @(@($settings.hooks.PreToolUse) | Where-Object { $_ -and ($_ | ConvertTo-Json -Depth 6) -notmatch 'user-guard' }) + $guard
    $settings.hooks.SubagentStop = @(@($settings.hooks.SubagentStop) | Where-Object { $_ -and ($_ | ConvertTo-Json -Depth 6) -notmatch 'jti-gate' }) + $gate
    if (-not $settings.statusLine -and (Test-Path (Join-Path $claudeHome 'statusline-command.ps1'))) {
        $settings.statusLine = @{ type = 'command'; command = "pwsh -NoProfile -File $claudeHomeSlash/statusline-command.ps1" }
    }
    if (Test-Path $settingsPath) { Copy-Item $settingsPath "$settingsPath.bak" -Force }
    $settings | ConvertTo-Json -Depth 30 | Set-Content $settingsPath -Encoding utf8
    Write-Host 'registered hooks (previous file kept as settings.json.bak)'
}

Step 'jplan'
$bin = Join-Path $claudeHome 'bin'
$jplan = Join-Path $bin ($IsWindows ? 'jplan.exe' : 'jplan')
if ($PSCmdlet.ShouldProcess($configPath, "set planningRoot to $PlanningRoot")) {
    New-Item -ItemType Directory -Force $claudeHome | Out-Null
    @{ planningRoot = $PlanningRoot } | ConvertTo-Json | Set-Content $configPath -Encoding utf8
    Write-Host "planning root: $PlanningRoot"
    if ($IsWindows -and (Get-UserEnv 'JPLAN_ROOT')) { [Environment]::SetEnvironmentVariable('JPLAN_ROOT', $PlanningRoot, 'User') }
}
$go = Find-Go
if (-not $go -and $PSCmdlet.ShouldProcess('Go', 'install')) {
    $goTool = $manifest.tools | Where-Object command -eq 'go'
    if (Install-Tool $goTool) { Update-SessionPath; $go = Find-Go }
    elseif (-not $IsWindows) { try { $go = Install-GoLocal } catch { Write-Host "go download failed: $_" } }
}
if (-not $go) {
    $problems.Add('Go is missing and could not be installed automatically; install it (https://go.dev/dl) and re-run to build jplan')
} elseif ($PSCmdlet.ShouldProcess($jplan, 'build')) {
    New-Item -ItemType Directory -Force $bin | Out-Null
    & $go test -C (Join-Path $repo 'jplan') ./... | Select-Object -Last 1 | Write-Host
    if ($LASTEXITCODE -ne 0) { $problems.Add('jplan tests failed') }
    & $go build -C (Join-Path $repo 'jplan') -ldflags '-s -w' -o $jplan .
    if ($LASTEXITCODE -ne 0) { $problems.Add('jplan build failed') }
    if ($IsWindows) {
        # Earlier versions kept the binary inside the planning root; that PATH entry would shadow the new one.
        $oldBin = Join-Path $PlanningRoot '_tools\bin'
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $entries = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $oldBin })
        if ($entries -notcontains $bin) { $entries += $bin }
        if (($entries -join ';') -ne $userPath.TrimEnd(';')) {
            [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
            Write-Host "user PATH now has $bin (open a new terminal)"
        }
    } else {
        $line = 'export PATH="$HOME/.claude/bin:$PATH"  # jflow'
        $rcFiles = @('.zshrc', '.bashrc', '.profile') | ForEach-Object { Join-Path $HOME $_ } | Where-Object { Test-Path $_ }
        if (-not $rcFiles) { $rcFiles = @(Join-Path $HOME '.profile') }
        foreach ($rc in $rcFiles) {
            if ((Test-Path $rc) -and (Get-Content $rc -Raw) -match '\.claude/bin') { continue }
            Add-Content $rc "`n$line"
            Write-Host "added ~/.claude/bin to PATH in $rc (open a new terminal)"
        }
    }
}

Step 'Planning root'
$profiles = Join-Path $PlanningRoot '_profiles'
if ($PSCmdlet.ShouldProcess($profiles, 'create and seed missing profiles')) {
    New-Item -ItemType Directory -Force $profiles | Out-Null
    $seeds = $sets | ForEach-Object { Join-Path $repo "sets/$_/profiles" } | Where-Object { Test-Path $_ }
    foreach ($file in $seeds | ForEach-Object { Get-ChildItem $_ -File }) {
        $target = Join-Path $profiles $file.Name
        if (-not (Test-Path $target)) { Copy-Item $file.FullName $target; Write-Host "seeded   $($file.Name)" }
    }
}

Step 'Hook tests'
if ($PSCmdlet.ShouldProcess('user-guard.tests.ps1', 'run')) {
    pwsh -NoProfile -File (Join-Path $claudeHome 'hooks/tests/user-guard.tests.ps1') | Select-Object -Last 1 | Write-Host
    if ($LASTEXITCODE -ne 0) { $problems.Add('hook tests failed') }
}

Step 'Result'
if ($problems.Count) { $problems | ForEach-Object { Write-Host "PROBLEM  $_" }; exit 1 }
Write-Host 'done. Restart Claude Code. Manual steps left: see "Not automated" in README.md.'
