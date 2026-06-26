# Find old side-by-side Windows SDK versions under Windows Kits\10 (keeps the newest).
# Output: <version>|<sizeMB>|<semicolon-separated Lib;Include;bin paths>
# With a WizTree CSV, prefer wt_lookup.py for the version-path sizes.
$sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10"
if (-not (Test-Path $sdkRoot)) { exit }

$libDir = Join-Path $sdkRoot "Lib"
if (Test-Path $libDir) {
    $versions = Get-ChildItem $libDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.' } |
        Sort-Object Name
    if ($versions.Count -gt 1) {
        $old = $versions | Select-Object -SkipLast 1
        foreach ($v in $old) {
            $totalSize = 0
            foreach ($sub in @("Lib", "Include", "bin")) {
                $vPath = Join-Path $sdkRoot "$sub\$($v.Name)"
                if (Test-Path $vPath) {
                    $s = (Get-ChildItem $vPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    $totalSize += $s
                }
            }
            if ($totalSize -gt 50MB) {
                $mb = [math]::Round($totalSize / 1MB)
                $paths = @("Lib", "Include", "bin") | ForEach-Object {
                    $p = Join-Path $sdkRoot "$_\$($v.Name)"
                    if (Test-Path $p) { $p }
                }
                Write-Output "$($v.Name)|$mb|$($paths -join ';')"
            }
        }
    }
}
