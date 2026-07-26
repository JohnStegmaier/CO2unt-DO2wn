extends Node2D

## Standalone harness for the treasure room — select this scene and press F6.
##
## It stands in for Game and calls precisely the things Game calls on this room:
## configure(), spawn_position(), interior_rect(), door_entered and
## treasure_opened. If the treasure room ever stops satisfying Room's contract,
## this scene breaks first and in isolation, instead of a floor deep into a run.
##
## The payout is the real drop pipeline — the run's own DropConfig, rolled by
## LootRoller into real ItemPickups granted to a real Player. What it deliberately
## is NOT is a copy of Game._spawn_loot: there is no scatter and no clearing of
## props, because there are no props in here and the point of the harness is the
## table and the chest, not the tidiness of the pile.
##
## No HUD and no clock: drawing the coin counter and running the countdown are
## Game's job. Leaving them out just says so.

const ITEM_PICKUP_SCENE := preload("res://src/entities/pickup/item_pickup.tscn")

## How far into the room to stand the player, off the door mouth they arrived at.
##
## Game warps them onto the landing itself and gets away with it because it holds
## _transitioning across the whole room build, so the door reporting a player who
## was placed inside it is ignored. A harness that reloads on that same signal has
## no such latch: it would spawn the player standing in the doorway, be told
## immediately that they are leaving, and reload forever.
const SPAWN_NUDGE := 26.0

## Where the chest's contents come from, exactly as game.tscn wires it.
@export var drop_config: DropConfig
## Which grid side the harness pretends the room was entered from.
@export_enum("north", "east", "south", "west") var arrive_side: int = 0
## Which descent index to roll as. Chest rules can be keyed per floor, so this is
## how you check floor 3's chest without playing to floor 3.
@export var floor_number: int = 0
## Come up as a chest the player already emptied on an earlier visit. The other
## half of the feature, and the half a harness that only ever opens a fresh chest
## would never exercise — see RoomData.treasure_opened.
@export var already_opened: bool = false
## Pin the roll to replay a payout exactly. Left at 0 it is randomised.
@export var loot_seed: int = 0

@onready var _room: TreasureRoom = $TreasureRoom
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if loot_seed != 0:
		_rng.seed = loot_seed

	# A stand-in for the cell the floor plan would hand over: a treasure room whose
	# one doorway is on arrive_side. Specials are only ever placed at dead ends, so
	# one door is not a simplification — it is what these rooms always look like.
	var data := RoomData.new(Vector2i.ZERO, RoomData.Kind.TREASURE)
	data.doors = GridDirection.bit(arrive_side)
	data.treasure_opened = already_opened
	_room.configure(data)

	_room.door_entered.connect(_on_door_entered)
	_room.treasure_opened.connect(_on_treasure_opened)

	# warp_to rather than an authored position, so the harness lands the player
	# where Game's slide would put them — then a step further in, see SPAWN_NUDGE.
	# Subtracting the arrival side's own outward offset walks that step inward.
	_player.warp_to(_room.spawn_position(arrive_side)
			- Vector2(GridDirection.offset(arrive_side)) * SPAWN_NUDGE)
	_camera.set_bounds(_room.interior_rect())

	if drop_config != null and drop_config.tables_for(&"chest", floor_number).is_empty():
		push_warning("TreasureDebug: nothing to drop — is there a &\"chest\" rule in the DropConfig?")
	print("TreasureDebug: entered from %s, chest %s. Walk up to it and press [E]." % [
		GridDirection.side_name(arrive_side), "already open" if already_opened else "shut"])


## The same two things Game does, in the same order: remember it, then pay out.
func _on_treasure_opened(at: Vector2) -> void:
	if drop_config == null:
		return
	var tables := drop_config.tables_for(&"chest", floor_number)
	var items := LootRoller.roll(tables, _rng)
	for i in items.size():
		var pickup: ItemPickup = ITEM_PICKUP_SCENE.instantiate()
		# Before it enters the tree: _ready is what draws it, so an item assigned
		# afterwards would be an invisible pickup.
		pickup.item = items[i]
		# Laid out in a row rather than scattered — this is a harness for reading
		# what came out, and a pile is harder to read than a line.
		_room.add_entity(pickup, _room.to_local(at) + Vector2((i - (items.size() - 1) * 0.5) * 22.0, 0))
		print("TreasureDebug: dropped %s" % items[i].display_name)


func _on_door_entered(side: int) -> void:
	print("TreasureDebug: would leave through %s" % GridDirection.side_name(side))
	# Reloaded rather than left standing: Game swaps the room at this point, and a
	# harness that let the player walk back and forth over the doorway would report
	# it once and then look broken.
	get_tree().reload_current_scene()
