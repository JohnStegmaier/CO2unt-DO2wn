extends Node2D

## The persistent run container.
##
## The player and the HUD live here rather than inside each room, so walking
## through a door swaps only the room node. That is what keeps the O2 countdown
## running across a floor instead of restarting at every doorway, and it is why
## rooms are instanced into RoomContainer instead of loaded with change_scene.

const ROOM_SCENE := preload("res://src/levels/room/room.tscn")
const ENEMY_SCENE := preload("res://src/entities/enemy/enemy.tscn")
const GAME_OVER_SCENE := "res://src/screens/game_over/game_over.tscn"

@export_group("Room Transition")
## Seconds to slide from one room to the next.
@export var transition_time: float = 0.85
## Curve of the slide. QUAD/OUT leaves fast and decelerates into place, which is
## the snappy Isaac feel; SINE/IN_OUT eases at both ends and reads as a glide.
@export var transition_trans: Tween.TransitionType = Tween.TRANS_QUAD
@export var transition_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("Enemies")
@export var enemies_min: int = 1
@export var enemies_max: int = 6
## Roughly one in ten hangs back and snipes. Deliberately lopsided — a room of
## all skirmishers is a shooting gallery, a room of all chasers is a scrum.
@export_range(0.0, 1.0) var skirmisher_chance: float = 0.1

@export_group("Death")
## Seconds for the heartbeat to swell up once the air goes critical. Runs
## alongside the letterbox slide, so keep it in the same ballpark.
@export var heartbeat_fade_in: float = 2.0
## Seconds the corpse is held under the closed vignette before the wipe. Just
## long enough to register that the body stopped moving.
@export var death_hold: float = 0.6

@export_group("Floor")
## Shape of every floor in the run. Tune it here and each generated floor obeys.
@export var floor_config: FloorConfig
## Pin a non-zero value to replay a run exactly, floor for floor. Left at 0 it is
## randomised on start and printed, so a floor that plays badly can be recovered
## from the log rather than described from memory.
@export var run_seed: int = 0

var _rng := RandomNumberGenerator.new()

@onready var _room_container: Node2D = $RoomContainer
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D
## The CanvasLayer itself, not the Node2D wrapping it: a CanvasLayer is not a
## CanvasItem, so hiding its Node2D parent leaves the HUD on screen.
@onready var _hud: CanvasLayer = $Ui/CanvasLayer
@onready var _o2_timer: O2Timer = $Ui/CanvasLayer/O2Timer
@onready var _ammo_counter: AmmoCounter = $Ui/CanvasLayer/AmmoCounter
@onready var _minimap: Minimap = $Ui/CanvasLayer/Minimap
## Deliberately under the camera rather than beside the HUD: the vignette is
## world content so the player can out-rank it on z_index and stay lit inside the
## closing dark. See death_overlay.gd.
@onready var _death_overlay: DeathOverlay = $Player/Camera2D/DeathOverlay
@onready var _pause_menu: PauseMenu = $PauseMenu
@onready var _ride: ElevatorRide = $ElevatorRide

var _plan: FloorPlan
var _current_room: Room
var _current_coord: Vector2i
var _transitioning: bool = false
## Fires-once guard on the death sequence, and the flag that tells the music
## re-arm on GlobalTimer.tick to stay down.
var _dying: bool = false
## Floors descended. 0 is the first, and it feeds both the seed and the room
## count, so every floor of a run is a different size and shape.
var _floor_number: int = 0


func _ready() -> void:
	GlobalTimer.tick.connect(_on_global_tick)
	GlobalTimer.tick.connect(_start_music)

	# The player reports hits upward and the O2 timer decides what they cost.
	# Game is the only node holding both ends, so the wiring belongs here.
	_player.damaged.connect(_o2_timer.apply_damage)
	_o2_timer.depleted.connect(_on_air_depleted)
	_o2_timer.air_restored.connect(_on_air_restored)
	_o2_timer.air_critical_changed.connect(_on_air_critical_changed)
	_o2_timer.suffocation_changed.connect(_death_overlay.set_vignette_progress)
	# The letterbox slides down over the corner the map sits in, so the map gets
	# out of its way rather than being drawn under it.
	_o2_timer.air_critical_changed.connect(_minimap.set_dimmed)
	_o2_timer.suffocated.connect(_on_player_died)

	_player.ammo_changed.connect(_ammo_counter.set_ammo)
	_ammo_counter.set_ammo(_player.ammo, _player.magazine_size)

	_rng.randomize()
	if run_seed == 0:
		run_seed = _rng.randi()
	if floor_config == null:
		# Belt and braces: the scene supplies one, but a Game dropped into
		# another scene without it should still generate rather than crash.
		floor_config = FloorConfig.new()

	_begin_floor(0)


## Called once per run, not once per room — the old per-level version restarted
## the track every doorway and could layer a second copy over the first.
##
## The 0.25s is the offset that puts the track a quarter-beat off the tick grid.
## process_always is false so a pause freezes this wait along with the grid —
## the default true would let the wait finish behind a pause menu and land the
## downbeat at the wrong offset for the rest of the run.
func _start_music() -> void:
	await get_tree().create_timer(0.25, false).timeout
	if _dying:
		return
	AudioManager.play_music("60000 light years", 1, 0, 0)


func _on_global_tick() -> void:
	AudioManager.play_sfx("tick_trim", 1, 0, 0)


## The walls are closing in and the player can hear their own pulse. Fired by the
## O2 timer as the letterbox crosses its threshold — in both directions, so a run
## that claws air back gets its silence back with the open frame.
func _on_air_critical_changed(critical: bool) -> void:
	if critical:
		AudioManager.start_heartbeat(heartbeat_fade_in)
	else:
		AudioManager.stop_heartbeat()


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
		previous_room.elevator_entered.disconnect(_on_elevator_entered)

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
	_current_room.configure(data)
	_current_room.door_entered.connect(_on_door_entered)
	_current_room.elevator_entered.connect(_on_elevator_entered)
	_current_coord = coord
	# Before the slide, not after: visited and _current_coord are both already
	# set, and a map that waited for the camera to land would be the one thing on
	# screen still claiming the player is in the room behind them.
	_minimap.set_current_room(coord)

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
	# After the physics frame, so six collision-shaped bodies cannot be added
	# mid-flush — the same hazard that forces _enter_room itself to be deferred.
	# After the slide, so enemies never get a free shot at a player who is still
	# a tween puppet with physics disabled.
	_populate(data)
	_transitioning = false


## Zelda-style room slide. Nothing is paused: the O2 countdown keeps running for
## the whole half second, so a transition costs you air like any other moment.
func _slide_to(landing: Vector2, previous_room: Room) -> void:
	_player.is_warping = true
	_player.velocity = Vector2.ZERO
	_camera.set_lead_enabled(false)

	# The room we are leaving stops acting the instant the slide starts. For the
	# next transition_time seconds the player is a tween puppet whose physics is
	# disabled, so anything still chasing or shooting is working a target that
	# cannot move, dodge, or shoot back.
	previous_room.process_mode = Node.PROCESS_MODE_DISABLED

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


## The player stepped into the exit room's elevator.
##
## The ride is what makes this cheap: it covers the screen, so the whole floor can
## be thrown away and a new one generated in a window the player cannot see. That
## is also why nothing here fades or waits on the world — the overlay is already
## hiding it.
func _on_elevator_entered() -> void:
	# _dying as well as _transitioning: a suffocating player keeps full control and
	# can still walk, so without this a body already on its way to the game over
	# screen could board the elevator and be carried to a floor it has no business
	# reaching.
	if _transitioning or _dying:
		return
	_transitioning = true
	# The player is a passenger for the duration. Without this, held movement keys
	# would still drive move_and_slide against a room that is being freed.
	_player.is_warping = true
	_player.velocity = Vector2.ZERO

	await _ride.descend()

	_clear_floor()
	await _begin_floor(_floor_number + 1)
	_on_floor_advanced()

	# Reclaimed after _begin_floor, which clears it on the way out. The doors are
	# still shut at this point, so nothing can be walked into until they open.
	_transitioning = true
	await _ride.arrive(_floor_number)

	_player.is_warping = false
	_transitioning = false


## Taking the elevator down. This is where O2 policy is applied, and the only
## reason it is a function of its own: if floors should get progressively less
## air, or air should carry over, this is the one place that changes.
func _on_floor_advanced() -> void:
	_o2_timer.refill()


## Throw the current floor away so the next one starts from nothing.
##
## The room is freed outright rather than slid away: the next floor is a different
## grid, so there is no adjacency for a camera pan to travel across.
func _clear_floor() -> void:
	get_tree().call_group("projectiles", "queue_free")
	# Above the early return deliberately: the map has to let go of the plan on
	# every path, or the model keeps a whole discarded floor alive behind it.
	_minimap.show_floor(null)
	if _current_room == null:
		return
	_current_room.door_entered.disconnect(_on_door_entered)
	_current_room.elevator_entered.disconnect(_on_elevator_entered)
	_current_room.queue_free()
	# Nulled so _enter_room takes its start-of-run path and warps the player in
	# rather than trying to slide between two rooms on unrelated grids.
	_current_room = null


## The tank read zero. The suit powers down and the ticking stops, leaving only
## the heartbeat — but the player is NOT dead and keeps full control. They have
## whatever is in their lungs, and the dark closing in is the clock on that.
##
## Nothing is frozen and nothing is torn down here, because this is a state the
## player can still get out of. See _on_air_restored.
func _on_air_depleted() -> void:
	GlobalTimer.tick.disconnect(_on_global_tick)
	GlobalTimer.tick.disconnect(_start_music)
	AudioManager.play_sfx("power_down", 1, 0, 0)
	AudioManager.stop_music()
	# Lift the player over the closing dark so they stay lit inside it. Set from
	# here rather than from either end, because Game is the only node holding
	# both the player and the overlay.
	_player.z_index = DeathOverlay.VIGNETTE_Z_INDEX + 1


## Air came back before the lungs ran out. Put the clock and the track back the
## way they were.
##
## Reconnecting _start_music is all the re-arming the music needs: it fires on
## the GlobalTimer beat and play_music claims a free player, so the track comes
## back on the grid exactly the way it does at the start of a run. The sync hack
## is untouched — this only reconnects the same signals it already relies on.
func _on_air_restored() -> void:
	if _dying:
		return
	GlobalTimer.tick.connect(_on_global_tick)
	GlobalTimer.tick.connect(_start_music)
	# Back into the ordinary draw order, so the player goes behind the room's
	# walls and trim again instead of standing in front of them.
	_player.z_index = 0


## Out of lungs. THIS is death — the vignette has shut and the player is done.
##
## The tree is deliberately NOT paused here — the death animation and the wipe
## both have to play, and a tree pause would freeze the very tweens carrying us
## to the game over screen. The world is stilled piece by piece instead.
func _on_player_died() -> void:
	if _dying:
		return
	_dying = true

	# A paused death sequence is a soft lock with no way out.
	_pause_menu.set_pause_allowed(false)

	if _current_room != null:
		_current_room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().call_group("projectiles", "queue_free")

	# Stop the camera chasing the cursor over a body that cannot move. Without
	# this the corpse keeps sliding around the screen after it is dead, and the
	# frame we are about to keep would be of a moving target.
	_camera.set_lead_enabled(false)

	await _player.die()
	# The suit's readout dies with the suit — and the frame we keep should be the
	# body in the dark, not a gauge reading zero over the top of it.
	_hud.visible = false
	await get_tree().create_timer(death_hold, false).timeout

	# Grabbed before the wipe: the closed vignette with the body still lit inside
	# it. The game over screen shows this, which is how the corpse stays exactly
	# where the player left it on screen.
	var last_frame: Texture2D = await _death_overlay.capture_screen()

	AudioManager.stop_heartbeat()
	await _death_overlay.fade_to_black()
	NavigationManager.go_to_screen(GAME_OVER_SCENE, last_frame)


## Stock a room with its bad guys. Only ordinary rooms fight, and a room whose
## count has reached zero stays quiet forever.
func _populate(data: RoomData) -> void:
	if data.kind != RoomData.Kind.NORMAL or data.enemies_remaining == 0:
		return
	if data.enemies_remaining < 0:
		data.enemies_remaining = _rng.randi_range(enemies_min, enemies_max)

	var player_local: Vector2 = _current_room.to_local(_player.global_position)
	var spots := EnemyPlacement.points(Room.FLOOR, data.enemies_remaining,
			player_local, _current_room.open_door_landings(), _rng)

	for spot in spots:
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		# Set before it enters the tree, so _ready() sees the finished article —
		# the dodge sensor is only armed for skirmishers.
		enemy.behaviour = Enemy.Behaviour.SKIRMISHER if _rng.randf() < skirmisher_chance \
				else Enemy.Behaviour.CHASER
		enemy.set_target(_player)
		enemy.died.connect(_on_enemy_died.bind(data))
		_current_room.add_entity(enemy, spot)

	# No way out until the room is quiet. The clock does not stop, which is the
	# point.
	_current_room.set_locked(true)


func _on_enemy_died(data: RoomData) -> void:
	data.enemies_remaining -= 1
	if data.enemies_remaining <= 0 and _current_room != null:
		_current_room.set_locked(false)


## Generate a floor and walk into its spawn room.
func _begin_floor(floor_number: int) -> void:
	_floor_number = floor_number
	var floor_seed: int = FloorGenerator.floor_seed_for(run_seed, floor_number)
	_plan = FloorGenerator.generate(floor_config, floor_number, floor_seed)
	# Before the awaited _enter_room below, or the spawn room announces itself to
	# a map that has no floor to place it on.
	_minimap.show_floor(_plan)

	# Enemy placement shares the floor's seed, so replaying a seed puts the bad
	# guys back too, not just the walls. Only along the same route, mind: rooms
	# are stocked as you reach them, so a different path draws differently.
	_rng.seed = floor_seed

	print("floor %d — run seed %d, %d rooms" % [floor_number + 1, run_seed, _plan.size()])
	print(_plan.to_ascii())
	# Awaited, so a caller riding the elevator can hold the overlay up until the
	# spawn room is built and stocked rather than opening onto an empty screen.
	await _enter_room(_plan.spawn_coord)
