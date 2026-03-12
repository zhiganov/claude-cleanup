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

Store this path — it is used for node_modules and build artifact categories.

### Step 2.5: WizTree Fast Scan (Windows only)

**Skip if platform is not windows.**

WizTree reads the NTFS Master File Table directly, providing instant directory sizes for the entire drive. When available, it replaces all slow PowerShell `Get-ChildItem` size measurements.

**Check if WizTree is installed:**

```bash
find "/c/Program Files/WizTree" "/c/Program Files (x86)/WizTree" "$LOCALAPPDATA/Programs/WizTree" -maxdepth 1 -name "WizTree64.exe" 2>/dev/null | head -1
```

Also check: `command -v WizTree64` and `where.exe WizTree64.exe 2>/dev/null`

**If WizTree is found**, run the export:

```bash
"<path_to_WizTree64.exe>" "C:" /export="/tmp/claude-cleanup/wiztree.csv" /admin=0 /silent
```

Wait for it to complete (typically 5-15 seconds).

**If WizTree is NOT found**, check if a recent WizTree CSV already exists in the workspace (the user may have exported one manually):

```bash
find /c/Users/temaz/claude-project/claude-cleanup -maxdepth 1 -name "WizTree*.csv" -newer /tmp/claude-cleanup 2>/dev/null | head -1
```

If a CSV is found (either exported or pre-existing), write a Python helper script to `/tmp/claude-cleanup/wt_lookup.py` that provides instant size lookups:

```python
import csv, sys

sizes = {}
with open(sys.argv[1], encoding='utf-8-sig') as f:
    next(f)  # skip comment line
    reader = csv.reader(f)
    next(reader)  # skip headers
    for row in reader:
        path = row[0].rstrip(chr(92))  # strip trailing backslash
        sizes[path.lower()] = int(row[1])

# Read requested paths from stdin, one per line
for line in sys.stdin:
    qpath = line.strip().lower().rstrip(chr(92))
    size = sizes.get(qpath, 0)
    print(f"{size // 1048576}|{line.strip()}")
```

Test the helper: pipe a known path to verify it works.

**Using WizTree data in categories:** When WizTree data is available, replace all PowerShell `Get-ChildItem -Recurse` size measurements with:

```bash
echo "C:\path\to\directory" | python /tmp/claude-cleanup/wt_lookup.py /tmp/claude-cleanup/wiztree.csv
```

Output: `sizeMB|path`

You can pipe multiple paths at once (one per line) for batch lookups. This turns a multi-minute scan phase into seconds.

**If neither WizTree nor a CSV is available**, fall back to the PowerShell approach described in each category below (marked as "Fallback:").

### Step 3: Scan All Categories

Scan each category below **in parallel where possible**. Show progress as each category completes. Skip categories that don't apply to the current platform or where required tools are missing.

**When WizTree data is available**, batch all size lookups for a category into a single `wt_lookup.py` call instead of running individual PowerShell scripts. This is dramatically faster.

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
        foreach ($d in $oldDirs) {
            Write-Output "$($_.Name)|$($d.Name)|$($d.FullName)"
        }
    }
}
```

Run the script to discover old app-* directories. Then measure sizes:
- **With WizTree:** Pipe all discovered paths to `wt_lookup.py`
- **Fallback:** Use PowerShell `Get-ChildItem -Recurse -File | Measure-Object -Property Length -Sum` per directory

Skip entries < 5 MB.

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
   - **With WizTree:** Pipe path to `wt_lookup.py`
   - **Fallback Windows:** PowerShell `Get-ChildItem` with `-Recurse -File | Measure-Object -Property Length -Sum`
   - **macOS/Linux:** `du -sm <path>/node_modules | cut -f1` (size in MB)
4. Skip if size < 10 MB

Only report **top-level** `node_modules` per project (not nested ones inside `node_modules/`).

Collect: project name, size, full path.

---

#### Category: Package Manager Caches

**All platforms.** Check each tool individually — skip any that aren't installed.

**npm:**
- Check: `command -v npm`
- Path: **Windows:** `~/AppData/Local/npm-cache`, **macOS/Linux:** `~/.npm/_cacache`
- **With WizTree:** Pipe path to `wt_lookup.py`
- **Fallback:** PowerShell or `du -sm`
- Clean command: `npm cache clean --force`

**pnpm:**
- Check: `command -v pnpm`
- Get store path: `pnpm store path`
- Measure the store directory size (WizTree or fallback)
- Clean command: `pnpm store prune`

**yarn:**
- Check: `command -v yarn`
- Detect version: `yarn --version` — if starts with `1.` → Classic, otherwise → Berry
- Classic (v1): `yarn cache dir` → measure. Clean: `yarn cache clean`
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

Use WizTree lookup or fallback PowerShell/du for sizes.

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

#### Category: Crash Dumps and Kernel Reports

**Platform-specific paths:**
- **Windows:** `~/AppData/Local/CrashDumps/` AND `C:\Windows\LiveKernelReports\`
- **macOS:** `~/Library/Logs/DiagnosticReports/`
- **Linux:** `/var/crash/` and `~/.local/share/apport/`

Check if each directory exists. Measure total size (WizTree or fallback).

`LiveKernelReports` can contain multi-GB kernel watchdog dumps (e.g., `DripsWatchdog-*.dmp`). These are safe to delete.

Skip if total size < 5 MB.

Clean command: For `CrashDumps`, `rm -rf <path>/*`. For `LiveKernelReports`, requires elevated PowerShell: `Remove-Item "C:\Windows\LiveKernelReports\*" -Recurse -Force`.

Collect: file count, total size, paths, breakdown by location.

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

Measure each found artifact directory (WizTree or fallback).

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

Check if `C:\Windows.old` exists. Measure size (WizTree or fallback PowerShell).

Skip if size is 0.

**IMPORTANT:** This category requires elevated privileges to delete. During cleanup (Step 6), warn the user that Windows.old must be removed via Settings > System > Storage > Temporary files > Previous Windows installation(s), or via Disk Cleanup run as Administrator. Do NOT attempt `rm -rf` — it will fail with permission errors.

Collect: size.

---

#### Category: Delivery Optimization Cache (Windows only)

**Skip if platform is not windows.**

Measure: `C:\ProgramData\Microsoft\Windows\DeliveryOptimization` (WizTree or fallback PowerShell).

Skip if size < 50 MB.

Clean command (Step 6): Elevated PowerShell:
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

Measure `%TEMP%` and `C:\Windows\Temp` (WizTree or fallback PowerShell).

Skip if total < 50 MB.

Clean command (Step 6): Exclude the `claude-cleanup` subdirectory used by this script. Files locked by running processes will be skipped automatically:
```powershell
Get-ChildItem "$env:TEMP" -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'claude-cleanup' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
```

Collect: total size, breakdown (user temp X MB, system temp Y MB).

---

#### Category: Browser Caches (Windows only)

**Skip if platform is not windows.**

Measure browser cache directories for installed browsers. Check these paths:

- Chrome: `%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache`, `...\Code Cache`
- Edge: `%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache`, `...\Code Cache`
- Brave: `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Default\Cache`
- Firefox: `%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2`

**With WizTree:** Pipe all paths to `wt_lookup.py` in one batch call.
**Fallback:** Use PowerShell `Get-ChildItem -Recurse` per path.

Group by browser name (sum sizes if multiple paths per browser). Skip if total across all browsers < 50 MB.

**IMPORTANT:** Warn the user to close browsers before cleaning for best results. Files locked by running browsers will be skipped automatically.

Clean command (Step 6): `rm -rf <each cache directory path>/*` (delete contents, not the directory itself — browsers recreate it).

Collect: browser names, sizes, paths.

---

#### Category: Electron App Caches (Windows only)

**Skip if platform is not windows.**

Electron apps store caches in `%APPDATA%/<AppName>/` and `%LOCALAPPDATA%/<AppName>/`. Scan for `Cache/`, `Code Cache/`, `GPUCache/`, and `Service Worker/CacheStorage/` subdirectories inside these app directories:

- Claude Desktop (`%APPDATA%\Claude`)
- Miro (`%APPDATA%\RealtimeBoard`)
- Slack (`%APPDATA%\Slack`)
- Discord (`%APPDATA%\discord`)
- Linear (`%APPDATA%\Linear`)
- Notion (`%APPDATA%\Notion`)
- Notion Calendar (`%APPDATA%\Notion Calendar`)
- Signal (`%APPDATA%\Signal`)
- Element (`%APPDATA%\Element`)
- Figma (`%APPDATA%\Figma`)
- Zoom (`%APPDATA%\Zoom`)
- Telegram (`%APPDATA%\Telegram Desktop`)
- Tana (`%LOCALAPPDATA%\tana`)
- TogglTrack (`%LOCALAPPDATA%\TogglTrack`)

For each installed app, discover cache subdirectories (PowerShell `Get-ChildItem -Directory -Filter <cacheName> -Recurse -Depth 2`), then measure sizes:

- **With WizTree:** Pipe all discovered cache paths to `wt_lookup.py`
- **Fallback:** PowerShell `Get-ChildItem -Recurse`

Skip apps with < 10 MB of caches. Skip category if total < 50 MB.

**IMPORTANT:** Warn the user to close the affected apps before cleaning for best results.

Clean command (Step 6): `rm -rf <each cache directory path>/*` (contents only).

Collect: app names, sizes, paths.

---

#### Category: Stale Updater Files (Windows only)

**Skip if platform is not windows.**

Electron apps using Squirrel or similar updaters keep downloaded update packages after they've been applied.

Check these paths:
- `%LOCALAPPDATA%\@lineardesktop-updater\pending`
- `%LOCALAPPDATA%\notion-updater\pending`
- `%APPDATA%\uTorrent\updates`
- `%APPDATA%\Signal\update-cache`

Also scan Squirrel apps (`%LOCALAPPDATA%\<app>\packages\`) for old `.nupkg` files — keep only the newest, measure the rest.

Measure sizes (WizTree or fallback PowerShell).

Skip if total < 20 MB.

Clean command (Step 6): `rm -rf <each path>/*` for directories, or `rm -f <path>` for individual .nupkg files.

Collect: app names, sizes, paths.

---

#### Category: Playwright Browsers (Windows only)

**Skip if platform is not windows.**

Playwright downloads full browser binaries to `%LOCALAPPDATA%\ms-playwright\`. These can be large (200-400 MB each) and accumulate when Playwright updates.

Measure size (WizTree or fallback PowerShell). List subdirectories (browser versions).

Skip if total < 50 MB.

**Note:** Deleting Playwright browsers means they'll need to be re-downloaded on next `npx playwright install`. Only clean if you're not actively running Playwright tests.

Clean command (Step 6): `rm -rf <ms-playwright path>/*`

Collect: total size, browser list, path.

---

#### Category: Windows System Logs (Windows only)

**Skip if platform is not windows.**

Windows accumulates large log files that are safe to clean periodically:

- `C:\Windows\Logs\CBS\` — Component-Based Servicing logs (can grow to 500+ MB)
- `C:\ProgramData\Comms\PCManager\log\` — OEM PC Manager logs (Huawei, Lenovo, etc.)

Measure sizes (WizTree or fallback PowerShell). Skip paths that don't exist.

Skip if total < 50 MB.

Clean command (Step 6): Requires elevated PowerShell:
```powershell
Remove-Item "$env:SystemRoot\Logs\CBS\*" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramData\Comms\PCManager\log\*" -Recurse -Force -ErrorAction SilentlyContinue
```

Collect: breakdown by path, total size.

---

#### Category: VS Package Cache (Windows only)

**Skip if platform is not windows.**

Visual Studio stores downloaded installer packages in `C:\ProgramData\Microsoft\VisualStudio\Packages\`. This cache can grow to several GB and is safe to clean — VS will re-download packages if needed for modifications or repairs.

Measure size (WizTree or fallback PowerShell). Skip if path doesn't exist or size < 100 MB.

Clean command (Step 6): Requires elevated PowerShell:
```powershell
Remove-Item "$env:ProgramData\Microsoft\VisualStudio\Packages\*" -Recurse -Force -ErrorAction SilentlyContinue
```

**Note:** After cleaning, VS component modifications/repairs will need to re-download packages. This is fine for normal use.

Collect: size.

---

#### Category: AppData Remnants (Windows only)

**Skip if platform is not windows.**

When apps are uninstalled, their data directories in `%APPDATA%` and `%LOCALAPPDATA%` often remain. Detect orphaned directories by cross-referencing against installed programs.

Write a PowerShell temp script to `/tmp/claude-cleanup/appdata_orphans.ps1`:
```powershell
# Get list of installed programs from registry (both 64-bit and 32-bit)
$installed = @()
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($rp in $regPaths) {
    Get-ItemProperty $rp -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.DisplayName) { $installed += $_.DisplayName.ToLower() }
        if ($_.InstallLocation) { $installed += (Split-Path $_.InstallLocation -Leaf).ToLower() }
    }
}

# Known system/safe directories to skip (never flag as orphaned)
$skipDirs = @(
    'microsoft', 'windows', '.net', 'identities', 'adobe', 'intel', 'nvidia',
    'apple', 'sun', 'java', 'oracle', 'nuget', 'python', 'pip', 'npm',
    'node.js', 'git', 'ssh', 'gnupg', 'local', 'locallow', 'roaming',
    'temp', 'temporary internet files', 'packages', 'connecteddevicesplatform',
    'publishers', 'comms', 'windowsapps', 'programs', 'microsoft\windows',
    'claude-cleanup'
)

function Test-Orphaned($dirName) {
    $lower = $dirName.ToLower()
    # Skip system/known directories
    foreach ($s in $skipDirs) { if ($lower -eq $s -or $lower.StartsWith('.')) { return $false } }
    # Check if any installed program matches this directory name
    foreach ($prog in $installed) {
        if ($prog.Contains($lower) -or $lower.Contains($prog.Split(' ')[0])) { return $false }
    }
    return $true
}

# Scan both AppData locations
$locations = @($env:APPDATA, $env:LOCALAPPDATA)
foreach ($loc in $locations) {
    Get-ChildItem $loc -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-Orphaned $_.Name) {
            $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $mb = [math]::Round($s / 1MB)
            if ($mb -gt 50) {
                Write-Output "$($_.Name)|$mb|$($_.FullName)"
            }
        }
    }
}
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/appdata_orphans.ps1)"`

**With WizTree:** Instead of measuring each directory with `Get-ChildItem`, pipe discovered orphan paths to `wt_lookup.py`.

Parse output. Each line is: `dirName|sizeMB|fullPath`

Skip if no orphans found or total < 100 MB.

**IMPORTANT:** This category requires user confirmation per-item during cleanup. Present the list of detected orphans and let the user confirm which to delete — false positives are possible (portable apps, manually installed tools). Never auto-delete orphaned AppData directories.

Clean command (Step 6): `rm -rf <each confirmed orphan path>` — only after user confirms the specific items.

Collect: directory names, sizes, paths.

---

#### Category: Windows SDK Old Versions (Windows only)

**Skip if platform is not windows.**

Windows SDK installs multiple versions side-by-side in `C:\Program Files (x86)\Windows Kits\10\`. Each version includes Lib, Include, and bin directories that can be 500 MB+.

Write a PowerShell temp script to `/tmp/claude-cleanup/winsdk.ps1`:
```powershell
$sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10"
if (-not (Test-Path $sdkRoot)) { exit }

# Check Lib versions (largest component)
$libDir = Join-Path $sdkRoot "Lib"
if (Test-Path $libDir) {
    $versions = Get-ChildItem $libDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.' } |
        Sort-Object Name
    if ($versions.Count -gt 1) {
        # Keep newest, report the rest
        $old = $versions | Select-Object -SkipLast 1
        foreach ($v in $old) {
            # Sum size across Lib, Include, and bin for this version
            $totalSize = 0
            foreach ($sub in @("Lib", "Include", "bin")) {
                $vPath = Join-Path $sdkRoot "$sub\$($v.Name)"
                if (Test-Path $vPath) {
                    $s = (Get-ChildItem $vPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    $totalSize += $s
                }
            }
            if ($totalSize -gt 50MB) {
                $mb = [math]::Round($totalSize / 1MB)
                $paths = @("Lib", "Include", "bin") | ForEach-Object {
                    $p = Join-Path $sdkRoot "$_\$($v.Name)"
                    if (Test-Path $p) { $p }
                }
                Write-Output "$($v.Name)|$mb|$($paths -join ';')"
            }
        }
    }
}
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/winsdk.ps1)"`

**With WizTree:** Pipe SDK version paths to `wt_lookup.py` instead of `Get-ChildItem`.

Parse output. Each line is: `versionNumber|sizeMB|semicolonSeparatedPaths`

Skip if no old versions found.

**Note:** Only old SDK versions are flagged — the newest version is always kept. Projects pinned to a specific SDK version may break if that version is removed. Report which versions will be deleted so the user can make an informed choice.

Clean command (Step 6): Requires elevated PowerShell:
```powershell
# For each old version's paths:
Remove-Item "<sdkRoot>\Lib\<version>" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "<sdkRoot>\Include\<version>" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "<sdkRoot>\bin\<version>" -Recurse -Force -ErrorAction SilentlyContinue
```

Collect: version numbers, sizes, paths.

---

#### Category: Orphaned VS Installations (Windows only)

**Skip if platform is not windows.**

Visual Studio installations can become orphaned — directories exist in `C:\Program Files (x86)\Microsoft Visual Studio\` but the VS Installer no longer tracks them.

Write a PowerShell temp script to `/tmp/claude-cleanup/vs_orphans.ps1`:
```powershell
$vsRoot = "${env:ProgramFiles(x86)}\Microsoft Visual Studio"
if (-not (Test-Path $vsRoot)) { exit }

$vswhere = Join-Path $vsRoot "Installer\vswhere.exe"
$knownPaths = @()
if (Test-Path $vswhere) {
    $installs = & $vswhere -all -products * -format json 2>$null | ConvertFrom-Json
    foreach ($i in $installs) { $knownPaths += $i.installationPath.ToLower() }
}

# Scan for year\edition directories
Get-ChildItem $vsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{4}$' } |
    ForEach-Object {
        Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($knownPaths -notcontains $_.FullName.ToLower()) {
                $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $mb = [math]::Round($s / 1MB)
                if ($mb -gt 100) {
                    Write-Output "$($_.Parent.Name) $($_.Name)|$mb|$($_.FullName)"
                }
            }
        }
    }
```

Run: `powershell.exe -File "$(cygpath -w /tmp/claude-cleanup/vs_orphans.ps1)"`

**With WizTree:** Pipe discovered paths to `wt_lookup.py`.

Parse output. Each line is: `displayName|sizeMB|fullPath`

Skip if no orphans found.

Clean command (Step 6): Requires elevated PowerShell:
```powershell
Remove-Item "<fullPath>" -Recurse -Force -ErrorAction SilentlyContinue
```

Collect: installation names, sizes, paths.

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

For each selected category, execute the appropriate cleanup.

**Elevated cleanup (Windows):** Several categories require admin privileges. When the user selects any elevated category, batch all elevated operations into a single PowerShell script and run it with `Start-Process -Verb RunAs` (triggers one UAC prompt instead of many):

```bash
cat > /tmp/claude-cleanup/admin_cleanup.ps1 << 'PS1'
# ... all elevated Remove-Item commands ...
PS1
powershell.exe -Command "Start-Process powershell.exe -ArgumentList '-File','<windows_path_to_script>' -Verb RunAs -Wait"
```

**Categories requiring elevation:** LiveKernelReports, CBS logs, OEM logs, VS Package Cache, Delivery Optimization, Windows SDK old versions, Orphaned VS installations, Windows.old (manual only).

**Full cleanup command reference:**

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
| Crash dumps | `rm -rf <CrashDumps path>/*`. LiveKernelReports: **elevated** `Remove-Item "C:\Windows\LiveKernelReports\*" -Recurse -Force` |
| Build artifacts | `rm -rf <each artifact directory path>` |
| Docker (images) | `docker image prune -f` |
| Docker (build cache) | `docker builder prune -f` |
| App caches | `rm -rf <each large cache directory path>` |
| Windows.old | **Cannot be deleted via CLI.** Instruct the user to use Settings > System > Storage > Temporary files > Previous Windows installation(s), or Disk Cleanup as Administrator. |
| Delivery Optimization | **Elevated:** `Stop-Service DoSvc -Force; Remove-Item ...\Cache\* -Recurse -Force; Start-Service DoSvc`. If access denied, instruct user to use Settings > Storage > Temporary files. |
| Windows Temp files | **Elevated for system temp.** User temp: PowerShell `Get-ChildItem "$env:TEMP" | Where-Object { $_.Name -ne 'claude-cleanup' } | Remove-Item -Recurse -Force`. System temp: **elevated** `Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force` |
| Browser caches | `rm -rf <each cache directory path>/*` (contents only). Warn user to close browsers first. |
| Electron app caches | `rm -rf <each cache directory path>/*` (contents only). Warn user to close affected apps first. |
| Stale updater files | `rm -rf <each updater directory path>/*` for directories, `rm -f <path>` for individual .nupkg files. |
| Playwright browsers | `rm -rf <ms-playwright path>/*` |
| AppData remnants | `rm -rf <each confirmed orphan path>` — **requires per-item user confirmation** before deleting. |
| Windows SDK old versions | **Elevated:** Remove old version dirs from `Lib\`, `Include\`, `bin\` under Windows Kits. Keep newest version. |
| Orphaned VS installations | **Elevated:** `Remove-Item "<path>" -Recurse -Force` for each orphaned VS directory. |
| Windows System Logs | **Elevated:** `Remove-Item "$env:SystemRoot\Logs\CBS\*" -Force; Remove-Item "$env:ProgramData\Comms\PCManager\log\*" -Recurse -Force` |
| VS Package Cache | **Elevated:** `Remove-Item "$env:ProgramData\Microsoft\VisualStudio\Packages\*" -Recurse -Force` |

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
