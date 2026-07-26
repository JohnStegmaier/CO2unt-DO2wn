class_name ShopRegistry
extends RefCounted

## Every shop's shelves, for the length of a run.
##
## This is what makes a purchase stick. Rooms are instanced when the player walks
## in and freed when they walk out, so stock held on the room node would be
## rebuilt from the provider on every visit and the same item could be bought
## over and over. The registry asks the provider ONCE per shop and hands the same
## [ShopStock] back every time after that.
##
## Keyed by floor as well as coord because coordinates repeat: the shop on floor
## 2 can easily land on the same cell as the one on floor 1, and it is a
## different shop with its own shelves.

var _stocks: Dictionary = {}


## The shelves for one shop, created on first visit.
##
## The provider is passed in rather than held, so the registry stays a cache and
## never becomes a second place that decides what a shop sells.
func stock_for(provider: ShopStockProvider, floor_number: int, coord: Vector2i,
		capacity: int) -> ShopStock:
	var key: String = _key(floor_number, coord)
	if _stocks.has(key):
		return _stocks[key]

	var offers: Array[ShopOffer] = []
	if provider != null:
		offers = provider.stock_for(floor_number, coord, capacity)
	var stock := ShopStock.new(capacity, offers)
	_stocks[key] = stock
	return stock


## Has this shop been opened yet? Only used by tests and the debug harness — the
## room does not care, it just asks for its shelves.
func knows(floor_number: int, coord: Vector2i) -> bool:
	return _stocks.has(_key(floor_number, coord))


## Drop a floor's shops once the lift has left it. Pure hygiene: there is no way
## back to a floor, so nothing would ever read these again.
func forget_floor(floor_number: int) -> void:
	var prefix: String = "%d:" % floor_number
	for key in _stocks.keys():
		if String(key).begins_with(prefix):
			_stocks.erase(key)


## Vector2i is a legal dictionary key on its own, but the floor has to be in
## there too, and a formatted string beats a nested dictionary for something
## printed straight into a debug log.
func _key(floor_number: int, coord: Vector2i) -> String:
	return "%d:%d,%d" % [floor_number, coord.x, coord.y]
