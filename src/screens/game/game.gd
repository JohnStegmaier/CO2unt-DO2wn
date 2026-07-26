extends Node2D

## The persistent run container.
##
## The player and the HUD live here rather than inside each room, so walking
## through a door swaps only the room node. That is what keeps the O2 countdown
## running across a floor instead of restarting at every doorway, and it is why
## rooms are instanced into RoomContainer instead of loaded with change_scene.

const ROOM_SCENE := preload("res://src/levels/room/room.tscn")
const ENEMY_SCENE := preload("res://src/entities/enemy/enemy.tscn")
const ITEM_PICKUP_SCENE := preload("res://src/entities/pickup/item_pickup.tscn")
const OBSTACLE_SCENE := preload("res://src/entities/obstacle/obstacle.tscn")
## The clock's voice, once a second. Named because [ClockHold] has to be able to
## cut it short as well as stop the beat that fires it.
const TICK_SFX := &"tick_trim"
const GAME_OVER_SCENE := "res://src/screens/game_over/game_over.tscn"
const VICTORY_SCENE := "res://src/screens/victory/victory.tscn"
## Where a profile's drop configs live, so `[drops] config = "economy"` names a
## file without spelling out a path.
const DROP_CONFIG_DIR := "res://src/config/drops"
## Any odd constant would do — this only has to make the loot stream differ from
## the placement stream. Same golden-ratio word FloorGenerator.floor_seed_for
## uses, for the same reason: it spreads neighbouring seeds apart.
const LOOT_SEED_SALT := 0x9E3779B9
## Pixels a drop may be nudged when more than one lands at once. Roughly the
## width of a pickup, so they read as a little pile rather than as one item.
const LOOT_SCATTER := 10.0
## Half a pickup's sprite, so a drop pushed off a prop clears its edge rather than
## sitting against it.
const LOOT_CLEARANCE := 6.0

@export_group("Room Transition")
## Seconds to slide from one room to the next.
@export var transition_time: float = 0.85
## Seconds for the camera's pan, kept a touch longer than transition_time so the
## view is still catching up to the player when they land — a beat of drift
## rather than the two arriving in lockstep.
@export var camera_pan_time: float = 1.0
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

@export_group("Bosses")
## How many bad guys a boss room holds. One by default: a boss is a thing you
## fight, not a crowd you clear.
@export var boss_enemies_min: int = 1
@export var boss_enemies_max: int = 1
## Hit points, as a multiple of an ordinary enemy's.
@export var boss_hp_scale: float = 6.0
## Hit points of the man in the suit waiting in the Basement, on the same scale.
## Lower than an ordinary floor boss on purpose: he is the end of the game, not
## the hardest fight in it, and going out on a wall of hit points would undercut
## the joke. Kept a separate absolute value rather than a multiplier of the line
## above, so tuning ordinary bosses cannot silently retune the ending.
@export var final_boss_hp_scale: float = 2.5
## What a boss hits for, as a multiple. Far gentler than the hit point scale on
## purpose — see Enemy.make_boss for why the two cannot be the same number.
@export var boss_damage_scale: float = 1.6
## How much bigger a boss is drawn, and how much wider its collider is.
@export var boss_size_scale: float = 1.7

@export_group("Death")
## Seconds for the heartbeat to swell up once the air goes critical. Runs
## alongside the letterbox slide, so keep it in the same ballpark.
@export var heartbeat_fade_in: float = 2.0
## Seconds the corpse is held under the closed vignette before the wipe. Just
## long enough to register that the body stopped moving.
@export var death_hold: float = 0.6

@export_group("Victory")
## Seconds the last body is left on screen before the wipe to the victory screen.
## Longer than death_hold: nothing is closing in, and the player has earned a beat
## to look at the room they finished the game in.
@export var victory_hold: float = 1.4

@export_group("Exit Room")
## Stand-in scene for the floor's exit cell. Empty means the exit is an ordinary
## room with the wall-mounted elevator in it, exactly as if this had never been
## added; point it at a room scene and that scene is used for the exit instead.
##
## Deliberately an injected scene rather than a preloaded const or a bool: this
## file names no alternative implementation and imports nothing from one, so the
## exit room is swapped, added or removed entirely from the inspector. Anything
## satisfying Room's contract — configure, spawn_position, interior_rect,
## door_entered, elevator_entered — can be dropped in, and clearing the slot takes
## it back out with no code change and nothing left behind.
##
## Wired in game.tscn. When the feature-flag system lands, this becomes one line
## here and the slot can stay as the registry of what the flag chooses between.
@export var exit_room_scene: PackedScene

@export_group("Treasure Room")
## Stand-in scene for the floor's treasure cell — a room with a chest in it. Empty
## means the treasure cell is an ordinary room wearing its placeholder tint and
## holding nothing, exactly as if this had never been added.
##
## A bare PackedScene rather than a config Resource, unlike the shop below: there is
## one knob here, and what the chest holds is already a row of the drop config
## rather than a setting of its own. Same escape hatch as exit_room_scene otherwise
## — this file names no treasure room implementation, and clearing the slot takes
## the feature back out with no code change.
@export var treasure_room_scene: PackedScene

@export_group("Shop")
## Everything about shops, in one slot — the room scene, where its stock comes
## from, what the player starts with and what plays in there. Bundled into a
## single Resource rather than four exports because game.tscn is edited by more
## than one branch at a time and scene files do not merge.
##
## Leave it empty, or leave its room_scene empty, and shops fall back to ordinary
## rooms with their placeholder tint — same escape hatch as exit_room_scene.
@export var shop_config: ShopConfig
@export_group("Drops")
## The run's whole economy: who drops what, on which floor, how often. Swap the
## resource and the game plays by a different drop design with no code change —
## see docs/DROPS.md. A profile can override which one is loaded without editing
## this scene; see [method _apply_drop_overrides].
@export var drop_config: DropConfig

@export_group("Obstacles")
## Which solid props rooms are furnished with, how many, and which kinds of room
## get them. Swap the resource for a different set of clutter with no code change;
## untick a room kind to leave it bare.
@export var obstacle_set: ObstacleSet

@export_group("Floor")
## Shape of every floor in the run. Tune it here and each generated floor obeys.
@export var floor_config: FloorConfig
## Pin a non-zero value to replay a run exactly, floor for floor. Left at 0 it is
## randomised on start and printed, so a floor that plays badly can be recovered
## from the log rather than described from memory.
@export var run_seed: int = 0

var _rng := RandomNumberGenerator.new()
## Loot rolls draw from here rather than from _rng, so a change to what drops
## cannot shuffle where the enemies stand. Both are seeded off the same floor
## seed, so a replayed seed still replays both.
var _loot_rng := RandomNumberGenerator.new()
## What is standing in the room the player is in, so enemies and drops can be
## kept out of it. Rebuilt with every room; never drawn from an RNG, because a
## room's props are a function of its coord and the floor seed alone.
var _obstacle_field := ObstacleField.new()

@onready var _room_container: Node2D = $RoomContainer
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D
## The CanvasLayer itself, not the Node2D wrapping it: a CanvasLayer is not a
## CanvasItem, so hiding its Node2D parent leaves the HUD on screen.
@onready var _hud: CanvasLayer = $Ui/CanvasLayer
@onready var _o2_timer: O2Timer = $Ui/CanvasLayer/O2Timer
@onready var _ammo_counter: AmmoCounter = $Ui/CanvasLayer/AmmoCounter
@onready var _coin_counter: CoinCounter = $Ui/CanvasLayer/CoinCounter
@onready var _minimap: Minimap = $Ui/CanvasLayer/Minimap
## Deliberately under the camera rather than beside the HUD: the vignette is
## world content so the player can out-rank it on z_index and stay lit inside the
## closing dark. See death_overlay.gd.
@onready var _death_overlay: DeathOverlay = $Player/Camera2D/DeathOverlay
@onready var _pause_menu: PauseMenu = $PauseMenu
@onready var _ride: ElevatorRide = $ElevatorRide
## The wipe used for room changes that cannot be slid across. Distinct from the
## ride, which is a whole sequence, and from the death wipe, which never reopens.
@onready var _fade: ScreenFade = $ScreenFade

var _plan: FloorPlan
var _current_room: Room
var _current_coord: Vector2i
var _transitioning: bool = false
## Fires-once guard on the death sequence, and the flag that tells the music
## re-arm on GlobalTimer.tick to stay down.
var _dying: bool = false
## Floors descended. 0 is the first, and it feeds both the seed and the room
## count, so every floor of a run is a different size and shape.
##
## Counts UP while the game counts DOWN. That is not an oversight — see
## [FloorLadder], which is the only thing that turns this into the number on the
## wall, so the generator can keep the value that grows with depth.
var _floor_number: int = 0
## This floor's boss room has been emptied. Reset per floor rather than per run,
## because what it unlocks is a property of the floor: on floor 1 it is the
## Basement, and on every other floor it is nothing at all.
var _boss_cleared: bool = false
## Fires-once guard on the ending, the mirror of _dying. Kept separate so the two
## terminal states cannot be confused for one another — a won run must not take
## any of the paths that check _dying to decide the player is suffocating.
var _won: bool = false
## Every shop's shelves, for the length of the run — see [ShopRegistry]. Held
## here rather than in the rooms because rooms are freed when the player leaves.
var _shop_registry := ShopRegistry.new()
## The clock/music freeze a shop puts the run into. Built in _ready once the HUD
## exists, because it needs the countdown to freeze.
var _clock_hold: ClockHold


func _ready() -> void:
	GlobalTimer.tick.connect(_on_global_tick)
	GlobalTimer.tick.connect(_start_music)

	# The player reports hits upward and the O2 timer decides what they cost.
	# Game is the only node holding both ends, so the wiring belongs here.
	_player.damaged.connect(_o2_timer.apply_damage)
	_player.healed.connect(_o2_timer.gain_seconds)
	_o2_timer.depleted.connect(_on_air_depleted)
	_o2_timer.air_restored.connect(_on_air_restored)
	_o2_timer.air_critical_changed.connect(_on_air_critical_changed)
	_o2_timer.suffocation_changed.connect(_death_overlay.set_vignette_progress)
	# The letterbox slides down over the corner the map sits in, so the map gets
	# out of its way rather than being drawn under it.
	_o2_timer.air_critical_changed.connect(_minimap.set_dimmed)
	_o2_timer.suffocated.connect(_on_player_died)

	_player.ammo_changed.connect(_ammo_counter.set_ammo)
	_player.reloading_changed.connect(_ammo_counter.set_reloading)
	_ammo_counter.set_ammo(_player.ammo, _player.magazine_size)

	_player.weapon_changed.connect(_ammo_counter.set_shotgun_equipped)
	_ammo_counter.set_shotgun_equipped(_player.is_shotgun_equipped())

	_player.bombs_changed.connect(_o2_timer.set_bombs)
	_o2_timer.set_bombs(_player.f_bombs, _player.max_f_bombs)

	_player.coins_changed.connect(_coin_counter.set_coins)
	_coin_counter.set_coins(_player.coins)

	_player.power_level_changed.connect(_o2_timer.set_power_level)
	_o2_timer.set_power_level(_player.POWER_LVL)
	_player.speed_lvl_changed.connect(_o2_timer.set_speed_lvl)
	_o2_timer.set_speed_lvl(_player.SPEED_LVL)
	_player.firerate_lvl_changed.connect(_o2_timer.set_firerate_lvl)
	_o2_timer.set_firerate_lvl(_player.FIRERATE_LVL)

	# Profile overrides, all of them landing before anything reads the values.
	# Defaults stay on the exports above, so a profile that names none of these
	# keys runs the shipped numbers — see docs/TUNING_PROFILES.md.
	enemies_min = GameConfig.get_value("enemies", "min", enemies_min)
	enemies_max = GameConfig.get_value("enemies", "max", enemies_max)
	# A profile that lowers only the ceiling should not leave the floor above it:
	# `[enemies] max = 0` on its own has to mean an empty room, not one enemy.
	enemies_min = mini(enemies_min, enemies_max)
	boss_enemies_min = GameConfig.get_value("enemies", "boss_min", boss_enemies_min)
	boss_enemies_max = GameConfig.get_value("enemies", "boss_max", boss_enemies_max)
	boss_enemies_min = mini(boss_enemies_min, boss_enemies_max)
	# A profile that empties the station has to empty its boss rooms too, or
	# `peaceful` still puts a boss between the player and the Basement. Keyed on
	# the ordinary ceiling rather than on the profile's name, so any profile that
	# turns the enemies off gets the same answer.
	if enemies_max == 0:
		boss_enemies_min = 0
		boss_enemies_max = 0
	run_seed = GameConfig.get_value("floor", "run_seed", run_seed)
	_apply_drop_overrides()

	_rng.randomize()
	if run_seed == 0:
		run_seed = _rng.randi()
	if floor_config == null:
		# Belt and braces: the scene supplies one, but a Game dropped into
		# another scene without it should still generate rather than crash.
		floor_config = FloorConfig.new()
	floor_config.apply_overrides()
	_apply_obstacle_overrides()

	_setup_shops()

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
	if _dying or _won:
		return
	# And not while a shop has the clock stopped. This runs a quarter-second after
	# the tick that armed it, which is long enough for the freeze to land in
	# between — and the freeze suspends whatever was already playing rather than
	# stopping it, so on the rare pass where the run's track happened not to be
	# playing at all (the first seconds of a floor, or just after air came back)
	# there is nothing for play_music to recognise and it starts the run's music
	# inside the shop.
	if _clock_hold != null and _clock_hold.is_held():
		return
	AudioManager.play_music("60000 light years", 1, -11, 0)


func _on_global_tick() -> void:
	AudioManager.play_sfx(TICK_SFX, 1, -5, 0)


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
	var previous_kind: int = -1
	if previous_room != null:
		previous_kind = _plan.get_room(_current_coord).kind
		previous_room.door_entered.disconnect(_on_door_entered)
		previous_room.elevator_entered.disconnect(_on_elevator_entered)
		if previous_room.has_signal(&"treasure_opened"):
			previous_room.treasure_opened.disconnect(_on_treasure_opened)

	# Bullets belong to the room they were fired in, not to the run.
	get_tree().call_group("projectiles", "queue_free")

	var data := _plan.get_room(coord)
	data.visited = true

	# The exit can be a room of its own — see exit_room_scene. Whatever comes back
	# is a Room and reports boarding through the same elevator_entered signal an
	# ordinary exit room does, so every line below this is unchanged and the ride
	# never learns which kind of elevator called it.
	var scene: PackedScene = ROOM_SCENE
	if data.kind == RoomData.Kind.EXIT and exit_room_scene != null:
		scene = exit_room_scene
	elif _shop_room_available() and data.kind == RoomData.Kind.SHOP:
		scene = shop_config.room_scene
	elif data.kind == RoomData.Kind.TREASURE and treasure_room_scene != null:
		scene = treasure_room_scene
	_current_room = scene.instantiate()
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
	# After configure, which is what decides whether this cell holds a car at all.
	# Read here rather than kept live: the exit and the boss are different dead
	# ends, so the player can never be standing in this room at the moment the
	# answer changes.
	_current_room.set_boardable(_exit_available())
	# Here rather than beside _populate, for three reasons: it is before every
	# await below, so there is no window in which the room could be freed out from
	# under it; the room slides into view already furnished; and the enemies
	# placed further down can be told what is in the way.
	_scatter_obstacles(data)
	_current_room.door_entered.connect(_on_door_entered)
	_current_room.elevator_entered.connect(_on_elevator_entered)
	# Asked of the room rather than keyed on its kind, for the same reason the scene
	# choice above is keyed on the slot being filled: this file names no treasure
	# room implementation and imports nothing from one. Anything that reports a
	# chest the same way gets paid out the same way.
	if _current_room.has_signal(&"treasure_opened"):
		_current_room.treasure_opened.connect(_on_treasure_opened)
	# Before the transition, not after: the beat grid has to stop before the fade
	# starts or the clock ticks on into a shop the player has already committed
	# to. See _apply_clock_hold.
	_apply_clock_hold(data)
	_current_coord = coord
	# Before the slide, not after: visited and _current_coord are both already
	# set, and a map that waited for the camera to land would be the one thing on
	# screen still claiming the player is in the room behind them.
	_minimap.set_current_room(coord)

	var landing: Vector2 = _current_room.default_spawn_position()
	if arrive_side >= 0:
		landing = _current_room.spawn_position(arrive_side)

	if previous_room == null:
		# Start of a run — there is nothing to slide from.
		_player.warp_to(landing)
		_camera.set_bounds(_current_room.interior_rect())
	elif _is_cut_transition(data.kind) or _is_cut_transition(previous_kind):
		await _cut_to(landing, previous_room)
		previous_room.queue_free()
	else:
		await _slide_to(landing, previous_room)
		previous_room.queue_free()

	await get_tree().physics_frame
	# Lead was never on to begin with for the start-of-run branch above, but
	# asking again here costs nothing and means every path into _populate goes
	# through the same held-still window rather than only the two that had a
	# transition to turn it off for.
	_camera.set_lead_enabled(false)
	# After the physics frame, so six collision-shaped bodies cannot be added
	# mid-flush — the same hazard that forces _enter_room itself to be deferred.
	# After the slide, so enemies never get a free shot at a player who is still
	# a tween puppet with physics disabled.
	var locked: bool = _populate(data)
	# Lead stays off for the door-shut slide too, not just the room slide that
	# preceded it — aim lead alone is enough drift to read as the camera
	# wandering off while the doors are still sealing the room.
	if locked:
		await get_tree().create_timer(Room.DOOR_SHUT_TIME, false).timeout
	_camera.set_lead_enabled(true)
	# After the line above, deliberately. A shop suppresses the camera's aim-lead
	# for the whole visit, and this is where the lead is switched back on for
	# every other room — so the shop has to have the last word or its suppression
	# is undone the instant it is applied.
	_apply_shop_services(data, coord)
	_transitioning = false


## Does moving into or out of a room of this kind have to be a cut?
##
## Only the swapped-in exit room, and only while one is actually installed. The
## slide assumes the two cells share an edge and are drawn the same way round;
## a replacement exit room is neither, so travelling to it has nothing to show.
##
## Keyed on the same fact that chose the scene rather than on the scene's type, so
## this file still names no alternative implementation — anything dropped into
## exit_room_scene gets the cut without announcing itself.
func _is_cut_transition(kind: int) -> bool:
	if kind == RoomData.Kind.EXIT and exit_room_scene != null:
		return true
	# The shop is drawn side-on for the same reason and travels the same way: a
	# slide assumes the two cells share an edge and are drawn the same way round,
	# and a belt-scroll room is neither.
	return kind == RoomData.Kind.SHOP and _shop_room_available()


## Swap rooms behind a wipe instead of travelling between them.
##
## The player is moved rather than tweened, so there is no path across the gap for
## anything to look wrong on. Everything that would be seen happens while the
## screen is black; the clock keeps running through it, same as the slide.
func _cut_to(landing: Vector2, previous_room: Room) -> void:
	_player.is_warping = true
	_player.velocity = Vector2.ZERO
	_camera.set_lead_enabled(false)
	previous_room.process_mode = Node.PROCESS_MODE_DISABLED

	await _fade.fade_out()

	_player.warp_to(landing)
	# Under the black, because the room being left may have been drawing the
	# player differently — the belt-scroll rooms scale her up to three times life
	# size and hide the gun. Restoring on the way out of the zone instead would
	# happen in plain sight (see ShopRoom._on_shop_exited), and leaving it to the
	# old room's _exit_tree would carry that size a frame or two into the next
	# room. Idempotent and a no-op on a corpse, so every cut can just do it.
	_player.reset_presentation()
	_camera.set_bounds(_current_room.interior_rect())
	# The camera rides the player, so it has just been teleported too. Physics
	# interpolation is on project-wide and would otherwise smear the first frame
	# after the wipe across the whole distance travelled.
	_camera.reset_physics_interpolation()
	# One frame under the black, so the new room's bodies are settled and the view
	# is already where it belongs before anything is visible.
	await get_tree().physics_frame

	await _fade.fade_in()

	# Lead stays off — _enter_room is what turns it back on, once the room
	# behind this wipe is done locking its doors, not before.
	_player.is_warping = false


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
	tween.tween_method(_pan_camera_between.bind(from_rect, to_rect), 0.0, 1.0, camera_pan_time)
	await tween.finished

	_camera.set_bounds(to_rect)
	# Lead stays off — _enter_room is what turns it back on, once the room
	# behind this slide is done locking its doors, not before.
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
	if _transitioning or _dying or _won:
		return
	# Belt and braces on top of set_boardable: the Basement's car is never live, so
	# nothing should be able to report boarding it, and a run that fell off the
	# bottom of the ladder would generate a floor the plates cannot even name.
	if FloorLadder.is_final(_floor_number):
		push_warning("Game: boarded the lift on %s, which has nothing below it" % FloorLadder.long_label(_floor_number))
		return
	_transitioning = true
	# The player is a passenger for the duration. Without this, held movement keys
	# would still drive move_and_slide against a room that is being freed.
	_player.is_warping = true
	_player.velocity = Vector2.ZERO

	await _ride.descend(_floor_number)

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


## Will this floor's lift take the player anywhere?
##
## Two reasons it might not. The Basement is the bottom of the building, so there
## is never anywhere further down. And floor 1 is where the game's one real secret
## lives: the panel shows no floor below until its boss is dead, and then it shows
## a Basement the player had no reason to think was there.
func _exit_available() -> bool:
	if FloorLadder.is_final(_floor_number):
		return false
	return not FloorLadder.gates_on_boss(_floor_number) or _boss_cleared


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
	# _win() has already taken the clock and the track down, and taking them down
	# twice faults on a connection that is no longer there.
	if _won:
		return
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
	if _dying or _won:
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
	# _won as well: winning on the last breath must not be overtaken by the tank
	# emptying while the ending plays out. The last thing to happen wins.
	if _dying or _won:
		return
	_dying = true

	# Released before anything else: dying inside a shop must not leave the run's
	# music frozen and the countdown out of processing behind the game over
	# screen. Idempotent, so it costs nothing on the ordinary path.
	_release_clock_hold()

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


## The man in the suit is on the Basement floor and the building is behind you.
##
## Structured as the mirror of [method _on_player_died] and for the same reasons:
## the tree is not paused, because the wipe carrying us to the victory screen is a
## tween and a paused tree would freeze it. The world is stilled piece by piece.
##
## What is deliberately NOT here is [method Player.die]. The player walks out of
## this one, so there is no squash and no vignette — the last frame kept is the
## room, lit, with the body standing up in it.
func _win() -> void:
	if _won or _dying:
		return
	_won = true

	# Same reason as in _on_player_died: the ending must not run over a frozen
	# clock. Nothing in a normal run wins from inside a shop, but the cost of
	# saying so is one idempotent call.
	_release_clock_hold()

	# The clock stops. Everywhere else in this file the countdown running through
	# a cutscene is the point; here it is the one thing that could still kill a
	# player who has already finished the game.
	#
	# Tested rather than disconnected outright: _on_air_depleted drops both of
	# these when the tank empties, so a player who wins while suffocating would
	# otherwise fault on a connection that is already gone.
	if GlobalTimer.tick.is_connected(_on_global_tick):
		GlobalTimer.tick.disconnect(_on_global_tick)
	if GlobalTimer.tick.is_connected(_start_music):
		GlobalTimer.tick.disconnect(_start_music)
	_o2_timer.process_mode = Node.PROCESS_MODE_DISABLED
	AudioManager.stop_heartbeat()

	# A paused ending is a soft lock with no way out, same as a paused death.
	_pause_menu.set_pause_allowed(false)

	# The player is a spectator from here: held keys must not walk them out of the
	# frame that is about to be kept.
	_player.is_warping = true
	_player.velocity = Vector2.ZERO
	_camera.set_lead_enabled(false)
	get_tree().call_group("projectiles", "queue_free")

	await get_tree().create_timer(victory_hold, false).timeout
	if _current_room != null:
		_current_room.process_mode = Node.PROCESS_MODE_DISABLED
	_hud.visible = false

	var last_frame: Texture2D = await _death_overlay.capture_screen()
	AudioManager.stop_music()
	await _death_overlay.fade_to_black()
	NavigationManager.go_to_screen(VICTORY_SCENE, last_frame)


## Stock a room with its bad guys. Ordinary rooms and boss rooms fight; a room
## whose count has reached zero stays quiet forever.
##
## Boss rooms differ only in how many and how hard, not in how any of this works
## — same placement, same lock, same count coming back if the player retreats
## mid-fight. That is deliberate: the climax of a floor should be the same
## machinery under load, so there is only ever one of these to get right.
##
## Returns whether the room actually got locked — _enter_room uses that to know
## whether to hold the camera still for the door-shut slide, or free it right
## away because there was no lock to wait on.
func _populate(data: RoomData) -> bool:
	var is_boss: bool = data.kind == RoomData.Kind.BOSS
	if not (is_boss or data.kind == RoomData.Kind.NORMAL) or data.enemies_remaining == 0:
		return false
	if data.enemies_remaining < 0:
		data.enemies_remaining = _rng.randi_range(boss_enemies_min, boss_enemies_max) if is_boss \
				else _rng.randi_range(enemies_min, enemies_max)

	# A room that stocks nothing must not seal itself. The doors are unlocked by
	# enemies dying, so locking an empty room locks it for good and the floor is
	# unfinishable. Normalised to 0 rather than left negative so a revisit takes
	# the early return above. Unreachable on the shipped values, where enemies_min
	# is 1 — the peaceful profile is what makes a zero roll possible.
	if data.enemies_remaining <= 0:
		data.enemies_remaining = 0
		# A boss room that stocks nothing is a boss room that is already beaten.
		# Nothing will ever die in it to say so, and the gate it opens is the only
		# way down off floor 1 — so a profile that turns the enemies off would
		# otherwise leave the run unfinishable rather than merely quiet.
		if is_boss:
			_clear_boss_gate()
		return false

	var player_local: Vector2 = _current_room.to_local(_player.global_position)
	var spots := EnemyPlacement.points(Room.FLOOR, data.enemies_remaining,
			player_local, _current_room.open_door_landings(), _rng, _obstacle_field)

	for spot in spots:
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		# Set before it enters the tree, so _ready() sees the finished article —
		# the dodge sensor is only armed for skirmishers, and Health copies its
		# maximum into its current value.
		enemy.behaviour = Enemy.Behaviour.SKIRMISHER if _rng.randf() < skirmisher_chance \
				else Enemy.Behaviour.CHASER
		enemy.loot_source = _loot_source_for(enemy.behaviour, is_boss)
		if is_boss:
			var hp_scale: float = final_boss_hp_scale if FloorLadder.is_final(_floor_number) \
					else boss_hp_scale
			enemy.make_boss(hp_scale, boss_damage_scale, boss_size_scale)
		enemy.set_target(_player)
		enemy.died.connect(_on_enemy_died.bind(data))
		_current_room.add_entity(enemy, spot)

	# No way out until the room is quiet. The clock does not stop, which is the
	# point.
	_current_room.set_locked(true)
	AudioManager.play_sfx("steel_drip",1,0,0.3)
	AudioManager.play_sfx("spikes_down",0.8,0,0.3)
	return true


func _on_enemy_died(loot_source: StringName, at: Vector2, data: RoomData) -> void:
	# Deferred, because this can run mid physics-query-flush — reached from a
	# bullet's body_entered — and adding a pickup's collision shape to the tree
	# right then is exactly the state change the physics server rejects. The
	# bookkeeping below is safe to do now and has to be, or the door would not
	# unlock until the next idle frame.
	_spawn_loot.call_deferred(loot_source, at)

	data.enemies_remaining -= 1
	if data.enemies_remaining > 0:
		return
	if _current_room != null:
		_current_room.set_locked(false)
		AudioManager.play_sfx("chest_open")
	if data.kind != RoomData.Kind.BOSS:
		return

	_clear_boss_gate()


## The floor's boss room is empty. On floor 1 that is what puts a Basement under
## the building; in the Basement itself there is nothing left below, so it is the
## end of the game.
##
## Reached both by killing the last boss and by walking into a boss room that
## stocked none — see _populate. Sharing one path is what stops the second case
## being a soft lock.
func _clear_boss_gate() -> void:
	_boss_cleared = true
	if FloorLadder.is_final(_floor_number):
		_win()


## Generate a floor and walk into its spawn room.
func _begin_floor(floor_number: int) -> void:
	if floor_number > FloorLadder.BASEMENT_INDEX:
		push_warning("Game: asked for floor index %d, below the Basement" % floor_number)
	_floor_number = floor_number
	# Per floor, not per run: what a dead boss unlocks belongs to the floor it
	# died on, and carrying the flag down would open the next floor's lift before
	# its own boss had been found.
	_boss_cleared = false
	var floor_seed: int = FloorGenerator.floor_seed_for(run_seed, floor_number)
	_plan = FloorGenerator.generate(floor_config, floor_number, floor_seed)
	# Before the awaited _enter_room below, or the spawn room announces itself to
	# a map that has no floor to place it on.
	_minimap.show_floor(_plan)

	# Enemy placement shares the floor's seed, so replaying a seed puts the bad
	# guys back too, not just the walls. Only along the same route, mind: rooms
	# are stocked as you reach them, so a different path draws differently.
	_rng.seed = floor_seed
	# Offset rather than shared, so retuning a drop table cannot move an enemy and
	# adding an enemy cannot change what the one before it dropped.
	_loot_rng.seed = floor_seed ^ LOOT_SEED_SALT

	print("%s — run seed %d, %d rooms" % [FloorLadder.long_label(floor_number), run_seed, _plan.size()])
	print(_plan.to_ascii())
	# Awaited, so a caller riding the elevator can hold the overlay up until the
	# spawn room is built and stocked rather than opening onto an empty screen.
	await _enter_room(_plan.spawn_coord)


# -- Shops -------------------------------------------------------------------
#
# Everything the run has to do about shops, gathered here rather than scattered
# through _enter_room. One call from up there and the bodies live down here, so
# the composition root stays readable while three branches are adding to it.


## Build the clock hold and hand the player their starting coins.
##
## Belt and braces on the config, the same way floor_config is handled: the scene
## supplies one, but a Game dropped into another scene without it should still
## run — with shops simply switched off.
func _setup_shops() -> void:
	if shop_config == null:
		shop_config = ShopConfig.new()
	shop_config.apply_overrides()

	# The tick goes in so the hold can silence it. Stopping the beat grid leaves
	# the last tick still sounding — it is a two-second sample on a one-second
	# beat, so there is always one in the air.
	_clock_hold = ClockHold.new(_o2_timer, shop_config.music, TICK_SFX)
	_grant_starting_coins()


## What the player opens a run with. add_coins rather than touching coins
## directly, so the HUD's counter hears about it through coins_changed like every
## other change to the balance.
func _grant_starting_coins() -> void:
	if shop_config.starting_coins <= 0:
		return
	_player.add_coins(shop_config.starting_coins)


## Is there a shop room to swap in at all?
func _shop_room_available() -> bool:
	return shop_config != null and shop_config.room_scene != null


## Take or release everything a shop changes about the run, derived from the room
## the player just walked into.
##
## Derived state rather than a pair of events, and re-asserted on EVERY room
## change rather than only on the ones that involve a shop. That is what makes a
## leaked hold — a run whose clock never restarts — unreachable rather than
## merely unlikely: there is no path out of a shop that does not come through
## here, and arriving anywhere that is not a shop puts the clock back.
## Stop or restart the run's clock, derived from the room being entered.
##
## Split out of [method _apply_shop_services] and called BEFORE the transition,
## because a cut into a shop is the better part of a second of fade and the beat
## grid was still running for all of it — you could hear the clock tick once or
## twice after the countdown had visibly stopped.
##
## The reason it used to sit after the transition was to let in-flight HUD tweens
## land before their node stopped processing. That does not hold up: ScreenFade
## is CanvasLayer 10 and the HUD is on the default layer, so the wipe covers the
## gauge too and a tween frozen underneath it cannot be seen.
##
## The corollary is that the clock is frozen for the fade INTO a shop and
## restarts as you fade out of one, so a visit costs no air at either end. That
## is the right reading: the safe room starts at the door.
func _apply_clock_hold(data: RoomData) -> void:
	if _clock_hold == null:
		return
	_clock_hold.set_held(data.kind == RoomData.Kind.SHOP and _shop_room_available())


## Wire up the room the player just walked into, if it is a shop.
##
## Stays after the transition AND after the camera's lead is switched back on,
## unlike the clock hold above. Every room goes through a held-still window that
## ends by re-enabling the lead, so a shop suppressing it any earlier would have
## its suppression undone on the way out of that window.
func _apply_shop_services(data: RoomData, coord: Vector2i) -> void:
	var is_shop: bool = data.kind == RoomData.Kind.SHOP and _shop_room_available()
	if not is_shop:
		return

	# The camera's own aim-lead is suppressed for the visit, or it wobbles
	# underneath the room's parallax and the two fight over the same few pixels.
	_camera.set_lead_enabled(false)

	if _current_room.has_method("configure_shop"):
		var capacity: int = _current_room.grid.capacity() if _current_room.grid != null else 0
		_current_room.configure_shop(
			_shop_registry.stock_for(shop_config.stock_provider, _floor_number, coord, capacity),
			_player)
		if not _current_room.offer_purchased.is_connected(_on_offer_purchased):
			_current_room.offer_purchased.connect(_on_offer_purchased)


func _release_clock_hold() -> void:
	if _clock_hold != null:
		_clock_hold.set_held(false)


## Somebody bought something.
##
## The room reports the sale and this decides what it means, which keeps the shop
## from being the one node that knows both what is on a shelf and what a player
## is made of. Applying the effects is the item catalogue's contract — see
## ItemEffect on the drops branch — and is duck-typed until it lands.
func _on_offer_purchased(offer: ShopOffer) -> void:
	if offer == null or offer.item == null:
		return
	# grant_to rather than walking the effects here: ItemDef says in its own
	# docstring that it exists so the shop hands an item over by exactly the path
	# a floor drop does, and a second implementation of "apply every effect" is
	# the one that would drift.
	offer.item.grant_to(_player)
## Let a tuning profile pick a different drop economy for the run.
##
## The inspector slot is what ships; this only redirects it, so a profile naming
## no config leaves the shipped tables exactly as they are — the same bargain
## every other override in _ready makes. See docs/TUNING_PROFILES.md.
func _apply_drop_overrides() -> void:
	var named: String = GameConfig.get_value("drops", "config", "")
	if named.is_empty():
		return

	var path := "%s/%s.tres" % [DROP_CONFIG_DIR, named]
	var loaded := load(path) as DropConfig
	if loaded == null:
		# Loudly, and without falling back: a mistyped config that quietly ran the
		# shipped tables would waste a whole playtest deciding they felt wrong.
		push_error("Game: no drop config '%s' at %s" % [named, path])
		return
	drop_config = loaded


## Which row of the drop table this enemy's death is looked up under.
##
## Decided here rather than left on the scene because this is where the enemy is
## made what it is — the same two lines that choose its behaviour and promote it
## to a boss. An enemy spawned by anything else keeps the scene's own default.
func _loot_source_for(behaviour: int, is_boss: bool) -> StringName:
	if is_boss:
		return &"boss"
	if behaviour == Enemy.Behaviour.SKIRMISHER:
		return &"skirmisher"
	return &"grunt"


## Pay out a treasure room's chest, once ever.
##
## The flag is written here rather than by the room for the same reason the room
## does not grant its own loot: a room is furniture for one visit, and this is the
## only thing on the floor that outlives it. Written before the deferred call and
## not inside it, so nothing can slip between the two and open the chest twice.
##
## The chest reports where its contents go rather than this deciding — it is the
## only thing here that knows how big it is, and a drop at its own centre would land
## somewhere the player cannot reach. See Chest.LOOT_OFFSET.
func _on_treasure_opened(at: Vector2) -> void:
	_plan.get_room(_current_coord).treasure_opened = true
	# Deferred to match the enemy drop path. This one arrives from _process rather
	# than from inside a physics flush, so it is insurance rather than a fix — but it
	# is the same insurance, and a pickup is a collision shape either way.
	_spawn_loot.call_deferred(&"chest", at)


## Roll this source's drop tables and put whatever comes out on the floor.
##
## Parented to the room rather than to the run container, so a drop keeps the
## position it was dropped at: the old behaviour outlived the room it belonged to
## but kept a world coordinate belonging to a freed grid, which put it inside the
## wall of whatever room came next. The cost is that loot left behind when you
## retreat mid-fight is gone — recording it on RoomData the way enemies_remaining
## already is would fix that, and is a job of its own.
func _spawn_loot(source: StringName, at: Vector2) -> void:
	if drop_config == null or _current_room == null:
		return

	var tables := drop_config.tables_for(source, _floor_number)
	if tables.is_empty():
		return

	var local: Vector2 = _current_room.to_local(at)
	var items := LootRoller.roll(tables, _loot_rng)
	var announced: Array[StringName] = []
	for item in items:
		var pickup: ItemPickup = ITEM_PICKUP_SCENE.instantiate()
		# Before it enters the tree: _ready is what draws it, so an item assigned
		# afterwards would be an invisible pickup.
		pickup.item = item
		# A single drop lands exactly where the body did; a handful is scattered,
		# or three coins stack into what looks like one coin and the player walks
		# away from two of them. Clamped to the floor so the scatter cannot push
		# one into a wall.
		var spot: Vector2 = local if items.size() == 1 else _scattered(local)
		_current_room.add_entity(pickup, spot)

		# Loot landing is audible; loot being collected is item_pickup.gd's job.
		# Once per distinct sound, or a table that drops three coins fires the
		# same sample three times in the same frame and it reads as a stutter.
		if not item.drop_sound.is_empty() and not announced.has(item.drop_sound):
			announced.append(item.drop_sound)
			AudioManager.play_sfx(item.drop_sound)


## A small random nudge off a drop point, kept inside the walkable floor and out
## of anything solid.
##
## A pickup inside a crate is not a softlock — the pickup's area still overlaps
## the player's body, and breaking the crate frees it either way — but it is a
## coin the player has to walk into a wall to see. Pushed out after the clamp
## rather than before, because the props all sit well inside the floor rect.
func _scattered(local: Vector2) -> Vector2:
	var offset := Vector2(
			_loot_rng.randf_range(-LOOT_SCATTER, LOOT_SCATTER),
			_loot_rng.randf_range(-LOOT_SCATTER, LOOT_SCATTER))
	var inside := Room.FLOOR.grow(-LOOT_SCATTER)
	var spot := (local + offset).clamp(inside.position, inside.end)
	return _obstacle_field.nudge_clear(spot, LOOT_CLEARANCE) \
			.clamp(inside.position, inside.end)


## Furnish a room with its solid props.
##
## Its own call rather than part of [method _populate], and the difference
## matters: a room is freed and rebuilt on every entry, but _populate returns
## early once the room has been cleared. Folding these two together — which is the
## obvious tidy-up — would silently strip the furniture out of every room the
## player has already fought through.
##
## Everything here is a function of the floor seed and the room's coord, never of
## _rng and never of where the player is standing. _rng is one stream drawn in
## room-visit order, so a prop taken from it would move when the player backtracks;
## and the player arrives through a different door each visit, so a layout that
## avoided them would rearrange itself for the same reason. A local generator
## seeded per cell is what keeps fixed_seed.cfg honest.
func _scatter_obstacles(data: RoomData) -> void:
	_obstacle_field = ObstacleField.new()
	if obstacle_set == null or not obstacle_set.allows_kind(data.kind):
		return

	# The room's own answer about its own floor: the exit room's is a shallow
	# strip built around the lift, and it returns an empty rect to say "not here".
	var floor_rect: Rect2 = _current_room.obstacle_rect()
	if not floor_rect.has_area():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = ObstaclePlacement.seed_for(
			FloorGenerator.floor_seed_for(run_seed, _floor_number), data.coord)

	# The doorways, plus the middle of the floor — that is where
	# default_spawn_position puts a player who arrives without a door, which is
	# every player at the start of every floor.
	var keep_clear := _current_room.open_door_landings()
	keep_clear.append(floor_rect.get_center())

	var plans := ObstaclePlacement.points(floor_rect, obstacle_set, keep_clear, rng)
	for i in plans.size():
		# Walk the whole list and skip the broken ones rather than filtering it
		# first: the index IS the identity, so renumbering after a break would
		# bring back the wrong prop.
		if (data.obstacles_destroyed & (1 << i)) != 0:
			continue
		var plan := plans[i]
		var obstacle: Obstacle = OBSTACLE_SCENE.instantiate()
		# Before it enters the tree, the same window make_boss uses: Health copies
		# max_hp into hp in its own _ready.
		obstacle.configure(plan.def, i)
		obstacle.destroyed.connect(_on_obstacle_destroyed.bind(data))
		_current_room.add_obstacle(obstacle, plan.position)
		_obstacle_field.add(plan.position, plan.def.body_radius)


## Remember a broken prop so it stays broken, and roll its drop table.
##
## The bookkeeping is written straight away rather than deferred: this is
## reached from a bullet's body_entered, so it runs mid physics-flush, but it
## touches no nodes. The loot spawn is deferred for the reason _on_enemy_died's
## is — a pickup's collision shape is a node the physics server would reject
## mid-flush.
##
## The field is not rebuilt. It is read when a room is stocked, which has already
## happened by the time anything can be shot, and leaving a broken prop in it
## costs nothing until the room is next entered and it is rebuilt from scratch.
func _on_obstacle_destroyed(index: int, loot_source: StringName, at: Vector2, data: RoomData) -> void:
	data.obstacles_destroyed |= 1 << index
	_spawn_loot.call_deferred(loot_source, at)


## Fold the active tuning profile into the obstacle set.
##
## Here rather than on ObstacleSet itself, which is where FloorConfig puts its
## equivalent. Naming GameConfig inside a Resource makes that autoload a
## compile-time dependency of every script that names the Resource's type, and
## `godot --headless --script` starts no autoloads — which is why check_floors.gd
## cannot currently load. Doing it from a Node keeps the systems/ side loadable
## from a terminal, which is the whole point of putting the rules there.
##
## Duplicated first, so a profile cannot write itself into the .tres on disk: the
## set is a shared resource, and editing it in place would follow the developer
## into a commit — the accident tuning profiles exist to prevent.
##
## No fallback when the slot is empty. A Game with no obstacle set is a game with
## bare rooms, which is a perfectly good game.
func _apply_obstacle_overrides() -> void:
	if obstacle_set == null:
		return
	obstacle_set = obstacle_set.duplicate()
	obstacle_set.count_min = GameConfig.get_value(
			"obstacles", "count_min", obstacle_set.count_min)
	obstacle_set.count_max = GameConfig.get_value(
			"obstacles", "count_max", obstacle_set.count_max)
	obstacle_set.room_kinds = GameConfig.get_value(
			"obstacles", "room_kinds", obstacle_set.room_kinds)
