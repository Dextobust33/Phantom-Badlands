"""THE UI / NAVIGATION MAP, derived from the source rather than written by hand.

Owner 2026-09-17: *"At some point we need to go through every menu path in the game, assess what
is still being used and what can be removed/retired, as well as ways to simplify them. We
mentioned controller support or phone support at some point, that simplification will be crucial
to that kind of support."*

The backlog item says what the audit has to PRODUCE before anything is deleted:

    every surface -> its entry points -> its one-line VERB.
    A surface with no entry point is dead. Two surfaces with the same verb are a merge.
    An entry point that reaches nothing is a dead button.

⚑ WHY THIS IS A TOOL AND NOT A DOCUMENT. A hand-written map of 28 panels, 119 chat commands and
the action bar is stale the day after it is written, and the whole point of the audit is to decide
what to DELETE - a decision that must not be made against a stale map. Generated, it can be re-run
after every deletion to prove the deletion did not orphan something else.

⚑ AND IT ANSWERS THE ONE QUESTION THAT BLOCKS RETIRING THE CHAT COMMANDS. The backlog records the
measured reason not to sweep them: `/dungeons` was the ONLY route to the dungeon list, so deleting
commands first would have removed a feature rather than a navigation path. This prints, for every
command, whether anything else reaches the same place - which is exactly the list needed to retire
them safely.

WHAT IT CANNOT SEE, stated so nobody trusts it too far:
  * a button whose handler exists but is unreachable because its MODE is never entered
  * a panel shown only from a branch that no longer runs
  * whether two surfaces with different verbs are the same thing to a PLAYER
Those need the game run. This narrows the search from "every menu in the game" to the rows it
flags.

USAGE
    python tools/ui_navigation_map.py            # writes docs/design/ui_navigation_map.md
    python tools/ui_navigation_map.py --print    # ...and echo the summary
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLIENT = os.path.join(ROOT, "client")
OUT = os.path.join(ROOT, "docs", "design", "ui_navigation_map.md")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def client_gd():
    return read(os.path.join(CLIENT, "client.gd"))


def join_continuations(text):
    """Fold GDScript `\\` line continuations onto one line.

    ⚑ WITHOUT THIS EVERY MULTI-LINE MATCH ARM READS AS UNHANDLED. Ten `help_*` action ids share a
    single arm written across four continued lines, and a line-by-line parser saw none of them -
    so the first run of this tool proposed deleting ten working buttons.
    """
    out = []
    for line in text.split("\n"):
        if out and out[-1].endswith("\\"):
            out[-1] = out[-1][:-1].rstrip() + " " + line.strip()
        else:
            out.append(line)
    return "\n".join(out)


def match_arms(body, depth):
    """The arms of a match at exactly `depth` tabs. Deeper arms belong to a NESTED match.

    ⚑ `process_command` contains sub-command matches (`/clan invite`, `/vault deposit`), so a
    depth-blind scan reports 23 sub-commands as top-level commands nothing can type.
    """
    pref = "\t" * depth + '"'
    found = set()
    for line in join_continuations(body).split("\n"):
        if not line.startswith(pref):
            continue
        t = line.strip()
        if re.fullmatch(r'("(?:[^"]+)"(?:\s*,\s*"[^"]+")*)\s*:', t):
            found.update(re.findall(r'"([^"]+)"', t))
    return found


def prefix_handled(body):
    """Ids handled by a PREFIX test rather than a match arm (`begins_with("job_commit_")`)."""
    return set(re.findall(r'begins_with\("([a-z_0-9]+)"\)', body))


# ══════════════════════════════════════════════════════════════════════════════════════════════
# CHAT COMMANDS
# ══════════════════════════════════════════════════════════════════════════════════════════════
def chat_commands(src):
    """Every whitelisted command, and whether `process_command` has an arm for it.

    Two separate registrations, which Pitfall #6 in CLAUDE.md exists because of: the
    `command_keywords` whitelist routes to `process_command`, and `process_command`'s match
    handles it. A command in one and not the other is a dead entry point either way round.
    """
    m = re.search(r"var command_keywords = \[(.*?)\]\n", src, re.S)
    if not m:
        return [], []
    listed = re.findall(r'"([^"]+)"', m.group(1))

    # the match arms of process_command: `"a", "b":` at one tab inside the function
    i = src.find("func process_command")
    j = src.find("\nfunc ", i + 10)
    body = src[i:j if j > i else len(src)]
    # Depth 2: `func` at 0, the `match` at 1, its arms at 2. Anything deeper is a SUB-command.
    handled = match_arms(body, 2) | prefix_handled(body)
    return listed, sorted(handled)


# ══════════════════════════════════════════════════════════════════════════════════════════════
# PANELS
# ══════════════════════════════════════════════════════════════════════════════════════════════
def panels(src):
    """Each `client/*_panel.gd`, its docstring verb, and how many places open it.

    "Opened" is counted as a `.visible = true`, an `.open`/`.show`/`.populate` call or an
    `enter_*` on the panel's variable name - the idioms this client actually uses. A panel with a
    script and no opener is the audit's "surface with no entry point".
    """
    out = []
    for fn in sorted(os.listdir(CLIENT)):
        if not fn.endswith("_panel.gd"):
            continue
        base = fn[:-3]                       # e.g. quest_board_panel
        text = read(os.path.join(CLIENT, fn))
        # ⚑ THE TOP OF THE FILE, NOTHING ELSE. Two earlier versions read a method's docstring
        # instead of the file's: searching the whole text found the first `##` anywhere, and
        # splitting on "\nfunc " does not stop at `static func`, so the header ran on past them.
        # `combat_scene_panel.gd` came out as "hide_picker" - a column of method names, useless
        # for the audit's actual question.
        verb = ""
        for raw in text.split("\n")[:40]:
            t = raw.strip()
            if t == "" or t.startswith("extends") or t.startswith("class_name") or t.startswith("@"):
                continue
            if t.startswith("##") or t.startswith("#"):
                verb = t.lstrip("#").strip()
                break
            break            # the first non-comment, non-header line: this file has no header doc
        verb = verb.strip('"').strip()
        # ⚑ ANY CALL, NOT A WHITELIST OF VERBS. The first version listed the verbs it expected
        # ("open", "show", "populate", ...) and therefore called `show_with_payload` and
        # `open_combat` dead - two live panels, in a tool whose output is a deletion list. Every
        # panel names its own opener, so a whitelist can never be complete.
        opens = 0
        verbs = set()
        for m in re.finditer(re.escape(base) + r"\s*\.\s*([a-zA-Z_0-9]+)\s*(\(|=)", src):
            # NOT named `verb`: that is the file's header doc, computed above, and reusing the
            # name here silently overwrote it with the last method call on the panel.
            mname, punct = m.group(1), m.group(2)
            if mname in ("connect", "disconnect", "emit", "new", "free", "queue_free"):
                continue
            if punct == "=" and mname != "visible":
                continue          # `panel.visible = true` opens it; other assignment is config
            verbs.add(mname)
            opens += 1
        # instantiated at all?
        made = src.count(base.title().replace("_", "") + "Script") + \
            src.count('preload("res://client/%s")' % fn)
        out.append({"file": fn, "var": base, "verb": verb, "opens": opens, "wired": made,
                    "verbs": ", ".join(sorted(verbs)[:6])})
    return out


# ══════════════════════════════════════════════════════════════════════════════════════════════
# ACTION BAR
# ══════════════════════════════════════════════════════════════════════════════════════════════
def action_bar(src):
    """Local action ids offered by the bar, against the cases `execute_local_action` handles.

    Pitfall #11 in CLAUDE.md: a `action_type: "local"` button needs a matching case or clicking it
    does nothing while its hotkey works. That is a dead button by the audit's definition, and it
    is invisible unless you click every button in every mode.
    """
    # The field is `action_data`, not `action`. The first version of this looked for `"action":`
    # and found ZERO local ids - and a detector that finds nothing looks exactly like one that
    # finds no faults, which is why the tool PRINTS the count rather than only the mismatches.
    offered = set(re.findall(
        r'"action_type"\s*:\s*"local"\s*,\s*"action_data"\s*:\s*"([a-z_0-9]+)"', src))
    offered |= set(re.findall(
        r'"action_data"\s*:\s*"([a-z_0-9]+)"\s*,\s*"action_type"\s*:\s*"local"', src))
    i = src.find("func execute_local_action")
    j = src.find("\nfunc ", i + 10)
    body = src[i:j if j > i else len(src)]
    handled = match_arms(body, 2) | match_arms(body, 1) | match_arms(body, 3)
    # ...and the prefix tests, which are not arms at all: `job_commit_<job>` is generated, so no
    # match case can ever exist for it.
    prefixes = prefix_handled(body)
    handled |= prefixes
    offered = set(a for a in offered
                  if a in handled or not any(a.startswith(pfx) for pfx in prefixes))
    return sorted(offered), sorted(handled)


def command_destinations(src):
    """For each top-level command arm: what it calls, and whether anything else calls the same.

    ⚑ THIS IS THE SECTION THAT MAKES THE COMMAND SWEEP SAFE. `/dungeons` was the ONLY route to
    the dungeon list, so a sweep done before the audit would have deleted a feature and called it
    tidying. A command is safe to retire when everything it reaches is also reached from
    somewhere else; it needs a button FIRST when it is the only caller.

    "Reaches" = the `display_*` / `show_*` / `open_*` / `_display_*` calls and panel openers in
    its arm. Deliberately narrow: those are the calls that put a SURFACE in front of the player,
    which is what a navigation audit is about. A command that only sends a server message or sets
    a flag has no surface of its own and needs no button.
    """
    i = src.find("func process_command")
    j = src.find("\nfunc ", i + 10)
    body = join_continuations(src[i:j if j > i else len(src)])
    arms = []               # (names, [lines])
    cur = None
    for line in body.split("\n"):
        if line.startswith('\t\t"') and re.fullmatch(r'("(?:[^"]+)"(?:\s*,\s*"[^"]+")*)\s*:', line.strip()):
            if cur:
                arms.append(cur)
            cur = (re.findall(r'"([^"]+)"', line.strip()), [])
        elif cur is not None:
            cur[1].append(line)
    if cur:
        arms.append(cur)

    # How many times each surface-opening call appears in the WHOLE client
    def surface_calls(text):
        out = set()
        for m in re.finditer(r"\b((?:_)?(?:display|show|open)_[a-z_0-9]+)\s*\(", text):
            out.add(m.group(1))
        for m in re.finditer(r"\b([a-z_0-9]+_panel)\s*\.\s*(open[a-z_0-9]*|show[a-z_0-9]*)\s*\(", text):
            out.add("%s.%s" % (m.group(1), m.group(2)))
        return out

    rows = []
    for names, lines in arms:
        arm_text = "\n".join(lines)
        dests = sorted(surface_calls(arm_text))
        only = []
        for d in dests:
            # count elsewhere: total occurrences minus the ones inside this arm
            total = len(re.findall(re.escape(d) + r"\s*\(", src))
            here = len(re.findall(re.escape(d) + r"\s*\(", arm_text))
            if total - here <= 0:
                only.append(d)
        rows.append({"names": names, "dests": dests, "only": only})
    return rows


def main():
    src = client_gd()
    listed, handled = chat_commands(src)
    pl = panels(src)
    offered, ab_handled = action_bar(src)
    cmd_dest = command_destinations(src)
    sole_doors = [r for r in cmd_dest if r["only"]]

    dead_cmd = [c for c in listed if c not in handled]
    unlisted = [c for c in handled if c not in listed]
    orphan_panels = [p for p in pl if p["opens"] == 0]
    dead_buttons = [a for a in offered if a not in ab_handled]

    lines = []
    A = lines.append
    A("# UI / navigation map")
    A("")
    A("**Generated by `tools/ui_navigation_map.py` — do not edit by hand.** Re-run it after every")
    A("deletion; the point of the audit is to decide what to remove, and that decision must not be")
    A("made against a stale map.")
    A("")
    A("Produced for the backlog's *FULL UI / NAVIGATION AUDIT*, which asks for every surface, its")
    A("entry points and its one-line verb — *a surface with no entry point is dead, two surfaces")
    A("with the same verb are a merge, an entry point that reaches nothing is a dead button.*")
    A("")
    A("## Headline counts")
    A("")
    A("| | count |")
    A("|---|---|")
    A("| chat commands whitelisted | %d |" % len(listed))
    A("| ...that are the ONLY door to a surface (need a button before retiring) | **%d** |"
      % len(sole_doors))
    A("| ...with no arm in `process_command` | **%d** |" % len(dead_cmd))
    A("| ...handled but not whitelisted (unreachable by typing) | **%d** |" % len(unlisted))
    A("| panel scripts | %d |" % len(pl))
    A("| ...never opened from `client.gd` | **%d** |" % len(orphan_panels))
    A("| local action-bar ids offered | %d |" % len(offered))
    A("| ...with no case in `execute_local_action` (click does nothing) | **%d** |" % len(dead_buttons))
    A("")

    A("## Dead ends")
    A("")
    if dead_cmd:
        A("**Whitelisted with no handler** — typing these reaches `process_command` and falls")
        A("through, so they are already retired in everything but the whitelist:")
        A("")
        A("`" + "`, `".join(dead_cmd) + "`")
        A("")
    else:
        A("Every whitelisted command has a handler.")
        A("")
    if unlisted:
        A("**Handled but not whitelisted** — the code to run them exists and nothing can type them.")
        A("Either the feature has another door or it is unreachable:")
        A("")
        A("`" + "`, `".join(unlisted) + "`")
        A("")
    if dead_buttons:
        A("**Action-bar ids with no `execute_local_action` case** — CLICKING these does nothing")
        A("while the hotkey may still work (CLAUDE.md pitfall #11):")
        A("")
        A("`" + "`, `".join(dead_buttons) + "`")
        A("")
    if orphan_panels:
        A("**Panels nothing appears to open:**")
        A("")
        for p in orphan_panels:
            A("* `%s` — %s" % (p["file"], p["verb"][:110] or "(no docstring)"))
        A("")
        A("Read before believing: a panel may be opened by another PANEL rather than by")
        A("`client.gd`, which this tool does not follow.")
        A("")

    A("## Surfaces")
    A("")
    A("| panel | calls from client.gd | how it is reached | verb (its own docstring) |")
    A("|---|---|---|---|")
    for p in sorted(pl, key=lambda x: -x["opens"]):
        A("| `%s` | %d | %s | %s |" % (
            p["file"], p["opens"], p["verbs"] or "—",
            (p["verb"][:130] or "—").replace("|", "/")))
    A("")

    A("## Chat commands, grouped by whether anything else reaches the same place")
    A("")
    A("The measured reason the backlog gives for not sweeping the commands first: **`/dungeons` was")
    A("the only route to the dungeon list**, so deleting commands before the audit would have")
    A("removed features rather than navigation. This is the list to work through — a command whose")
    A("destination has a button is safe to retire; one whose destination has none needs a button")
    A("first.")
    A("")
    A("### ⛑ These are a feature's ONLY door — give each a button before retiring it")
    A("")
    if sole_doors:
        A("| command(s) | the surface only they open |")
        A("|---|---|")
        for r in sole_doors:
            A("| %s | `%s` |" % (", ".join("`/%s`" % n for n in r["names"]),
                                 "`, `".join(r["only"])))
    else:
        A("None — every command's surface is reachable from somewhere else as well.")
    A("")
    A("### Every command, and where it goes")
    A("")
    A("A blank destination means the command opens no surface of its own (it sends a server")
    A("message, sets a flag, or prints a line), so retiring it removes navigation and not a")
    A("feature.")
    A("")
    A("| command(s) | opens |")
    A("|---|---|")
    for r in cmd_dest:
        A("| %s | %s |" % (", ".join("`/%s`" % n for n in r["names"]),
                           ("`" + "`, `".join(r["dests"]) + "`") if r["dests"] else "—"))
    A("")
    A("## What this tool cannot see")
    A("")
    A("* a button whose handler exists but whose MODE is never entered")
    A("* a panel shown only from a branch that no longer runs")
    A("* whether two surfaces with different verbs are the same thing to a PLAYER")
    A("")
    A("Those need the game run. This narrows the search from *every menu in the game* to the rows")
    A("flagged above.")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")

    print("wrote %s" % os.path.relpath(OUT, ROOT))
    print("  chat commands      %d whitelisted, %d with no handler, %d handled-but-untypable"
          % (len(listed), len(dead_cmd), len(unlisted)))
    print("  panels             %d scripts, %d never opened from client.gd" % (len(pl), len(orphan_panels)))
    print("  action bar         %d local ids, %d with no case" % (len(offered), len(dead_buttons)))
    print("  command doors      %d arms, %d are a surface's ONLY door" % (len(cmd_dest), len(sole_doors)))
    if "--print" in sys.argv:
        print()
        print("\n".join(lines))


if __name__ == "__main__":
    main()
