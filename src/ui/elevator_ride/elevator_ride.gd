class_name ElevatorRide
extends CanvasLayer

## The ride between floors: a cutaway of the car descending its shaft with the
## player aboard.
##
## An overlay inside the persistent Game root, deliberately not a screen you swap
## to. A scene change would rebuild the world and reset the O2 countdown at every
## floor — the exact bug that put the player and HUD in a persistent root in the
## first place. Covering the screen instead means the floor below can be torn
## down and regenerated behind it with nothing to hide.
##
## Placeholder geometry, not art. The beats and their timing are the part worth
## keeping: real sprites drop into the same three phases.
##
## Split into [method descend] and [method arrive] rather than one call so the
## caller owns the hidden window in the middle — that is where the next floor
## gets built.
##
## Sits on canvas layer 15: above the HUD, but below the pause menu at 20, so
## pausing mid-ride still puts the menu on top of the car rather than behind it.

## Seconds for the car doors to travel, each way.
@export var door_time: float = 0.5
## Seconds spent travelling between floors. Long enough to read as a journey,
## short enough not to be a toll on every floor.
@export var descend_time: float = 1.6
## Overlay fade at each end, so the cut into and out of the ride is not a snap.
@export var fade_time: float = 0.18
## Pixels per second the shaft lights streak past. Faster reads as deeper.
@export var shaft_speed: float = 620.0

## Vertical gap between shaft lights. The strip is wrapped by exactly this, so
## changing it here means changing the spacing in the scene too.
const LIGHT_SPACING := 80.0

## Door leaf travel. Shut, the pair meet at the car's centre; open, each sits
## retracted against its jamb.
const LEAF_SHUT_EDGE := 320.0
const LEAF_LEFT_OPEN_EDGE := 212.0
const LEAF_RIGHT_OPEN_EDGE := 428.0

var _travelling: bool = false

@onready var _screen: Control = $Screen
@onready var _lights: Control = $Screen/Lights
@onready var _leaf_left: ColorRect = $Screen/leaf_left
@onready var _leaf_right: ColorRect = $Screen/leaf_right
@onready var _label: Label = $Screen/label


func _ready() -> void:
	visible = false
	_screen.modulate.a = 0.0
	_apply_doors(0.0)


func _process(delta: float) -> void:
	if not _travelling:
		return
	# Lights run upward to sell downward travel. Wrapped by one spacing rather
	# than repositioned per light, so the strip only has to be long enough to
	# cover the screen plus one gap.
	_lights.position.y -= shaft_speed * delta
	while _lights.position.y <= -LIGHT_SPACING:
		_lights.position.y += LIGHT_SPACING


## Fade in on the open car, shut the doors, and travel. Returns once the car has
## arrived, with the overlay still covering the screen — the caller is expected
## to swap floors before calling [method arrive].
func descend() -> void:
	_apply_doors(0.0)
	_label.text = "DESCENDING"
	visible = true

	await _fade_to(1.0)
	await _slide_doors(1.0)

	_travelling = true
	# process_always false, so pausing mid-ride freezes the descent with everything
	# else. The default true would run this wait out behind the pause menu and open
	# the doors onto a floor the player never saw arrive.
	await get_tree().create_timer(descend_time, false).timeout
	_travelling = false


## Open onto the new floor and clear the overlay.
func arrive(floor_number: int) -> void:
	_label.text = "FLOOR %d" % (floor_number + 1)
	await _slide_doors(0.0)
	await _fade_to(0.0)
	visible = false


func _slide_doors(shut_amount: float) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_method(_apply_doors, 1.0 - shut_amount, shut_amount, door_time)
	await tween.finished


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_screen, "modulate:a", alpha, fade_time)
	await tween.finished


## 0 is fully open, 1 is shut. The leaves meet at the car's centre line, so the
## rider stays visible above the threshold either way — this is a cutaway, and
## hiding the passenger would defeat the point of showing the ride at all.
func _apply_doors(shut_amount: float) -> void:
	_leaf_left.offset_right = lerpf(LEAF_LEFT_OPEN_EDGE, LEAF_SHUT_EDGE, shut_amount)
	_leaf_right.offset_left = lerpf(LEAF_RIGHT_OPEN_EDGE, LEAF_SHUT_EDGE, shut_amount)
