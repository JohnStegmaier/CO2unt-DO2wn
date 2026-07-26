extends Node2D

## Standalone harness for the shop — select this scene and press F6.
##
## It stands in for Game and calls precisely the things Game calls on a room:
## configure(), configure_shop(), spawn_position(), interior_rect(),
## door_entered and offer_purchased. If the shop ever stops satisfying Room's
## contract, this scene breaks first and in isolation, instead of a floor deep
## into a run.
##
## No HUD and no clock: pausing the countdown, swapping the music and drawing the
## coin counter are Game's job. Leaving just says so.
##
## Everything here is the real thing now. It used to carry a stub purse and a
## stub item because coins and the catalogue lived on another branch; both have
## landed, so this uses the run's actual DropConfig, the actual ItemDefs and the
## actual Player.

## Where a shop's stock comes from, exactly as game.tscn wires it. Pointed at the
## same DropConfig the run uses, so what you see on the shelf here is what you
## would see in a real shop on the given floor.
@export var drop_config: DropConfig
## Which grid side the harness pretends the shop was entered from.
@export_enum("north", "east", "south", "west") var arrive_side: int = 0
## Which descent index to stock as. Shop rules can be keyed per floor, so this is
## how you check floor 3's shelf without playing to floor 3.
@export var floor_number: int = 0
## What to give the player to spend. 60 is what a run opens with.
@export var starting_coins: int = 60

@onready var _room: ShopRoom = $ShopRoom
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D


func _ready() -> void:
	# A stand-in for the cell the floor plan would hand over: a shop whose one
	# doorway is on arrive_side.
	var data := RoomData.new(Vector2i.ZERO, RoomData.Kind.SHOP)
	data.doors = GridDirection.bit(arrive_side)
	_room.configure(data)

	_player.add_coins(starting_coins)

	var provider := DropTableShopStockProvider.new()
	provider.drop_config = drop_config
	# Through the registry rather than straight from the provider, so the harness
	# exercises the same path Game does.
	var registry := ShopRegistry.new()
	var capacity: int = _room.grid.capacity() if _room.grid != null else 0
	var stock: ShopStock = registry.stock_for(provider, floor_number, Vector2i.ZERO, capacity)
	_room.configure_shop(stock, _player)

	_room.door_entered.connect(_on_door_entered)
	_room.offer_purchased.connect(_on_offer_purchased)

	# warp_to rather than an authored position, so the harness lands the player
	# exactly where Game's cut would put them.
	_player.warp_to(_room.spawn_position(arrive_side))
	_camera.set_bounds(_room.interior_rect())
	# Game suppresses the camera's own aim-lead in a shop so it is not wobbling
	# underneath the parallax. Mirrored here or the harness looks wrong in a way
	# the real game does not.
	_camera.set_lead_enabled(false)

	if stock.is_empty():
		push_warning("ShopDebug: nothing in stock — is there a &\"shop\" rule in the DropConfig?")
	print("ShopDebug: %d coins, %d on the shelf. [E]/pad-X talk, arrows browse, [Backspace]/pad-Y back."
			% [_player.coins, stock.count()])


func _on_offer_purchased(offer: ShopOffer) -> void:
	# The same call Game makes. Doing it here rather than only printing means the
	# harness proves the effects actually land on a real Player.
	offer.item.grant_to(_player)
	print("ShopDebug: sold %s for %d — %d coins left, speed lvl %d" % [
		offer.display_name(), offer.price, _player.coins, _player.SPEED_LVL])


func _on_door_entered(side: int) -> void:
	print("ShopDebug: would leave through %s" % GridDirection.side_name(side))
	# Reloaded rather than left standing: Game swaps the room at this point, and
	# a harness that let the player walk back and forth over the exit line would
	# report it once and then look broken.
	get_tree().reload_current_scene()
