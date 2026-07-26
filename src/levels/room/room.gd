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

## Room-local rect anything on foot may stand in.
##
## Deliberately inside the walls rather than flush with them: their inner faces
## are x 37..405 and y 38..248, and this keeps a further ~12px clear so props and
## spawns never end up wedged against a wall or straddling a door landing. Do not
## re-derive it from the wall shapes — tools/check_obstacles.gd pins this value
## and flood-fills the room for crossability against it.
const FLOOR := Rect2(49, 49, 343, 187)

## How far a plug reaches past the doorway into the wall on either side, so that
## rounding in the authored geometry can never leave a hairline gap at the join.
const PLUG_OVERLAP := 4.0

## Placeholder wash per RoomData.Kind, indexed the same way KIND_GLYPHS is — one
## tells you which room you are in from the terminal, the other from the screen.
## Ordinary and spawn rooms are untinted, so a colour always means "something is
## here". Stand-ins until the special rooms have art of their own.
const KIND_TINTS: Array[Color] = [
	Color(0, 0, 0, 0),                        # NORMAL
	Color(0, 0, 0, 0),                        # SPAWN
	Color(0.85, 0.12, 0.14, 0.1),             # BOSS
	Color(0.85, 0.66, 0.16, 0.24),            # SHOP
	Color(0.16, 0.42, 0.82, 0.26),            # TREASURE
	Color(0.16, 0.72, 0.36, 0.24),            # EXIT
]

## How far a shut door travels sliding into place. Moves along that side's own
## GridDirection.offset — the direction the door itself faces — so the north
## door slides up into its slot, the east door slides right into its, and so
## on; see _animate_door_shut.
const DOOR_SHUT_RISE_DISTANCE := 24.0
## Seconds the shut-door slide takes.
const DOOR_SHUT_TIME := 0.35

## Reveals a shut door in step with its slide, so no part of the sprite is
## ever drawn ahead of where the door has actually reached — see
## door_shut_reveal.gdshader.
const DOOR_SHUT_SHADER := preload("res://assets/shaders/door_shut_reveal.gdshader")
## Which axis each side's shut sprite wipes in — X for the doors on the east
## and west walls, Y for north and south — indexed the same way GridDirection
## SIDES is.
const DOOR_SHUT_AXIS: Array[int] = [1, 0, 1, 0] # NORTH, EAST, SOUTH, WEST
## Whether that side's wipe grows from the texture's far edge (UV 1.0) rather
## than its near one (UV 0.0) — set so the reveal always grows from the edge
## the door is travelling toward.
const DOOR_SHUT_FROM_END: Array[bool] = [false, true, true, false] # NORTH, EAST, SOUTH, WEST

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
@onready var _wall_body: StaticBody2D = $Walls/WallBody
@onready var _plugs: Node2D = $Walls/Plugs
@onready var _entities: Node2D = $Entities
@onready var _tint: ColorRect = $Tint
@onready var _elevator: Elevator = $Elevator

## The door mask this room was configured with. Remembered so the doors can be
## sealed for a fight and restored afterwards without the room having to know
## why.
var _open_doors: int = 0
## Where each side's shut sprite is authored to sit once fully closed. Read
## once in _ready(), before anything has ever moved it, so a slide that gets
## interrupted mid-flight and reversed still has a true resting spot to aim
## for instead of whatever position the animation left it at.
var _door_shut_resting: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
## The logical shut/open state each door is currently sliding toward or
## already at — distinct from the sprite's own `visible`, which lags behind
## it for the whole way the door takes to open (see _animate_door_open).
## Comparing against this rather than `visible` is what lets a lock land while
## the door is still retracting from the last one and have it reverse cleanly.
var _door_shut_state: Array[bool] = [false, false, false, false]
## The slide currently playing for each side, if any. Killed before a new one
## starts so a door asked to reverse mid-slide picks up from wherever it
## actually is rather than fighting the tween already driving it.
var _door_shut_tweens: Array[Tween] = [null, null, null, null]
## Is this the cell the floor plan marked as its way out? Only an exit room has a
## car to stand in, and only an exit room can be made boardable.
var _is_exit: bool = false
## Is the way off this floor open? Owned by whoever generated the floor — see
## [method set_boardable].
var _boardable: bool = true
## Doorways held shut for a reason that outlives the fight in this room — see
## [method set_sealed_sides].
var _sealed_doors: int = 0
## Is the room sealed for a fight right now? Kept because the two reasons a door
## can be shut arrive from different places at different times, and whichever
## lands second must not undo the first.
var _fight_locked: bool = false


func _ready() -> void:
	_fit_openings()
	for side in GridDirection.SIDES:
		door_for(side).player_entered.connect(_on_door_player_entered)
		_setup_door_shut_material(side)
	_elevator.entered.connect(_on_elevator_entered)


## Fit every plug and door trigger to the hole its wall actually leaves.
##
## This is the fix for a bug worth remembering. The plugs used to be authored
## independently of the walls, both 28 deep. An art pass thinned the walls to
## 17/16 and repositioned them, and left the plugs alone — so every plug stuck
## 11-13px past the wall's inner face, invisibly, onto the floor. Walking along a
## wall you stopped dead on nothing, and a shot fired along one died in mid-air
## short of the door. The door triggers had the same copied thickness and the same
## overhang.
##
## Measuring the walls at load rather than authoring a second set of numbers is
## what stops that happening again: move or resize a wall and the plug, the seal
## and the trigger follow it. The values in room.tscn are an editor preview.
##
## Only rooms built from room.tscn have any of this. ShopRoom and ElevatorRoom are
## drawn side-on, have neither doorways nor plugs, and deliberately do not call
## super._ready().
func _fit_openings() -> void:
	for side in GridDirection.SIDES:
		var opening := _doorway(side)
		var is_vertical: bool = side == GridDirection.Side.EAST \
				or side == GridDirection.Side.WEST
		var depth: float = opening.size.x if is_vertical else opening.size.y
		var width: float = opening.size.y if is_vertical else opening.size.x

		# Fresh per plug rather than the shared sub-resource, for the same reason
		# LevelDoor.fit_opening builds its own: one resource cannot hold four
		# sizes, and every instance of this scene would share whatever it held.
		var shape := RectangleShape2D.new()
		var plugged := width + PLUG_OVERLAP * 2.0
		shape.size = Vector2(depth, plugged) if is_vertical else Vector2(plugged, depth)

		var plug := _plug_for(side)
		plug.position = opening.get_center()
		# Deferred for the reason given in _apply_doors: the physics server
		# rejects shape changes made while it is flushing queries.
		plug.get_node("shape").set_deferred("shape", shape)

		door_for(side).fit_opening(depth, width)


## The hole in a wall, room-local: as deep as the band and as wide as the space
## its two shapes leave between them.
##
## Read off the wall shapes themselves so there is one source of truth for where a
## wall is. Each side is two CollisionShape2Ds named for it, and the doorway is
## what they do not cover.
func _doorway(side: int) -> Rect2:
	var band := Rect2()
	var gap_start := INF
	var gap_end := -INF
	var is_vertical: bool = side == GridDirection.Side.EAST \
			or side == GridDirection.Side.WEST

	for shape: CollisionShape2D in _wall_body.get_children():
		if not shape.name.begins_with("wall_" + GridDirection.side_name(side) + "_"):
			continue
		var rect := Rect2(shape.position - shape.shape.size * 0.5, shape.shape.size)
		band = rect if band.size == Vector2.ZERO else band.merge(rect)
		# The near edge of the far shape and the far edge of the near one are the
		# two sides of the gap, whichever order the children happen to be in.
		if is_vertical:
			gap_start = minf(gap_start, rect.end.y)
			gap_end = maxf(gap_end, rect.position.y)
		else:
			gap_start = minf(gap_start, rect.end.x)
			gap_end = maxf(gap_end, rect.position.x)

	if is_vertical:
		return Rect2(band.position.x, gap_start, band.size.x, gap_end - gap_start)
	return Rect2(gap_start, band.position.y, gap_end - gap_start, band.size.y)


## Give this side's shut sprite its own ShaderMaterial. One per sprite rather
## than one shared resource, because each carries its own axis/from_end — and
## once a fight starts, more than one door can be mid-slide with its own
## reveal value at once.
func _setup_door_shut_material(side: int) -> void:
	var sprite := _shut_sprite_for(side)
	_door_shut_resting[side] = sprite.position

	var material := ShaderMaterial.new()
	material.shader = DOOR_SHUT_SHADER
	material.set_shader_parameter("axis", DOOR_SHUT_AXIS[side])
	material.set_shader_parameter("from_end", DOOR_SHUT_FROM_END[side])
	material.set_shader_parameter("reveal", 1.0)
	sprite.material = material


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


## Put a piece of cosmetic floor dressing down. Same contract as
## [method add_obstacle] — position before the tree, interpolation reset after
## — but its own layer, one below Obstacles: a blood splat under a crate should
## stay under it rather than fight it for the same z_index.
func add_decal(node: Node2D, local_position: Vector2) -> void:
	node.position = local_position
	_decal_holder().add_child(node)
	node.reset_physics_interpolation()


## The layer decals are parented to, made if this room has not got one. Same
## reasoning as [method _obstacle_holder] — a Room subclass with its own tree
## must not be assumed to carry this node.
func _decal_holder() -> Node2D:
	var holder := get_node_or_null(^"Decals") as Node2D
	if holder != null:
		return holder
	holder = Node2D.new()
	holder.name = "Decals"
	holder.z_index = -1
	add_child(holder)
	return holder
## Room-local rect anything on foot may stand in.
##
## [constant FLOOR] is the answer for the shell, and was for a long time the only
## answer there was — which is why it used to be read straight off the class by
## everything that stocked a room. It stopped being the only answer the moment a
## room could be a different size from its cell: the Basement's board room is one
## cell in the plan and two cells tall on the screen, and an enemy clamped to
## FLOOR in there patrols the near half of a room it is standing at the far end
## of.
##
## Ask the room. The constant is still the default, so every ordinary room
## answers exactly as before.
func floor_rect() -> Rect2:
	return FLOOR


## Room-local rect that solid props may be scattered into. An empty rect means
## "not this room".
##
## Distinct from [method floor_rect] for the same reason
## [method default_spawn_position] is distinct from the centre of
## [method interior_rect]: a room whose walkable area is a shallow strip rather
## than the whole floor has to answer differently, and a caller that conflates
## them builds a barrel into the back wall.
func obstacle_rect() -> Rect2:
	return FLOOR


## Add whatever this room built into its own scene to the field of things in the
## way. Nothing, for a room whose only furniture is scattered into it.
##
## The scattered props register themselves as they are placed, because they are
## chosen at runtime. Furniture that is part of a room's scene is not, and would
## otherwise be invisible to everything that asks where the floor is free —
## enemies would walk through the board room table, spawn on it, and shoot each
## other across it.
##
## Circles, because that is what [ObstacleField] holds: a rectangular table is
## reported as the string of circles that covers it. Approximating one shape with
## several is the room's business, not the field's.
func register_solids(field: ObstacleField) -> void:
	pass


## Room-local spots this room wants its enemies stood in, or empty to let
## [EnemyPlacement] choose.
##
## Empty is the right answer for every generated room: a fight whose bad guys
## always stand in the same four places is a fight you learn once. It is the
## wrong answer for a room that was drawn by hand around a specific tableau — six
## men in suits are seated AT the board room table, not scattered near it, and
## no placement grid is going to work that out from a rect.
func authored_spawns() -> Array[Vector2]:
	return []


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
## has for doorways that lead nowhere — same collision. The two do not look alike:
## a doorway that leads nowhere shows nothing, and a sealed one slides its shut
## door into place. See _apply_doors.
## has for doorways that lead nowhere — same collision, same visual.
##
## "Restore" means the doors the plan gave this room MINUS the ones sealed for a
## reason of their own; see [method set_sealed_sides]. Clearing the fight lock
## must not open a door the floor never unlocked.
func set_locked(locked: bool) -> void:
	_fight_locked = locked
	_apply_doors(0 if locked else _open_doors & ~_sealed_doors)


## Hold particular doorways shut for a reason outside this room's fight.
##
## Today there is one: the way into an exit room the floor has not unlocked yet.
## Floor 1 hides the Basement behind its boss, and a dead lift was not enough to
## hide it — the player could still walk into the lobby and find the trick. The
## doorway itself has to be shut.
##
## Deliberately a mask and not a bool, and deliberately not folded into
## [method set_locked]: the two answer different questions on different clocks —
## one is "is this fight over", the other is "has the floor opened this way yet"
## — and a room can be under both at once. They compose because both resolve
## through [method _apply_doors], which has always taken an arbitrary mask.
##
## A sealed side is indistinguishable from a doorway that leads nowhere, which is
## the point: the room says nothing about what is behind it.
func set_sealed_sides(sides: int) -> void:
	_sealed_doors = sides
	# Nothing to do mid-fight — every door is shut anyway, and set_locked(false)
	# is what will read the new mask when the fight ends.
	if not _fight_locked:
		_apply_doors(_open_doors & ~_sealed_doors)


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
		# A plug draws nothing of its own — the doorway art is what you see — so
		# this only reaches the shape drawn by Debug > Visible Collision Shapes.
		# Worth keeping: it is what makes a mis-sized plug obvious on sight.
		# visible is not physics state, so it can be set straight away.
		plug.visible = not is_open
		# Hiding a body does not stop it colliding, so clear the layer too —
		# deferred for the same reason as monitoring above.
		plug.set_deferred("collision_layer", 0 if is_open else CollisionLayers.WORLD)

		_open_sprite_for(side).visible = is_open

		var should_be_shut: bool = has_door and not is_open
		# Compared against the logical state rather than the sprite's own
		# `visible` — see _door_shut_state — so a lock landing mid-retreat still
		# registers as a change and reverses the door instead of being ignored
		# because the sprite happens to still be visible from the last slide.
		if should_be_shut != _door_shut_state[side]:
			_door_shut_state[side] = should_be_shut
			if should_be_shut:
				_animate_door_shut(_shut_sprite_for(side), side)
			else:
				_animate_door_open(_shut_sprite_for(side), side)


## Slide a just-shut door into the resting spot it was authored at, arriving
## from the direction that side itself faces — that authored position is the
## end of the slide, never its start. The reveal shader rides along with the
## same progress, so nothing of the sprite is ever visible ahead of where the
## slide has actually gotten to: at t=0 it is sitting at its start coordinate
## and showing nothing, and every part of it only appears once the slide has
## carried it past that.
func _animate_door_shut(sprite: Sprite2D, side: int) -> void:
	var resting := _door_shut_resting[side]
	var direction := Vector2(GridDirection.offset(side))
	var start := resting - direction * DOOR_SHUT_RISE_DISTANCE

	_kill_door_tween(side)
	sprite.visible = true
	sprite.position = start
	sprite.material.set_shader_parameter("reveal", 0.0)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_step_door_shut.bind(sprite, start, resting), 0.0, 1.0, DOOR_SHUT_TIME)
	_door_shut_tweens[side] = tween


func _step_door_shut(t: float, sprite: Sprite2D, start: Vector2, resting: Vector2) -> void:
	sprite.position = start.lerp(resting, t)
	sprite.material.set_shader_parameter("reveal", t)


## The reverse of _animate_door_shut: retreats the door back out along the
## same path it slid in on and un-reveals it the same way in step, so a door
## leaves exactly how it arrived. Reads the sprite's current position and
## reveal as the start of the retreat rather than assuming it is at rest,
## so a lock that lands mid-slide and un-locks again just as quickly reverses
## smoothly instead of jumping.
func _animate_door_open(sprite: Sprite2D, side: int) -> void:
	var resting := _door_shut_resting[side]
	var direction := Vector2(GridDirection.offset(side))
	var start := resting - direction * DOOR_SHUT_RISE_DISTANCE
	var from_position := sprite.position
	var from_reveal: float = sprite.material.get_shader_parameter("reveal")

	_kill_door_tween(side)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(
			_step_door_open.bind(sprite, from_position, start, from_reveal), 0.0, 1.0, DOOR_SHUT_TIME)
	_door_shut_tweens[side] = tween

	await tween.finished
	# Only the slide that actually finishes gets to hide the door and reset it
	# — one killed early by a re-lock must leave the sprite exactly where that
	# newer slide takes over from.
	if _door_shut_tweens[side] == tween:
		sprite.visible = false
		sprite.position = resting
		sprite.material.set_shader_parameter("reveal", 1.0)


func _step_door_open(t: float, sprite: Sprite2D, from_position: Vector2, start: Vector2, from_reveal: float) -> void:
	sprite.position = from_position.lerp(start, t)
	sprite.material.set_shader_parameter("reveal", lerpf(from_reveal, 0.0, t))


func _kill_door_tween(side: int) -> void:
	var tween: Tween = _door_shut_tweens[side]
	if tween != null and tween.is_valid():
		tween.kill()


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
