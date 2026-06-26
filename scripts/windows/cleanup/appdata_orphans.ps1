# Detect orphaned %APPDATA% / %LOCALAPPDATA% dirs (app uninstalled, data left behind).
# Cross-references against installed programs in the registry. Output: <dirName>|<sizeMB>|<fullPath>
# NOTE: with a WizTree CSV, prefer piping the discovered dirs to wt_lookup.py for sizes
# rather than the Get-ChildItem measurement here. Always require per-item user confirmation
# before deleting -- false positives (portable / manually-installed apps) are common.
$installed = @()
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($rp in $regPaths) {
    Get-ItemProperty $rp -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.DisplayName) { $installed += $_.DisplayName.ToLower() }
        if ($_.InstallLocation) { $installed += (Split-Path $_.InstallLocation -Leaf).ToLower() }
    }
}

$skipDirs = @(
    'microsoft', 'windows', '.net', 'identities', 'adobe', 'intel', 'nvidia',
    'apple', 'sun', 'java', 'oracle', 'nuget', 'python', 'pip', 'npm',
    'node.js', 'git', 'ssh', 'gnupg', 'local', 'locallow', 'roaming',
    'temp', 'temporary internet files', 'packages', 'connecteddevicesplatform',
    'publishers', 'comms', 'windowsapps', 'programs', 'microsoft\windows',
    'claude-cleanup'
)

function Test-Orphaned($dirName) {
    $lower = $dirName.ToLower()
    foreach ($s in $skipDirs) { if ($lower -eq $s -or $lower.StartsWith('.')) { return $false } }
    foreach ($prog in $installed) {
        if ($prog.Contains($lower) -or $lower.Contains($prog.Split(' ')[0])) { return $false }
    }
    return $true
}

$locations = @($env:APPDATA, $env:LOCALAPPDATA)
foreach ($loc in $locations) {
    Get-ChildItem $loc -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-Orphaned $_.Name) {
            $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $mb = [math]::Round($s / 1MB)
            if ($mb -gt 50) {
                Write-Output "$($_.Name)|$mb|$($_.FullName)"
            }
        }
    }
}
