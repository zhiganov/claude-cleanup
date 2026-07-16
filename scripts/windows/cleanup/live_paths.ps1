# Emit filesystem paths that RUNNING processes depend on, so a delete candidate can be
# vetoed on liveness rather than on a proxy for liveness.
#
#   stdout          : one live path per line (feed to assert_list.py --live)
#   stderr, -Summary: Claude Code session count + MCP servers per session
#
# Why (2026-07-16). Git inactivity, registry absence and "no lockfile" are proxies for
# "dead", and they are wrong often enough to destroy things. One /cleanup run produced
# five near-misses and FOUR were caught by a file lock rather than by judgement:
#
#   npm-cache      %LOCALAPPDATA%\npm-cache\_npx\ is where npx -y materialises packages,
#                  so live MCP servers execute from inside it -- one set per session.
#   %TEMP%\claude  Claude Code's own scratch; deleting it killed a Bash call mid-flight.
#   .next          another session's build, 11 minutes old, 1250/1279 files fresh.
#   node_modules   two book-power dirs flagged INACTIVE by git while backing live MCPs.
#
# A path appearing in a running process's command line is live REGARDLESS of what git,
# the registry, or a config file says. That is the only signal that is not a proxy.
#
# Parallel sessions make this sharper, not softer: two sessions were live when the run
# above happened, 12 MCP servers each. Assume another session exists.
[CmdletBinding()]
param([switch]$Summary)

$procs = @{}
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
    $procs[[int]$_.ProcessId] = $_
}

# --resume takes a UUID *or* a quoted session name ("Avails - standing availability epic").
# A bare \S+ capture silently truncates the name at the first space and keeps the opening
# quote -- fine for grouping, wrong for display. Match the quoted form first.
function Get-ResumeId($cmdline) {
    if ($cmdline -match '--resume\s+"([^"]*)"') { return $Matches[1] }
    if ($cmdline -match '--resume\s+(\S+)')     { return $Matches[1] }
    return '(no --resume id)'
}

function Get-OwningSession([int]$id) {
    $seen = @{}; $c = $id
    while ($c -and $procs.ContainsKey($c) -and -not $seen[$c]) {
        $seen[$c] = $true
        $p = $procs[$c]
        if ($p.Name -eq 'claude.exe') { return (Get-ResumeId $p.CommandLine) }
        $c = [int]$p.ParentProcessId
    }
    return $null
}

if ($Summary) {
    $sessions = $procs.Values | Where-Object { $_.Name -eq 'claude.exe' }
    [Console]::Error.WriteLine("claude code sessions live: $($sessions.Count)")
    foreach ($s in $sessions) {
        $id = Get-ResumeId $s.CommandLine
        $mcp = @($procs.Values | Where-Object {
            $_.Name -eq 'node.exe' -and $_.CommandLine -match '_npx|mcp' -and
            (Get-OwningSession([int]$_.ProcessId)) -eq $id
        }).Count
        [Console]::Error.WriteLine("  pid=$($s.ProcessId)  mcp_servers=$mcp  session=$id")
    }
    if ($sessions.Count -gt 1) {
        [Console]::Error.WriteLine("  NOTE: more than one session is live. Every session holds its own set of")
        [Console]::Error.WriteLine("        MCP servers under npm-cache\_npx and its own %TEMP%\claude scratch,")
        [Console]::Error.WriteLine("        and may be mid-build in a project whose git looks cold.")
    }
}

# Windows paths out of every command line: quoted (may contain spaces) and bare.
$out = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($p in $procs.Values) {
    if ($p.ExecutablePath) { [void]$out.Add($p.ExecutablePath) }
    if (-not $p.CommandLine) { continue }
    foreach ($m in [regex]::Matches($p.CommandLine, '"([A-Za-z]:\\[^"]+)"')) {
        [void]$out.Add($m.Groups[1].Value)
    }
    foreach ($m in [regex]::Matches($p.CommandLine, '(?<![":\w])([A-Za-z]:[\\/][^"''\s]+)')) {
        [void]$out.Add($m.Groups[1].Value)
    }
}
# Normalise forward slashes -- node is routinely launched with C:/Users/... style args.
$out | ForEach-Object { $_ -replace '/', '\' } |
    Sort-Object -Unique |
    ForEach-Object { Write-Output $_ }
