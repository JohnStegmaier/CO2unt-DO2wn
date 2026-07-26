class_name ElevatorRide
extends CanvasLayer

## The ride between floors: the car seen head-on, with its floor readout counting
## down and the shaft streaking past behind it.
##
## An overlay inside the persistent Game root, deliberately not a screen you swap
## to. A scene change would rebuild the world and reset the O2 countdown at every
## floor — the exact bug that put the player and HUD in a persistent root in the
## first place. Covering the screen instead means the floor below can be torn
## down and regenerated behind it with nothing to hide.
##
## The readout is the whole point of this overlay. The game is called CO₂unt
## DO₂wn, and this is the only place the number is ever shown: 5, 4, 3, 2, 1, and
## then a B nobody was told about. See [FloorLadder] for that ladder, and
## [constant PLATES] for the art it is drawn with.
##
## Split into [method descend] and [method arrive] rather than one call so the
## caller owns the hidden window in the middle — that is where the next floor
## gets built, and where the readout goes dark.
##
## Sits on canvas layer 15: above the HUD, but below the pause menu at 20, so
## pausing mid-ride still puts the menu on top of the car rather than behind it.

## The car, one texture per floor, indexed by descent index — so PLATES[0] is the
## fifth floor and the last entry is the Basement. The seven plates are pixel-
## identical outside a 6x18 readout window, which is exactly why swapping the
## whole texture is the honest way to change the number: there is no seam to line
## up and nothing to keep in register.
const PLATES: Array[Texture2D] = [
	preload("res://assets/sprites/environment/Elevator_lv5.png"),
	preload("res://assets/sprites/environment/Elevator_lv4.png"),
	preload("res://assets/sprites/environment/Elevator_lv3.png"),
	preload("res://assets/sprites/environment/Elevator_lv2.png"),
	preload("res://assets/sprites/environment/Elevator_lv1.png"),
	preload("res://assets/sprites/environment/Elevator_base.png"),
]
## The readout unlit — what the car wears between floors, so the number arriving
## at the far end is something that appears rather than something that was always
## there. Also the source the door leaves are cropped from: the doors are the same
## pixels on all seven plates, so the leaves never need re-texturing.
const PLATE_BLANK := preload("res://assets/sprites/environment/Elevator_blank.png")

## How much the 100x100 plate is blown up. An integer, because a pixel-art plate
## at a fractional scale gets uneven pixels no filter setting can fix.
const PLATE_SCALE := 3
## Where sprite pixel (0, 0) lands on the 640x360 frame. Puts the plate at
## 170..470 x 30..330 — centred, with the shaft showing down both sides.
const PLATE_ORIGIN := Vector2(170, 30)

## The door opening in plate-local pixels, inside its black surround. Measured off
## the art (the surround runs down x 13 and x 88 and across y 10 and y 88), not
## chosen: everything below is derived from it, so the leaves cannot drift out of
## the hole they are meant to fill.
const DOOR_RECT := Rect2i(14, 11, 74, 77)
## Plate-local x the two leaves meet on. Not the middle: the art's own seam is the
## two black columns at x 49 and 50, so splitting here gives the left leaf 36
## pixels and the right 38, and the pair shut back into exactly the opening the
## plate already draws.
const DOOR_SEAM := 50

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

var _travelling: bool = false

@onready var _screen: Control = $Screen
@onready var _lights: Control = $Screen/Lights
@onready var _plate: Sprite2D = $Screen/Plate
@onready var _leaf_left: Sprite2D = $Screen/leaf_left
@onready var _leaf_right: Sprite2D = $Screen/leaf_right
@onready var _label: Label = $Screen/label


func _ready() -> void:
	visible = false
	_screen.modulate.a = 0.0
	_plate.texture = PLATE_BLANK
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
##
## [param from_index] is the floor being left, so the readout starts on the number
## the player has been looking at all this time rather than snapping to the next
## one before the doors are even shut.
func descend(from_index: int) -> void:
	_apply_doors(0.0)
	_set_plate(from_index)
	_label.text = "DESCENDING"
	visible = true

	await _fade_to(1.0)
	await _slide_doors(1.0)

	# Dark for the journey. The readout has nothing true to say between floors,
	# and going blank is what makes the number at the other end land as news.
	_plate.texture = PLATE_BLANK

	_travelling = true
	# process_always false, so pausing mid-ride freezes the descent with everything
	# else. The default true would run this wait out behind the pause menu and open
	# the doors onto a floor the player never saw arrive.
	await get_tree().create_timer(descend_time, false).timeout
	_travelling = false


## Light the readout on the floor we have arrived at, open onto it, and clear the
## overlay.
func arrive(floor_index: int) -> void:
	_set_plate(floor_index)
	_label.text = FloorLadder.long_label(floor_index)
	await _slide_doors(0.0)
	await _fade_to(0.0)
	visible = false


## Put a floor's number on the car. An index with no plate leaves the readout
## unlit rather than faulting: a ride that arrives somewhere unlabelled is a bug
## worth a warning, not one worth stranding the player mid-overlay for.
func _set_plate(floor_index: int) -> void:
	if floor_index < 0 or floor_index >= PLATES.size():
		push_warning("ElevatorRide: no plate for floor index %d" % floor_index)
		_plate.texture = PLATE_BLANK
		return
	_plate.texture = PLATES[floor_index]


func _slide_doors(shut_amount: float) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_method(_apply_doors, 1.0 - shut_amount, shut_amount, door_time)
	await tween.finished


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_screen, "modulate:a", alpha, fade_time)
	await tween.finished


## 0 is fully open, 1 is shut.
##
## The leaves are the plate's own door pixels, cropped out of it and grown back
## across the opening — so a shut car is pixel-for-pixel the plate as drawn, and
## an open one is the same doors retracted into the jambs they came from. Behind
## them sits the car well, which is why opening reveals a lit interior with the
## rider in it rather than a hole in the overlay.
##
## Region width rather than position, because a leaf that slid clear would have to
## go somewhere, and there is nowhere for it to go inside a 100 pixel frame.
func _apply_doors(shut_amount: float) -> void:
	var left_span: int = DOOR_SEAM - DOOR_RECT.position.x
	var right_span: int = DOOR_RECT.end.x - DOOR_SEAM

	var left_width: int = roundi(left_span * shut_amount)
	_leaf_left.region_rect = Rect2i(DOOR_RECT.position.x, DOOR_RECT.position.y,
			left_width, DOOR_RECT.size.y)
	_leaf_left.position = _plate_to_screen(Vector2i(DOOR_RECT.position.x, DOOR_RECT.position.y))

	var right_width: int = roundi(right_span * shut_amount)
	var right_x: int = DOOR_RECT.end.x - right_width
	_leaf_right.region_rect = Rect2i(right_x, DOOR_RECT.position.y,
			right_width, DOOR_RECT.size.y)
	_leaf_right.position = _plate_to_screen(Vector2i(right_x, DOOR_RECT.position.y))


## A pixel of the plate, in the frame the overlay is drawn in.
func _plate_to_screen(plate_pixel: Vector2i) -> Vector2:
	return PLATE_ORIGIN + Vector2(plate_pixel) * PLATE_SCALE
