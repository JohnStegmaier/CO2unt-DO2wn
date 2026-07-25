class_name AmmoCounter
extends Node2D

@onready var label: Label = $Label

const RELOAD_COLOR := Color(1.0, 0.451, 0.0, 1.0)


func set_ammo(current: int, magazine_size: int) -> void:
	if current <= 0:
		label.text = "RELOAD"
		label.modulate = RELOAD_COLOR
	else:
		label.text = "%d / %d" % [current, magazine_size]
		label.modulate = Color.WHITE
