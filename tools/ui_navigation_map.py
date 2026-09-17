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
    # ⚑ THE ADMIN SET IS ALREADY GROUPED IN THE SOURCE - the player commands are on the array's
    # FIRST line and the GM ones on the continuation lines after it. Reading that beats judging
    # each name, and it means the file's own layout is the authority.
    body_lines = m.group(1).split("\n")
    ADMIN.clear()
    for line in body_lines[1:]:
        ADMIN.update(re.findall(r'"([^"]+)"', line))

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
    # \u26d1 PRINTING IS NOT NAVIGATION. `display_game` and `display_chat` put a line of text in the
    # log; they open nothing. Counting them as surfaces made every arm that prints its answer
    # look like it opens a screen - and then "a button opens that surface too" was trivially
    # true, because everything in the client calls `display_game`. That single mistake is most of
    # why this list read as 78 safe when it is a small fraction of that.
    NOT_A_SURFACE = {"display_game", "display_chat", "display_game_wide", "show_status"}

    def surface_calls(text):
        out = set()
        for m in re.finditer(r"\b((?:_)?(?:display|show|open)_[a-z_0-9]+)\s*\(", text):
            if m.group(1) in NOT_A_SURFACE:
                continue
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
        rows.append({"names": names, "dests": dests, "only": only, "body": arm_text})
    return rows


## Commands that are SPEECH rather than navigation. A chat line is the right interface for
## talking to somebody, so these have no button equivalent, want none, and are not part of the
## retirement question at all. Kept as a literal list because it is a judgement about what a
## command is FOR, which no amount of source reading can derive.
## Filled by `chat_commands` from the whitelist's own line grouping - see the note there.
ADMIN = set()

## ⚑ CHECKED BY HAND AND NOT SAFE, whatever the columns say. The tool can see that a command
## opens no SURFACE; it cannot see that the capability has no ROUTE, and those are different
## statements. Each of these was traced to its handler and no non-command caller was found.
##
## Unrecorded, the next reading of this map deletes seven working features - which is the exact
## failure this file exists to prevent. Delete a row here when you give it a button.
KEEP_NO_ROUTE = {
    "clear": "no Clear button anywhere",
    "crucible": "starts the Elder gauntlet; no UI at all",
    "clanposts": "the clan post list; the Clan panel does not show it",
    "mentors": "lists online mentors; the player list shows a badge, not a list",
    "debughatch": "a dev tool sitting in the player section - belongs in /admin",
    "catches": "ONE arm with `deck`, and it is the ZONE deck preview - the Deck shortcut opens "
               "the ABILITY deck, a different screen. Retiring it deletes a feature",
    "deck": "see `catches` - same arm, and the shortcut is not the same screen",
    "bountyboard": "`_open_bounty_board()` is called only from this arm. Command-only",
    "bb": "see `bountyboard`",
}

SPEECH_COMMANDS = {
    "whisper", "w", "msg", "tell", "reply", "r",
    "c", "cc", "clanchat", "p", "pc", "partychat",
    "afk", "away", "back", "afkoff", "here",
    "clist", "clanlist", "clanonline", "who", "players",
}


def command_reach(src, cmd_dest):
    """For each command's destinations: is any of them reached from something that is NOT a
    command arm?

    ⚑ THE "ONLY DOOR" TEST IS NOT ENOUGH ON ITS OWN. It asks whether a surface is called from
    anywhere else, and another COMMAND counts as anywhere else - so two commands that open the
    same screen and nothing else both read as safe, and retiring both removes the feature. The
    audit's order is map -> give every surviving feature a button -> then retire, so what matters
    is whether a NON-command path reaches it.
    """
    i = src.find("func process_command")
    j = src.find("\nfunc ", i + 10)
    cmd_body = src[i:j if j > i else len(src)]
    rows = []
    for r in cmd_dest:
        button_reached = []
        command_only = []
        for d in r["dests"]:
            total = len(re.findall(re.escape(d) + r"\s*\(", src))
            in_cmds = len(re.findall(re.escape(d) + r"\s*\(", cmd_body))
            if total - in_cmds > 0:
                button_reached.append(d)
            else:
                command_only.append(d)
        speech = all((n in SPEECH_COMMANDS) for n in r["names"])
        admin = any((n in ADMIN) for n in r["names"])
        # \u2691 DOES IT TAKE AN ARGUMENT? `/block bob` is not replaced by a button that opens the
        # block LIST - "open the screen" and "do this to THAT name" are different capabilities,
        # and only the first is what `dests` checks.
        #
        # \u26d1 THE FIRST VERSION LOOKED FOR `parts[` ONLY, and missed TWELVE arms that read their
        # words as `text.split(" ", false, 1)` instead - `/duel <player> [stakes]`,
        # `/spendstat <stat>`, `/clandesc <text>`, `/settitle`, `/vault <sub>` and more. Every
        # one of them was sitting in the "safe to retire" list. A detector that recognises one
        # spelling of a thing reports the others as absent, and here "absent" meant "delete it".
        body_txt = r.get("body", "")
        # \u26d1 FOUR SPELLINGS SO FAR: `parts[...]`, `text.split(...)`, `parts.slice(...)` - which
        # is how `/search <term>` reached the approved list - and `parts.size()`. The last is the
        # reliable one: an arm that reads arguments has to ASK how many there are first, whatever
        # it does with them afterwards. The others are kept because an arm could read `parts[1]`
        # without checking, and being wrong here means deleting a capability.
        takes_arg = bool(re.search(r"\bparts\s*(\[|\.\s*(size|slice)\s*\()", body_txt)) \
            or bool(re.search(r"\btext\s*\.\s*(split|substr|to_lower|strip_edges)\s*\(", body_txt))
        rows.append({"names": r["names"], "dests": r["dests"], "speech": speech, "admin": admin,
                     "takes_arg": takes_arg,
                     "button": button_reached, "command_only": command_only})
    return rows


def orphan_handlers(src):
    """`_on_*_pressed` / `_on_*_toggled` functions that nothing connects.

    ⚑ THE MIRROR OF THE DEAD-BUTTON CHECK, and it found a real one: `_on_bug_button_pressed`
    was complete, correct and connected to NOTHING, so reporting a bug was command-only - the
    worst thing in the game to be command-only, since a player who has just hit a bug is exactly
    the one who does not know the command.

    The map looks for entry points that reach nothing. This is the opposite: a destination
    nothing reaches, and from the source it looks exactly like a working feature.
    """
    out = []
    for m in re.finditer(r"^func (_on_[a-z_0-9]+)\(", src, re.M):
        name = m.group(1)
        # Connected by name, or referenced as a Callable (`.connect(name)`, `bind`, a dict value)
        uses = len(re.findall(r"\b" + re.escape(name) + r"\b", src))
        if uses <= 1:
            out.append(name)
    return out


def main():
    src = client_gd()
    listed, handled = chat_commands(src)
    pl = panels(src)
    offered, ab_handled = action_bar(src)
    cmd_dest = command_destinations(src)
    orphans = orphan_handlers(src)
    sole_doors = [r for r in cmd_dest if r["only"]]
    reach = command_reach(src, cmd_dest)
    speech = [r for r in reach if r["speech"] and not r["admin"]]
    admin = [r for r in reach if r["admin"]]
    rest = [r for r in reach if not r["speech"] and not r["admin"]]
    needs_button = [r for r in rest if r["command_only"]]
    argy = [r for r in rest if r["takes_arg"]]
    plain = [r for r in rest if not r["takes_arg"]]
    kept = [r for r in plain if any((n in KEEP_NO_ROUTE) for n in r["names"])]
    plain = [r for r in plain if not any((n in KEEP_NO_ROUTE) for n in r["names"])]
    retirable = [r for r in plain if not r["command_only"] and r["dests"]]
    no_surface = [r for r in plain if not r["dests"]]

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
    A("| ...that are SPEECH, not navigation (not part of the sweep) | %d |" % len(speech))
    A("| ...that are ADMIN tools (a separate decision, see CLAUDE.md) | %d |" % len(admin))
    A("| ...that take a TARGET argument (a button may not be able to) | **%d** |" % len(argy))
    A("| ...kept after a HAND check found no route (see below) | %d |" % len(kept))
    A("| ...whose surface only COMMANDS reach (need a button first) | **%d** |" % len(needs_button))
    A("| ...reaching a surface a button also reaches (safe to retire) | %d |" % len(retirable))
    A("| ...opening no surface at all (pure navigation, safe to retire) | %d |" % len(no_surface))
    A("| ...with no arm in `process_command` | **%d** |" % len(dead_cmd))
    A("| ...handled but not whitelisted (unreachable by typing) | **%d** |" % len(unlisted))
    A("| panel scripts | %d |" % len(pl))
    A("| ...never opened from `client.gd` | **%d** |" % len(orphan_panels))
    A("| local action-bar ids offered | %d |" % len(offered))
    A("| ...with no case in `execute_local_action` (click does nothing) | **%d** |" % len(dead_buttons))
    A("| `_on_*` handlers nothing connects (a feature with no door) | **%d** |" % len(orphans))
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
    if orphans:
        A("**Handlers nothing connects** — the mirror of a dead button: a destination nothing")
        A("reaches, which from the source looks exactly like a working feature. This is how")
        A("reporting a bug stayed command-only (`_on_bug_button_pressed` was never wired).")
        A("")
        A("Each one is either a MISSING DOOR or DEAD CODE, and the tool cannot tell which — read")
        A("it before acting. `_on_move_button` is the known dead-code case: a movement-pad handler")
        A("from a pad that no longer exists. It is kept deliberately, as the obvious starting")
        A("point for the touch controls the phone-support item will need.")
        A("")
        A("`" + "`, `".join(orphans) + "`")
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
    A("### ⛑ THE RETIREMENT LIST, in the three groups it has to be worked in")
    A("")
    A("The audit's order is *map → give every surviving feature a button → then retire the")
    A("commands*. These are those groups.")
    A("")
    A("**SPEECH — not part of the sweep at all (%d).** A chat line is the right interface for" % len(speech))
    A("talking to somebody; these have no button equivalent and want none. Retiring them because")
    A("they begin with a slash would delete the ability to whisper.")
    A("")
    A("> " + ", ".join(sorted("`/%s`" % n for r in speech for n in r["names"])))
    A("")
    A("**ADMIN — a separate decision, and not implied by the ask (%d).** CLAUDE.md: *\"Existing" % len(admin))
    A("chat admin commands stay as fallbacks — don't migrate in a cleanup pass without explicit")
    A("ask (muscle memory).\"* And *\"we no longer use those\"* is the opposite of true for the")
    A("owner's own tools. Grouped from the whitelist's own line layout, not judged by name.")
    A("")
    A("> " + ", ".join(sorted("`/%s`" % n for r in admin for n in r["names"])))
    A("")
    A("**KEPT — the columns call these safe and a hand check says they are not (%d).**" % len(kept))
    A("")
    A("The tool can see that a command opens no SURFACE. It cannot see that the CAPABILITY has no")
    A("route, and those are different statements. Each was traced to its handler and no")
    A("non-command caller was found.")
    A("")
    if kept:
        A("| command(s) | why it survives |")
        A("|---|---|")
        for r in kept:
            why = ""
            for n in r["names"]:
                if n in KEEP_NO_ROUTE:
                    why = KEEP_NO_ROUTE[n]
                    break
            A("| %s | %s |" % (", ".join("`/%s`" % n for n in r["names"]), why))
    A("")
    A("**TAKES AN ARGUMENT — check the button can supply it (%d).** `/block bob` is not" % len(argy))
    A("replaced by a button that opens the block LIST: *open the screen* and *do this to THAT")
    A("name* are different capabilities, and only the first is what the destination check")
    A("answers. Detected by the arm reading `parts[...]`.")
    A("")
    A("> " + ", ".join(sorted("`/%s`" % n for r in argy for n in r["names"])))
    A("")
    A("**NEEDS A BUTTON FIRST (%d)** — the surface these open is reached from no non-command" % len(needs_button))
    A("path, so retiring them removes a feature rather than a shortcut.")
    A("")
    if needs_button:
        A("| command(s) | the surface only commands reach |")
        A("|---|---|")
        for r in needs_button:
            A("| %s | `%s` |" % (", ".join("`/%s`" % n for n in r["names"]),
                                 "`, `".join(r["command_only"])))
    else:
        A("> None.")
    A("")
    A("**SAFE TO RETIRE (%d + %d)** — %d open a surface a button also opens, and %d open no"
      % (len(retirable), len(no_surface), len(retirable), len(no_surface)))
    A("surface at all (they send a server message, set a flag or print a line).")
    A("")
    A("> " + ", ".join(sorted("`/%s`" % n for r in (retirable + no_surface) for n in r["names"])))
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
    print("  orphan handlers    %d _on_* functions nothing connects" % len(orphans))
    print("  command doors      %d arms, %d are a surface's ONLY door" % (len(cmd_dest), len(sole_doors)))
    print("  retirement         %d speech, %d admin, %d argument, %d kept by hand, %d safe"
          % (len(speech), len(admin), len(argy), len(kept),
             len(retirable) + len(no_surface)))
    if "--print" in sys.argv:
        print()
        print("\n".join(lines))


if __name__ == "__main__":
    main()
