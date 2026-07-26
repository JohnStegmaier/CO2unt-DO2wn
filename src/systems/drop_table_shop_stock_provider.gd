class_name DropTableShopStockProvider
extends ShopStockProvider

## ADAPTER — stocks a shop from the run's drop configuration.
##
## docs/DROPS.md keys a [DropRule] on a source rather than on "enemy" precisely
## so the shop and the treasure room can route through the same table instead of
## needing a loot system each. This is the shop end of that: it reads the rule
## for [member source] and turns its rows into priced offers.
##
## A [DropTable] is rolled here exactly the way it is everywhere else in the
## loot path — [member DropTable.rolls] draws that many rows, weighted by
## [member DropEntry.weight] — which is what lets one table be "always this,
## and this, and this" (as many single-row guaranteed tables as there are
## always-on items) sitting in the same rule as a table that is "one of these
## three weapons, at random." [ShopRegistry] is what keeps a shelf from
## reshuffling on every visit: it asks a provider ONCE per shop and hands back
## the same [ShopStock] after that, so the roll below only ever happens once
## per (floor, coord) — see [method _rng_for].
##
## Rows with no item, or priced at zero, are skipped: a free row is a drop-table
## row that wandered into a shop rule, and putting it on a shelf with no price
## would be a giveaway rather than a shop.

## Where the routing table comes from. Wired in the inspector to the same
## DropConfig the run uses, rather than passed in, so the port's signature stays
## the three arguments every provider gets and this one does not need a special
## call from Game.
@export var drop_config: DropConfig

## The [DropRule] source to read. Matches the docs/DROPS.md convention, and is an
## export so a second kind of shop — a black market, a vending machine — is a
## second provider pointing at a different rule rather than a code change.
@export var source: StringName = &"shop"


func stock_for(floor_number: int, coord: Vector2i, capacity: int) -> Array[ShopOffer]:
	var offers: Array[ShopOffer] = []
	if drop_config == null:
		return offers

	var rng := _rng_for(floor_number, coord)
	for table in drop_config.tables_for(source, floor_number):
		if table == null:
			continue
		for entry in LootRoller.roll_entries(table, rng):
			if offers.size() >= capacity:
				return offers
			if entry.price <= 0:
				continue
			var offer := ShopOffer.new()
			offer.item = entry.item
			offer.price = entry.price
			offers.append(offer)
	return offers


## Deterministic per shop, the same identity [ShopRegistry] caches stock under —
## two shops sharing a coord on different floors still roll differently, and
## reloading the same floor with the same coord rolls the same shelf, without
## this needing the run's seed threaded all the way down through
## [ShopConfig] and [ShopRegistry] for what is, so far, one random row.
func _rng_for(floor_number: int, coord: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d,%d" % [floor_number, coord.x, coord.y])
	return rng
