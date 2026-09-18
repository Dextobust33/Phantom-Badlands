#!/usr/bin/env python3
"""Turn the in-game What's Changed entry for ONE version into GitHub release notes.

⚑ THE LAUNCHER'S "RECENT CHANGES" PANEL IS FED BY THE RELEASE BODY, and for seven releases that
body was the single line "See the in-game What's Changed screen."

Nobody decided that. `tools/release.sh` was written on 2026-09-16 to make releases one call, and
in doing so it replaced a hand-written `gh release create --notes "..."` with a placeholder.
Owner, 2026-09-17: *"who made the decision to stop putting the patch update notes on the
launcher. That's literally what that section is for, undo that."*

Hand-writing them again would only wait to go stale a second time, because the release notes and
the in-game changelog are the same information written twice. So they are written ONCE, in
`display_changelog()`, and this extracts them. The launcher and the game cannot disagree, and a
release with no changelog entry now FAILS rather than shipping a placeholder.

Usage:
    python tools/make_release_notes.py 0.9.799            # markdown to stdout
    python tools/make_release_notes.py 0.9.799 -o out.md
"""
import argparse
import os
import re
import sys

CLIENT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "client", "client.gd")

# The version header and the body lines are the same `display_game(...)` call. Anchored on the
# CALL rather than on indentation, because this block is nested in a function and its indent has
# changed before.
VERSION_LINE = re.compile(r'display_game\("\[color=#[0-9A-Fa-f]{6}\]v(\d+\.\d+\.\d+)\[/color\]')
BODY_LINE = re.compile(r'^\s*display_game\("(.*)"\)\s*$')
# The HEADLINE of an entry is whatever sits in its first colour tag. That tag IS the boundary
# between the headline and the detail - and stripping BBCode first throws it away, which is how
# the first version of this produced three undifferentiated walls of text.
LEAD = re.compile(r'^\s*\[color=#[0-9A-Fa-f]{6}\](.*?)\[/color\]\s*(.*)$', re.S)

MARKERS = ("★", "◆")   # headline change, smaller change


def strip_bbcode(text):
    """BBCode out, markdown in. Colour carries no meaning outside the game."""
    text = text.replace("[b]", "**").replace("[/b]", "**")
    text = text.replace("[i]", "_").replace("[/i]", "_")
    text = re.sub(r"\[/?color(=#[0-9A-Fa-f]{6})?\]", "", text)
    text = re.sub(r"\[/?url(=[^\]]*)?\]", "", text)
    text = text.replace('\\"', '"')      # GDScript escapes quotes inside its own literal
    return text.strip()


def split_lead(payload):
    """(headline, detail) - read the colour-tag boundary BEFORE destroying it."""
    m = LEAD.match(payload)
    if not m:
        return ("", payload)
    return (m.group(1), m.group(2))


def extract(version, source):
    """Every body line under `version`'s header, up to the blank line that closes the block."""
    lines = source.split("\n")
    start = -1
    for i, ln in enumerate(lines):
        m = VERSION_LINE.search(ln)
        if m and m.group(1) == version:
            start = i + 1
            break
    if start < 0:
        return []
    out = []
    for ln in lines[start:]:
        m = BODY_LINE.match(ln)
        if not m:
            # Comments and blank SOURCE lines sit between entries; only a `display_game("")` ends
            # the block. Anything else that is not a display call ends it too.
            if ln.strip().startswith("#") or ln.strip() == "":
                continue
            break
        payload = m.group(1)
        if payload == "":
            break
        if VERSION_LINE.search(ln):
            break            # ran into the next version without a blank line
        lead, rest = split_lead(payload)
        out.append((strip_bbcode(lead), strip_bbcode(rest)))
    return out


def to_markdown(entries):
    """Bold lead-in per entry. Not `##` headings: the launcher panel renders the body as text,
    so hashes would show up as literal hashes."""
    parts = []
    for lead, rest in entries:
        for marker in MARKERS:
            if lead.startswith(marker):
                lead = lead[len(marker):].lstrip()
                break
        parts.append(("**%s** %s" % (lead.rstrip(), rest)) if lead else rest)
    return "\n\n".join(p.strip() for p in parts) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("version")
    ap.add_argument("-o", "--out")
    ap.add_argument("--title-out", dest="title_out",
                    help="write a one-line release TITLE here (version + the headline change)")
    a = ap.parse_args()
    with open(CLIENT, encoding="utf-8") as fh:
        source = fh.read()
    entries = extract(a.version, source)
    if not entries:
        # LOUD, not silent. A release whose notes come out empty is the exact failure this ends,
        # so it must not be possible to ship one by accident.
        sys.stderr.write(
            "make_release_notes: no changelog entry for v%s in display_changelog().\n"
            "Add one to client/client.gd before releasing - the launcher's Recent Changes\n"
            "panel has nothing else to show.\n" % a.version)
        return 1
    # ⛑ THE RELEASE NEEDS A NAME, NOT JUST A NUMBER. Owner 2026-09-17: *"we should bring back
    # the summary line/update name ... instead of just the version number and a wall of text."*
    # The launcher already draws the release's `name` as a gold bold heading - but release.sh was
    # passing `--title "v0.9.802"`, so the heading said the version and the headline points sat
    # undifferentiated in the body below it. Nothing was hiding the name; nothing had written one.
    #
    # The first entry of a release is its headline by construction (the changelog is authored
    # most-important-first), so the title is that headline, trimmed to fit a heading.
    if a.title_out:
        first = entries[0][0] if entries and entries[0] else ""
        # Drop the ★ / ◆ importance marker: it is a cue INSIDE the list, and a heading
        # that opens with a floating star reads like a typo.
        for _m in MARKERS:
            first = first.replace(_m, " ")
        first = re.sub(r"\s+", " ", first).strip().rstrip(".")
        if len(first) > 72:
            first = first[:69].rstrip() + "..."
        with open(a.title_out, "w", encoding="utf-8") as fh:
            fh.write("v%s - %s" % (a.version, first) if first else "v%s" % a.version)
    md = to_markdown(entries)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(md)
        sys.stderr.write("wrote %s (%d entries)\n" % (a.out, len(entries)))
    else:
        sys.stdout.write(md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
