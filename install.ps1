# Sets up a machine for jflow: tools, Claude Code plugins, personal Claude files, the jplan tool
# and the planning root. Safe to re-run; existing files that differ are backed up first.
#
#   pwsh -File install.ps1                      full setup
#   pwsh -File install.ps1 -PlanningRoot E:\plans    put the task ledger somewhere else (remembered for later runs)
#   pwsh -File install.ps1 -SkipTools -SkipPlugins   only sync the repo's files into ~/.claude and rebuild jplan
#   pwsh -File install.ps1 -WhatIf              show what would change

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PlanningRoot,
    [switch]$SkipTools,
    [switch]$SkipPlugins
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$claudeHome = Join-Path $HOME '.claude'
$configPath = Join-Path $claudeHome 'jflow.json'

# Same order as jplan: environment, then the config file, then the home folder.
if (-not $PlanningRoot) { $PlanningRoot = [Environment]::GetEnvironmentVariable('JPLAN_ROOT', 'User') }
if (-not $PlanningRoot -and (Test-Path $configPath)) { $PlanningRoot = (Get-Content $configPath -Raw | ConvertFrom-Json).planningRoot }
if (-not $PlanningRoot) { $PlanningRoot = Join-Path $HOME 'project-planning' }
$PlanningRoot = [IO.Path]::GetFullPath($PlanningRoot)
$manifest = Get-Content (Join-Path $repo 'plugins.json') -Raw | ConvertFrom-Json
$problems = [Collections.Generic.List[string]]::new()

function Step([string]$text) { Write-Host "== $text" }

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw 'Claude Code is not installed. Install it first (https://claude.com/claude-code), sign in, then re-run.'
}

if (-not $SkipTools) {
    Step 'Tools'
    foreach ($tool in $manifest.tools) {
        if (Get-Command $tool.command -ErrorAction SilentlyContinue) { Write-Host "ok       $($tool.command)"; continue }
        if ($PSCmdlet.ShouldProcess($tool.winget, 'winget install')) {
            winget install --id $tool.winget --silent --accept-package-agreements --accept-source-agreements | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "installed $($tool.command)" } else { $problems.Add("winget install $($tool.winget) failed") }
        }
    }
    # Pick up what winget just put on PATH, so the jplan build below works in this same run.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    foreach ($cmd in $manifest.languageServers) { Write-Host "manual   $cmd" }
}

if (-not $SkipPlugins) {
    Step 'Marketplaces and plugins'
    $known = (claude plugin marketplace list 2>&1) -join "`n"
    foreach ($m in $manifest.marketplaces) {
        if ($known -match [regex]::Escape($m.name)) { Write-Host "ok       marketplace $($m.name)"; continue }
        if ($PSCmdlet.ShouldProcess($m.source, 'claude plugin marketplace add')) {
            claude plugin marketplace add $m.source 2>&1 | Select-Object -Last 1 | Write-Host
            if ($LASTEXITCODE -ne 0) { $problems.Add("marketplace $($m.name) not added") }
        }
    }
    $installed = (claude plugin list 2>&1) -join "`n"
    foreach ($p in $manifest.plugins) {
        if ($installed -match [regex]::Escape($p)) { Write-Host "ok       $p"; continue }
        if ($PSCmdlet.ShouldProcess($p, 'claude plugin install')) {
            claude plugin install $p 2>&1 | Select-Object -Last 1 | Write-Host
            if ($LASTEXITCODE -ne 0) { $problems.Add("plugin $p not installed") }
        }
    }
}

Step 'Personal Claude files'
$backup = Join-Path $claudeHome ("backups\jflow-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$source = Join-Path $repo 'claude'
foreach ($file in Get-ChildItem $source -Recurse -File) {
    $relative = $file.FullName.Substring($source.Length + 1)
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

Step 'Hooks in settings.json'
$settingsPath = Join-Path $claudeHome 'settings.json'
$hookRoot = ($claudeHome -replace '\\', '/') + '/hooks'
$settingsText = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw } else { '{}' }
if ($settingsText -match 'user-guard\.ps1' -and $settingsText -match 'jti-gate\.ps1' -and $settingsText -match '\[Jj\]ira') {
    Write-Host 'ok       hooks already registered'
} elseif ($PSCmdlet.ShouldProcess($settingsPath, 'register hooks')) {
    $settings = $settingsText | ConvertFrom-Json -AsHashtable
    if (-not $settings.hooks) { $settings.hooks = @{} }
    $guard = @{ matcher = 'Bash|PowerShell|mcp__.*([Jj]ira|[Aa]tlassian|[Ss]lack).*'; hooks = @(@{ type = 'command'; command = "pwsh -NoProfile -File $hookRoot/user-guard.ps1" }) }
    $gate = @{ matcher = 'jurgis-the-implementer'; hooks = @(@{ type = 'command'; command = "pwsh -NoProfile -File $hookRoot/jti-gate.ps1" }) }
    $settings.hooks.PreToolUse = @(@($settings.hooks.PreToolUse) | Where-Object { $_ -and ($_ | ConvertTo-Json -Depth 6) -notmatch 'user-guard' }) + $guard
    $settings.hooks.SubagentStop = @(@($settings.hooks.SubagentStop) | Where-Object { $_ -and ($_ | ConvertTo-Json -Depth 6) -notmatch 'jti-gate' }) + $gate
    if (-not $settings.statusLine -and (Test-Path (Join-Path $claudeHome 'statusline-command.ps1'))) {
        $settings.statusLine = @{ type = 'command'; command = "pwsh -NoProfile -File $(($claudeHome -replace '\\','/'))/statusline-command.ps1" }
    }
    if (Test-Path $settingsPath) { Copy-Item $settingsPath "$settingsPath.bak" -Force }
    $settings | ConvertTo-Json -Depth 30 | Set-Content $settingsPath -Encoding utf8
    Write-Host 'registered hooks (previous file kept as settings.json.bak)'
}

Step 'jplan'
$bin = Join-Path $claudeHome 'bin'
$go = (Get-Command go -ErrorAction SilentlyContinue)?.Source ?? 'C:\Program Files\Go\bin\go.exe'
if (-not (Test-Path $go) -and (Get-Command winget -ErrorAction SilentlyContinue) -and $PSCmdlet.ShouldProcess('GoLang.Go', 'winget install')) {
    winget install --id GoLang.Go --silent --accept-package-agreements --accept-source-agreements | Out-Null
}
if ($PSCmdlet.ShouldProcess($configPath, "set planningRoot to $PlanningRoot")) {
    @{ planningRoot = $PlanningRoot } | ConvertTo-Json | Set-Content $configPath -Encoding utf8
    Write-Host "planning root: $PlanningRoot"
    if ([Environment]::GetEnvironmentVariable('JPLAN_ROOT', 'User')) { [Environment]::SetEnvironmentVariable('JPLAN_ROOT', $PlanningRoot, 'User') }
}
if (-not (Test-Path $go)) {
    $problems.Add('go not found and winget could not install it; install Go (https://go.dev/dl) and re-run to build jplan')
} elseif ($PSCmdlet.ShouldProcess((Join-Path $bin 'jplan.exe'), 'build')) {
    New-Item -ItemType Directory -Force $bin | Out-Null
    & $go test -C (Join-Path $repo 'jplan') ./... | Select-Object -Last 1 | Write-Host
    if ($LASTEXITCODE -ne 0) { $problems.Add('jplan tests failed') }
    & $go build -C (Join-Path $repo 'jplan') -ldflags '-s -w' -o (Join-Path $bin 'jplan.exe') .
    if ($LASTEXITCODE -ne 0) { $problems.Add('jplan build failed') }
    # Earlier versions kept the binary inside the planning root; that PATH entry would shadow the new one.
    $oldBin = Join-Path $PlanningRoot '_tools\bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $oldBin })
    if ($entries -notcontains $bin) { $entries += $bin }
    if (($entries -join ';') -ne $userPath.TrimEnd(';')) {
        [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
        Write-Host "user PATH now has $bin (open a new terminal)"
    }
}

Step 'Planning root'
$profiles = Join-Path $PlanningRoot '_profiles'
if ($PSCmdlet.ShouldProcess($profiles, 'create and seed missing profiles')) {
    New-Item -ItemType Directory -Force $profiles | Out-Null
    foreach ($file in Get-ChildItem (Join-Path $repo 'profiles') -File) {
        $target = Join-Path $profiles $file.Name
        if (-not (Test-Path $target)) { Copy-Item $file.FullName $target; Write-Host "seeded   $($file.Name)" }
    }
}

Step 'Hook tests'
if ($PSCmdlet.ShouldProcess('user-guard.tests.ps1', 'run')) {
    pwsh -NoProfile -File (Join-Path $claudeHome 'hooks\tests\user-guard.tests.ps1') | Select-Object -Last 1 | Write-Host
    if ($LASTEXITCODE -ne 0) { $problems.Add('hook tests failed') }
}

Step 'Result'
if ($problems.Count) { $problems | ForEach-Object { Write-Host "PROBLEM  $_" }; exit 1 }
Write-Host 'done. Restart Claude Code. Manual steps left: see "Not automated" in README.md.'
