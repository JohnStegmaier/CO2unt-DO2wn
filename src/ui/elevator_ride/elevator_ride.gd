class_name ElevatorRide
extends CanvasLayer

## The ride between floors, seen from inside the car: the doors filling the frame with
## the player stood in front of them, the floor readout counting down, and the shaft
## streaking past in the margins.
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

## The rider's idle, one texture per frame — the player's own front-facing idle, the
## same art and the same order as player.tscn's idle_down animation.
##
## Rebuilt here rather than shared with the player: player.tscn keeps its SpriteFrames
## as an inline sub-resource, so sharing it would mean extracting a .tres and editing
## that scene, which is expensive on a branch that cannot merge .tscn files. The cost
## of that choice is this list — if the player's front-facing idle is ever re-drawn or
## re-timed, it has to be re-listed here too.
const RIDER_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/characters/player/Idle_forward/Player_Idle1.png"),
	preload("res://assets/sprites/characters/player/Idle_forward/Player_Idle2.png"),
	preload("res://assets/sprites/characters/player/Idle_forward/Player_Idle3.png"),
	preload("res://assets/sprites/characters/player/Idle_forward/Player_Idle4.png"),
]
## Frames per second for that idle. Matches the player's SpriteFrames.
const RIDER_FPS := 5.0
const RIDER_ANIM := &"idle"

## Named SFX from AudioManager for the descent itself, and for arriving.
##
## Empty names play nothing, so a build whose registry has not caught up is quiet rather
## than broken — the same contract ElevatorRoom.board_sfx has.
const DESCENT_SFX := "elevator_whir"
const ARRIVE_SFX := "elevator_ding"

## Seconds for the car doors to travel, each way.
@export var door_time: float = 0.5
## Seconds spent travelling between floors. Long enough to read as a journey,
## short enough not to be a toll on every floor.
@export var descend_time: float = 1.6
## Overlay fade at each end, so the cut into and out of the ride is not a snap.
@export var fade_time: float = 0.18
## Pixels per second the shaft lights streak past. Faster reads as deeper.
@export var shaft_speed: float = 620.0

## How much the 16x32 rider is blown up. An integer for the same reason
## [constant PLATE_SCALE] is one.
##
## Six, not the plate's own three: only 23 of the frame's 32 rows have anything drawn
## in them, so the figure is about two thirds of what the frame's height suggests. At 3
## she is 69 pixels against a 231 pixel doorway and reads as someone stood at the far
## end of a hall; at 6 she is 138 and reads as someone stood in a lift with you, which
## is the whole point of being inside the car.
@export var rider_scale: int = 6

## Vertical gap between shaft lights. The strip is wrapped by exactly this, so
## changing it here means changing the spacing in the scene too.
const LIGHT_SPACING := 80.0

var _travelling: bool = false

@onready var _screen: Control = $Screen
@onready var _lights: Control = $Screen/Lights
@onready var _plate: Sprite2D = $Screen/Plate
@onready var _leaf_left: Sprite2D = $Screen/leaf_left
@onready var _leaf_right: Sprite2D = $Screen/leaf_right
@onready var _rider: AnimatedSprite2D = $Screen/Rider
@onready var _label: Label = $Screen/label


func _ready() -> void:
	visible = false
	_screen.modulate.a = 0.0
	_plate.texture = PLATE_BLANK
	_place_rider()
	# Resting state is SHUT. The overlay is only ever faded up on a car the lobby has
	# just sealed, so this is the position it has to be in before anyone can see it.
	_apply_doors(1.0)


func _process(delta: float) -> void:
	if not _travelling:
		return
	# Lights run upward to sell downward travel. Wrapped by one spacing rather
	# than repositioned per light, so the strip only has to be long enough to
	# cover the screen plus one gap.
	_lights.position.y -= shaft_speed * delta
	while _lights.position.y <= -LIGHT_SPACING:
		_lights.position.y += LIGHT_SPACING


## Fade in on the sealed car and travel. Returns once the car has arrived, with the
## overlay still covering the screen — the caller is expected to swap floors before
## calling [method arrive].
##
## Deliberately does not animate the doors. The lobby has just spent its own slide
## shutting them ON the player and held on them, and this used to reset them to fully
## open and shut them a second time: 0.68 seconds of watching the same event again, at
## a different scale, in a different art style. THAT was the seam. The overlay's job
## at this end is to continue the lobby's doors, not to repeat them — so the car it
## fades up on is the car the player was last looking at.
##
## [param from_index] is the floor being left, so the readout starts on the number
## the player has been looking at all this time rather than snapping to the next
## one before the doors are even shut.
func descend(from_index: int) -> void:
	_set_plate(from_index)
	_label.text = "DESCENDING"
	visible = true

	await _fade_to(1.0)

	# Dark for the journey. The readout has nothing true to say between floors,
	# and going blank is what makes the number at the other end land as news.
	_plate.texture = PLATE_BLANK

	# Started with the travel rather than with the fade, so the machinery is heard to
	# take up the weight at the moment the car moves. Sound is also the one thing that
	# carries over a dissolve unbroken, which makes it the cheapest continuity there is.
	_play_sfx(DESCENT_SFX)

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
	# On the number appearing, not on the doors opening: the ding is the car announcing
	# where it has got to, and the readout is where it says so.
	_play_sfx(ARRIVE_SFX)
	await _slide_doors(0.0)
	await _fade_to(0.0)
	visible = false
	# Back to the resting position, now that nobody can see it happen. Without this
	# the next descent would fade up on the doors this one left standing open, and the
	# double-shut [method descend] exists to avoid would come back as its mirror image:
	# a car that opens itself before it travels.
	_apply_doors(1.0)


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
## them sits the car well, which is why opening reveals a lit interior rather than a
## hole in the overlay. The rider is in front of all of it and never moves.
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


## Guarded because audio_manager.gd indexes its dictionary directly and will hard error
## on a name it does not have — the same guard ElevatorRoom._play_board_sfx uses.
##
## Reached by PATH rather than by the AudioManager identifier every other caller uses,
## and that is deliberate: tools/check_ladder.gd preloads THIS script and runs it under
## `godot --headless --script`, where no autoloads are registered. An identifier the
## compiler cannot resolve fails the whole check, and the check exists to protect the
## plate table from drifting out of step with the floor ladder — worth more than
## consistency with the shorter spelling. A path is resolved at runtime instead, so the
## ride stays loadable outside a running game.
func _play_sfx(sound_name: String) -> void:
	if sound_name.is_empty() or not is_inside_tree():
		return
	var audio: Node = get_node_or_null(^"/root/AudioManager")
	if audio == null or not audio.sounds.has(sound_name):
		return
	audio.play_sfx(sound_name)


## A pixel of the plate, in the frame the overlay is drawn in.
func _plate_to_screen(plate_pixel: Vector2i) -> Vector2:
	return PLATE_ORIGIN + Vector2(plate_pixel) * PLATE_SCALE


## Stand the player in the car, in front of the doors.
##
## In FRONT of them, which is the whole difference between this being a shot of a lift
## and a shot from inside one. She is the last thing in the Screen's child order for
## exactly that reason — the door leaves draw under her, so shutting them cannot swallow
## her and opening them does not reveal her.
##
## Front-facing idle because it is the only view that exists: player.tscn's idle_up
## reuses the right-facing frames, so there is no back to turn to the doors. Facing out
## of the car is also the readable choice — a rider drawn from behind would be a
## silhouette with nothing to recognise.
##
## Placed on the door's own bottom edge, at the seam the leaves meet on, so her feet
## land on the line where the car floor meets the doors rather than on a number typed
## in twice. Everything here is derived from the plate, so re-scaling the car moves her
## with it.
func _place_rider() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation(RIDER_ANIM)
	frames.set_animation_loop(RIDER_ANIM, true)
	frames.set_animation_speed(RIDER_ANIM, RIDER_FPS)
	for frame in RIDER_FRAMES:
		frames.add_frame(RIDER_ANIM, frame)
	# The default "default" animation is left behind by SpriteFrames.new() and would
	# show as an empty entry in the inspector.
	frames.remove_animation(&"default")
	_rider.sprite_frames = frames

	_rider.scale = Vector2(rider_scale, rider_scale)
	_rider.position = _plate_to_screen(Vector2i(DOOR_SEAM, DOOR_RECT.end.y))
	# Bottom edge on that point rather than centre, so she stands on the floor instead
	# of hovering half a body through it. Measured off the art for the same reason
	# ElevatorRoom measures it: art of a different height still lands on the floor.
	var first: Texture2D = frames.get_frame_texture(RIDER_ANIM, 0)
	if first != null:
		_rider.offset = Vector2(0, -first.get_height() * 0.5)
	_rider.play(RIDER_ANIM)
