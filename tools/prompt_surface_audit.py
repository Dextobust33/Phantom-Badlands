"""EVERY PROMPT THAT WAITS FOR AN ANSWER, AND WHETHER IT CLAIMED A PAGE FIRST.

Owner 2026-09-18: *"Just used a Scroll of Finding, can't actually see anything to select, I think
it tried to popup in the left window instead of the right column and then got overwrote. We really
need to do a thorough sweep to fix this across the board for all menus and items."*

WHAT GOES WRONG, stated once. `display_game` routes text three ways - the dungeon run log, the
overworld side column, or the canvas - and the choice depends on whether a page currently OWNS the
canvas. `_page_clear()` is what claims it. A screen that prints without claiming is placed by
whatever happened to close a moment earlier: open it from the inventory and the panel has just
handed the canvas back to the map, so the text lands on the canvas and the next map redraw paints
over it. That is the Scroll of Finding, and it is a CLASS, not an item.

WHAT THIS MEASURES. Every function in client.gd that renders a screen the player must ANSWER -
found by looking for the numbered-option shape `[%d]` / `[1]` and for `display_*_page` /
`display_*_options` / `display_*_select` names - and whether that function (or its immediate
caller) starts a page.

WHAT IT CANNOT SEE, so nobody trusts it too far:
  * a prompt drawn by a PANEL rather than by text - those are fine and are filtered out below
  * a caller that clears two frames earlier through some other path
  * whether the page, once placed, survives the next `character_update` (that is the
    Player-Visible Output Rule in CLAUDE.md, a different check)
It narrows "every menu in the game" to the functions worth opening.

USAGE
    python tools/prompt_surface_audit.py
"""
import re
import sys

SRC = 'client/client.gd'

# A function that renders a screen the player answers.
# Functions the shape-matcher catches that are not prompts: an entry point, the connect banner,
# the chat dispatcher, a dev harness. Named rather than silently filtered so the exemption is
# visible and cannot quietly grow.
NOT_A_PROMPT = {'_ready', 'connect_to_server', 'process_command', '_run_altsprite_test'}

# Sub-renderers APPENDED to a page that has already been drawn - the stat block and the
# side-by-side comparison under an item's title. Clearing inside them would erase the item they
# are describing, which is the opposite of the fix. Listed rather than silently skipped so the
# reason is visible; both callers (`display_item_details`, `display_shop_item_details`) do clear.
APPENDED_TO_A_PAGE = {'_display_computed_item_bonuses', '_display_item_comparison'}

NAME_HINT = re.compile(r'^func (display_\w*(page|options|select|menu|picker|prompt)\w*|'
                       r'_display_\w+|_start_\w+_prompt)\(')
# The numbered-option shape every text menu in this file uses.
OPTION_SHAPE = re.compile(r'\[%d\]|\[1\]|\[color=#FFFF00\]\[%d\]')


def events_with_a_continue(src_lines):
    """Every place that asks the player to press Continue, and whether it claimed a page first.

    ⚡ THE SWEEP ABOVE COVERS PROMPTS AND MISSED THIS ENTIRELY. Owner 2026-09-18, with a
    screenshot of a Continue button and nothing above it: *"Why are we still having issues where
    the text is being lost? I can't see anything about the companion... It's literally killing
    features."*

    A prompt waits for an ANSWER; an event waits for an ACKNOWLEDGEMENT. Same requirement - the
    text has to be somewhere the player can read it - and the audit only looked at the first kind,
    so an egg hatching was out of scope by construction. `pending_continue = true` marks the second.

    ⛑ CLAIMING A PAGE IS NECESSARY AND WAS NOT SUFFICIENT. The hatch DID call `_page_clear()`
    and still lost its text: a hatch fires on a step, and the `location` message that same step
    produced wiped the pinned block. That is fixed where the pass is decided rather than here - but
    this is the check that would have found the next one.
    """
    out = []
    for i, line in enumerate(src_lines):
        if 'pending_continue = true' not in line:
            continue
        # Look back for the page claim in the same handler - a generous window, because the print
        # block between the clear and the flag can be long.
        window = '\n'.join(src_lines[max(0, i - 80):i])
        # ⛑ A LINE IS NOT A PAGE, and the first version of this check did not know the
        # difference - it flagged seven combat outcomes ("You escaped from combat!", "You fled
        # to (x, y)!") that print ONE OR TWO lines into the accumulating LOG, where they survive
        # perfectly well. Patching those would have been seven regressions chasing a false
        # positive, which is precisely the failure CLAUDE.md's advisory note warns about.
        #
        # What needs a page is a multi-line SCREEN - the hatch prints fifteen lines and a banner.
        # So the threshold is the block's size, and it is stated rather than tuned to taste: five
        # lines is more than any log message in this file and fewer than any page.
        # Count only the run immediately before the flag, not the whole 80-line window.
        tail = '\n'.join(src_lines[max(0, i - 25):i])
        out.append({
            'line': i + 1,
            'clears': '_page_clear(' in window,
            'prints': tail.count('display_game(') >= 5,
        })
    return out


def main():
    src = open(SRC, encoding='utf-8').read().split('\n')
    funcs = []
    cur = None
    for i, line in enumerate(src):
        if line.startswith('func ') or line.startswith('static func '):
            if cur:
                funcs.append(cur)
            cur = {'name': line.split('(')[0].replace('static ', '').replace('func ', ''),
                   'line': i + 1, 'body': []}
        elif cur is not None:
            cur['body'].append(line)
    if cur:
        funcs.append(cur)

    prompts = []
    for f in funcs:
        if f['name'] in NOT_A_PROMPT or f['name'] in APPENDED_TO_A_PAGE:
            continue
        body = '\n'.join(f['body'])
        named = NAME_HINT.match('func %s(' % f['name']) is not None
        prints_options = bool(OPTION_SHAPE.search(body)) and 'display_game(' in body
        if not (named and 'display_game(' in body) and not prints_options:
            continue
        # A panel-rendered picker is not at risk - it is its own Control.
        panel_only = ('show_item_picker' in body or 'combat_scene_panel' in body) \
            and 'display_game(' not in body
        if panel_only:
            continue
        prompts.append({
            'name': f['name'],
            'line': f['line'],
            'body': body,
            'clears': '_page_clear(' in body,
            'panel_branch': 'show_item_picker' in body or '_panel.' in body,
        })

    # ⛑ A SUB-RENDERER IS NOT A FAULT. Half of these are tabs and rows drawn BY a page that
    # already cleared - `_display_trade_items_tab` is only ever reached from `display_trade_screen`.
    # Counting them made the first run report 35 problems where there were far fewer, which is how
    # a useful audit gets ignored. So every caller is checked: a prompt is covered when EVERY
    # function that calls it starts a page itself.
    by_name = {f['name']: f for f in funcs}
    for p in prompts:
        if p['clears']:
            continue
        callers = []
        for f in funcs:
            if f['name'] == p['name']:
                continue
            if re.search(r'(?<![\w.])' + re.escape(p['name']) + r'\s*\(', '\n'.join(f['body'])):
                callers.append(f['name'])
        p['callers'] = callers
        p['covered'] = bool(callers) and all(
            '_page_clear(' in '\n'.join(by_name[c]['body']) for c in callers if c in by_name)

    bad = [p for p in prompts if not p['clears'] and not p.get('covered', False)]
    covered = [p for p in prompts if not p['clears'] and p.get('covered', False)]
    print('')
    print('===== EVERY TEXT PROMPT THAT WAITS FOR AN ANSWER =====')
    print('  %d prompt-shaped functions in %s' % (len(prompts), SRC))
    print('  %d start a page themselves' % len([p for p in prompts if p['clears']]))
    print('  %d are drawn BY a page that already cleared (every caller clears)' % len(covered))
    print('  %d are placed by whatever closed last' % len(bad))
    print('')
    if bad:
        print('  NOT CLAIMING A PAGE - each of these is placed by whatever closed last:')
        for p in sorted(bad, key=lambda x: x['name']):
            tag = '  [panel branch]' if p['panel_branch'] else ''
            who = ('  <- %s' % ', '.join(p.get('callers', [])[:2])) if p.get('callers') else '  <- (no caller found)'
            print('    %-42s %s:%-6d%s%s' % (p['name'], SRC, p['line'], tag, who))
    print('')
    print('  A prompt with a PANEL branch is only at risk on its text fallback.')

    print('')
    print('===== EVERY EVENT THAT ASKS FOR A CONTINUE =====')
    evs = events_with_a_continue(src)
    bad_ev = [e for e in evs if e['prints'] and not e['clears']]
    print('  %d places set `pending_continue`; %d print a PAGE without claiming one'
          % (len(evs), len(bad_ev)))
    print('  (a one- or two-line outcome goes to the accumulating log and is safe - see the note)')
    for e in bad_ev:
        print('    %s:%d' % (SRC, e['line']))
    print('')
    print('  ADVISORY, NOT A GATE - and that distinction was earned. The first cut of this section')
    print('  flagged seven combat outcomes and I nearly patched all seven; they print one or two')
    print('  lines into the accumulating LOG, where they survive. Raising the threshold to five')
    print('  lines left four, and those four are `for msg in messages: display_game(msg)` - combat')
    print('  text, which is exactly what the log is for. Counting lines cannot tell a long log')
    print('  burst from a titled page, so this half NAMES candidates and the prompt half gates.')
    print('')
    print('  The reliable fix for the whole class is SCROLLBACK (backlog item 10): nothing can be')
    print('  lost if the player can scroll back to it, and no per-site rule is needed at all.')
    print('')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
