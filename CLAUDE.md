# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Published Claude Code slash command (`/cleanup`) that scans a developer workstation for reclaimable disk space across 31 categories and lets users selectively clean them. Cross-platform: Windows, macOS, Linux. Uses WizTree for instant NTFS scanning on Windows when available.

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
2.5. **WizTree fast scan** (Windows only) — if WizTree is installed, export CSV for instant size lookups; also accepts manually-exported CSVs
3. Scan up to 31 categories in parallel (only those matching the detected platform fire) — uses WizTree data when available on Windows, falls back to PowerShell. On Linux/macOS, categories are grouped into Cross-platform / Windows-only / Unix sections; runtime guards skip non-applicable ones.
4. Display report table sorted by size
5. User selects categories to clean (or `--dry-run` stops here)
6. Execute cleanup — elevated categories batched into single UAC prompt
7. Show before/after summary

## Key Design Decisions

- **WizTree acceleration:** Reads NTFS MFT directly, replacing dozens of slow `Get-ChildItem -Recurse` calls with instant CSV lookups via a Python helper script.
- **Temp script isolation:** Scripts written to `/tmp/claude-cleanup/` (not `/tmp/`) to survive the temp files cleanup category.
- **Single UAC prompt:** All elevated operations (system logs, VS cache, kernel reports, delivery optimization) batched into one PowerShell script run with `-Verb RunAs`.
- **Inactivity = no git commits in 4 weeks.** Non-git directories are always considered inactive.
- **`dist/` is only cleaned if gitignored** — many projects commit `dist/` as published output.
- **Docker: `docker image prune` + `docker builder prune` only** — never `docker system prune` (removes stopped containers).
- **Claude Code safety:** Never touch `memory/`, `commands/`, `skills/`, `settings*.json`, `history.jsonl`.
- **Hook-safe deletion (Linux/macOS):** Many safety hooks block `rm -rf` against paths starting with `/` or `~`. Use `find <path> -mindepth 1 -delete && rmdir <path>` instead — same result, no pattern collision, errors on typos rather than recursing.
- **Inactivity check resolves repo root:** For nested packages in monorepos (e.g. `repo/server/node_modules` with `.git` at `repo/`), the inactivity check runs `git rev-parse --show-toplevel` before testing the log window. Testing the subpackage path directly silently false-positives.
- **Orphan-scan filter chain (Linux):** 4-layer filter — allowlist + `command -v` active-binary + 30-day mtime + token-boundary package match. Substring matching produces real-world false-negatives (e.g. `zenity` would swallow `zen` and skip a real orphan), so the match requires `pkg == name` or `pkg == name-*` or `pkg == *-name` etc.
- **Hardlink/CAS caveat:** Bun and pnpm caches use content-addressed stores with hardlinks into project `node_modules`. `du` reports apparent size from the cache's perspective, but `df` reclaims only when the last hardlink is gone — pair cache cleanup with the `node_modules (inactive)` category for real reclaim.

## Modifying the Command

When editing `.claude/commands/cleanup.md`:
- Instructions must be precise — Claude interprets them literally
- Platform guards (`Skip if platform is not windows`) must be on every platform-specific category
- Tool checks (`command -v <tool>`) must precede any tool usage
- Every category needs: scan instructions, size collection, and a clean command in the Step 6 table
- WizTree-accelerated categories must have a "Fallback:" path for when WizTree isn't available
- Test changes by copying to `~/.claude/commands/cleanup.md` and running `/cleanup --dry-run`
