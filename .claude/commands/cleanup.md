# Developer Workstation Disk Cleanup

Scan the workstation for reclaimable disk space, report findings in a categorized table, let the user select which categories to clean, and execute the cleanup.

## Arguments

- `$ARGUMENTS` — optional flags

Parse `$ARGUMENTS`: if it contains `--dry-run`, operate in report-only mode (skip selection and deletion steps).

## Instructions

### Step 1: Detect Platform and Measure Disk Space

Create a temp directory for cleanup scripts (on Windows, `/tmp/` maps to `%TEMP%` which gets cleaned by the temp files category — using a subdirectory lets us exclude it):
```bash
mkdir -p /tmp/claude-cleanup
```

Run:
```bash
uname -s
```

Determine platform:
- Output starts with `MINGW` or `MSYS` → **windows**
- Output is `Darwin` → **macos**
- Output is `Linux` → **linux**

Measure current disk space ("before" snapshot for the final summary):

- **Windows:** Write a PowerShell temp script to `/tmp/claude-cleanup/diskspace.ps1`:
  ```powershell
  $drive = (Get-Location).Drive.Name
  $d = Get-PSDrive $drive
  $free = [math]::Round($d.Free / 1GB, 1)
  $total = [math]::Round(($d.Used + $d.Free) / 1GB, 1)
  $pct = [math]::Round($d.Used / ($d.Used + $d.Free) * 100)
  Write-Output "$free $total $pct"
  ```
  Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/diskspace.ps1)"`
  Parse output: free_gb total_gb used_pct

- **macOS/Linux:** Run `df -h /` and parse the output for free space, total size, and usage percentage.

Store the "before" free space value for the summary.

### Step 2: Detect Workspace Root

Determine the workspace root for scanning node_modules and build artifacts:
- Walk up from the current working directory to find a directory containing `.claude/`
- If found, that directory is the workspace root
- If not found, use the current working directory

Store this path — it is used for categories 2 (node_modules) and 7 (build artifacts).

### Step 3: Scan All Categories

Scan each category below **in parallel where possible**. Show progress as each category completes. Skip categories that don't apply to the current platform or where required tools are missing.

---

#### Category: Squirrel Old Versions (Windows only)

**Skip if platform is not windows.**

Electron apps on Windows use the Squirrel updater, which keeps old versions in `~/AppData/Local/<app>/app-*` directories.

Write a PowerShell temp script to `/tmp/claude-cleanup/squirrel.ps1`:
```powershell
Get-ChildItem "$env:LOCALAPPDATA" -Directory -ErrorAction SilentlyContinue | Where-Object {
    Test-Path (Join-Path $_.FullName "Update.exe")
} | ForEach-Object {
    $appDirs = Get-ChildItem $_.FullName -Directory -Filter "app-*" -ErrorAction SilentlyContinue | Sort-Object Name
    if ($appDirs.Count -gt 1) {
        $oldDirs = $appDirs | Select-Object -SkipLast 1
        $totalSize = 0
        $oldNames = @()
        foreach ($d in $oldDirs) {
            $size = (Get-ChildItem $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $totalSize += $size
            $oldNames += $d.Name
        }
        if ($totalSize -gt 5MB) {
            Write-Output "$([math]::Round($totalSize / 1MB))MB|$($_.Name)|$($oldNames -join ',')|$($oldDirs.FullName -join ',')"
        }
    }
}
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/squirrel.ps1)"`

Parse output. Each line is: `sizeMB|appName|oldVersions|fullPaths`

Collect: app names, old version names, sizes, and full paths (needed for deletion).

---

#### Category: node_modules (Inactive Projects)

**All platforms.** Requires workspace root from Step 2.

Find all top-level `node_modules` directories under the workspace root. For each:

1. Get the parent project directory
2. Check inactivity:
   - If the project has no `.git` directory → inactive
   - If `command -v git` fails (git not installed) → treat all as inactive
   - If `git -C <project> log -1 --since="4 weeks ago" --oneline` returns empty → inactive
   - Otherwise → active (skip it)
3. Measure `node_modules` size:
   - **Windows:** PowerShell `Get-ChildItem` with `-Recurse -File | Measure-Object -Property Length -Sum`
   - **macOS/Linux:** `du -sm <path>/node_modules | cut -f1` (size in MB)
4. Skip if size < 10 MB

Only report **top-level** `node_modules` per project (not nested ones inside `node_modules/`).

Collect: project name, size, full path.

---

#### Category: Package Manager Caches

**All platforms.** Check each tool individually — skip any that aren't installed.

**npm:**
- Check: `command -v npm`
- Measure:
  - **Windows:** Size of `~/AppData/Local/npm-cache` (via PowerShell)
  - **macOS/Linux:** Size of `~/.npm/_cacache` (via `du -sm`)
- Clean command: `npm cache clean --force`

**pnpm:**
- Check: `command -v pnpm`
- Get store path: `pnpm store path`
- Measure the store directory size
- Clean command: `pnpm store prune`

**yarn:**
- Check: `command -v yarn`
- Detect version: `yarn --version` — if starts with `1.` → Classic, otherwise → Berry
- Classic (v1): `yarn cache dir` → measure that directory's size. Clean: `yarn cache clean`
- Berry (v2+): Uses per-project `.yarn/cache`. Clean: `yarn cache clean --all`

Collect: tool name, cache path, size for each installed tool. Sum total.

---

#### Category: pip Cache

**All platforms.** Skip if neither `pip` nor `pip3` is installed (`command -v pip || command -v pip3`).

- Run `pip cache info` (or `pip3 cache info`) — parse the "Location" and total size
- Clean command: `pip cache purge` (or `pip3 cache purge`)

Collect: cache size.

---

#### Category: Claude Code Debris

**All platforms.**

Measure sizes of these directories (they are always safe to delete):
- `~/.claude/debug/`
- `~/.claude/file-history/`
- `~/.claude/telemetry/`

Count and measure old session logs:
- **macOS/Linux:** `find ~/.claude/projects -maxdepth 2 -name "*.jsonl" -mtime +28`
- **Windows:** PowerShell to find `.jsonl` files under `~/.claude/projects/*/` with LastWriteTime older than 28 days

**SAFETY — NEVER touch any of the following:**
- `~/.claude/projects/*/memory/` (persistent memories)
- `~/.claude/commands/` (slash commands)
- `~/.claude/skills/` (skills)
- `~/.claude/settings*.json` (settings)
- `~/.claude/history.jsonl` (conversation history)

Collect: breakdown (debug X MB, file-history Y MB, telemetry Z MB, N old sessions W MB), total size.

---

#### Category: Crash Dumps

**Platform-specific paths:**
- **Windows:** `~/AppData/Local/CrashDumps/`
- **macOS:** `~/Library/Logs/DiagnosticReports/`
- **Linux:** `/var/crash/` and `~/.local/share/apport/`

Check if the directory exists. If so, measure total size. Skip if directory doesn't exist or is empty.

Collect: file count, total size, paths.

---

#### Category: Build Artifacts (Inactive Projects)

**All platforms.** Requires workspace root from Step 2.

Use the **same inactivity check** as the node_modules category (no git commits in 4 weeks, or no `.git` directory).

In inactive projects, look for these directories:
- `.next/`
- `.turbo/`
- `.parcel-cache/`
- `.vite/`
- `dist/` — **ONLY if `dist` appears in the project's `.gitignore` file.** Many projects commit `dist/` as published output. Never delete committed `dist/` directories.

Measure each found artifact directory.

Collect: project name, artifact type, size, full path.

---

#### Category: Docker

**All platforms.** Skip if Docker is not installed or daemon is not running.

- Check: `command -v docker` — skip if fails
- Check: `docker info > /dev/null 2>&1` — skip if fails (daemon not running)
- Run: `docker system df` — parse reclaimable space for Images and Build Cache
- Clean commands: `docker image prune -f` (dangling images) and `docker builder prune -f` (build cache)
- Do **NOT** use `docker system prune` — it also removes stopped containers

Collect: dangling images size, build cache size, total.

---

#### Category: Windows.old (Windows only)

**Skip if platform is not windows.**

Check if `C:\Windows.old` exists. If so, measure its size:

Write a PowerShell temp script to `/tmp/claude-cleanup/windowsold.ps1`:
```powershell
$p = "C:\Windows.old"
if (Test-Path $p) {
    $s = (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Output "$([math]::Round($s / 1MB))"
} else {
    Write-Output "0"
}
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/windowsold.ps1)"`

Skip if size is 0.

**IMPORTANT:** This category requires elevated privileges to delete. During cleanup (Step 6), warn the user that Windows.old must be removed via Settings > System > Storage > Temporary files > Previous Windows installation(s), or via Disk Cleanup run as Administrator. Do NOT attempt `rm -rf` — it will fail with permission errors.

Collect: size.

---

#### Category: Delivery Optimization Cache (Windows only)

**Skip if platform is not windows.**

Measure the Delivery Optimization cache:

Write a PowerShell temp script to `/tmp/claude-cleanup/delopt.ps1`:
```powershell
$p = "$env:SystemDrive\ProgramData\Microsoft\Windows\DeliveryOptimization"
if (Test-Path $p) {
    $s = (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Output "$([math]::Round($s / 1MB))"
} else {
    Write-Output "0"
}
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/delopt.ps1)"`

Skip if size < 50 MB.

Clean command (Step 6): Write a PowerShell script that stops the DoSvc service, deletes cache contents, and restarts the service:
```powershell
Stop-Service -Name "DoSvc" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemDrive\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service -Name "DoSvc" -ErrorAction SilentlyContinue
```

**Note:** Requires elevated privileges. If cleanup fails with access denied, inform the user to run via Settings > System > Storage > Temporary files > Delivery Optimization Files.

Collect: size.

---

#### Category: Windows Temp Files (Windows only)

**Skip if platform is not windows.**

Measure temp file directories:

Write a PowerShell temp script to `/tmp/claude-cleanup/tempfiles.ps1`:
```powershell
$userTemp = $env:TEMP
$sysTemp = "$env:SystemRoot\Temp"
$userSize = 0
$sysSize = 0
if (Test-Path $userTemp) {
    $userSize = (Get-ChildItem $userTemp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
}
if (Test-Path $sysTemp) {
    $sysSize = (Get-ChildItem $sysTemp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
}
$totalMB = [math]::Round(($userSize + $sysSize) / 1MB)
$userMB = [math]::Round($userSize / 1MB)
$sysMB = [math]::Round($sysSize / 1MB)
Write-Output "$totalMB|$userMB|$sysMB|$userTemp|$sysTemp"
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/tempfiles.ps1)"`

Parse output: `totalMB|userTempMB|sysTempMB|userTempPath|sysTempPath`

Skip if total < 50 MB.

Clean command (Step 6): Delete contents of both temp directories (not the directories themselves). Exclude the `claude-cleanup` subdirectory used by this script. Files locked by running processes will be skipped automatically by `-ErrorAction SilentlyContinue`:
```powershell
Get-ChildItem "$env:TEMP" -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'claude-cleanup' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
```

Collect: total size, breakdown (user temp X MB, system temp Y MB).

---

#### Category: Browser Caches (Windows only)

**Skip if platform is not windows.**

Measure browser cache directories for installed browsers:

Write a PowerShell temp script to `/tmp/claude-cleanup/browsercache.ps1`:
```powershell
$browsers = @(
    @{ Name = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" },
    @{ Name = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache" },
    @{ Name = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache" },
    @{ Name = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache" },
    @{ Name = "Firefox"; Path = "" },
    @{ Name = "Brave"; Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache" }
)
# Firefox uses a profile-based path
$ffProfiles = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $ffProfiles) {
    Get-ChildItem $ffProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $cachePath = Join-Path $_.FullName "cache2"
        if (Test-Path $cachePath) {
            $s = (Get-ChildItem $cachePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($s -gt 0) {
                Write-Output "Firefox|$([math]::Round($s / 1MB))|$cachePath"
            }
        }
    }
}
foreach ($b in $browsers) {
    if ($b.Path -ne "" -and (Test-Path $b.Path)) {
        $s = (Get-ChildItem $b.Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($s -gt 10MB) {
            Write-Output "$($b.Name)|$([math]::Round($s / 1MB))|$($b.Path)"
        }
    }
}
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/browsercache.ps1)"`

Parse output. Each line is: `browserName|sizeMB|fullPath`

Group by browser name (sum sizes if multiple paths per browser). Skip if total across all browsers < 50 MB.

**IMPORTANT:** Warn the user to close browsers before cleaning for best results. Files locked by running browsers will be skipped automatically.

Clean command (Step 6): `rm -rf <each cache directory path>/*` (delete contents, not the directory itself — browsers recreate it).

Collect: browser names, sizes, paths.

---

#### Category: Electron App Caches (Windows only)

**Skip if platform is not windows.**

Electron apps store caches in `%APPDATA%/<AppName>/` and `%LOCALAPPDATA%/<AppName>/`. Scan for `Cache/`, `Code Cache/`, `GPUCache/`, and `Service Worker/CacheStorage/` subdirectories inside known Electron app directories.

Write a PowerShell temp script to `/tmp/claude-cleanup/electroncache.ps1`:
```powershell
$apps = @(
    @{ Name = "Claude Desktop"; Path = "$env:APPDATA\Claude" },
    @{ Name = "Miro"; Path = "$env:APPDATA\RealtimeBoard" },
    @{ Name = "Slack"; Path = "$env:APPDATA\Slack" },
    @{ Name = "Discord"; Path = "$env:APPDATA\discord" },
    @{ Name = "Linear"; Path = "$env:APPDATA\Linear" },
    @{ Name = "Notion"; Path = "$env:APPDATA\Notion" },
    @{ Name = "Notion Calendar"; Path = "$env:APPDATA\Notion Calendar" },
    @{ Name = "Signal"; Path = "$env:APPDATA\Signal" },
    @{ Name = "Element"; Path = "$env:APPDATA\Element" },
    @{ Name = "Figma"; Path = "$env:APPDATA\Figma" },
    @{ Name = "Zoom"; Path = "$env:APPDATA\Zoom" },
    @{ Name = "Telegram"; Path = "$env:APPDATA\Telegram Desktop" },
    @{ Name = "Tana"; Path = "$env:LOCALAPPDATA\tana" },
    @{ Name = "TogglTrack"; Path = "$env:LOCALAPPDATA\TogglTrack" }
)
$cacheDirNames = @("Cache", "Code Cache", "GPUCache", "cache", "blob_storage")

foreach ($app in $apps) {
    if (-not (Test-Path $app.Path)) { continue }
    $totalSize = 0
    $paths = @()
    foreach ($cacheName in $cacheDirNames) {
        # Search recursively but only 2 levels deep
        Get-ChildItem $app.Path -Directory -Filter $cacheName -Recurse -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object {
            $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($s -gt 1MB) {
                $totalSize += $s
                $paths += $_.FullName
            }
        }
    }
    # Also check for Service Worker/CacheStorage
    $swPath = Join-Path $app.Path "Service Worker\CacheStorage"
    if (Test-Path $swPath) {
        $s = (Get-ChildItem $swPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($s -gt 1MB) {
            $totalSize += $s
            $paths += $swPath
        }
    }
    if ($totalSize -gt 10MB) {
        $mb = [math]::Round($totalSize / 1MB)
        Write-Output "$($app.Name)|$mb|$($paths -join ';')"
    }
}
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/electroncache.ps1)"`

Parse output. Each line is: `appName|sizeMB|semicolonSeparatedPaths`

Skip if total across all apps < 50 MB.

**IMPORTANT:** Warn the user to close the affected apps before cleaning for best results. Files locked by running apps will be skipped automatically.

Clean command (Step 6): `rm -rf <each cache directory path>/*` (delete contents, not the directory itself — apps recreate cache dirs on next launch).

Collect: app names, sizes, paths.

---

#### Category: Stale Updater Files (Windows only)

**Skip if platform is not windows.**

Electron apps using Squirrel or similar updaters keep downloaded update packages in `pending/` and `updates/` directories after they've been applied.

Write a PowerShell temp script to `/tmp/claude-cleanup/staleupdaters.ps1`:
```powershell
$updaterPaths = @(
    @{ Name = "Linear"; Path = "$env:LOCALAPPDATA\@lineardesktop-updater\pending" },
    @{ Name = "Notion"; Path = "$env:LOCALAPPDATA\notion-updater\pending" },
    @{ Name = "uTorrent"; Path = "$env:APPDATA\uTorrent\updates" },
    @{ Name = "Signal"; Path = "$env:APPDATA\Signal\update-cache" }
)

foreach ($u in $updaterPaths) {
    if (Test-Path $u.Path) {
        $s = (Get-ChildItem $u.Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($s -gt 5MB) {
            Write-Output "$($u.Name)|$([math]::Round($s / 1MB))|$($u.Path)"
        }
    }
}

# Also scan for any Squirrel app packages/ directories with old .nupkg files
Get-ChildItem "$env:LOCALAPPDATA" -Directory -ErrorAction SilentlyContinue | Where-Object {
    Test-Path (Join-Path $_.FullName "Update.exe")
} | ForEach-Object {
    $pkgDir = Join-Path $_.FullName "packages"
    if (Test-Path $pkgDir) {
        # Keep only the newest .nupkg, measure the rest
        $nupkgs = Get-ChildItem $pkgDir -Filter "*.nupkg" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
        if ($nupkgs.Count -gt 1) {
            $old = $nupkgs | Select-Object -SkipLast 1
            $s = ($old | Measure-Object -Property Length -Sum).Sum
            if ($s -gt 5MB) {
                $paths = ($old | ForEach-Object { $_.FullName }) -join ';'
                Write-Output "$($_.Name) (old packages)|$([math]::Round($s / 1MB))|$paths"
            }
        }
    }
}
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/staleupdaters.ps1)"`

Parse output. Each line is: `appName|sizeMB|pathOrPaths`

Skip if total < 20 MB.

Clean command (Step 6): `rm -rf <each path>/*` for directories, or `rm -f <each file path>` for individual .nupkg files.

Collect: app names, sizes, paths.

---

#### Category: Playwright Browsers (Windows only)

**Skip if platform is not windows.**

Playwright downloads full browser binaries to `%LOCALAPPDATA%\ms-playwright\`. These can be large (200-400 MB each) and accumulate when Playwright updates.

Write a PowerShell temp script to `/tmp/claude-cleanup/playwright.ps1`:
```powershell
$p = "$env:LOCALAPPDATA\ms-playwright"
if (Test-Path $p) {
    $dirs = Get-ChildItem $p -Directory -ErrorAction SilentlyContinue
    $totalSize = 0
    $names = @()
    foreach ($d in $dirs) {
        $s = (Get-ChildItem $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $totalSize += $s
        $names += "$($d.Name) ($([math]::Round($s / 1MB))MB)"
    }
    Write-Output "$([math]::Round($totalSize / 1MB))|$($names -join ',')|$p"
} else {
    Write-Output "0||"
}
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/playwright.ps1)"`

Parse output: `totalMB|browserList|path`

Skip if total < 50 MB.

**Note:** Deleting Playwright browsers means they'll need to be re-downloaded on next `npx playwright install`. Only clean if you're not actively running Playwright tests.

Clean command (Step 6): `rm -rf <ms-playwright path>/*`

Collect: total size, browser list, path.

---

#### Category: App Caches (macOS + Linux only)

**Skip on Windows** (other Windows-specific categories cover app bloat).

- **macOS:** Scan `~/Library/Caches/` for subdirectories larger than 50 MB
- **Linux:** Scan `~/.cache/` for subdirectories larger than 50 MB

Use `du -sm` to measure each subdirectory. Report only those exceeding 50 MB.

Collect: app/directory name, size, full path.

---

### Step 4: Build and Display Report

Assemble the scan results into a report table.

**Only include categories that found reclaimable items** (total size > 0). Skip empty categories entirely.

Sort rows by size descending. Number them sequentially (1, 2, 3...) based on what's shown — these are NOT fixed category IDs.

Display format:

```
Disk: [free]GB free / [total]GB total ([used]%)

 #  Category                  Items                              Size
 1  [largest category]        [brief item list]                  X.X GB
 2  [next category]           [brief item list]                  XXX MB
 3  [next category]           [brief item list]                  XXX MB
 ...
                                                         Total: X.X GB
```

For the "Items" column, show up to 3 specific names then `(+N more)` if there are additional items.

### Step 5: User Selection

**If `--dry-run` mode:** Stop here. Do not prompt for selection or perform any deletions.

Otherwise, ask the user:

> Which categories to clean? Enter numbers (e.g., `1,2,3`), `all`, or `none` to cancel.

Wait for user response. Parse their selection:
- Specific numbers: clean only those categories
- `all`: clean everything in the report
- `none`: cancel, do not delete anything

### Step 6: Execute Cleanup

For each selected category, execute the appropriate cleanup:

| Category | Clean Command |
|----------|--------------|
| Squirrel old versions | `rm -rf <each old app-* directory path>` |
| node_modules (inactive) | `rm -rf <each inactive project>/node_modules` |
| npm cache | `npm cache clean --force` |
| pnpm cache | `pnpm store prune` |
| yarn v1 cache | `yarn cache clean` |
| yarn v2+ cache | `yarn cache clean --all` |
| pip cache | `pip cache purge` (or `pip3 cache purge`) |
| Claude Code debris | `rm -rf ~/.claude/debug/* ~/.claude/file-history/* ~/.claude/telemetry/*` and delete old `.jsonl` files: macOS/Linux `find ~/.claude/projects -maxdepth 2 -name "*.jsonl" -mtime +28 -delete`, Windows use PowerShell equivalent |
| Crash dumps | `rm -rf <contents of platform-specific crash dump paths>` |
| Build artifacts | `rm -rf <each artifact directory path>` |
| Docker (images) | `docker image prune -f` |
| Docker (build cache) | `docker builder prune -f` |
| App caches | `rm -rf <each large cache directory path>` |
| Windows.old | **Cannot be deleted via CLI.** Instruct the user to use Settings > System > Storage > Temporary files > Previous Windows installation(s), or Disk Cleanup as Administrator. |
| Delivery Optimization | PowerShell: `Stop-Service DoSvc -Force; Remove-Item "$env:SystemDrive\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache\*" -Recurse -Force; Start-Service DoSvc`. If access denied, instruct user to use Settings > Storage > Temporary files. |
| Windows Temp files | PowerShell: `Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue` |
| Browser caches | `rm -rf <each cache directory path>/*` (contents only, not the directory). Warn user to close browsers first. |
| Electron app caches | `rm -rf <each cache directory path>/*` (contents only, not the directory). Warn user to close affected apps first. |
| Stale updater files | `rm -rf <each updater directory path>/*` for directories, `rm -f <path>` for individual .nupkg files. |
| Playwright browsers | `rm -rf <ms-playwright path>/*` |

**Show progress** as each category is cleaned: what's being deleted and confirmation when done.

**Partial failure handling:** If cleaning a category fails (e.g., permission denied, Docker daemon stopped mid-operation), log the error and continue with remaining selected categories. Track failures for the summary.

### Step 7: Summary

Re-measure disk space using the same method as Step 1.

Calculate freed space: `after_free - before_free`.

Display:

```
Done! Freed X.X GB ([before]GB → [after]GB free, [new_pct]%)
```

If any categories failed during cleanup, list them:

```
Failed: [category name] ([error reason])
```
