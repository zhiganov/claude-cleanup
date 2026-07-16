#!/usr/bin/env python3
"""Assert the composition of a scrub.ps1 list file BEFORE anything is deleted.

Usage:
    python assert_list.py <listfile> [--require LABEL=SUBSTR]...
                                     [--forbid  LABEL=SUBSTR]...
                                     [--allow-unclassified]

Pass the list path as a command-line argument (MSYS converts argv, not paths
written inside a script). Matching is FIXED-STRING and case-insensitive --
never regex.

Why this exists (2026-07-16). Building a scrub list means filtering Windows
paths in bash, and every regex-flavoured tool treats a backslash as an escape:

    grep -v '\\Claude\\' electron_paths.txt >> "$LIST"
    # -> grep: Trailing backslash
    # -> appends NOTHING, exit status lost to the redirect

The list built, `wc -l` reported a healthy 197 lines, and the run looked fine.
The entire Electron category -- 42 dirs, ~1.4 GB, the largest selection -- was
silently missing from the delete list. Worse, the verification was broken the
SAME way (`grep -c 'AppData\\Roaming'` also died on the trailing backslash and
printed 0 next to a "must be 0" check for a different row), so the wrong answer
read as a passing test.

A check that fails identically to the thing it checks is worse than no check.
So: assert composition here, in code, off argv, with fixed strings.

Exit 0 = PASS, 1 = FAIL. A --require bucket matching 0 lines is a FAIL --
a category the user selected showing zero is a bug, not a clean bill of health.
"""
import sys


def parse_pairs(args, flag):
    """Collect every `--flag LABEL=SUBSTR` into [(label, substr), ...]."""
    out = []
    i = 0
    while i < len(args):
        if args[i] == flag:
            if i + 1 >= len(args):
                sys.exit(f"assert_list: {flag} needs LABEL=SUBSTR")
            spec = args[i + 1]
            if '=' not in spec:
                sys.exit(f"assert_list: {flag} expects LABEL=SUBSTR, got {spec!r}")
            label, _, substr = spec.partition('=')
            if not substr:
                sys.exit(f"assert_list: {flag} {label!r} has an empty pattern")
            out.append((label.strip(), substr))
            i += 2
        else:
            i += 1
    return out


def main(argv):
    if not argv or argv[0].startswith('--'):
        sys.exit(__doc__)

    listfile = argv[0]
    rest = argv[1:]
    allow_unclassified = '--allow-unclassified' in rest
    requires = parse_pairs(rest, '--require')
    forbids = parse_pairs(rest, '--forbid')

    try:
        with open(listfile, encoding='utf-8') as fh:
            raw = fh.read()
    except OSError as e:
        sys.exit(f"assert_list: cannot read {listfile}: {e}")

    # Tolerate CRLF or LF; drop blanks.
    lines = [ln.strip() for ln in raw.replace('\r\n', '\n').split('\n')]
    lines = [ln for ln in lines if ln]

    print(f"list: {listfile}")
    print(f"total targets: {len(lines)}")

    failures = []

    if not lines:
        failures.append("list is EMPTY -- nothing to delete; do not invoke scrub.ps1")

    lower = [ln.lower() for ln in lines]

    def count(substr):
        s = substr.lower()
        return sum(1 for ln in lower if s in ln)

    if requires:
        print("\n  expected buckets (each must be > 0):")
        for label, substr in requires:
            n = count(substr)
            ok = n > 0
            print(f"    {label:<28} {n:>5}  {'OK' if ok else '** FAIL — selected but absent **'}")
            if not ok:
                failures.append(
                    f"require {label!r} matched 0 lines (pattern {substr!r}) -- "
                    f"a selected category missing from the list is the 2026-07-16 bug"
                )

    if forbids:
        print("\n  forbidden (each must be 0):")
        for label, substr in forbids:
            n = count(substr)
            ok = n == 0
            print(f"    {label:<28} {n:>5}  {'OK' if ok else '** FAIL — present in delete list **'}")
            if not ok:
                failures.append(f"forbid {label!r} matched {n} lines (pattern {substr!r})")

    # Anything not claimed by a require bucket is unaccounted-for deletion.
    if requires:
        claimed = set()
        for _, substr in requires:
            s = substr.lower()
            claimed.update(i for i, ln in enumerate(lower) if s in ln)
        stray = [lines[i] for i in range(len(lines)) if i not in claimed]
        print(f"\n  unclassified: {len(stray)}")
        for s in stray[:5]:
            print(f"    ? {s}")
        if len(stray) > 5:
            print(f"    ... and {len(stray) - 5} more")
        if stray and not allow_unclassified:
            failures.append(
                f"{len(stray)} line(s) match no expected bucket -- account for them "
                f"or pass --allow-unclassified"
            )

    dupes = len(lines) - len(set(lower))
    if dupes:
        print(f"\n  duplicate lines: {dupes}")

    print()
    if failures:
        print("RESULT: FAIL")
        for f in failures:
            print(f"  - {f}")
        print("\nDo NOT invoke scrub.ps1. Rebuild the list and re-assert.")
        return 1
    print("RESULT: PASS — list composition matches the selection")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
