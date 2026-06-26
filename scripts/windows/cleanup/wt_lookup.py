#!/usr/bin/env python3
"""WizTree size lookup.

Usage:  printf '%s\\n' 'C:\\path\\one' 'C:\\path\\two' | python wt_lookup.py <csv>

Reads the WizTree CSV path from argv[1] (pass it as a command-line argument so
MSYS converts /tmp/... to a real Windows path -- a hardcoded /tmp path inside the
script does NOT get converted and fails with FileNotFoundError). Query paths come
in on stdin, one per line. Emits `sizeMB|path` per line; unknown paths report 0.
"""
import csv
import sys

BS = chr(92)  # backslash, written via chr() so heredocs can't mangle it

sizes = {}
with open(sys.argv[1], encoding='utf-8-sig') as f:
    next(f)            # skip WizTree comment line
    reader = csv.reader(f)
    next(reader)       # skip header row
    for row in reader:
        path = row[0].rstrip(BS)
        sizes[path.lower()] = int(row[1])

for line in sys.stdin:
    qpath = line.strip().lower().rstrip(BS)
    print(f"{sizes.get(qpath, 0) // 1048576}|{line.strip()}")
