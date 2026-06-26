# Discover Squirrel (Electron) old app versions kept under %LOCALAPPDATA%\<app>\app-*.
# The newest app-* is the live one and is kept; older ones are emitted for removal.
# Output (one per old version):  <app>|<oldVersionDir>|<fullPath>
Get-ChildItem "$env:LOCALAPPDATA" -Directory -ErrorAction SilentlyContinue | Where-Object {
    Test-Path (Join-Path $_.FullName "Update.exe")
} | ForEach-Object {
    $appDirs = Get-ChildItem $_.FullName -Directory -Filter "app-*" -ErrorAction SilentlyContinue | Sort-Object Name
    if ($appDirs.Count -gt 1) {
        $oldDirs = $appDirs | Select-Object -SkipLast 1
        foreach ($d in $oldDirs) {
            Write-Output "$($_.Name)|$($d.Name)|$($d.FullName)"
        }
    }
}
