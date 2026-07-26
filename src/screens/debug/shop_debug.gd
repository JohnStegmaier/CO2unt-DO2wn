extends Node2D

## Standalone harness for the shop — select this scene and press F6.
##
## It stands in for Game and calls precisely the things Game calls on a room:
## configure(), configure_shop(), spawn_position(), interior_rect() and
## door_entered. If the shop ever stops satisfying Room's contract, this scene
## breaks first and in isolation, instead of a floor deep into a run.
##
## No HUD and no clock: pausing the countdown and swapping the music are Game's
## job. Leaving just says so.
##
## It also carries the two stubs this branch is not allowed to ship. Coins belong
## on the Player and the item catalogue belongs to another branch; until both
## land, StubPurse and the offer built below stand in for them. Everything the
## shop touches is duck-typed, so when the real ones arrive this file loses two
## classes and nothing else moves.

const STUB_ICON := "res://assets/sprites/items/vinaigrette.png"

## Which grid side the harness pretends the shop was entered from.
@export_enum("north", "east", "south", "west") var arrive_side: int = 0
## What the stub player starts with. 60 is what a run will open with.
@export var starting_coins: int = 60
## What the stub vinaigrette costs.
@export var stub_price: int = 10
## How many of it to put on the shelf. More than one is the quickest way to see
## the selection frame step between cubbies and skip the holes.
@export var stub_count: int = 3

@onready var _room: ShopRoom = $ShopRoom
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D

var _purse: StubPurse


## Stands in for the drops branch's ItemDef.
##
## Only the two properties [ShopOffer] duck-types for, so it is shaped like an
## ItemDef without being one. Declaring a local `class_name ItemDef` would be a
## duplicate-class error the moment the real one merges, which is exactly why the
## stub is an inner class of the harness and not a file in src/systems.
class StubItem:
	extends Resource

	var display_name: String = ""
	var icon: Texture2D
	## The real ItemDef carries an array of ItemEffect. Left empty here: what an
	## item DOES is the catalogue's business, and the harness only proves the
	## shop reports the sale.
	var effects: Array = []


## Stands in for Player.coins / spend_coins, which the drops branch ships.
##
## Deliberately the smallest thing that satisfies what the shop asks for, and
## deliberately NOT added to player.gd — that file has three branches queued on
## it, and inventing a second wallet is the exact collision the parallel brief
## rules out.
class StubPurse:
	extends RefCounted

	var coins: int = 0

	func _init(starting: int) -> void:
		coins = starting

	func spend_coins(amount: int) -> bool:
		if amount > coins:
			return false
		coins -= amount
		return true


func _ready() -> void:
	# A stand-in for the cell the floor plan would hand over: a shop whose one
	# doorway is on arrive_side.
	var data := RoomData.new(Vector2i.ZERO, RoomData.Kind.SHOP)
	data.doors = GridDirection.bit(arrive_side)
	_room.configure(data)

	_purse = StubPurse.new(starting_coins)
	var provider := StaticShopStockProvider.new()
	provider.offers = _stub_offers()
	# Through the registry rather than straight from the provider, so the harness
	# exercises the same path Game does.
	var registry := ShopRegistry.new()
	var capacity: int = _room.grid.capacity() if _room.grid != null else 0
	_room.configure_shop(registry.stock_for(provider, 0, Vector2i.ZERO, capacity), _purse)

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

	print("ShopDebug: %d coins, %d on the shelf. [E]/pad-X talk, arrows browse, [Backspace]/pad-Y back."
			% [starting_coins, stub_count])


## The stub catalogue entry. A bare Resource with the two properties ShopOffer
## duck-types for, so it is shaped like an ItemDef without being one — declaring
## a local ItemDef would collide with the drops branch's on merge.
func _stub_offers() -> Array[ShopOffer]:
	var item := StubItem.new()
	item.display_name = "Vinaigrette"
	if ResourceLoader.exists(STUB_ICON):
		item.icon = load(STUB_ICON)

	var offers: Array[ShopOffer] = []
	for i in maxi(stub_count, 0):
		var offer := ShopOffer.new()
		offer.item = item
		offer.price = stub_price
		offers.append(offer)
	return offers


func _on_offer_purchased(offer: ShopOffer) -> void:
	# Game applies the item's effects to the player here. There are none to apply
	# until the catalogue lands, so the harness just reports the sale.
	print("ShopDebug: sold %s for %d — %d coins left" % [
		offer.display_name(), offer.price, _purse.coins])


func _on_door_entered(side: int) -> void:
	print("ShopDebug: would leave through %s" % GridDirection.side_name(side))
	# Reloaded rather than left standing: Game swaps the room at this point, and
	# a harness that let the player walk back and forth over the exit line would
	# report it once and then look broken.
	get_tree().reload_current_scene()
