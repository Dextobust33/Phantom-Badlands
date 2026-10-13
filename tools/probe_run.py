#!/usr/bin/env python3
"""Run probes ONE AT A TIME and fail on anything a bare exit code hides.

WHY THIS EXISTS (2026-10-13). Three bugs in one session - the threat-quest dungeon entry, the rescue
NPC placement, and a stranded player after a quest abandon - had the same shape: a script ERROR that
the live server never reports. The exported (release) server is built without GDScript's debug
checks, so `Invalid access to property or key` does not stop anything: the expression quietly yields
null and the code carries on into a corrupt state. The journal showed no runtime error for a bug that
stranded a player. A DEBUG run prints the error; nothing was reading it:

  * a probe can print `SCRIPT ERROR` and still print PASS and exit 0 (several do, today);
  * `tools/test_setup/shots.py` threw the server's output away entirely.

So a probe is judged on four things, not one:
  1. exit status is 0 and it did not time out (a probe that fails to PARSE never exits at all - see
     CLAUDE.md - so the timeout is a verdict, not a nuisance);
  2. its own output carries a PASS verdict (exit 0 with no verdict line is not a pass);
  3. it printed no `SCRIPT ERROR` / `Parse Error` / `Invalid call` line;
  4. ...unless that exact line is listed in tools/probe/script_error_allowlist.txt WITH a reason, so
     known noise is recorded rather than silently tolerated, and a NEW error is never hidden by it.

Usage:
    python tools/probe_run.py --smoke            # the release gate's set (a few minutes)
    python tools/probe_run.py --all              # all of tools/probe/*.gd (long - run it in the background)
    python tools/probe_run.py name1 name2        # specific probes (no .gd)
    python tools/probe_run.py --all --report out.txt
Exit status is non-zero if ANY probe failed any of the four tests.
"""
import os
import re
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PROBE_DIR = os.path.join(HERE, "probe")
ALLOWLIST = os.path.join(PROBE_DIR, "script_error_allowlist.txt")
GODOT = os.environ.get("GODOT_BIN", r"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe")
TIMEOUT_S = int(os.environ.get("PROBE_TIMEOUT", "240"))
# Seconds of silence after a script error before the probe is declared hung and killed.
ERROR_QUIET_S = float(os.environ.get("PROBE_ERROR_QUIET", "12"))

# The release gate. Chosen to cover the surfaces this class has bitten, and to stay a few minutes:
# dungeon entry/erase/placement/loot, the map-canvas ownership rule, and the loader.
SMOKE = [
    "threat_quest_entry_has_an_interior",
    "rescue_npc_is_reachable",
    "erasing_a_dungeon_never_strands_its_occupants",
    "world_dungeon_roll_is_uniform",
    "floor_loot_matches_the_floor",
    "a_menu_page_owns_the_canvas",
    "nothing_paints_over_a_waiting_page",
    "the_map_has_one_home_per_situation",
    "a_choice_is_never_text",
    "lazy_dungeon_interior",
    "dungeon_grade_truth",
    "dungeon_card_reward",
    "danger_words_agree",
    "danger_step_guard",
    "escort_flag_is_server_only",
]

ERROR_RE = re.compile(r"(SCRIPT ERROR|Parse Error|Invalid call\.|Invalid access to property|Invalid get index|Invalid set index)")
# A verdict is the probe's own PASS line. FAIL anywhere on a verdict-looking line overrides it.
PASS_RE = re.compile(r"(\]\s*PASS\b|^PASS\b|ALL PASS|all checks PASS|VERDICT)", re.M)
FAIL_RE = re.compile(r"(\]\s*FAIL\b|^FAIL\b|FAILURES|SOME FAIL)", re.M)


def load_allowlist():
    """Lines of `regex<TAB>reason`. A line without a reason is rejected: the reason IS the record."""
    allowed = []
    if not os.path.isfile(ALLOWLIST):
        return allowed
    with open(ALLOWLIST, encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if "\t" not in line or not line.split("\t", 1)[1].strip():
                print("allowlist line %d has no reason - ignored: %s" % (n, line))
                continue
            allowed.append(re.compile(line.split("\t", 1)[0]))
    return allowed


def run_probe(name, allowed):
    path = os.path.join(PROBE_DIR, name + ".gd")
    if not os.path.isfile(path):
        return {"name": name, "ok": False, "why": ["probe file not found"], "secs": 0.0}
    t0 = time.time()
    # Streamed, not captured whole, so a script error can be acted on while the probe is still
    # "running": an error aborts `_init` before its `quit()`, and the process then sits forever.
    proc = subprocess.Popen(
        [GODOT, "--headless", "--path", ROOT, "--script", "res://tools/probe/%s.gd" % name],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    chunks = []
    state = {"last_out": time.time(), "err_at": None}

    def reader():
        for raw in iter(proc.stdout.readline, b""):
            line = raw.decode("utf-8", errors="replace")
            chunks.append(line)
            state["last_out"] = time.time()
            if state["err_at"] is None and ERROR_RE.search(line) and not any(rx.search(line) for rx in allowed):
                state["err_at"] = time.time()
    th = threading.Thread(target=reader, daemon=True)
    th.start()
    timed_out = False
    hung_after_error = False
    while proc.poll() is None:
        time.sleep(0.25)
        now = time.time()
        if now - t0 > TIMEOUT_S:
            timed_out = True
            break
        # An error was printed and nothing has been said for a while: it is not going to finish.
        if state["err_at"] is not None and now - state["last_out"] > ERROR_QUIET_S:
            hung_after_error = True
            break
    if proc.poll() is None:
        proc.kill()
        # A probe that never exits is a zombie Godot (CLAUDE.md); do not leave it eating a core.
        subprocess.run(["taskkill", "/F", "/PID", str(proc.pid)], capture_output=True)
    th.join(timeout=5)
    out = "".join(chunks)
    code = proc.returncode if proc.returncode is not None else -1
    secs = time.time() - t0

    why = []
    if timed_out:
        why.append("TIMED OUT after %ds (a script that fails to parse never exits)" % TIMEOUT_S)
    elif hung_after_error:
        why.append("hung after a script error (the error aborted the script before its quit())")
    elif code != 0:
        why.append("exit status %d" % code)
    if FAIL_RE.search(out):
        why.append("its own output reports FAIL")
    if not PASS_RE.search(out) and not timed_out and not hung_after_error:
        why.append("no PASS verdict line (exit 0 alone is not a pass)")
    errs = []
    for line in out.splitlines():
        if ERROR_RE.search(line) and not any(rx.search(line) for rx in allowed):
            errs.append(line.strip())
    if errs:
        uniq = sorted(set(errs))
        why.append("%d script error line(s), %d distinct: %s" % (len(errs), len(uniq), " | ".join(uniq[:3])[:300]))
    return {"name": name, "ok": not why, "why": why, "secs": secs}


def crlf_files():
    """Tracked files whose WORKING COPY has CRLF while the repo says LF (`.gitattributes`: eol=lf).

    ⚑ WHY THIS IS A GATE. 2026-10-13: the tree was a mix - 8 big sources plus 21 probes CRLF, the
    rest LF - and a source-reading probe only matches when its own line endings agree with the file
    it reads: a `"\n"` needle fails against a CRLF source, a raw newline stored in a CRLF probe fails
    against an LF one. Git itself never notices (the index is LF either way), so seven probes failed
    for a reason that no diff could show. A probe that fails for line endings is a lie about the game."""
    out = subprocess.run(["git", "ls-files", "--eol"], cwd=ROOT, capture_output=True, text=True).stdout
    bad = []
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) >= 4 and parts[1] == "w/crlf" and parts[0] == "i/lf":
            bad.append(line.split("\t", 1)[1])
    return bad


def fix_eol(files):
    for f in files:
        path = os.path.join(ROOT, f)
        with open(path, "rb") as fh:
            data = fh.read()
        with open(path, "wb") as fh:
            fh.write(data.replace(b"\r\n", b"\n"))
    # The index still remembers the old file sizes; refreshing it stages nothing (content == HEAD).
    subprocess.run(["git", "add", "-u"], cwd=ROOT, capture_output=True)


def main(argv):
    if "--fix-eol" in argv:
        bad = crlf_files()
        fix_eol(bad)
        print("converted %d file(s) to LF" % len(bad))
        argv = [a for a in argv if a != "--fix-eol"]
        if not argv:
            return 0
    bad = crlf_files()
    if bad:
        print("REFUSING TO RUN: %d tracked file(s) are CRLF in the working tree but LF in the repo:" % len(bad))
        for f in bad[:10]:
            print("   " + f)
        print("Source-reading probes only match when line endings agree, so every result would be")
        print("untrustworthy. Fix with:  python tools/probe_run.py --fix-eol   (git will see no change)")
        return 1
    report = None
    if "--report" in argv:
        i = argv.index("--report")
        report = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    if "--smoke" in argv:
        names = list(SMOKE)
    elif "--all" in argv:
        names = sorted(f[:-3] for f in os.listdir(PROBE_DIR)
                       if f.endswith(".gd") and not f.startswith("_"))
    else:
        names = [a for a in argv if not a.startswith("--")]
    if not names:
        print(__doc__)
        return 2
    allowed = load_allowlist()
    bad = []
    lines = []
    for n, name in enumerate(names, 1):
        r = run_probe(name, allowed)
        tag = "ok  " if r["ok"] else "FAIL"
        row = "[%d/%d] %s %-60s %5.1fs" % (n, len(names), tag, r["name"], r["secs"])
        print(row, flush=True)
        lines.append(row)
        if not r["ok"]:
            bad.append(r)
            for w in r["why"]:
                print("        - " + w, flush=True)
                lines.append("        - " + w)
    summary = "\n%d probe(s) run, %d failed" % (len(names), len(bad))
    print(summary)
    lines.append(summary)
    if report:
        with open(report, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
