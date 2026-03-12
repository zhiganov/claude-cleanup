# claude-cleanup

Claude Code slash command that scans your developer workstation for reclaimable disk space and lets you selectively clean up.

## Install

```bash
npx skillsadd zhiganov/claude-cleanup
```

**Alternative (manual):**

macOS/Linux:
```bash
curl -fsSL https://raw.githubusercontent.com/zhiganov/claude-cleanup/master/install.sh | bash
```

Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/zhiganov/claude-cleanup/master/install.ps1 | iex
```

## Usage

```
/cleanup              # scan, report, select, clean
/cleanup --dry-run    # scan and report only
```

## WizTree Acceleration (Windows)

If [WizTree](https://www.diskanalyzer.com/) is installed, the scan phase completes in seconds instead of minutes. WizTree reads the NTFS Master File Table directly for instant directory sizes.

- Auto-detected from common install paths
- Falls back to PowerShell scanning if not installed
- Also accepts a manually-exported WizTree CSV

## What It Scans (19 categories)

Cross-platform:

| Category | What it finds |
|----------|---------------|
| node_modules (inactive) | `node_modules` in projects with no git activity in 4+ weeks |
| Package manager caches | npm, pnpm, yarn global caches |
| pip cache | Python package cache |
| Claude Code debris | Debug logs, telemetry, old session logs (4+ weeks) |
| Build artifacts | `.next/`, `.turbo/`, `.parcel-cache/`, `.vite/` in inactive projects |
| Docker | Dangling images, build cache |

Windows-specific:

| Category | What it finds |
|----------|---------------|
| Squirrel old versions | Old Electron app versions (Slack, Discord, Figma, etc.) |
| Windows.old | Previous Windows installation (10-30 GB after upgrades) |
| Delivery Optimization | Windows Update distribution cache (up to 20 GB) |
| Windows Temp files | `%TEMP%` and `C:\Windows\Temp` |
| Browser caches | Chrome, Edge, Firefox, Brave cache and code cache |
| Electron app caches | Cache dirs in Slack, Discord, Miro, Claude Desktop, Notion, etc. |
| Stale updater files | Applied update packages in Linear, Notion, Signal, Squirrel apps |
| Playwright browsers | Downloaded browser binaries in `ms-playwright` |
| Crash dumps & kernel reports | CrashDumps + LiveKernelReports (multi-GB watchdog dumps) |
| Windows System Logs | CBS logs, OEM PC Manager logs |
| VS Package Cache | Visual Studio installer package cache |

macOS/Linux:

| Category | What it finds |
|----------|---------------|
| Crash dumps | OS crash reports |
| App caches | Large app cache directories (>50 MB) |

## Example Output

```
Disk: 6.5GB free / 120GB total (95%)

 #  Category                  Items                              Size
 1  VS Package Cache          VisualStudio\Packages              2.4 GB
 2  Crash dumps               LiveKernelReports (1 dump)         2.0 GB
 3  npm cache                 npm-cache                          1.9 GB
 4  Browser caches            Firefox, Chrome, Edge              1.7 GB
 5  Windows System Logs       CBS, PCManager                     1.3 GB
 6  Electron app caches       Miro, Claude Desktop, Slack        1.0 GB
 7  Playwright browsers       chromium-1208, chromium_headless    655 MB
 8  Windows Temp files        User temp (282 MB)                  282 MB
 9  node_modules (inactive)   dear-neighbors, my-community        141 MB
                                                         Total: 11.3 GB

Which categories to clean? Enter numbers (e.g., 1,2,3), all, or none to cancel.
```

## Safety

- **Report first, act second.** Nothing is deleted until you choose.
- **WizTree = fast + safe.** Only used for size measurements, never deletes anything.
- **Keeps newest versions.** Squirrel cleanup only removes old `app-*` directories.
- **Respects active projects.** Only cleans node_modules and build artifacts in projects with no git activity in 4+ weeks.
- **Protects Claude Code data.** Never touches memories, commands, skills, settings, or history.
- **Safe Docker cleanup.** Only prunes dangling images and build cache — never removes stopped containers or volumes.
- **Single UAC prompt.** Elevated categories (system logs, VS cache, kernel reports) are batched into one admin PowerShell invocation.
- **Browser/app-safe.** Warns to close apps before cleaning caches; locked files are skipped automatically.
- **Skips missing tools.** If Docker, pip, pnpm, yarn, or WizTree isn't installed, gracefully falls back or skips.
- **Handles failures gracefully.** If one category fails, continues with the rest and reports what failed.

## License

MIT
