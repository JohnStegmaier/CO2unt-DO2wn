class_name Room
extends Node2D

## One screen-sized room — a single cell of a floor.
##
## The shell is fixed: every room has all four doorways in its geometry. A room
## with fewer exits is the same scene with the unused doorways plugged, which is
## why there is one room scene instead of one per door combination.

signal door_entered(side: int)
## The player stepped into the exit room's elevator.
signal elevator_entered

## Distance between neighbouring room origins. Must equal the background texture
## size exactly, or rooms will not tile edge to edge.
const STRIDE := Vector2(442, 286)

## Room-local rect the camera is allowed to show.
const INTERIOR := Rect2(0, 0, 442, 286)

## Room-local rect anything on foot may stand in. The perimeter wall shapes are
## 28 deep, centred at 35/250 vertically and 35/406 horizontally, so the floor is
## everything inside their inner faces.
const FLOOR := Rect2(49, 49, 343, 187)

## Placeholder wash per RoomData.Kind, indexed the same way KIND_GLYPHS is — one
## tells you which room you are in from the terminal, the other from the screen.
## Ordinary and spawn rooms are untinted, so a colour always means "something is
## here". Stand-ins until the special rooms have art of their own.
const KIND_TINTS: Array[Color] = [
	Color(0, 0, 0, 0),                        # NORMAL
	Color(0, 0, 0, 0),                        # SPAWN
	Color(0.55, 0.06, 0.09, 0.3),             # BOSS
	Color(0.85, 0.66, 0.16, 0.24),            # SHOP
	Color(0.16, 0.42, 0.82, 0.26),            # TREASURE
	Color(0.16, 0.72, 0.36, 0.24),            # EXIT
]

## Where the elevator stands when this room is the exit, indexed by the wall it
## is set into. Each sits with its back against that wall's inner face, so the
## room can use any wall it has no doorway on — and a dead end, which is the only
## kind of room the exit is placed at, always has three spare.
const ELEVATOR_POSITIONS: Array[Vector2] = [
	Vector2(221, 85),    # NORTH
	Vector2(360, 143),   # EAST
	Vector2(221, 200),   # SOUTH
	Vector2(81, 143),    # WEST
]

## Walls tried in turn for the elevator. North and south come first because the
## car is drawn front-on: against a side wall it reads as facing the wrong way.
## A dead end only ever has one door, so in practice it is always north, or south
## when the door is north.
const ELEVATOR_WALL_PREFERENCE: Array[int] = [
	GridDirection.Side.NORTH,
	GridDirection.Side.SOUTH,
	GridDirection.Side.EAST,
	GridDirection.Side.WEST,
]

@onready var _doors: Node2D = $Doors
@onready var _plugs: Node2D = $Walls/Plugs
@onready var _entities: Node2D = $Entities
@onready var _tint: ColorRect = $Tint
@onready var _elevator: Elevator = $Elevator

## The door mask this room was configured with. Remembered so the doors can be
## sealed for a fight and restored afterwards without the room having to know
## why.
var _open_doors: int = 0
## Is this the cell the floor plan marked as its way out? Only an exit room has a
## car to stand in, and only an exit room can be made boardable.
var _is_exit: bool = false
## Is the way off this floor open? Owned by whoever generated the floor — see
## [method set_boardable].
var _boardable: bool = true


func _ready() -> void:
	for side in GridDirection.SIDES:
		door_for(side).player_entered.connect(_on_door_player_entered)
	_elevator.entered.connect(_on_elevator_entered)


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


## Put a solid prop on the floor. Same contract as [method add_entity] — position
## before the tree, interpolation reset after — but a different parent.
##
## Entities sit at z_index 2 and the player does not: they are on opposite sides
## of the scene, so everything in Entities draws in front of her. That is survivable
## for an enemy the same height as she is, and not survivable for a barrel, which
## would simply hide her. Obstacles go in a layer that draws with the walls
## instead.
##
## The real answer is y-sorting the room, which would fix the enemy case too. That
## is a change to how every room draws and belongs on its own branch.
func add_obstacle(node: Node2D, local_position: Vector2) -> void:
	node.position = local_position
	_obstacle_holder().add_child(node)
	node.reset_physics_interpolation()


## The layer props are parented to, made if this room has not got one.
##
## Looked up rather than @onready, and made rather than assumed, because a Room
## subclass is a separate scene and not an inherited one — ElevatorRoom declares
## its own tree from scratch, as ShopRoom does. An @onready $Obstacles therefore
## errors on every subclass the moment it enters the tree, whether or not that
## room ever holds a prop, and the fix cannot be "add the node to their scenes
## too": that breaks again for the next subclass, in a branch nobody has written
## yet.
##
## room.tscn still authors one, so the ordinary room gets it in the right place in
## the child list. This is only the fallback.
func _obstacle_holder() -> Node2D:
	var holder := get_node_or_null(^"Obstacles") as Node2D
	if holder != null:
		return holder
	holder = Node2D.new()
	holder.name = "Obstacles"
	# Explicit, because the whole reason this node exists is to draw beneath the
	# player rather than in front of her the way Entities does.
	holder.z_index = 0
	add_child(holder)
	return holder


## Room-local rect that solid props may be scattered into. An empty rect means
## "not this room".
##
## Distinct from [constant FLOOR] for the same reason
## [method default_spawn_position] is distinct from the centre of
## [method interior_rect]: a room whose walkable area is a shallow strip rather
## than the whole floor has to answer differently, and a caller that conflates
## them builds a barrel into the back wall.
func obstacle_rect() -> Rect2:
	return FLOOR


## Room-local landing spots of the doors that are currently open. Used to keep
## spawns clear of the mouths the player walks through.
func open_door_landings() -> Array[Vector2]:
	var landings: Array[Vector2] = []
	for side in GridDirection.SIDES:
		if (_open_doors & GridDirection.bit(side)) != 0:
			landings.append(to_local(door_for(side).spawn_position()))
	return landings


## Dress this shell as the cell the floor plan describes: open the doors it has,
## plug the rest, and wash it in its kind's colour. The door mask is remembered
## so a temporary seal can be lifted again.
func configure(data: RoomData) -> void:
	_open_doors = data.doors
	_apply_doors(data.doors)
	_tint.color = KIND_TINTS[data.kind]
	_is_exit = data.kind == RoomData.Kind.EXIT
	_place_elevator(data)


## Is there a floor below this one to go to?
##
## Separate from [method configure] because it answers a question about the RUN,
## not about the cell: the plan says which room holds the car, and this says
## whether the car will move. False leaves it dead — not shown, not monitoring,
## nothing to walk into — which is how floor 1 keeps the player in the building
## until its boss is dead, and how the Basement stays the bottom.
##
## Called after configure(), and cheap enough to call again at any time.
func set_boardable(boardable: bool) -> void:
	_boardable = boardable
	_elevator.set_active(_is_exit and _boardable)


## Stand the elevator against a bare wall, or put it away if this is not the exit.
##
## It must never share a wall with a doorway: arriving through a door places the
## player just inside it, and that is deep enough to land in the car and take the
## elevator the instant they walk in.
##
## Chooses the wall only. Whether the car is live is [method set_boardable]'s
## business, so the two cannot disagree about it.
func _place_elevator(data: RoomData) -> void:
	if not _is_exit:
		_elevator.set_active(false)
		return

	var wall: int = GridDirection.Side.NORTH
	for side in ELEVATOR_WALL_PREFERENCE:
		if not data.has_door(side):
			wall = side
			break
	_elevator.position = ELEVATOR_POSITIONS[wall]
	_elevator.set_active(_boardable)


## Seal every doorway, or restore the ones the floor plan gave this room.
##
## A sealed door is just a plugged one, so this reuses the plug the room already
## has for doorways that lead nowhere — same collision, same visual.
func set_locked(locked: bool) -> void:
	_apply_doors(0 if locked else _open_doors)


func _apply_doors(doors: int) -> void:
	for side in GridDirection.SIDES:
		var is_open: bool = (doors & GridDirection.bit(side)) != 0
		# Whether this side has a doorway at all, open or temporarily sealed —
		# distinct from is_open, which also goes false while the door is merely
		# locked shut for a fight.
		var has_door: bool = (_open_doors & GridDirection.bit(side)) != 0
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

		_open_sprite_for(side).visible = is_open
		_shut_sprite_for(side).visible = has_door and not is_open


func door_for(side: int) -> LevelDoor:
	return _doors.get_node("door_" + GridDirection.side_name(side))


func _open_sprite_for(side: int) -> Sprite2D:
	return _doors.get_node("door_" + GridDirection.side_name(side) + "_open")


func _shut_sprite_for(side: int) -> Sprite2D:
	return _doors.get_node("door_" + GridDirection.side_name(side) + "_shut")


## Where to put a player who just walked in through the given side.
func spawn_position(arrive_side: int) -> Vector2:
	return door_for(arrive_side).spawn_position()


## Camera clamp, in global space.
func interior_rect() -> Rect2:
	return Rect2(global_position + INTERIOR.position, INTERIOR.size)


## Where to put a player who arrives without walking through a door — the start of
## a floor, or anything else that drops them in directly.
##
## Deliberately its own method rather than interior_rect().get_center(). That rect
## is the CAMERA's, and its centre only lands on the floor because an ordinary
## room's walkable area happens to sit in the middle of its view. A room where
## that is not true — one whose floor is a strip at the bottom of a tall frame,
## say — has to answer the two questions differently, and a caller that conflates
## them stands the player in a wall.
func default_spawn_position() -> Vector2:
	return global_position + FLOOR.get_center()


func _plug_for(side: int) -> StaticBody2D:
	return _plugs.get_node("plug_" + GridDirection.side_name(side))


func _on_door_player_entered(side: int) -> void:
	door_entered.emit(side)


func _on_elevator_entered() -> void:
	elevator_entered.emit()
