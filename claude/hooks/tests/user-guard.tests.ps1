# Table-driven tests for user-guard.ps1. Usage: pwsh -NoProfile -File user-guard.tests.ps1 [-Script <path>]
param([string]$Script = (Join-Path $PSScriptRoot '..\user-guard.ps1'))

$jira = 'mcp__claude_ai_Atlassian_Jira__'
$slack = 'mcp__claude_ai_Slack__'
$cases = @(
    @('deny',  'Bash', 'git add -A'),
    @('deny',  'Bash', 'git add --all'),
    @('deny',  'Bash', 'git add .'),
    @('deny',  'Bash', 'git add ./'),
    @('deny',  'Bash', 'git add -Av'),
    @('deny',  'Bash', 'git add :/'),
    @('deny',  'Bash', 'git add *'),
    @('deny',  'Bash', 'git stage .'),
    @('deny',  'Bash', 'git -C D:/Projects/ATO/core add .'),
    @('deny',  'PowerShell', 'git -C "D:\My Repos\core" add -A'),
    @('deny',  'Bash', 'git -c core.autocrlf=false add . && git commit -m x'),
    @('deny',  'Bash', 'cd tna && git status && git add .'),
    @('allow', 'Bash', 'git add src/Foo.cs tests/FooTests.cs'),
    @('allow', 'Bash', 'git -C D:/Projects/ATO/core add src/Foo.cs'),
    @('allow', 'Bash', 'git add -u'),
    @('allow', 'Bash', 'git add -p src/Foo.cs'),
    @('allow', 'Bash', 'git status'),
    @('allow', 'Bash', 'git commit -m "tidy"'),
    @('deny',  'Bash', 'sqlcmd -S prod-sql.database.windows.net -Q "select 1"'),
    @('allow', 'Bash', 'sqlcmd -S localhost -Q "select 1"'),
    @('ask',   'Bash', 'gh pr review 123 --approve'),
    @('ask',   'Bash', 'gh pr comment 123 --body "x"'),
    @('ask',   'PowerShell', 'gh pr merge 123 --squash'),
    @('ask',   'Bash', 'gh issue comment 5 --body "x"'),
    @('ask',   'Bash', 'gh api repos/o/r/pulls/1/comments -f body=hi'),
    @('ask',   'Bash', 'gh api -X POST repos/o/r/issues/1/comments'),
    @('ask',   'Bash', 'gh api graphql -f query=''mutation { resolveReviewThread(input:{threadId:"x"}) { thread { id } } }'''),
    @('ask',   'Bash', 'gh api graphql -F query=@reply.graphql'),
    @('allow', 'Bash', 'gh pr view 123 --json state'),
    @('allow', 'Bash', 'gh pr list --repo o/r'),
    @('allow', 'Bash', 'gh pr create --draft --title x --body y'),
    @('allow', 'Bash', 'gh api repos/o/r/compare/a...main --jq .ahead_by'),
    @('allow', 'Bash', 'gh api -X GET repos/o/r/pulls -f state=open'),
    @('allow', 'Bash', 'gh api graphql -f query=''query { viewer { login } }'''),
    @('ask',   ($jira + 'jira_issues_transition'), ''),
    @('ask',   ($jira + 'jira_issues_assign'), ''),
    @('ask',   ($jira + 'jira_issues_comment'), ''),
    @('ask',   ($jira + 'jira_issues_create'), ''),
    @('ask',   ($jira + 'jira_issues_update'), ''),
    @('allow', ($jira + 'jira_issues_get'), ''),
    @('allow', ($jira + 'jira_issues_comments_get'), ''),
    @('allow', ($jira + 'jira_search_jql'), ''),
    @('allow', ($jira + 'jira_issue_create_preflight'), ''),
    @('allow', ($jira + 'jira_my_issues'), ''),
    @('ask',   ($slack + 'slack_send_message'), ''),
    @('ask',   ($slack + 'slack_add_list_record'), ''),
    @('allow', ($slack + 'slack_send_message_draft'), ''),
    @('allow', ($slack + 'slack_read_channel'), ''),
    @('allow', 'mcp__context7__query-docs', ''),
    @('allow', 'Read', '')
)

$failed = 0
foreach ($c in $cases) {
    $expected, $tool, $command = $c
    $payload = @{ tool_name = $tool; tool_input = @{ command = $command } } | ConvertTo-Json -Compress
    $out = $payload | pwsh -NoProfile -File $Script 2>$null
    $code = $LASTEXITCODE
    $actual = if ($code -eq 2) { 'deny' } elseif ("$out" -match '"permissionDecision":"ask"') { 'ask' } elseif ($code -eq 0) { 'allow' } else { "exit $code" }
    $label = if ($command) { "$tool :: $command" } else { $tool }
    if ($actual -eq $expected) { "ok    $expected  $label" } else { $failed++; "FAIL  expected $expected got $actual  $label" }
}
"--- $($cases.Count) cases, $failed failed"
exit $failed
