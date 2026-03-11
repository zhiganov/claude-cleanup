# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Published Claude Code slash command (`/cleanup`) that scans a developer workstation for reclaimable disk space across 9 categories and lets users selectively clean them. Cross-platform: Windows, macOS, Linux.

Repo: `zhiganov/claude-cleanup`. Install: `npx skillsadd zhiganov/claude-cleanup`.

## Architecture

This is a **slash command repo**, not a code project. The entire product is a single markdown file (`.claude/commands/cleanup.md`) containing structured instructions that Claude Code interprets at runtime. There is no runtime code, no dependencies, no build step.

```
.claude/commands/cleanup.md   ← the slash command (this IS the product)
install.sh / install.ps1      ← alternative install scripts
docs/                          ← spec and implementation plan
```

## How the Command Works

The command instructs Claude Code through 7 steps:
1. Detect platform (`uname -s`) and measure disk space
2. Detect workspace root (walk up to find `.claude/`)
3. Scan 9 categories in parallel (Squirrel old versions, inactive node_modules, package manager caches, pip cache, Claude Code debris, crash dumps, build artifacts, Docker, app caches)
4. Display report table sorted by size
5. User selects categories to clean (or `--dry-run` stops here)
6. Execute cleanup commands per category
7. Show before/after summary

## Key Design Decisions

- **Windows uses PowerShell temp scripts** written to `/tmp/*.ps1` and run via `powershell.exe -File` — `du` is unreliable on NTFS via Git Bash.
- **Inactivity = no git commits in 4 weeks.** Non-git directories are always considered inactive.
- **`dist/` is only cleaned if gitignored** — many projects commit `dist/` as published output.
- **Docker: `docker image prune` + `docker builder prune` only** — never `docker system prune` (removes stopped containers).
- **Claude Code safety:** Never touch `memory/`, `commands/`, `skills/`, `settings*.json`, `history.jsonl`.

## Modifying the Command

When editing `.claude/commands/cleanup.md`:
- Instructions must be precise — Claude interprets them literally
- Platform guards (`Skip if platform is not windows`) must be on every platform-specific category
- Tool checks (`command -v <tool>`) must precede any tool usage
- Every category needs: scan instructions, size collection, and a clean command in the Step 6 table
- Test changes by copying to `~/.claude/commands/cleanup.md` and running `/cleanup --dry-run`
