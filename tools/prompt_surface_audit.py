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
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
