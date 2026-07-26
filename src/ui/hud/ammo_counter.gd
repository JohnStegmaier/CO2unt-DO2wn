class_name AmmoCounter
extends Node2D

@onready var label: Label = $Label

const RELOAD_COLOR := Color(1.0, 0.451, 0.0, 1.0)
## "RELOADING" is far wider than any ammo count, so it gets its own smaller
## size to keep it from overflowing the label's box off the edge of the screen.
const AMMO_FONT_SIZE := 22
const RELOAD_FONT_SIZE := 14

var _current := 0
var _magazine_size := 0
## Tracked separately from _current: a manual reload can start with rounds
## still in the mag, so "empty" alone is not enough to know a reload is on.
var _reloading := false


func set_ammo(current: int, magazine_size: int) -> void:
	_current = current
	_magazine_size = magazine_size
	_refresh()


func set_reloading(reloading: bool) -> void:
	_reloading = reloading
	_refresh()


func _refresh() -> void:
	if _reloading or _current <= 0:
		label.text = "RELOADING"
		label.modulate = RELOAD_COLOR
		label.add_theme_font_size_override("font_size", RELOAD_FONT_SIZE)
	else:
		label.text = "%d / %d" % [_current, _magazine_size]
		label.modulate = Color.WHITE
		label.add_theme_font_size_override("font_size", AMMO_FONT_SIZE)
