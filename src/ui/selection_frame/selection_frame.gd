class_name SelectionFrame
extends Node2D

## The four corners of a box around whatever is currently selected, breathing
## outward in whole-pixel steps.
##
## Deliberately NOT a Tween. A tween interpolates every frame and gives a smooth
## glide, which on a 640x360 pixel-art viewport reads as a modern UI dropped into
## the game by mistake. This walks an integer step index instead, holding each
## step a little longer than the last, so the box gets bigger and slower as it
## goes and every edge lands on an exact pixel. The corners stay the same length
## while the box grows, so the gap between them opens up as it breathes.
##
## Drawn in the parent's space rather than by moving the node, so it can be
## parented to a parallax plane and travel with the shelf it is pointing at.

@export_group("Animation")
## How far past the cell each step pushes the corners, in pixels. Authored as a
## list rather than computed so the shape of the breath is something you can see
## and edit — slow out and fast back, uneven steps, whatever reads best.
@export var steps: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4, 5])
## How long the first step is held.
@export var first_step_time: float = 0.05
## Multiplied into the hold time at every step. Above 1.0 is the "and slower"
## half of the brief; at 1.0 the box grows at a constant rate and reads as a
## machine rather than a breath.
@export_range(0.5, 3.0, 0.05) var step_time_growth: float = 1.55
## Beat at full extent before snapping back to the first step. The snap is the
## point — easing back down would put the smooth motion straight back in.
@export var hold_time: float = 0.30

@export_group("Shape")
## Length of each arm of the corner brackets.
@export var corner_length: int = 4
## How thick the brackets are drawn.
@export var thickness: int = 1
@export var color: Color = Color(1.0, 0.94, 0.62)

@export_group("Feedback")
## How far the frame jolts when a purchase is refused.
@export var shake_pixels: int = 2
## How long the jolt lasts.
@export var shake_time: float = 0.22
## Jolts per second while shaking. Whole-pixel jumps at a fixed rate, for the
## same reason the breath is stepped.
@export var shake_rate: float = 24.0

## The cell being pointed at, in the parent's space.
var _cell: Rect2 = Rect2()
var _step: int = 0
var _elapsed: float = 0.0
var _holding: bool = false
var _shake_left: float = 0.0


func _ready() -> void:
	# The frame is drawn from _cell, which starts empty — without this it would
	# draw four brackets around a zero-sized rect at the origin for one frame.
	visible = false


## Point at a cell. Resets the breath so a moved selection starts from tight
## against the item rather than halfway through someone else's cycle.
func set_cell(cell: Rect2) -> void:
	_cell = cell
	_step = 0
	_elapsed = 0.0
	_holding = false
	_shake_left = 0.0
	visible = true
	queue_redraw()


func clear_cell() -> void:
	visible = false
	_shake_left = 0.0


## Refuse feedback: a couple of whole-pixel jolts, no colour change.
##
## Public so the room can say "no" without knowing how the frame draws itself.
func deny() -> void:
	_shake_left = shake_time
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return

	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - delta, 0.0)
		# Redrawn every frame while shaking because the offset is derived from
		# the remaining time — see _shake_offset.
		queue_redraw()

	if steps.is_empty():
		return

	_elapsed += delta

	if _holding:
		if _elapsed >= hold_time:
			_holding = false
			_step = 0
			_elapsed = 0.0
			queue_redraw()
		return

	var duration: float = _step_duration(_step)
	if _elapsed < duration:
		return

	# Subtracted rather than zeroed, so a long frame does not silently swallow
	# the overshoot and slow the whole cycle down.
	_elapsed -= duration
	_step += 1
	if _step >= steps.size():
		_step = steps.size() - 1
		_holding = true
		_elapsed = 0.0
	queue_redraw()


## Each step is held longer than the one before it. Exponential rather than
## linear because the difference has to be obvious across only a handful of
## steps.
func _step_duration(step: int) -> float:
	return first_step_time * pow(step_time_growth, float(step))


## Whole pixels, alternating, decaying to nothing. Derived from the remaining
## time rather than accumulated so it always finishes centred.
func _shake_offset() -> Vector2:
	if _shake_left <= 0.0:
		return Vector2.ZERO
	var progress: float = _shake_left / maxf(shake_time, 0.001)
	var phase: int = int(_shake_left * shake_rate) % 2
	var amplitude: int = int(round(shake_pixels * progress))
	return Vector2(amplitude if phase == 0 else -amplitude, 0.0)


func _draw() -> void:
	if steps.is_empty() or _cell.size == Vector2.ZERO:
		return

	var inset: float = float(steps[clampi(_step, 0, steps.size() - 1)])
	var box := Rect2(
		_cell.position - Vector2(inset, inset) + _shake_offset(),
		_cell.size + Vector2(inset, inset) * 2.0
	)
	# Snapped after every offset is folded in, so the drawn rect is on whole
	# pixels whatever the cell's own position happens to be.
	box = Rect2(box.position.round(), box.size.round())

	var arm: float = float(corner_length)
	var thick: float = float(thickness)
	var left: float = box.position.x
	var top: float = box.position.y
	var right: float = box.end.x
	var bottom: float = box.end.y

	# Four L-brackets. draw_rect rather than draw_line: a line of odd width
	# straddles the pixel grid and comes out blurred at this scale.
	# Top-left
	draw_rect(Rect2(left, top, arm, thick), color)
	draw_rect(Rect2(left, top, thick, arm), color)
	# Top-right
	draw_rect(Rect2(right - arm, top, arm, thick), color)
	draw_rect(Rect2(right - thick, top, thick, arm), color)
	# Bottom-left
	draw_rect(Rect2(left, bottom - thick, arm, thick), color)
	draw_rect(Rect2(left, bottom - arm, thick, arm), color)
	# Bottom-right
	draw_rect(Rect2(right - arm, bottom - thick, arm, thick), color)
	draw_rect(Rect2(right - thick, bottom - arm, thick, arm), color)
