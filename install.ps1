$RepoUrl = "https://raw.githubusercontent.com/zhiganov/claude-cleanup/master"
$ClaudeDir = "$env:USERPROFILE\.claude"

Write-Host "Installing claude-cleanup..."

New-Item -ItemType Directory -Force -Path "$ClaudeDir\commands" | Out-Null
Invoke-WebRequest -Uri "$RepoUrl/.claude/commands/cleanup.md" -OutFile "$ClaudeDir\commands\cleanup.md"
Write-Host "Installed cleanup.md -> ~/.claude/commands/"

Write-Host ""
Write-Host "Installation complete! Use /cleanup in Claude Code to get started."
