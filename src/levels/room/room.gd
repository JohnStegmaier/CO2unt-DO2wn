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

## Room-local rect anything on foot may stand in. The perimeter wall shapes are
## 28 deep, centred at 35/250 vertically and 35/406 horizontally, so the floor is
## everything inside their inner faces.
const FLOOR := Rect2(49, 49, 343, 187)

@onready var _doors: Node2D = $Doors
@onready var _plugs: Node2D = $Walls/Plugs
@onready var _entities: Node2D = $Entities

## The door mask this room was configured with. Remembered so the doors can be
## sealed for a fight and restored afterwards without the room having to know
## why.
var _open_doors: int = 0


func _ready() -> void:
	for side in GridDirection.SIDES:
		door_for(side).player_entered.connect(_on_door_player_entered)


## Put something on the floor at a room-local position.
##
## Positioned before entering the tree and interpolation reset after, for the
## reason game.gd spells out when it spawns a room: physics interpolation is on
## project-wide, so a node that enters at the origin and moves afterwards renders
## one frame smeared from wherever the room sits on the grid.
func add_entity(node: Node2D, local_position: Vector2) -> void:
	node.position = local_position
	_entities.add_child(node)
	node.reset_physics_interpolation()


## Room-local landing spots of the doors that are currently open. Used to keep
## spawns clear of the mouths the player walks through.
func open_door_landings() -> Array[Vector2]:
	var landings: Array[Vector2] = []
	for side in GridDirection.SIDES:
		if (_open_doors & GridDirection.bit(side)) != 0:
			landings.append(to_local(door_for(side).spawn_position()))
	return landings


## Open the doors in the mask and plug the rest. This is the room's shape as the
## floor plan defines it — the mask is remembered so a temporary seal can be
## lifted again.
func configure(doors: int) -> void:
	_open_doors = doors
	_apply_doors(doors)


## Seal every doorway, or restore the ones the floor plan gave this room.
##
## A sealed door is just a plugged one, so this reuses the plug the room already
## has for doorways that lead nowhere — same collision, same visual.
func set_locked(locked: bool) -> void:
	_apply_doors(0 if locked else _open_doors)


func _apply_doors(doors: int) -> void:
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
		plug.set_deferred("collision_layer", 0 if is_open else CollisionLayers.WORLD)


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
