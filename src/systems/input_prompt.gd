class_name InputPrompt
extends RefCounted

## "Which button does this action live on, right now?", as a short ASCII string.
##
## Every on-screen prompt in the game used to spell its key out by hand — the
## chest said "[E] OPEN" and the shopkeeper said "[E] TALK" — which is a lie the
## moment anybody picks up a controller, where `interact` is pad X. A prompt that
## names the wrong button is worse than no prompt: the player presses what they
## were told, nothing happens, and they conclude the thing is broken. So the
## binding is read out of [InputMap] instead of written down twice.
##
## Static and node-free so it can be exercised without a scene tree — the same
## reasoning as [LookInput], and what lets tools/check_prompts.gd assert every
## glyph in a terminal rather than by squinting at a pad.
##
## The device latch below is a static rather than an autoload deliberately. An
## autoload is the better long-term home: it would see events with no Player in
## the scene and could keep latching through a pause. But every prompt site today
## needs a Player standing within a few pixels of it anyway, so the extra
## [code][autoload][/code] entry in the one file the whole team edits buys
## nothing yet. Promote it the day a menu needs a glyph.

## Matches player.gd's AIM_DEADZONE. An untouched stick still emits motion
## events, so without this a pad sitting on the desk would flip every prompt in
## the game to pad glyphs and keep it there.
const STICK_DEADZONE := 0.25

## Keys whose engine name is unreadable at 9px, or just wrong for a prompt.
## Anything not in here falls through to OS.get_keycode_string, which already
## gives "E", "R", "TAB" and friends.
const KEY_NAMES := {
	KEY_ESCAPE: "ESC",
	KEY_ENTER: "ENTER",
	KEY_KP_ENTER: "ENTER",
	KEY_SPACE: "SPACE",
	KEY_BACKSPACE: "BKSP",
}

## Godot's JoyButton enum already lines up with this project's input map:
## interact is button 2 (X) and back is button 3 (Y). Named rather than
## numbered because "PAD 2" tells a player nothing.
const PAD_NAMES := {
	JOY_BUTTON_A: "PAD A",
	JOY_BUTTON_B: "PAD B",
	JOY_BUTTON_X: "PAD X",
	JOY_BUTTON_Y: "PAD Y",
	JOY_BUTTON_LEFT_SHOULDER: "PAD LB",
	JOY_BUTTON_RIGHT_SHOULDER: "PAD RB",
	JOY_BUTTON_START: "PAD START",
	JOY_BUTTON_BACK: "PAD SELECT",
}

## Last device to speak wins, exactly like player.gd's aiming_with_gamepad —
## but this one listens to the KEYBOARD too, which is the whole reason it is not
## just that flag reused. aiming_with_gamepad clears only on mouse motion,
## because teaching it about keys would snap the gun back to mouse aim every
## time the player pressed W. A prompt has no such problem and genuinely needs
## to go back to "[E]" for a player who has no mouse.
static var _using_gamepad := false


## Feed every input event through here. One call, from Player._input.
static func note_event(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseMotion \
			or event is InputEventMouseButton:
		_using_gamepad = false
	elif event is InputEventJoypadButton:
		_using_gamepad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > STICK_DEADZONE:
		_using_gamepad = true


## Which device the prompts should be speaking to. Defaults to the keyboard, so
## a fresh install with a pad plugged in but untouched still reads right.
static func using_gamepad() -> bool:
	return _using_gamepad


## The glyph for [param action] on whichever device the player last used.
static func glyph(action: StringName) -> String:
	return glyph_for(action, _using_gamepad)


## The glyph for [param action] on a named device. Pure, so it can be asserted.
##
## Returns "" for an action that does not exist, or one with nothing bound on
## the device asked for — never a guess. A caller that gets "" must drop the
## whole clause rather than draw "[] LEAVE", which reads as a rendering bug.
static func glyph_for(action: StringName, gamepad: bool) -> String:
	if not InputMap.has_action(action):
		return ""

	for event in InputMap.action_get_events(action):
		if gamepad:
			if event is InputEventJoypadButton:
				return PAD_NAMES.get(event.button_index, "PAD %d" % event.button_index)
		elif event is InputEventKey:
			return _key_name(event)
		# Everything else — mouse buttons, stick axes — is deliberately skipped.
		# "LMB BUY" is true but it is not the button the prompt is teaching, and
		# an axis has no name a player would recognise.

	return ""


## The printable name of a key event.
##
## Both storage forms in this project have to work: the actions bound from the
## editor's key picker (pause, interact's Enter) carry a keycode, while the ones
## bound by physical position (E, R, WASD) carry only a physical_keycode and
## leave keycode at 0. Reading one field would silently return "" for half the
## input map.
static func _key_name(event: InputEventKey) -> String:
	var code: Key = event.keycode
	if code == KEY_NONE:
		# A physical binding is a US-layout Key already, which is the answer for
		# most players and the only answer available headless — the dummy display
		# server has no keyboard to ask and treats the call as an error. Where
		# there IS a keyboard, ask it, so a player on AZERTY reads the letter
		# actually printed on the key under their finger.
		code = event.physical_keycode
		if DisplayServer.get_name() != "headless":
			var localised: Key = DisplayServer.keyboard_get_keycode_from_physical(
					event.physical_keycode)
			if localised != KEY_NONE:
				code = localised
	if code == KEY_NONE:
		return ""
	if KEY_NAMES.has(code):
		return KEY_NAMES[code]
	return OS.get_keycode_string(code).to_upper()
