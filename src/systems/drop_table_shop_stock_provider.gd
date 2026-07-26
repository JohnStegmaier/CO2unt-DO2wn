class_name DropTableShopStockProvider
extends ShopStockProvider

## ADAPTER — stocks a shop from the run's drop configuration.
##
## docs/DROPS.md keys a [DropRule] on a source rather than on "enemy" precisely
## so the shop and the treasure room can route through the same table instead of
## needing a loot system each. This is the shop end of that: it reads the rule
## for [member source] and turns its rows into priced offers.
##
## One deliberate reinterpretation. A [DropTable] is normally a pool you ROLL —
## [member DropTable.rolls] draws from it at random. A shelf is not a roll; it is
## everything on offer, laid out. So this takes every row rather than sampling,
## and [member DropEntry.weight] is ignored for this source. Weight still has to
## be there because it is on the row, and check_drops.gd still reports it — but
## for a shop it means nothing, and a shelf that shuffled its contents every
## visit would fight [ShopRegistry], which exists to make stock stay put.
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


func stock_for(floor_number: int, _coord: Vector2i, capacity: int) -> Array[ShopOffer]:
	var offers: Array[ShopOffer] = []
	if drop_config == null:
		return offers

	for table in drop_config.tables_for(source, floor_number):
		if table == null:
			continue
		for entry in table.entries:
			if offers.size() >= capacity:
				return offers
			if entry == null or entry.item == null or entry.price <= 0:
				continue
			var offer := ShopOffer.new()
			offer.item = entry.item
			offer.price = entry.price
			offers.append(offer)
	return offers
