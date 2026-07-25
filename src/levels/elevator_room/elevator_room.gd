class_name ElevatorRoom
extends Room

## The floor's exit, seen from the side.
##
## A belt-scroll lobby: the camera looks along the floor instead of down at it, so
## the player's Y is depth rather than a second direction to run in. There is no
## way out to the left or right — the only two choices are the elevator at the far
## end and the doorway back toward the camera.
##
## It is a Room because Game treats it as one: instanced into RoomContainer at
## coord * STRIDE, clamped to the same INTERIOR rect, reporting the side the
## player left through. Everything below is the difference between this cell and
## an ordinary one, and nothing in game.gd has to know which it got.

## The player boarded and the floor is over.
##
## refill_o2 is this elevator's own setting, passed rather than acted on: whether
## a floor change costs you your remaining air is O2 policy, and O2 policy lives
## with the timer. A door decides only that it is that kind of door.
signal boarded(refill_o2: bool)

## Room-local rect anything on foot may stand in. Narrower in depth than
## Room.FLOOR because the far wall is 104 deep instead of 49 — it has to hold an
## elevator. The x extent is unchanged, so the side walls line up with every
## other room's.
const LOBBY_FLOOR := Rect2(49, 104, 343, 132)

@export_group("Doors")
## How long a full open or shut takes. A partial move is scaled down from this.
@export var door_slide_time: float = 0.45
## Curve of the slide. SINE/IN_OUT reads as motorised; QUAD/OUT reads as sprung.
@export var door_slide_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var door_slide_ease: Tween.EaseType = Tween.EASE_IN_OUT
## How far each leaf travels. Half the opening, so fully open is fully clear.
@export var door_travel: float = 48.0
## How far open the leaves must be before they stop being solid. Below 1.0 so the
## way is walkable a moment before it looks completely clear, which feels
## responsive; too low and you can squeeze through a crack.
@export_range(0.0, 1.0) var door_clear_at: float = 0.8

@export_group("Boarding")
## Seconds to walk the player from the threshold into the car.
@export var board_walk_time: float = 0.35
## The beat between the doors sealing and the floor advancing. This is the pause
## that makes boarding read as a decision rather than a trip hazard.
@export var board_hold_time: float = 0.8
## Refill the tank on boarding. The single switch for "is the elevator a
## checkpoint, or just a door" — Game applies it, this only decides it.
@export var refill_o2_on_board: bool = true
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
## Hide the player's gun while they are in the lobby. It is aimed with a mouse in
## a top-down frame and reads as broken side-on, and there is nothing in here to
## shoot. Off would mean shipping the odd-looking version, so it defaults on.
@export var hide_player_gun: bool = true

@onready var _leaf_left: Node2D = $Elevator/LeftLeaf
@onready var _leaf_right: Node2D = $Elevator/RightLeaf
@onready var _leaf_left_body: StaticBody2D = $Elevator/LeftLeaf/body
@onready var _leaf_right_body: StaticBody2D = $Elevator/RightLeaf/body
@onready var _car_marker: Marker2D = $Elevator/CarMarker
@onready var _cutscene_layer: CanvasLayer = $Cutscene
@onready var _near_door: LevelDoor = $Doors/door_near
@onready var _near_plug: StaticBody2D = $Walls/Plugs/plug_near

## 0 shut, 1 fully open. The single source of truth for where the leaves are —
## see _set_doors_open for why there is only ever one number.
var _open_amount: float = 0.0
var _leaves_solid: bool = true
var _door_tween: Tween

## Which grid side walking toward the camera leads back to. The near doorway is a
## physical thing that always faces the viewer; where it goes is the floor plan's
## business, so it is read from the door mask in configure().
var _return_side: int = GridDirection.Side.NORTH

var _boarding: bool = false
## Whoever is standing in the lobby, handed over by LobbyZone. Physics tells us
## who the player is rather than us reaching up the tree for them.
var _player: Player
var _gun_was_visible: bool = true

@onready var _leaf_home_left: Vector2 = _leaf_left.position
@onready var _leaf_home_right: Vector2 = _leaf_right.position


func _ready() -> void:
	# Deliberately NOT super._ready(): Room's version connects all four doors, and
	# this room has one. The rest of Room's behaviour is inherited untouched.
	_near_door.player_entered.connect(_on_near_door_entered)
	_apply_door_open(0.0)


func _exit_tree() -> void:
	# The room can be freed mid-transition — Game frees it the moment boarding
	# reports in. A player who left without their gun would stay that way for the
	# rest of the run, so the restore cannot live only on the way out.
	_restore_player()


## Which door this lobby was given. The mask has one bit for a dead-end exit room,
## and that bit is the way back.
##
## Deliberately not super.configure(): Room's version walks all four sides through
## door_for(), and this scene has one doorway. The mask is still remembered — a
## temporary seal has to be liftable — it just describes where the single door
## leads rather than which of four exist.
func configure(doors: int) -> void:
	_open_doors = doors
	set_locked(false)

	for side in GridDirection.SIDES:
		if (doors & GridDirection.bit(side)) != 0:
			_return_side = side
			return
	push_warning("ElevatorRoom: configured with no doors, defaulting the way back to north")


## Where to put a player who just walked in. There is one doorway whatever side
## the plan attached it to, so the argument is deliberately ignored — an arrival
## from the east still lands at the near door, because that is the only door.
func spawn_position(_arrive_side: int) -> Vector2:
	return _near_door.spawn_position()


## The one landing this room has. Room's version walks all four sides and would
## fault on the three doors this scene does not have.
func open_door_landings() -> Array[Vector2]:
	return [to_local(_near_door.spawn_position())]


## Seal the way out, or restore it. Same contract as Room's, one door's worth.
func set_locked(locked: bool) -> void:
	var is_open: bool = not locked
	# Deferred for the reason room.gd spells out: the physics server rejects these
	# changes mid-flush, and boarding starts from inside a body_entered.
	_near_door.set_deferred("monitoring", is_open)
	# visible is not physics state, so it can be set straight away.
	_near_plug.visible = locked
	# Hiding a body does not stop it colliding, so clear the layer too.
	_near_plug.set_deferred("collision_layer", CollisionLayers.WORLD if locked else 0)


## The near doorway reports whichever grid side the floor plan gave this room,
## not the south it physically faces. Walking toward the camera is always the way
## back; which neighbour that is, is data.
func _on_near_door_entered(_side: int) -> void:
	door_entered.emit(_return_side)


func _on_approach_entered(body: Node2D) -> void:
	# An `as` cast rather than `if body is Player`, because GDScript does not
	# narrow a Node2D parameter from an `is` test and body.is_warping below would
	# not compile.
	#
	# is_warping is the important half. Game._slide_to tweens the player in a
	# straight line from the previous room's doorway to this one's, and that line
	# enters the lobby through its TOP edge — straight through the car and this
	# whole zone. Without the guard, every arrival flaps the doors and boards a
	# player who never chose to.
	var player := body as Player
	if player == null or player.is_warping or _boarding:
		return
	_set_doors_open(true)


func _on_approach_exited(body: Node2D) -> void:
	# No warping guard needed: shutting doors that are already shut hits the
	# early-return in _set_doors_open. The boarding guard is needed, because the
	# tween that walks the player into the car must not slam them behind it.
	if body is Player and not _boarding:
		_set_doors_open(false)


func _on_car_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null or player.is_warping or _boarding:
		return
	_board(player)


func _on_lobby_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	_player = player
	if hide_player_gun:
		_gun_was_visible = player.gun.visible
		player.gun.visible = false


func _on_lobby_exited(body: Node2D) -> void:
	if body is Player:
		_restore_player()


func _restore_player() -> void:
	if _player == null:
		return
	if hide_player_gun and is_instance_valid(_player):
		_player.gun.visible = _gun_was_visible
	_player = null


## Open or shut the car doors, from wherever they currently are.
##
## Tweening a scalar and deriving the leaves from it — rather than tweening two
## positions — is what makes this safe to interrupt. A player oscillating on the
## threshold reverses mid-slide every time, and the leaves neither jump nor end up
## disagreeing with each other, because there is only ever one number.
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
	var layer: int = CollisionLayers.WORLD if solid else 0
	_leaf_left_body.set_deferred("collision_layer", layer)
	_leaf_right_body.set_deferred("collision_layer", layer)


## Doors shut, a beat, then the floor is over.
##
## The player is frozen for the whole sequence with the same is_warping flag the
## room transition uses. It is the documented hook for exactly this, and it is
## what stops a dodge or a held direction fighting the tween that walks them in.
func _board(player: Player) -> void:
	_boarding = true
	set_locked(true)
	player.is_warping = true
	player.velocity = Vector2.ZERO

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

	player.is_warping = false
	_restore_player()

	# Last statement on purpose: the handler frees this room, and anything after
	# the emit would be running on a node already on its way out.
	boarded.emit(refill_o2_on_board)


## The seam for a cutscene that does not exist yet. With the slot empty this
## returns on its first line, so nothing about boarding depends on it — and
## awaiting a function that never yields costs a frame of nothing.
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
