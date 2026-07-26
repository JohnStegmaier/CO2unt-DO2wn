class_name ReloadIndicator
extends Node2D

## Small spinning arc drawn over the player during a reload, in place of a
## text label that read as too large for how little screen space it has.
const RADIUS := 5.0
const ARC_LENGTH := TAU * 0.75
const SPIN_SPEED := TAU * 1.5
const COLOR := Color(1.0, 0.451, 0.0, 1.0)

var _spin := 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_spin = wrapf(_spin + SPIN_SPEED * delta, 0.0, TAU)
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, RADIUS, _spin, _spin + ARC_LENGTH, 12, COLOR, 1.5, true)
