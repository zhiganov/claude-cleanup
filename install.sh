#!/bin/bash
set -e

REPO_URL="https://raw.githubusercontent.com/zhiganov/claude-cleanup/master"
CLAUDE_DIR="$HOME/.claude"

echo "Installing claude-cleanup..."

mkdir -p "$CLAUDE_DIR/commands"
curl -fsSL "$REPO_URL/.claude/commands/cleanup.md" -o "$CLAUDE_DIR/commands/cleanup.md"
echo "✓ Installed cleanup.md → ~/.claude/commands/"

# Windows helper scripts (used by the scan/delete steps under MSYS2/Git Bash).
# The command resolves these from ~/.claude/cleanup-scripts/ when present.
mkdir -p "$CLAUDE_DIR/cleanup-scripts"
for f in wt_lookup.py find_targets.py assert_list.py live_paths.ps1 diskspace.ps1 run_wiztree.ps1 squirrel.ps1 \
         appdata_orphans.ps1 winsdk.ps1 vs_orphans.ps1 scrub.ps1 README.md; do
  curl -fsSL "$REPO_URL/scripts/windows/cleanup/$f" -o "$CLAUDE_DIR/cleanup-scripts/$f"
done
echo "✓ Installed Windows helper scripts → ~/.claude/cleanup-scripts/"

echo ""
echo "Installation complete! Use /cleanup in Claude Code to get started."
