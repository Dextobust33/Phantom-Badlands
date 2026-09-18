extends RefCounted
## ⚑ ONE ANSWER TO "HOW DO I GET OUT OF THIS SCREEN".
##
## Owner 2026-09-18: *"A lot of these menus with popup windows like the atlas and the quest board
## require me to click the x or maybe hit escape to get out of. Lots of the others I can press
## space to get out of. We need to make it uniform."*
##
## ⛑ MEASURED FIRST, AND IT WAS THREE DIFFERENT ANSWERS. Of 31 panel scripts, eight handled their
## own key and took ESCAPE only, three took SPACE, and the rest closed through the action bar's
## Space button in `client.gd` — so which key worked depended on something a player has no way to
## see. The full-screen panels the owner named are exactly the eight that were Escape-only.
##
## Every panel that handles its own keys asks THIS, so there is one list of close keys and
## `tools/probe/panels_close_the_same_way.gd` can check that nothing grows a ninth answer.
##
## Enter is included because a modal that is only telling you something is dismissed the way every
## other prompt in the game is dismissed.
class_name PanelCloseKeys

const CLOSE_KEYS := [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]

## The label every close button carries, so the screen SAYS what the keys are rather than leaving
## the player to try them.
const CLOSE_HINT := "Close (Esc / Space)"


static func wants_close(event: InputEvent) -> bool:
	"""True when this key press means 'get me out of here'.

	⛑ A FOCUSED TEXT FIELD IS NOT A PROBLEM HERE and that is worth stating, because Space closing
	a screen sounds like it would eat a space bar in a search box. Every caller runs from
	`_unhandled_key_input`, which only sees a key no Control consumed — a focused `LineEdit`
	consumes its own typing before it ever reaches this."""
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return false
	return k.keycode in CLOSE_KEYS
