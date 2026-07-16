#!/usr/bin/env python3
"""Enumerate node_modules and build-artifact directories from a WizTree CSV.

Usage:  python find_targets.py <csv> <workspace_root>

Pass both as command-line arguments (MSYS converts them). Emits, sorted largest
first:

    nm|<sizeMB>|<path>                 top-level node_modules (>=10 MB)
    artifact:<name>|<sizeMB>|<path>    .next/.turbo/.parcel-cache/.vite (>=10 MB)
    ---NM_TOTAL <mb> across <n>---

"Top-level" node_modules = no other `node_modules` segment higher in the path
(skips the nested ones inside a node_modules tree). This script does NOT decide
inactivity -- the skill applies the git-recency filter per project afterward, and
handles `dist/` separately (only when gitignored).
"""
import csv
import json
import os
import sys

BS = chr(92)
csv_path = sys.argv[1]
root = sys.argv[2].replace('/', BS).rstrip(BS).lower()
nm = BS + 'node_modules'
ARTIFACTS = ('.next', '.turbo', '.parcel-cache', '.vite')


def _mcp_entry_paths():
    """Lowercased file paths from every registered stdio MCP server's `args`
    in ~/.claude.json. A node_modules whose parent dir contains one of these
    backs a LIVE MCP server, so it must never be reclaimed -- the project may
    have no recent git activity but the deps are required for the server to
    start. (Book-power MCPs broke with -32000 after a cleanup wiped their
    node_modules, 2026-06-29.)"""
    out = []
    try:
        with open(os.path.expanduser('~/.claude.json'), encoding='utf-8') as fh:
            cfg = json.load(fh)
    except Exception:
        return out
    blocks = [cfg.get('mcpServers') or {}]
    for proj in (cfg.get('projects') or {}).values():
        blocks.append((proj or {}).get('mcpServers') or {})
    for block in blocks:
        for srv in block.values():
            for a in (srv or {}).get('args') or []:
                if isinstance(a, str):
                    out.append(a.replace('/', BS).lower())
    return out


_MCP_PATHS = _mcp_entry_paths()


def backs_mcp_server(server_dir_lower):
    """True if a registered MCP server's entry file lives under this dir."""
    return any(ap.startswith(server_dir_lower + BS) for ap in _MCP_PATHS)

nm_rows = []
art_rows = []
with open(csv_path, encoding='utf-8-sig') as f:
    next(f)
    reader = csv.reader(f)
    next(reader)
    for row in reader:
        p = row[0].rstrip(BS)
        pl = p.lower()
        if not pl.startswith(root + BS):
            continue
        mb = int(row[1]) // 1048576
        if mb < 10:
            continue
        if pl.endswith(nm):
            inner = pl[:-len(nm)]
            if 'node_modules' not in inner and not backs_mcp_server(inner):
                nm_rows.append((mb, p))
        else:
            base = pl.rsplit(BS, 1)[-1]
            if base in ARTIFACTS and 'node_modules' not in pl:
                art_rows.append((mb, base, p))

nm_rows.sort(reverse=True)
art_rows.sort(reverse=True)
for mb, p in nm_rows:
    print(f"nm|{mb}|{p}")
for mb, base, p in art_rows:
    print(f"artifact:{base}|{mb}|{p}")
print(f"---NM_TOTAL {sum(r[0] for r in nm_rows)} across {len(nm_rows)}---")
