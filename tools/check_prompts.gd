extends SceneTree

## Assert that every on-screen button prompt names the right button.
##
## [InputPrompt] is pure logic, but unlike the rest of src/systems its answers
## are a function of something outside itself — project.godot's input map. Move
## an event, reorder a list, unbind a key, and the prompts keep rendering
## happily while telling the player to press something that does nothing. That
## failure is silent on whichever device you are not holding, which is exactly
## the bug this file exists to catch:
##
##   godot --headless --script tools/check_prompts.gd
##
## Exits non-zero when an invariant breaks.

const SHOP_SCENE := "res://src/levels/shop_room/shop_room.tscn"

## ShopRoom.FRAME, copied rather than imported: shop_room.gd reaches for
## AudioManager, and a --script harness has no autoloads, so the script cannot be
## compiled here. Same reason tools/check_basement.gd reads scenes as text.
const FRAME := Rect2(0, 0, 442, 240)

## How far SelectionFrame breathes outside a cubby: 5px of bracket plus the 2px
## of deny-shake. A prompt inside this has the frame drawn through it.
const FRAME_BREATHING_ROOM := 7.0

## The O2 bar is a full-width HUD strip across the top of the screen. The room
## maps 1:1.5 vertically (240 x 1.5 = 360, no clamp), so it covers room y 0-31.
const HUD_BOTTOM := 31.0

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_check_glyphs()
	_check_missing_bindings()
	_check_migration()
	_check_both_devices_covered()
	_check_prompt_geometry()

	print("ran %d assertions" % _checks)
	if _failures.is_empty():
		print("OK — every prompt names a real button")
		quit(0)
		return

	print("FAILED — %d problems" % _failures.size())
	for failure in _failures:
		print("  " + failure)
	quit(1)


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s — got %s, expected %s" % [message, actual, expected])


func _fail(message: String) -> void:
	_checks += 1
	_failures.append(message)


# -- The glyphs ----------------------------------------------------------------


## What the prompts in the game actually render.
##
## The keyboard answers pin the ORDER of each action's event list as much as its
## contents: `interact` also carries Enter, and a prompt reading "[ENTER] BUY"
## when the button under the player's finger is E is the lie this file is for.
func _check_glyphs() -> void:
	_equal(InputPrompt.glyph_for("interact", false), "E", "interact on a keyboard")
	_equal(InputPrompt.glyph_for("interact", true), "PAD X", "interact on a pad")
	_equal(InputPrompt.glyph_for("back", false), "ESC", "back on a keyboard")
	_equal(InputPrompt.glyph_for("back", true), "PAD Y", "back on a pad")


## Nothing is ever invented. A prompt with no answer says nothing at all.
func _check_missing_bindings() -> void:
	_equal(InputPrompt.glyph_for("no_such_action", false), "",
			"an action that does not exist has no keyboard glyph")
	_equal(InputPrompt.glyph_for("no_such_action", true), "",
			"an action that does not exist has no pad glyph")

	# aim_left is stick-only: no key, no button, just an axis.
	_equal(InputPrompt.glyph_for("aim_left", false), "",
			"a stick-only action has no keyboard glyph")
	_equal(InputPrompt.glyph_for("aim_left", true), "",
			"an axis is not a button and is not named as one")

	# shoot is the left mouse button on a keyboard. True, but not a button a
	# prompt can teach, so it is skipped rather than rendered as "LMB".
	_equal(InputPrompt.glyph_for("shoot", false), "",
			"a mouse binding is not offered as a keyboard glyph")


## The Backspace-to-Escape migration, pinned so it cannot quietly come undone.
func _check_migration() -> void:
	# Only this game's actions. Godot's built-in ui_text_* actions are full of
	# Backspace and always will be — they drive LineEdit, not the player.
	for action in _project_actions():
		_ok(not _has_key(action, KEY_BACKSPACE),
				"Backspace is bound to %s; it was taken out on purpose" % action)

	# Escape deliberately belongs to two actions. ShopRoom._input consumes it
	# while browsing so the same press cannot also pause; anywhere else it falls
	# through to PauseMenu. Asserted so dropping it from either is a decision.
	_ok(_has_key("back", KEY_ESCAPE), "Escape leaves browsing")
	_ok(_has_key("pause", KEY_ESCAPE), "Escape still pauses")


## Every action a prompt names must be answerable on both devices, or somebody
## reads half a prompt.
func _check_both_devices_covered() -> void:
	for action in ["interact", "back"]:
		_ok(not InputPrompt.glyph_for(action, false).is_empty(),
				"%s has something to show a keyboard player" % action)
		_ok(not InputPrompt.glyph_for(action, true).is_empty(),
				"%s has something to show a pad player" % action)


# -- Where the shop's prompts sit ----------------------------------------------


## Text length is the thing most likely to change here, and a wider string in the
## wrong band is drawn through the shelves or under the O2 bar — visible only by
## walking into a shop and looking at it.
func _check_prompt_geometry() -> void:
	var source: String = _read(SHOP_SCENE)
	if source.is_empty():
		return

	var grid: ShopGrid = _parse_grid(source)
	var browse: Variant = _parse_control_rect(source, "BrowsePrompt", "Depth/Shelves")
	var talk: Variant = _parse_control_rect(source, "TalkPrompt", "Depth/Shopkeeper")
	if grid == null or browse == null or talk == null:
		_fail("shop_room.tscn is missing the grid, BrowsePrompt or TalkPrompt")
		return

	# Bank by bank rather than the whole footprint: bounds() spans the centre gap,
	# and the centre gap is exactly where TalkPrompt is supposed to be. Both
	# prompts hang off nodes sitting at the room origin, so their offsets are
	# already in room-local space.
	var banks: Array[Rect2] = []
	for row in grid.rows:
		for bank in 2:
			var shelf: Rect2 = grid.bank_rect(row, bank)
			if shelf.size.x > 0.0:
				banks.append(shelf.grow(FRAME_BREATHING_ROOM))

	for named in [["BrowsePrompt", browse], ["TalkPrompt", talk]]:
		var rect: Rect2 = named[1]
		_ok(FRAME.encloses(rect), "%s is inside the room" % named[0])
		var clear := true
		for shelf in banks:
			clear = clear and not shelf.intersects(rect)
		_ok(clear, "%s is clear of the shelves and the selection frame" % named[0])

	var browse_rect: Rect2 = browse
	_ok(browse_rect.position.y >= HUD_BOTTOM, "BrowsePrompt clears the O2 bar")
	_ok(browse_rect.end.y <= grid.bounds().position.y - FRAME_BREATHING_ROOM,
			"BrowsePrompt sits above the shelves")


# -- Reading the input map -----------------------------------------------------


## The actions this game plays with.
##
## Godot's own ui_* estate is skipped: ui_text_backspace and friends are full of
## Backspace and always will be, because they drive LineEdit rather than the
## player. The four ui_ actions this project does override are movement, which no
## prompt names.
func _project_actions() -> Array[String]:
	var actions: Array[String] = []
	for setting in ProjectSettings.get_property_list():
		var key: String = setting.get("name", "")
		if key.begins_with("input/") and not key.begins_with("input/ui_"):
			actions.append(key.substr(6))
	return actions


func _has_key(action: StringName, keycode: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event.keycode == keycode
				or (event.keycode == KEY_NONE and event.physical_keycode == keycode)):
			return true
	return false


# -- Reading the scene ---------------------------------------------------------


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("could not read %s" % path)
		return ""
	return file.get_as_text()


## The body of a `[node name="X" ... parent="Y"]` block, up to the next block.
func _node_body(source: String, node_name: String, parent: String) -> String:
	var regex := RegEx.create_from_string(
			r'\[node name="' + node_name + r'"[^\]]*parent="' + parent + r'"[^\]]*\]([^\[]*)')
	var found := regex.search(source)
	if found == null:
		return ""
	return found.get_string(1)


## A Control's authored rect, from its four offsets.
func _parse_control_rect(source: String, node_name: String, parent: String) -> Variant:
	var body: String = _node_body(source, node_name, parent)
	if body.is_empty():
		return null
	var left: Variant = _number(body, "offset_left")
	var top: Variant = _number(body, "offset_top")
	var right: Variant = _number(body, "offset_right")
	var bottom: Variant = _number(body, "offset_bottom")
	if left == null or top == null or right == null or bottom == null:
		return null
	return Rect2(left, top, right - left, bottom - top)


## The shelf grid, rebuilt from the sub_resource the scene hands ShopRoom.
##
## ShopGrid itself is pure logic and compiles fine here, so the layout maths is
## the code the game runs rather than a second copy of it.
func _parse_grid(source: String) -> ShopGrid:
	var regex := RegEx.create_from_string(r'\[sub_resource[^\]]*id="Resource_grid"\]([^\[]*)')
	var found := regex.search(source)
	if found == null:
		return null
	var body: String = found.get_string(1)

	var grid := ShopGrid.new()
	grid.rows = int(_number(body, "rows"))
	grid.columns = int(_number(body, "columns"))
	grid.origin = _vector(body, "origin")
	grid.cell_size = _vector(body, "cell_size")
	grid.cell_spacing = _vector(body, "cell_spacing")
	grid.center_gap = float(_number(body, "center_gap"))
	return grid


## `field = 12.5`
func _number(body: String, field: String) -> Variant:
	var regex := RegEx.create_from_string(field + r"\s*=\s*(-?[\d.]+)")
	var found := regex.search(body)
	if found == null:
		return null
	return found.get_string(1).to_float()


## `field = Vector2(x, y)`
func _vector(body: String, field: String) -> Vector2:
	var regex := RegEx.create_from_string(
			field + r"\s*=\s*Vector2\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)")
	var found := regex.search(body)
	if found == null:
		return Vector2.ZERO
	return Vector2(found.get_string(1).to_float(), found.get_string(2).to_float())
