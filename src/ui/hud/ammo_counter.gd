class_name AmmoCounter
extends Node2D

@onready var label: Label = $Label

const RELOAD_COLOR := Color(1.0, 0.451, 0.0, 1.0)

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
	else:
		label.text = "%d / %d" % [_current, _magazine_size]
		label.modulate = Color.WHITE
