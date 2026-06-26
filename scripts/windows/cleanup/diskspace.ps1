# Report "free total pct" (GB, GB, %) for a drive. Defaults to the system drive.
# Run:  powershell.exe -NoProfile -File diskspace.ps1 [C]
param([string]$Drive)
if (-not $Drive) { $Drive = $env:SystemDrive }   # e.g. "C:"
$letter = $Drive.Substring(0, 1)
$d = Get-PSDrive $letter
$free  = [math]::Round($d.Free / 1GB, 1)
$total = [math]::Round(($d.Used + $d.Free) / 1GB, 1)
$pct   = [math]::Round($d.Used / ($d.Used + $d.Free) * 100)
Write-Output "$free $total $pct"
