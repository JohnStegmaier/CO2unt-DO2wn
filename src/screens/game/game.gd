extends Node2D

## The persistent run container.
##
## The player and the HUD live here rather than inside each room, so walking
## through a door swaps only the room node. That is what keeps the O2 countdown
## running across a floor instead of restarting at every doorway, and it is why
## rooms are instanced into RoomContainer instead of loaded with change_scene.

const ROOM_SCENE := preload("res://src/levels/room/room.tscn")

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
	_enter_room(target, GridDirection.opposite(side))


## arrive_side is the side of the NEW room the player walks in through.
## Leave it unset to drop the player in the middle, which is how a run starts.
func _enter_room(coord: Vector2i, arrive_side: int = -1) -> void:
	_transitioning = true

	if _current_room != null:
		_current_room.door_entered.disconnect(_on_door_entered)
		_current_room.queue_free()

	# Bullets belong to the room they were fired in, not to the run.
	get_tree().call_group("projectiles", "queue_free")

	var data := _plan.get_room(coord)
	data.visited = true

	_current_room = ROOM_SCENE.instantiate()
	_room_container.add_child(_current_room)
	# Rooms sit at their true grid position rather than all at the origin, so
	# world space and map space never disagree.
	_current_room.position = Vector2(coord) * Room.STRIDE
	_current_room.configure(data.doors)
	_current_room.door_entered.connect(_on_door_entered)
	_current_coord = coord

	var landing: Vector2 = _current_room.interior_rect().get_center()
	if arrive_side >= 0:
		landing = _current_room.spawn_position(arrive_side)
	_player.warp_to(landing)
	_camera.set_bounds(_current_room.interior_rect())

	await get_tree().physics_frame
	_transitioning = false


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
