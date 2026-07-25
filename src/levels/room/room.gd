class_name Room
extends Node2D

## One screen-sized room — a single cell of a floor.
##
## The shell is fixed: every room has all four doorways in its geometry. A room
## with fewer exits is the same scene with the unused doorways plugged, which is
## why there is one room scene instead of one per door combination.

signal door_entered(side: int)

## Distance between neighbouring room origins. Must equal the background texture
## size exactly, or rooms will not tile edge to edge.
const STRIDE := Vector2(442, 286)

## Room-local rect the camera is allowed to show.
const INTERIOR := Rect2(0, 0, 442, 286)

@onready var _doors: Node2D = $Doors
@onready var _plugs: Node2D = $Walls/Plugs


func _ready() -> void:
	for side in GridDirection.SIDES:
		door_for(side).player_entered.connect(_on_door_player_entered)


## Open the doors in the mask and plug the rest.
func configure(doors: int) -> void:
	for side in GridDirection.SIDES:
		var is_open: bool = (doors & GridDirection.bit(side)) != 0
		var door := door_for(side)
		# Deferred defensively: the physics server rejects these changes if it is
		# mid-flush, which is easy to hit when rooms are built in response to a
		# collision. Game defers room construction for the same reason.
		door.set_deferred("monitoring", is_open)

		var plug := _plug_for(side)
		# visible is not physics state, so it can be set straight away.
		plug.visible = not is_open
		# Hiding a body does not stop it colliding, so clear the layer too —
		# deferred for the same reason as monitoring above.
		plug.set_deferred("collision_layer", 0 if is_open else 1)


func door_for(side: int) -> LevelDoor:
	return _doors.get_node("door_" + GridDirection.side_name(side))


## Where to put a player who just walked in through the given side.
func spawn_position(arrive_side: int) -> Vector2:
	return door_for(arrive_side).spawn_position()


## Camera clamp, in global space.
func interior_rect() -> Rect2:
	return Rect2(global_position + INTERIOR.position, INTERIOR.size)


func _plug_for(side: int) -> StaticBody2D:
	return _plugs.get_node("plug_" + GridDirection.side_name(side))


func _on_door_player_entered(side: int) -> void:
	door_entered.emit(side)
