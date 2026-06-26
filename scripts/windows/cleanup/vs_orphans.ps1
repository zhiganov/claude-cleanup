# Find Visual Studio install dirs that vswhere no longer tracks (orphaned installs).
# Output: <displayName>|<sizeMB>|<fullPath>
# With a WizTree CSV, prefer wt_lookup.py for the dir sizes.
$vsRoot = "${env:ProgramFiles(x86)}\Microsoft Visual Studio"
if (-not (Test-Path $vsRoot)) { exit }

$vswhere = Join-Path $vsRoot "Installer\vswhere.exe"
$knownPaths = @()
if (Test-Path $vswhere) {
    $installs = & $vswhere -all -products * -format json 2>$null | ConvertFrom-Json
    foreach ($i in $installs) { $knownPaths += $i.installationPath.ToLower() }
}

Get-ChildItem $vsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{4}$' } |
    ForEach-Object {
        Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($knownPaths -notcontains $_.FullName.ToLower()) {
                $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $mb = [math]::Round($s / 1MB)
                if ($mb -gt 100) {
                    Write-Output "$($_.Parent.Name) $($_.Name)|$mb|$($_.FullName)"
                }
            }
        }
    }
