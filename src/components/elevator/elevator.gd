class_name Elevator
extends Node2D

## The way off a floor: a car set into a wall of the exit room.
##
## The doors are the whole interaction. They slide open as the player approaches
## and shut again if they walk away, so the elevator invites rather than demands
## — and taking it is simply walking through them, with no prompt to read.
##
## Deliberately placeholder geometry rather than art: coloured rectangles
## standing in until the real sprites exist. Nothing outside this scene depends
## on how it looks, only on [signal entered].

signal entered

## Width of one closed leaf. Two of them cover the opening exactly, so this is
## also half the opening and the distance a leaf has to travel.
const LEAF_WIDTH := 24.0

## Indicator above the doors. Red means shut, green means you may step in — the
## cheapest possible way to make an unfinished mechanism legible.
const LIGHT_SHUT := Color(0.72, 0.19, 0.16)
const LIGHT_OPEN := Color(0.35, 0.85, 0.42)

## Seconds for the doors to travel their whole span. Partial travel is
## proportionally quicker, so the leaves always move at the same speed.
@export var door_time: float = 0.45
## How far a leaf retracts into its jamb, as a fraction of its closed width.
## Short of 1.0 so a sliver stays showing and the doors do not appear to vanish.
@export_range(0.0, 1.0) var open_travel: float = 0.94

## 0 shut, 1 open. Not an export — it is driven, never authored.
var _open_amount: float = 0.0
var _slide: Tween
## The player, while they are standing in the car. Held rather than acted on
## immediately because standing inside and the doors being open are two separate
## conditions that can become true in either order — see _try_depart.
var _rider: Node2D
## One ride per elevator, whichever condition completed the pair.
var _departed: bool = false

@onready var _leaf_left: ColorRect = $leaf_left
@onready var _leaf_right: ColorRect = $leaf_right
@onready var _glow: ColorRect = $glow
@onready var _light: ColorRect = $light
@onready var _approach: Area2D = $Approach
@onready var _entry: Area2D = $Entry


func _ready() -> void:
	_apply_open_amount(0.0)


## Show and arm this elevator, or hide and disarm it.
##
## Every room instances the scene and only the exit room's copy is ever live.
## That keeps a room a single fixed shell — the same reason doorways are plugged
## rather than a scene existing per door combination.
func set_active(active: bool) -> void:
	visible = active
	# Deferred: rooms are built inside the body_entered of the door the player
	# just touched, and the physics server rejects monitoring changes while it is
	# flushing queries. The doors and plugs already work around the same hazard.
	_approach.set_deferred("monitoring", active)
	_entry.set_deferred("monitoring", active)
	_rider = null
	_departed = false
	if not active:
		_stop_slide()
		_apply_open_amount(0.0)


func _on_approach_body_entered(body: Node2D) -> void:
	if body is Player:
		_slide_to(1.0)


func _on_approach_body_exited(body: Node2D) -> void:
	if body is Player:
		_slide_to(0.0)


func _on_entry_body_entered(body: Node2D) -> void:
	if body is Player:
		_rider = body
		_try_depart()


func _on_entry_body_exited(body: Node2D) -> void:
	if body == _rider:
		_rider = null


## Leave once the player is in the car and the doors have finished opening.
##
## Called from both halves because either can complete the pair. The approach zone
## reaches barely past the car, so a player walking in at full speed is inside
## well before the doors finish — waiting only on body_entered would mean the
## common case never fires at all, and stepping out and back in would be the only
## way to make it work.
func _try_depart() -> void:
	if _departed or _rider == null or not is_equal_approx(_open_amount, 1.0):
		return
	# Game tears the floor down in response, but not in this frame, and a second
	# report would descend two floors at once.
	_departed = true
	entered.emit()


func _slide_to(target: float) -> void:
	_stop_slide()
	var travel: float = absf(target - _open_amount)
	if is_zero_approx(travel):
		_on_slide_finished(target)
		return

	_slide = create_tween()
	_slide.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# Scaled by the distance left, so reversing a half-open door takes half the
	# time rather than restarting the full span at the same speed.
	_slide.tween_method(_apply_open_amount, _open_amount, target, door_time * travel)
	_slide.finished.connect(_on_slide_finished.bind(target))


func _on_slide_finished(target: float) -> void:
	if is_equal_approx(target, 1.0):
		_try_depart()


func _apply_open_amount(amount: float) -> void:
	_open_amount = amount
	var retracted: float = LEAF_WIDTH * open_travel * amount
	# The leaves shrink into their jambs rather than sliding clear of the frame,
	# which is what a real door does and avoids them poking out of the surround.
	_leaf_left.offset_right = -retracted
	_leaf_right.offset_left = retracted
	# The car lights as it opens, so the room reads as having a way out from
	# further off than the gap itself is visible.
	_glow.color.a = 0.55 * amount
	_light.color = LIGHT_SHUT.lerp(LIGHT_OPEN, amount)


func _stop_slide() -> void:
	if _slide != null and _slide.is_valid():
		# kill() does not emit finished, so no stale arming can land after this.
		_slide.kill()
	_slide = null
