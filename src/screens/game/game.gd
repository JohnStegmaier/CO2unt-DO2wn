extends Node2D

## The persistent run container.
##
## The player and the HUD live here rather than inside each room, so walking
## through a door swaps only the room node. That is what keeps the O2 countdown
## running across a floor instead of restarting at every doorway, and it is why
## rooms are instanced into RoomContainer instead of loaded with change_scene.

const ROOM_SCENE := preload("res://src/levels/room/room.tscn")

@export_group("Room Transition")
## Seconds to slide from one room to the next.
@export var transition_time: float = 0.85
## Curve of the slide. QUAD/OUT leaves fast and decelerates into place, which is
## the snappy Isaac feel; SINE/IN_OUT eases at both ends and reads as a glide.
@export var transition_trans: Tween.TransitionType = Tween.TRANS_QUAD
@export var transition_ease: Tween.EaseType = Tween.EASE_OUT

@onready var _room_container: Node2D = $RoomContainer
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D
@onready var _o2_timer: Node2D = $Ui/CanvasLayer/O2Timer

var _plan: FloorPlan
var _current_room: Room
var _current_coord: Vector2i
var _transitioning: bool = false


func _ready() -> void:
	GlobalTimer.tick.connect(_on_global_tick)
	_start_music()

	_plan = _build_debug_plan()
	print(_plan.to_ascii())
	_enter_room(_plan.spawn_coord)


## Called once per run, not once per room — the old per-level version restarted
## the track every doorway and could layer a second copy over the first.
func _start_music() -> void:
	await get_tree().create_timer(0.25).timeout
	AudioManager.play_music("60000 light years", 1, 0, 0)


func _on_global_tick() -> void:
	AudioManager.play_sfx("tick_trim", 1, 0, 0)


func _on_door_entered(side: int) -> void:
	if _transitioning:
		return
	var target: Vector2i = _current_coord + GridDirection.offset(side)
	if not _plan.has_room(target):
		push_warning("Game: %s door leads nowhere from %v" % [GridDirection.side_name(side), _current_coord])
		return

	# Claim the transition now, but build the room outside this callback. We are
	# inside the door's body_entered, which the physics server emits while it is
	# flushing queries — and adding a node full of collision shapes to the tree
	# is rejected outright at that moment. Deferring runs it after the flush.
	_transitioning = true
	_enter_room.call_deferred(target, GridDirection.opposite(side))


## arrive_side is the side of the NEW room the player walks in through.
## Leave it unset to drop the player in the middle, which is how a run starts.
func _enter_room(coord: Vector2i, arrive_side: int = -1) -> void:
	_transitioning = true

	# The room we are leaving stays in the tree until the slide finishes — both
	# rooms have to be on screen at once for the view to travel between them.
	var previous_room := _current_room
	if previous_room != null:
		previous_room.door_entered.disconnect(_on_door_entered)

	# Bullets belong to the room they were fired in, not to the run.
	get_tree().call_group("projectiles", "queue_free")

	var data := _plan.get_room(coord)
	data.visited = true

	_current_room = ROOM_SCENE.instantiate()
	# Rooms sit at their true grid position rather than all at the origin, so
	# world space and map space never disagree — which is also what makes the
	# slide below a plain camera pan instead of a compositing trick.
	#
	# Positioned BEFORE entering the tree, and reset after. Physics interpolation
	# is on project-wide: a node that enters at the origin and is moved afterwards
	# renders one frame interpolated from the origin, flashing the new room on top
	# of the one the player is still standing in. See bullet spawning in player.gd
	# for the same trap.
	_current_room.position = Vector2(coord) * Room.STRIDE
	_room_container.add_child(_current_room)
	_current_room.reset_physics_interpolation()
	_current_room.configure(data.doors)
	_current_room.door_entered.connect(_on_door_entered)
	_current_coord = coord

	var landing: Vector2 = _current_room.interior_rect().get_center()
	if arrive_side >= 0:
		landing = _current_room.spawn_position(arrive_side)

	if previous_room == null:
		# Start of a run — there is nothing to slide from.
		_player.warp_to(landing)
		_camera.set_bounds(_current_room.interior_rect())
	else:
		await _slide_to(landing, previous_room)
		previous_room.queue_free()

	await get_tree().physics_frame
	_transitioning = false


## Zelda-style room slide. Nothing is paused: the O2 countdown keeps running for
## the whole half second, so a transition costs you air like any other moment.
func _slide_to(landing: Vector2, previous_room: Room) -> void:
	_player.is_warping = true
	_player.velocity = Vector2.ZERO
	_camera.set_lead_enabled(false)

	var from_rect := previous_room.interior_rect()
	var to_rect := _current_room.interior_rect()

	var tween := create_tween()
	# Physics process, so engine physics interpolation smooths the travel rather
	# than fighting it — the player is a CharacterBody2D being moved directly.
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_ease(transition_ease).set_trans(transition_trans)
	tween.set_parallel(true)
	tween.tween_property(_player, "global_position", landing, transition_time)
	tween.tween_method(_pan_camera_between.bind(from_rect, to_rect), 0.0, 1.0, transition_time)
	await tween.finished

	_camera.set_bounds(to_rect)
	_camera.set_lead_enabled(true)
	_player.is_warping = false


## Slide the camera's clamp rect from one room to the next.
##
## This IS the pan. A room is barely bigger than the viewport, so the clamp pins
## the view near the room centre — but the player lands at a doorway, far from
## it. Widening the clamp for the slide and restoring it at the end therefore
## yanked the view most of a room's width in a single frame. Moving the clamp
## itself means it is already where it belongs when the tween ends.
func _pan_camera_between(t: float, from_rect: Rect2, to_rect: Rect2) -> void:
	_camera.set_bounds(Rect2(from_rect.position.lerp(to_rect.position, t), from_rect.size))


## Taking the elevator to the next level. Not wired to anything yet — the exit
## room is still a visual stub — but this is where O2 policy is applied.
func _on_floor_advanced() -> void:
	_o2_timer.refill()


## Hand-authored stand-in for the generator. Spawn has all four exits, with a
## couple of arms and a special room at the end of each. FloorGenerator will
## replace this one call and nothing else here moves.
func _build_debug_plan() -> FloorPlan:
	var plan := FloorPlan.new()
	var kinds := {
		Vector2i(0, 0): RoomData.Kind.SPAWN,
		Vector2i(0, -1): RoomData.Kind.SHOP,
		Vector2i(-1, 0): RoomData.Kind.NORMAL,
		Vector2i(-2, 0): RoomData.Kind.TREASURE,
		Vector2i(1, 0): RoomData.Kind.NORMAL,
		Vector2i(0, 1): RoomData.Kind.NORMAL,
		Vector2i(0, 2): RoomData.Kind.EXIT,
		Vector2i(1, 1): RoomData.Kind.BOSS,
	}
	for coord in kinds:
		plan.add_room(RoomData.new(coord, kinds[coord]))

	plan.connect_rooms(Vector2i(0, 0), GridDirection.Side.NORTH)
	plan.connect_rooms(Vector2i(0, 0), GridDirection.Side.EAST)
	plan.connect_rooms(Vector2i(0, 0), GridDirection.Side.SOUTH)
	plan.connect_rooms(Vector2i(0, 0), GridDirection.Side.WEST)
	plan.connect_rooms(Vector2i(-1, 0), GridDirection.Side.WEST)
	plan.connect_rooms(Vector2i(0, 1), GridDirection.Side.SOUTH)
	plan.connect_rooms(Vector2i(0, 1), GridDirection.Side.EAST)

	return plan
