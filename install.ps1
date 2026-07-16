$RepoUrl = "https://raw.githubusercontent.com/zhiganov/claude-cleanup/master"
$ClaudeDir = "$env:USERPROFILE\.claude"

Write-Host "Installing claude-cleanup..."

New-Item -ItemType Directory -Force -Path "$ClaudeDir\commands" | Out-Null
Invoke-WebRequest -Uri "$RepoUrl/.claude/commands/cleanup.md" -OutFile "$ClaudeDir\commands\cleanup.md"
Write-Host "Installed cleanup.md -> ~/.claude/commands/"

# Windows helper scripts used by the scan/delete steps. The command resolves
# these from ~/.claude/cleanup-scripts/ when present.
New-Item -ItemType Directory -Force -Path "$ClaudeDir\cleanup-scripts" | Out-Null
$scripts = @('wt_lookup.py','find_targets.py','assert_list.py','live_paths.ps1','diskspace.ps1','run_wiztree.ps1','squirrel.ps1',
             'appdata_orphans.ps1','winsdk.ps1','vs_orphans.ps1','scrub.ps1','README.md')
foreach ($f in $scripts) {
  Invoke-WebRequest -Uri "$RepoUrl/scripts/windows/cleanup/$f" -OutFile "$ClaudeDir\cleanup-scripts\$f"
}
Write-Host "Installed Windows helper scripts -> ~/.claude/cleanup-scripts/"

Write-Host ""
Write-Host "Installation complete! Use /cleanup in Claude Code to get started."
