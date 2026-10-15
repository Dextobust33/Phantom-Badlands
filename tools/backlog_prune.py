#!/usr/bin/env python3
"""Move CLOSED top-level items of docs/BACKLOG.md into a dated archive file.

Why this exists: the backlog had grown past 10,000 lines of mostly ticked history, which made it slow to
read, hard to plan from, and is how finished work kept being re-offered. Closed history belongs in the
archive (docs/archive/), searchable but out of the way.

What counts as CLOSED: a column-0 list item whose box is [x] (done) or [✗] (withdrawn), together with every
indented / blank line that follows it up to the next column-0 line. Open items ([ ]), headings and plain
paragraphs are never touched, and an open item keeps its own ticked sub-bullets (they are indented).

    python tools/backlog_prune.py              # dry run: prints what would move
    python tools/backlog_prune.py --apply      # write the archive and the slimmer backlog

Safety: it refuses to apply unless the set of OPEN top-level items is identical before and after.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKLOG = os.path.join(ROOT, "docs", "BACKLOG.md")
ARCHIVE = os.path.join(ROOT, "docs", "archive", "BACKLOG_closed_to_2026-10-15.md")
ITEM = re.compile(r"^(?:\d+\.\s+)?-\s+\[(x|✗| )\]")


def split_blocks(lines):
    """[(is_item, box, [lines])] - a run of non-item lines, or one item with its indented body."""
    out = []
    i = 0
    n = len(lines)
    while i < n:
        m = ITEM.match(lines[i])
        if not m:
            j = i
            while j < n and not ITEM.match(lines[j]):
                j += 1
            out.append((False, "", lines[i:j]))
            i = j
            continue
        j = i + 1
        while j < n:
            ln = lines[j]
            if ln.strip() == "" or ln[:1] in (" ", "\t"):
                j += 1
                continue
            break
        # trailing blank lines belong to the gap, not to the item, so a kept item keeps its spacing
        k = j
        while k > i + 1 and lines[k - 1].strip() == "":
            k -= 1
        out.append((True, m.group(1), lines[i:k]))
        if k < j:
            out.append((False, "", lines[k:j]))
        i = j
    return out


def main():
    apply = "--apply" in sys.argv
    raw = open(BACKLOG, encoding="utf-8", newline="").read()
    eol = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.replace("\r\n", "\n").split("\n")
    blocks = split_blocks(lines)
    keep, closed = [], []
    nested = re.compile(r"^\s+(?:\d+\.\s+)?-\s+\[ \]")
    open_before = [b[2][0] for b in blocks if b[0] and b[1] == " "]
    # A nested OPEN sub-item counts too: the first run archived "[17] NOT STARTED" because it sat inside a
    # ticked parent, and a top-level-only check could not see it go.
    nested_before = sum(1 for b in blocks for ln in b[2] if nested.match(ln))
    kept_for_nested = 0
    for is_item, box, body in blocks:
        if is_item and box in ("x", "✗") and any(nested.match(ln) for ln in body):
            keep.append(body)           # closed parent, open child: stays where the work is still visible
            kept_for_nested += 1
        elif is_item and box in ("x", "✗"):
            closed.append(body)
        else:
            keep.append(body)
    kept_lines = [ln for body in keep for ln in body]
    open_after = [b[2][0] for b in split_blocks(kept_lines) if b[0] and b[1] == " "]
    moved = sum(len(b) for b in closed)
    print("%d lines total; %d closed items (%d lines) would move; %d lines stay" % (
        len(lines), len(closed), moved, len(kept_lines)))
    nested_after = sum(1 for ln in kept_lines if nested.match(ln))
    print("open items before/after: %d / %d; nested open sub-items before/after: %d / %d (%d closed parents kept for them)" % (
        len(open_before), len(open_after), nested_before, nested_after, kept_for_nested))
    if open_before != open_after or nested_before != nested_after:
        print("REFUSING: the open items changed")
        return 1
    if not apply:
        print("dry run - pass --apply to write")
        return 0
    os.makedirs(os.path.dirname(ARCHIVE), exist_ok=True)
    head = ["# Master Backlog - CLOSED items moved out 2026-10-15", "",
            "Everything below was a ticked ([x]) or withdrawn ([✗]) top-level item of `docs/BACKLOG.md`,",
            "moved here verbatim and in original order by `tools/backlog_prune.py`. Search this file before",
            "re-opening anything: several entries record why an approach was REJECTED.", "", "---", ""]
    body = []
    for b in closed:
        body.extend(b)
        body.append("")
    with open(ARCHIVE, "w", encoding="utf-8", newline="") as f:
        f.write(eol.join(head + body))
    pointer = ("> Closed (ticked) items live in `docs/archive/BACKLOG_closed_to_2026-10-15.md`; "
               "`tools/backlog_prune.py` moves new ones there.")
    out = kept_lines
    for idx, ln in enumerate(out):
        if ln.startswith("History lives in `docs/archive/BACKLOG_journal_to_2026-09-07.md`"):
            out = out[:idx] + [pointer, ""] + out[idx:]
            break
    with open(BACKLOG, "w", encoding="utf-8", newline="") as f:
        f.write(eol.join(out))
    print("wrote", ARCHIVE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
