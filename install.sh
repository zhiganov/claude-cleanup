#!/bin/bash
set -e

REPO_URL="https://raw.githubusercontent.com/zhiganov/claude-cleanup/master"
CLAUDE_DIR="$HOME/.claude"

echo "Installing claude-cleanup..."

mkdir -p "$CLAUDE_DIR/commands"
curl -fsSL "$REPO_URL/.claude/commands/cleanup.md" -o "$CLAUDE_DIR/commands/cleanup.md"
echo "✓ Installed cleanup.md → ~/.claude/commands/"

echo ""
echo "Installation complete! Use /cleanup in Claude Code to get started."
