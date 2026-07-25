class_name ElevatorRoom
extends Room

## The floor's exit, seen from the side.
##
## A belt-scroll lobby. The camera looks along the floor rather than down at it,
## so there is no wall in front of the player and nothing between them and the
## viewport — walking to the bottom edge is walking back out the way they came.
##
## Depth is carried by SCALE, not by screen position. The walkable band is a
## shallow strip and crossing it barely moves the player up the frame; what sells
## the distance is that they shrink to two thirds of their size on the way to the
## lift and grow back on the way out. Vertical movement is slowed to match, since
## a strip this shallow would otherwise be crossed in a third of a second.
##
## It is a Room because Game treats it as one: instanced into RoomContainer at
## coord * STRIDE, reporting the side the player left through, and reporting
## boarding through Room's own elevator_entered — so the ride, the floor
## regeneration and the O2 refill all work without knowing this room exists.

## The frame, 442 x 240. Shorter than Room.INTERIOR on purpose: 240 is exactly
## what the camera can show at zoom 1.5, so the view is pinned and the authored
## picture is the whole picture. Only possible because Game cuts to this room
## behind a fade instead of sliding — a slide keeps the departing room's rect size
## for the whole tween and would pop against a different one.
const FRAME := Rect2(0, 0, 442, 240)

## Room-local rect anything on foot may stand in. A shallow strip at the bottom of
## a tall wall: that ratio is what makes the room read side-on rather than tilted.
const LOBBY_FLOOR := Rect2(49, 190, 343, 50)

## Nearest and furthest the player's origin ever gets, in room-local y. The
## walkable strip bottoms out against the near lip at 233, and the far end is
## inside the car. Everything about depth is measured between these two numbers.
const DEPTH_NEAR_Y := 233.0
const DEPTH_FAR_Y := 182.0

## Walk to at least here, and the doors open. Comfortably above the landing, so
## arriving does not open them.
const DOOR_OPEN_Y := 212.0
## And back to here before they shut again. The gap between the two is hysteresis:
## without it, standing exactly on the threshold flutters the doors every frame.
const DOOR_SHUT_Y := 219.0
## Step this far into the alcove with the doors open and you have boarded.
const BOARD_Y := 188.0
## The mouth of the car, in room-local x. Boarding tests against this as well as
## depth: "far enough up the screen" alone would also be true of anywhere the
## walls happen not to reach, and a rule that only holds because of the geometry
## around it is one bad edit away from being wrong.
const CAR_X := Vector2(189.0, 253.0)
## Push down to here and you leave. Almost against the lip, so leaving is a
## deliberate walk into the bottom of the frame rather than a drift.
const EXIT_Y := 231.0
## Where a player arriving from the previous room is put. Between the two
## thresholds, so neither fires on arrival.
const LANDING := Vector2(221, 220)

@export_group("Doors")
## How long a full open or shut takes. A partial move is scaled down from this.
@export var door_slide_time: float = 0.45
## Curve of the slide. SINE/IN_OUT reads as motorised; QUAD/OUT reads as sprung.
@export var door_slide_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var door_slide_ease: Tween.EaseType = Tween.EASE_IN_OUT
## How far each leaf travels. Half the opening, so fully open is fully clear.
@export var door_travel: float = 32.0
## How far open the leaves must be before they stop being solid. Below 1.0 so the
## way is walkable a moment before it looks completely clear, which feels
## responsive; too low and you can squeeze through a crack.
@export_range(0.0, 1.0) var door_clear_at: float = 0.8

@export_group("Boarding")
## Seconds to walk the player from the threshold into the car.
@export var board_walk_time: float = 0.35
## The beat between the doors sealing and the floor advancing.
##
## Kept short: Game's ElevatorRide plays straight after this and has its own doors
## and fades, so a long hold here is dead air in front of the ride, not drama.
@export var board_hold_time: float = 0.4
## Named SFX from AudioManager. Empty plays nothing, so this cannot break a build
## that has not recorded one yet.
@export var board_sfx: String = ""

@export_group("Cutscene")
## Played between the doors sealing and the floor advancing. Empty by default and
## skipped entirely when empty, so this is a seam and not a dependency: whoever
## builds the real cutscene drops the scene in this slot and no line here moves.
@export var cutscene_scene: PackedScene
## How long to wait for a cutscene that does not report finishing. A cutscene that
## forgets to say it is done must not be able to strand a run.
@export var cutscene_fallback_time: float = 1.5

@export_group("Perspective")
## Hide the player's gun in here. It is aimed with a mouse in a top-down frame and
## reads as broken side-on, and there is nothing in this room to shoot.
@export var hide_player_gun: bool = true
## Draw the player bigger near the camera and smaller toward the lift. In a side
## view this is what distance IS — the strip is too shallow for position to say it.
@export var depth_scale_enabled: bool = true
## Size at the near edge, closest to the viewport.
##
## Large because this is a side view and the player is a person standing in a
## corridor, not a token seen from above: at 1.0 the 16x32 sprite is a fifth of
## the height of a doorway she is supposed to walk through.
@export_range(0.5, 5.0) var depth_scale_near: float = 3.30
## Size inside the car, furthest away. The ratio between the two is the illusion;
## the absolute values are how big she reads against the architecture.
@export_range(0.5, 5.0) var depth_scale_far: float = 1.45
## How much slower depth is than sideways movement. Sideways is untouched. At 1.0
## the strip is crossed in a third of a second and walking into the lift becomes a
## twitch input; this is what buys the slow, deliberate trudge into the distance.
@export_range(0.1, 1.0) var depth_move_scale: float = 0.28

@onready var _leaf_left: Node2D = $Alcove/LeftLeaf
@onready var _leaf_right: Node2D = $Alcove/RightLeaf
@onready var _leaf_left_body: StaticBody2D = $Alcove/LeftLeaf/body
@onready var _leaf_right_body: StaticBody2D = $Alcove/RightLeaf/body
@onready var _car_marker: Marker2D = $Alcove/CarMarker
@onready var _cutscene_layer: CanvasLayer = $Cutscene

## 0 shut, 1 fully open. The single source of truth for where the leaves are —
## see _set_doors_open for why there is only ever one number.
var _open_amount: float = 0.0
var _leaves_solid: bool = true
var _door_tween: Tween
var _doors_open: bool = false

## Which grid side walking toward the camera leads back to. The bottom edge is a
## physical thing that always faces the viewer; where it goes is the floor plan's
## business, so it is read from the door mask in configure().
var _return_side: int = GridDirection.Side.NORTH
## Cleared while a fight seals the room, and latched once the player leaves so a
## single walk into the bottom edge cannot fire the transition twice.
var _exit_armed: bool = true

var _boarding: bool = false
## Set once the player has been seen standing out on the floor. Boarding waits for
## it, so riding the lift is always something they walked into rather than
## something that was true the instant they appeared: Game drops a player who
## arrives without a door at the room's centre, which in a room this shape is
## inside the car. Nothing in a normal run does that — the exit is always entered
## through a doorway — but advancing a floor is far too destructive to leave
## resting on that.
var _stood_on_floor: bool = false
## Whoever is standing in the lobby, handed over by LobbyZone. Physics tells us
## who the player is rather than us reaching up the tree for them.
var _player: Player
var _gun_was_visible: bool = true
## The player's own transform and movement, captured on the way in and put back on
## the way out. Held rather than assumed, because the room does not own the player
## and must leave them exactly as it found them.
var _sprite_scale: Vector2 = Vector2.ONE
var _sprite_offset: Vector2 = Vector2.ZERO
## Half the sprite's height, negated: the offset that puts its bottom edge on the
## body origin. The player's own offset does not do that — it leaves the sprite
## hanging ten pixels below its feet, which is invisible at top-down scale and
## becomes a third of a body once she is drawn three times life size. Measured
## from the art rather than assumed, so new frames of a different size still land
## on the floor.
var _foot_offset: float = -16.0

@onready var _leaf_home_left: Vector2 = _leaf_left.position
@onready var _leaf_home_right: Vector2 = _leaf_right.position


func _ready() -> void:
	# Deliberately NOT super._ready(): Room's version wires four doorways and a
	# top-down car, none of which this scene has. The rest is inherited untouched.
	_apply_door_open(0.0)


func _exit_tree() -> void:
	# The room is freed the moment boarding reports in, and a player who left with
	# squashed movement or no gun would stay that way for the rest of the run.
	_restore_player()


## Which door this lobby was given. The mask has one bit for a dead-end exit room,
## and that bit is the way back.
##
## Deliberately not super.configure(): Room's version walks all four sides through
## door_for(), stands a top-down car against a bare wall and washes the room in its
## kind's tint — none of which applies here.
func configure(data: RoomData) -> void:
	_open_doors = data.doors
	set_locked(false)

	# The inherited top-down car is put away rather than removed. It is the base
	# scene's way off a floor and this room replaces it, but Room reaches for the
	# node unconditionally, so it has to exist.
	_elevator.set_active(false)

	for side in GridDirection.SIDES:
		if data.has_door(side):
			_return_side = side
			return
	push_warning("ElevatorRoom: configured with no doors, defaulting the way back to north")


## The camera clamp. Overridden because this room is shorter than a standard cell:
## at 240 the view cannot be smaller than the room, so PlayerCamera._clamp_axis
## centres vertically and the frame stops drifting with the player.
func interior_rect() -> Rect2:
	return Rect2(global_position + FRAME.position, FRAME.size)


## Where to put a player who just walked in. There is one way in and out whatever
## side the plan attached it to, so the argument is deliberately ignored.
func spawn_position(_arrive_side: int) -> Vector2:
	return global_position + LANDING


## And the same spot for anyone who did not use the door. Room's version returns
## the middle of its FLOOR rect, which for this room is a strip at the bottom of
## the frame — the middle of the FRAME is inside the back wall, in the car mouth.
func default_spawn_position() -> Vector2:
	return global_position + LANDING


## The one landing this room has. Room's version walks all four sides and would
## fault on the doorways this scene does not have.
func open_door_landings() -> Array[Vector2]:
	return [LANDING]


## Seal the way out, or restore it. Same contract as Room's, with a strip of floor
## standing in for a doorway.
func set_locked(locked: bool) -> void:
	_exit_armed = not locked


## Doors, boarding and the way out are all decided from where the player is
## standing rather than from Area2D crossings.
##
## Position tests, because the player does not walk into this room — they are
## warped in behind a fade. A body that appears already inside a zone never emits
## body_entered, so a landing that happened to overlap the alcove trigger would
## leave the doors shut until the player walked out and back in again. Reading the
## position every frame cannot be fooled that way, and it is the same read the
## depth scaling needs anyway.
func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var local: Vector2 = to_local(_player.global_position)
	var depth: float = local.y
	_update_depth_scale(depth)

	if _boarding or _player.is_warping or _player._is_dead:
		return

	# Hysteresis: opening and shutting at the same line would flutter the leaves
	# every frame for a player standing exactly on it.
	if depth <= DOOR_OPEN_Y and not _doors_open:
		_doors_open = true
		_set_doors_open(true)
	elif depth >= DOOR_SHUT_Y and _doors_open:
		_doors_open = false
		_set_doors_open(false)

	if depth > BOARD_Y:
		_stood_on_floor = true

	var in_car: bool = depth <= BOARD_Y and local.x >= CAR_X.x and local.x <= CAR_X.y
	if _doors_open and in_car and _stood_on_floor:
		_board(_player)
	elif _exit_armed and depth >= EXIT_Y:
		# Latched, because the player is still standing in the strip while Game
		# tears the floor down around them.
		_exit_armed = false
		door_entered.emit(_return_side)


## Size the player by how far down the room they are standing.
func _update_depth_scale(depth: float) -> void:
	if not depth_scale_enabled:
		return
	# Yield to the death squash. player.gd's die() tweens this very property to a
	# flattened pose and sets _is_dead before it starts, so without this the corpse
	# would be fighting us for the sprite every frame.
	if _player._is_dead:
		return

	var t: float = clampf(inverse_lerp(DEPTH_FAR_Y, DEPTH_NEAR_Y, depth), 0.0, 1.0)
	var size: float = lerpf(depth_scale_far, depth_scale_near, t)

	_player.sprite.scale = _sprite_scale * size
	# Anchored by the feet rather than by the player's own offset, and scaled with
	# her, so growing happens upward from the floor instead of in both directions.
	# Without this she sinks through the floor as she approaches, and at these
	# sizes her legs would be cut off by the bottom of the frame.
	_player.sprite.position = Vector2(_sprite_offset.x, _foot_offset * size)


func _on_lobby_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	_player = player
	_sprite_scale = player.sprite.scale
	_sprite_offset = player.sprite.position
	_foot_offset = _measure_foot_offset(player)
	# Sideways is left alone. Only depth is slowed, because only depth is lying
	# about how far it goes.
	player.move_scale = Vector2(1.0, depth_move_scale)
	if hide_player_gun:
		_gun_was_visible = player.gun.visible
		player.gun.visible = false


## Half the height of a frame of the player's art, negated. Read off the sprite so
## that art of a different size still stands on the floor rather than in it.
func _measure_foot_offset(player: Player) -> float:
	var frames: SpriteFrames = player.sprite.sprite_frames
	if frames == null:
		return _foot_offset
	var anim: StringName = player.sprite.animation
	if not frames.has_animation(anim) or frames.get_frame_count(anim) == 0:
		return _foot_offset
	var texture: Texture2D = frames.get_frame_texture(anim, 0)
	if texture == null:
		return _foot_offset
	return -texture.get_height() * 0.5


func _on_lobby_exited(body: Node2D) -> void:
	if body is Player:
		_restore_player()


func _restore_player() -> void:
	if _player == null:
		return
	if is_instance_valid(_player):
		_player.move_scale = Vector2.ONE
		if hide_player_gun:
			_player.gun.visible = _gun_was_visible
		# Put the sprite back even if the scaling was never applied — the export can
		# be turned off mid-run, and a player left shrunk would stay that way.
		#
		# Not for a corpse, though. Dying in here frees the room on the way to the
		# game over screen, and restoring then would stand the flattened body back
		# up for the frame the death shot is captured on.
		if not _player._is_dead:
			_player.sprite.scale = _sprite_scale
			_player.sprite.position = _sprite_offset
	_player = null


## Open or shut the car doors, from wherever they currently are.
##
## Tweening a scalar and deriving the leaves from it — rather than tweening two
## positions — is what makes this safe to interrupt. A player hovering on the
## threshold reverses mid-slide, and the leaves neither jump nor end up disagreeing
## with each other, because there is only ever one number.
func _set_doors_open(open: bool) -> void:
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()

	var target: float = 1.0 if open else 0.0
	if is_equal_approx(_open_amount, target):
		return

	# Proportional to the distance still to travel, so a reversal at 5% open is a
	# flick rather than a full-length tween crawling back.
	var duration: float = door_slide_time * absf(target - _open_amount)

	_door_tween = create_tween()
	# Physics process, because this moves collision shapes and the thing standing
	# in front of them is a CharacterBody2D — the same reason game.gd's room slide
	# runs on physics rather than idle.
	_door_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_door_tween.set_trans(door_slide_trans).set_ease(door_slide_ease)
	_door_tween.tween_method(_apply_door_open, _open_amount, target, duration)


func _apply_door_open(amount: float) -> void:
	_open_amount = amount
	_leaf_left.position.x = _leaf_home_left.x - door_travel * amount
	_leaf_right.position.x = _leaf_home_right.x + door_travel * amount

	# The leaves stay solid until they are nearly clear, so you cannot squeeze
	# through a crack. Touched on the crossing rather than every step: this runs on
	# every physics tick of a slide, and set_deferred is not free.
	var solid: bool = amount < door_clear_at
	if solid == _leaves_solid:
		return
	_leaves_solid = solid
	# Deferred for the reason room.gd spells out — the physics server rejects layer
	# changes mid-flush.
	var layer: int = CollisionLayers.WORLD if solid else 0
	_leaf_left_body.set_deferred("collision_layer", layer)
	_leaf_right_body.set_deferred("collision_layer", layer)


## Doors shut, a beat, then the floor is over.
##
## The player is frozen for the whole sequence with the same is_warping flag the
## room transition uses. It is the documented hook for exactly this, and it is what
## stops a held direction fighting the tween that walks them in.
func _board(player: Player) -> void:
	_boarding = true
	set_locked(true)
	player.is_warping = true
	player.velocity = Vector2.ZERO

	# The leaves spend the rest of the room's life in front of the player, so the
	# doors are seen to close ON them. They sit behind for everything before this:
	# someone standing in the lobby is in front of the lift, not inside it.
	_leaf_left.z_index = 1
	_leaf_right.z_index = 1

	var walk_in := create_tween()
	walk_in.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	walk_in.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	walk_in.tween_property(player, "global_position", _car_marker.global_position,
			board_walk_time)
	await walk_in.finished

	_set_doors_open(false)
	if _door_tween != null and _door_tween.is_valid():
		await _door_tween.finished

	_play_board_sfx()
	await get_tree().create_timer(board_hold_time).timeout
	await _play_cutscene()

	_restore_player()

	# is_warping stays TRUE. Game's _on_elevator_entered takes the player over for
	# the ride and hands control back at the far end; releasing it here would give
	# them a frame of movement in a room that is about to be freed.
	#
	# Last statement on purpose: the handler tears this floor down, and anything
	# after the emit would be running on a node already on its way out.
	elevator_entered.emit()


## The seam for a cutscene that does not exist yet. With the slot empty this
## returns on its first line, so nothing about boarding depends on it.
func _play_cutscene() -> void:
	if cutscene_scene == null:
		return
	var cutscene := cutscene_scene.instantiate()
	# Onto a CanvasLayer, so a cutscene is authored in screen space and does not
	# inherit this room's position on the floor grid.
	_cutscene_layer.add_child(cutscene)
	# Duck-typed on one string, so this works with a Control, a Node2D, or a whole
	# cutscene system whose root happens to report finishing. The timer covers
	# anything that reports nothing at all.
	if cutscene.has_signal("finished"):
		await cutscene.finished
	else:
		await get_tree().create_timer(cutscene_fallback_time).timeout
	cutscene.queue_free()


## Guarded because audio_manager.gd indexes its dictionary directly and will hard
## error on a name it does not have.
func _play_board_sfx() -> void:
	if board_sfx.is_empty() or not AudioManager.sounds.has(board_sfx):
		return
	AudioManager.play_sfx(board_sfx)
