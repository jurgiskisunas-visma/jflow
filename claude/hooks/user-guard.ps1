# PreToolUse hook: deterministic guards for the mistakes that already cost real damage.
# Registered in ~/.claude/settings.json. Fails open on anything unexpected.
# Complements the ato-safety plugin (destructive DB/git/docker) — no overlap with its patterns.
# Tests: hooks/tests/user-guard.tests.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$payloadText = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($payloadText)) { exit 0 }

try { $payload = $payloadText | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

$tool = [string]$payload.tool_name

function Deny([string]$reason) {
    [Console]::Error.WriteLine($reason)
    exit 2
}

# Outbound actions are never blocked, only handed to the user for a yes.
function Ask([string]$what) {
    $decision = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'ask'
            permissionDecisionReason = "Outbound action: $what. Nothing leaves the machine without your yes."
        }
    }
    [Console]::Out.WriteLine(($decision | ConvertTo-Json -Compress -Depth 4))
    exit 0
}

# 3b. Jira and Slack writes through any MCP connection.
if ($tool -like 'mcp__*') {
    if ($tool -notmatch '(?i)jira|atlassian|slack') { exit 0 }
    $op = $tool -replace '^mcp__.*__', ''
    if ($op -match '(?i)_draft$') { exit 0 }
    $isWrite = $op -match '(?i)^(jira|slack)_(add|update|create|send|schedule|complete)_'
    if (-not $isWrite) {
        if ($op -match '(?i)(^|_)(get|search|list|read|current|preflight|meta|download|draft|lookup|find)(_|$)') { exit 0 }
        $isWrite = $op -match '(?i)(transition|assign|comment|create|update|delete|link|send|schedule|reaction|add|upload|edit)'
    }
    if ($isWrite) { Ask "$op via MCP" }
    exit 0
}

if ($tool -notin @('Bash', 'PowerShell', 'pwsh', 'cmd')) { exit 0 }

$cmd = [string]$payload.tool_input.command
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# 1. git add/stage that sweeps the tree — pulls untracked, non-gitignored secret files into commits.
#    ATO-19012 pushed tna/build/docker/.env (live ghp_ tokens) this way; rotation followed.
#    Global options (-C <dir>, -c k=v, --git-dir=...) may sit between `git` and the subcommand.
$gitAdd = [regex]'(?i)\bgit(?:\.exe)?(?:\s+(?:-[cC]\s+(?:"[^"]*"|''[^'']*''|\S+)|--?[\w-]+(?:=(?:"[^"]*"|\S+))?))*\s+(?:add|stage)\b([^|;&\r\n]*)'
foreach ($m in $gitAdd.Matches($cmd)) {
    $tokens = @($m.Groups[1].Value -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Trim('"', "'") })
    if ($tokens -ccontains '-u' -or $tokens -contains '--update') { continue }
    foreach ($t in $tokens) {
        $sweeps = $t -cmatch '^-[a-zA-Z]*A[a-zA-Z]*$' -or
                  $t -in @('--all', '--no-ignore-removal') -or
                  $t -match '^(\.|\./|\.\\|:/|\*|:\(top\))$'
        if ($sweeps) {
            Deny @'
BLOCKED: `git add` that sweeps the tree (-A, --all, ., ./, :/, *).
ATO repos hold untracked, non-gitignored secret files (tna/build/docker/.env with live
PATs, taxation/docs/local-secrets-*.md). Run `git status`, then stage explicit paths:
  git add <path1> <path2>
'@
        }
    }
}

# 2. sqlcmd against a non-local server — local dev use is routine, remote writes are not.
if ($cmd -match '\bsqlcmd\b') {
    $serverMatch = [regex]::Match($cmd, '(?:-S|--server)\s+"?([^"\s]+)"?')
    if ($serverMatch.Success) {
        $server = $serverMatch.Groups[1].Value
        $isLocal = $server -match '^(?i)(\(localdb\)|localhost|127\.0\.0\.1|\.|\(local\)|tcp:localhost|tcp:127\.0\.0\.1)([\\,].*)?$'
        if (-not $isLocal) {
            Deny "BLOCKED: sqlcmd against non-local server '$server'. Local dev databases only from an agent. Run remote/prod queries yourself, or use a read-only MCP query tool."
        }
    }
}

# 3a. GitHub posts. Wrong-session and over-broad prompts already posted approvals and comments.
$short = if ($cmd.Length -gt 200) { $cmd.Substring(0, 200) + '...' } else { $cmd }

if ($cmd -match '(?i)\bgh(?:\.exe)?\s+pr\s+(review|comment|merge|close)\b') { Ask "gh pr $($Matches[1]) [$short]" }
if ($cmd -match '(?i)\bgh(?:\.exe)?\s+issue\s+(comment|create|close)\b') { Ask "gh issue $($Matches[1]) [$short]" }

$ghApi = [regex]::Match($cmd, '(?i)\bgh(?:\.exe)?\s+api\b([^|;&\r\n]*)')
if ($ghApi.Success) {
    $apiArgs = $ghApi.Groups[1].Value
    $methodMatch = [regex]::Match($apiArgs, '(?i)(?:-X|--method)[\s=]+"?(\w+)')
    $hasFields = $apiArgs -cmatch '(^|\s)(-f|-F|--field|--raw-field|--input)(\s|=)'
    if ($apiArgs -match '(?i)\bgraphql\b') {
        # A mutation kept in a file cannot be read here, so a file-fed query asks too.
        if ($apiArgs -match '(?i)mutation' -or $apiArgs -match '=@') { Ask "gh api graphql write [$short]" }
    }
    elseif ($methodMatch.Success) {
        if ($methodMatch.Groups[1].Value -ne 'GET') { Ask "gh api $($methodMatch.Groups[1].Value.ToUpper()) [$short]" }
    }
    elseif ($hasFields) { Ask "gh api with fields, POST by default [$short]" }
}

exit 0
