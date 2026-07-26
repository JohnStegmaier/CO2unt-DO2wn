extends Node2D

## Standalone harness for the board room — select this scene and press F6.
##
## Built to the same shape as treasure_debug.gd, which should be read first: it
## stands in for Game and calls precisely the things Game calls on this room —
## configure(), spawn_position(), interior_rect(), floor_rect(),
## register_solids(), authored_spawns() and door_entered. If the board room ever
## stops satisfying Room's contract, this breaks first and in isolation instead
## of six floors into a run.
##
## Why it exists at all: the board room is the last room of the game, and the
## only way to reach it in play is to clear five floors and a boss. Iterating on
## a table by the descent is how a table never gets iterated on. The
## `basement` profile is the other half of this — that one plays the real
## Basement, this one plays the room.
##
## The fight is real: real Enemy scenes, dressed from the run's own bestiary,
## steering on a real ObstacleField the room fills in itself. What it deliberately
## is NOT is a copy of Game._populate — nothing here locks a door, counts the
## dead, drops loot or ends the game. Those are Game's, and a harness that
## reimplemented them would be testing the copy.

const ENEMY_SCENE := preload("res://src/entities/enemy/enemy.tscn")

## How far in from the door mouth to stand the player. Same reasoning as
## TreasureDebug.SPAWN_NUDGE: Game holds _transitioning across the whole room
## build and so ignores the door reporting a player it placed inside it, and a
## harness that reloads on that signal would spawn, be told it is leaving, and
## reload forever.
const SPAWN_NUDGE := 26.0

## The run's bestiary, exactly as game.tscn wires it.
@export var enemy_set: EnemySet
## Who is at the table, matching game.gd's basement_suit_id.
@export var suit_id: StringName = &"guard"
## How many, matching game.gd's basement_suit_count. Raise it past the seats the
## room offers to watch the overflow fall through to the placement grid, which is
## the path Game takes if the two ever disagree.
@export var suits: int = 6
## Leave the room empty to look at it. The table, the chairs and the camera pan
## are the point as often as the fight is.
@export var spawn_enemies: bool = true

@onready var _room: BoardRoom = $BoardRoom
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D

var _rng := RandomNumberGenerator.new()
var _field := ObstacleField.new()


func _ready() -> void:
	# The cell BasementPlan hands over: a boss room whose one doorway is on the
	# south wall. Not configurable, unlike the treasure harness's arrive_side —
	# this room is DRAWN around being entered from its short end, so a version of
	# it entered from anywhere else is not a thing that can happen.
	var data := RoomData.new(Vector2i.ZERO, RoomData.Kind.BOSS)
	data.doors = GridDirection.bit(GridDirection.Side.SOUTH)
	_room.configure(data)
	_room.door_entered.connect(_on_door_entered)

	# The room's own furniture, in the order Game does it: solids before bodies,
	# so nobody spawns in the table and everybody steers around it.
	_room.register_solids(_field)

	_player.warp_to(_room.spawn_position(GridDirection.Side.SOUTH)
			+ Vector2(0, -SPAWN_NUDGE))
	_camera.set_bounds(_room.interior_rect())

	if spawn_enemies:
		_seat_the_board()

	print("BoardRoomDebug: floor %s, camera %s. Walk north."
			% [_room.floor_rect(), _room.interior_rect()])


## Six men in suits, in the seats the room named.
func _seat_the_board() -> void:
	if enemy_set == null:
		push_warning("BoardRoomDebug: no enemy_set, so the room is empty")
		return
	var def := enemy_set.by_id(suit_id)
	if def == null:
		push_warning("BoardRoomDebug: no enemy def '%s' in the set" % suit_id)
		return

	var seats := _room.authored_spawns()
	var landings := _room.open_door_landings()
	var player_local: Vector2 = _room.to_local(_player.global_position)
	# Only for anybody the room has no chair for — see the `suits` export.
	var spare := EnemyPlacement.points(_room.floor_rect(), maxi(suits - seats.size(), 0),
			player_local, landings, _rng, _field)

	for i in suits:
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		# Before it enters the tree, the window configure() requires: the collider
		# is sized from the def and Health copies max_hp in its own _ready.
		enemy.configure(def)
		enemy.set_target(_player)
		enemy.set_room(_field, _room.global_position, _room.floor_rect())
		var spot: Vector2
		if i < seats.size():
			spot = seats[i]
		elif not spare.is_empty():
			spot = spare.pop_back()
		else:
			continue
		_room.add_entity(enemy, spot)

	print("BoardRoomDebug: seated %d x '%s' in %d chairs" % [suits, suit_id, seats.size()])


func _on_door_entered(side: int) -> void:
	print("BoardRoomDebug: would leave through %s" % GridDirection.side_name(side))
	# Reloaded rather than left standing, for TreasureDebug's reason: Game swaps
	# the room at this point, and a harness that let the player walk back and
	# forth over the doorway would report it once and then look broken.
	get_tree().reload_current_scene()
