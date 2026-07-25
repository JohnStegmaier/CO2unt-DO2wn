extends Control

## Throwaway input diagnostic — DELETE BEFORE MERGING.
##
## Run this scene on its own (select it in the FileSystem dock and press F6)
## with the controller connected, then read what the engine actually receives.
## It answers, in order: does Godot see a pad at all, which axes do the sticks
## move, and do those axes reach the game's actions.

@onready var _label: Label = $Readout

var _last_event: String = "(nothing yet)"


func _ready() -> void:
	var pads := Input.get_connected_joypads()
	print("--- input debug ---")
	if pads.is_empty():
		print("NO JOYPADS CONNECTED — Godot cannot see a controller at all")
	for d in pads:
		print("joypad %d: %s" % [d, Input.get_joy_name(d)])
		print("   guid: %s" % Input.get_joy_guid(d))


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		_last_event = "JoypadMotion  device=%d  axis=%d  value=%+.3f" % [
			event.device, event.axis, event.axis_value]
	elif event is InputEventJoypadButton:
		_last_event = "JoypadButton  device=%d  button=%d  pressed=%s" % [
			event.device, event.button_index, event.pressed]
	elif event is InputEventMouseMotion:
		_last_event = "MouseMotion (a mouse is driving input)"
	elif event is InputEventKey:
		_last_event = "Key %s" % event.as_text()


func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	var pads := Input.get_connected_joypads()

	lines.append("CONNECTED JOYPADS: %s" % str(pads))
	if pads.is_empty():
		lines.append("  *** GODOT SEES NO GAMEPAD ***")
		lines.append("  Steam Input is not presenting a pad to this process.")
	for d in pads:
		lines.append("  [%d] %s" % [d, Input.get_joy_name(d)])
		var axes := ""
		for a in range(6):
			axes += "%d:%+.2f  " % [a, Input.get_joy_axis(d, a)]
		lines.append("      axes   %s" % axes)
		var held := ""
		for b in range(16):
			if Input.is_joy_button_pressed(d, b):
				held += "%d " % b
		lines.append("      buttons %s" % ("(none)" if held.is_empty() else held))

	lines.append("")
	lines.append("LAST EVENT: %s" % _last_event)
	lines.append("")
	lines.append("move vector (ui_*)   : %s" % Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down"))
	lines.append("aim  vector (aim_*)  : %s" % Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down"))

	var pressed := ""
	for a in ["ui_left", "ui_right", "ui_up", "ui_down", "shoot", "dodge",
			"aim_left", "aim_right", "aim_up", "aim_down"]:
		if Input.is_action_pressed(a):
			pressed += a + " "
	lines.append("actions held         : %s" % ("(none)" if pressed.is_empty() else pressed))
	lines.append("")
	lines.append("Left stick should move axes 0/1. Right stick should move axes 2/3 —")
	lines.append("that is what aim_* is bound to. If it moves different axes, rebind.")

	_label.text = "\n".join(lines)
