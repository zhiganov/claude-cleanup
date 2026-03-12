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

## What It Scans

| Category | Platforms | What it finds |
|----------|-----------|---------------|
| Squirrel old versions | Windows | Old Electron app versions (Slack, Discord, Figma, etc.) |
| node_modules (inactive) | All | `node_modules` in projects with no git activity in 4+ weeks |
| Package manager caches | All | npm, pnpm, yarn global caches |
| pip cache | All | Python package cache |
| Claude Code debris | All | Debug logs, telemetry, old session logs (4+ weeks) |
| Crash dumps | All | OS crash reports |
| Build artifacts | All | `.next/`, `.turbo/`, `.parcel-cache/`, `.vite/` in inactive projects |
| Docker | All | Dangling images, build cache |
| App caches | macOS, Linux | Large app cache directories (>50 MB) |
| Windows.old | Windows | Previous Windows installation (10-30 GB after upgrades) |
| Delivery Optimization | Windows | Windows Update distribution cache (up to 20 GB) |
| Windows Temp files | Windows | `%TEMP%` and `C:\Windows\Temp` |
| Browser caches | Windows | Chrome, Edge, Firefox, Brave cache and code cache |
| Electron app caches | Windows | Cache/Code Cache dirs in Slack, Discord, Miro, Claude Desktop, Notion, etc. |
| Stale updater files | Windows | Applied update packages in Linear, Notion, Signal, Squirrel apps |
| Playwright browsers | Windows | Downloaded browser binaries in `ms-playwright` |

## Example Output

```
Disk: 12GB free / 120GB total (90%)

 #  Category                  Items                              Size
 1  Squirrel old versions     Slack, Discord, Figma (+2 more)    1.3 GB
 2  node_modules (inactive)   my-old-project, another-one        1.0 GB
 3  npm cache                 ~/.npm/_cacache                    2.2 GB
 4  Claude Code debris        debug (242 files), telemetry       224 MB
 5  pip cache                 ~/pip/cache                        100 MB
                                                         Total: 4.8 GB

Which categories to clean? Enter numbers (e.g., 1,2,3), all, or none to cancel.
```

## Safety

- **Report first, act second.** Nothing is deleted until you choose.
- **Keeps newest versions.** Squirrel cleanup only removes old `app-*` directories.
- **Respects active projects.** Only cleans node_modules and build artifacts in projects with no git activity in 4+ weeks.
- **Protects Claude Code data.** Never touches memories, commands, skills, settings, or history.
- **Safe Docker cleanup.** Only prunes dangling images and build cache — never removes stopped containers or volumes.
- **Handles elevated categories.** Windows.old and Delivery Optimization require admin access — provides clear instructions if CLI cleanup fails.
- **Browser-safe.** Warns to close browsers before cleaning caches; locked files are skipped automatically.
- **Skips missing tools.** If Docker, pip, pnpm, or yarn isn't installed, that category is silently skipped.
- **Handles failures gracefully.** If one category fails, continues with the rest and reports what failed.

## License

MIT
