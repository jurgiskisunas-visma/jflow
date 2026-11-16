$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$input_json = [Console]::In.ReadToEnd()
$data = $input_json | ConvertFrom-Json

# Session start location (where the session was launched), not the current cwd.
$loc = $data.workspace.current_dir
if (-not $loc) { $loc = $data.workspace.project_dir }
if (-not $loc) { $loc = $data.cwd }
$home_dir = $HOME
if ($loc -and $home_dir -and $loc.StartsWith($home_dir)) {
    $loc = '~' + $loc.Substring($home_dir.Length)
}
if ($loc) { $loc = $loc -replace '\\', '/' }

$model = $data.model.display_name
$used  = [double]$data.context_window.used_percentage

# ANSI color helpers
$e = [char]27
function Color($text, $code) { "$e[${code}m$text$e[0m" }

# Build a 10-cell bar using block characters; final cell uses a partial block
# so the bar reflects fractional progress smoothly.
function Bar([double]$pct, [int]$width = 10) {
    if ($pct -lt 0)   { $pct = 0 }
    if ($pct -gt 100) { $pct = 100 }
    $blocks = @(' ', "$([char]0x258F)", "$([char]0x258E)", "$([char]0x258D)", "$([char]0x258C)", "$([char]0x258B)", "$([char]0x258A)", "$([char]0x2589)", "$([char]0x2588)")
    $full_units = $pct / 100.0 * $width
    $full = [int][math]::Floor($full_units)
    $remainder = $full_units - $full
    $partial_index = [int][math]::Round($remainder * 8)
    $bar = ''
    for ($i = 0; $i -lt $full; $i++) { $bar += $blocks[8] }
    if ($full -lt $width) {
        $bar += $blocks[$partial_index]
        for ($i = $full + 1; $i -lt $width; $i++) { $bar += ' ' }
    }
    return $bar
}

# Color the bar by usage: green < 50, yellow 50-80, red > 80.
if ($used -lt 50)      { $bar_color = '38;5;42' }   # green
elseif ($used -lt 80)  { $bar_color = '38;5;220' }  # yellow
else                   { $bar_color = '38;5;203' }  # red

$sep = Color "$([char]0x2502)" '38;5;240'
$dir_icon  = Color "$([char]0x1F4C1)" '38;5;39'
$model_icon = Color "$([char]0x2728)" '38;5;213'
$ctx_icon  = Color "$([char]0x1F9E0)" '38;5;245'
$branch_icon = Color "$([char]0x2387)" '38;5;208'

$branch = $null
$git_dir = $data.cwd
if (-not $git_dir) { $git_dir = $data.workspace.current_dir }
if ($git_dir) {
    $branch = (& git -C $git_dir rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $branch = $null }
}

$loc_str   = Color $loc '38;5;39'
$model_str = if ($model) { Color $model '38;5;213' } else { '' }

$bracket = Color '[' '38;5;240'
$bracket_r = Color ']' '38;5;240'
$bar_str = "$bracket" + (Color (Bar $used 10) $bar_color) + "$bracket_r"
$pct_str = Color ("{0,3:N0}%" -f $used) $bar_color

$parts = @()
if ($loc)    { $parts += "$dir_icon $loc_str" }
if ($branch) { $parts += "$branch_icon " + (Color $branch '38;5;208') }
if ($model)  { $parts += "$model_icon $model_str" }
$parts += "$ctx_icon $bar_str $pct_str"

[Console]::Out.Write(($parts -join " $sep "))
