class_name LootRoller
extends RefCounted

## Turns drop tables into a list of items.
##
## The only part of the loot path that touches an RNG, and it never owns one —
## the caller passes theirs in. That is what lets a run's drops be reproducible
## from its seed while the checker rolls the same tables a hundred thousand times
## from a different seed without either knowing about the other.
##
## Static and node-free, the same shape as [FloorGenerator], so its behaviour can
## be settled in a terminal instead of by playing until something drops.


## Every item the given tables produce, in order. An empty array is a perfectly
## ordinary result: most enemies drop nothing most of the time.
static func roll(tables: Array[DropTable], rng: RandomNumberGenerator) -> Array[ItemDef]:
	var items: Array[ItemDef] = []
	for table in tables:
		if table == null:
			continue
		_roll_table(table, rng, items)
	return items


static func _roll_table(table: DropTable, rng: RandomNumberGenerator,
		into: Array[ItemDef]) -> void:
	var total := table.total_weight()
	if is_zero_approx(total):
		return
	for i in maxi(0, table.rolls):
		var entry := _pick(table, total, rng)
		# The empty item is the "nothing drops" row doing its job, not a fault.
		if entry == null or entry.item == null:
			continue
		for n in entry.roll_count(rng):
			into.append(entry.item)


## Weighted pick over the table's rows, the same walk FloorGenerator._weighted_pick
## does. Kept here rather than shared with it: that one takes a prepared array of
## floats and this one has to skip empty rows, and folding both into one helper
## would need a callable per call site to save four lines.
static func _pick(table: DropTable, total: float, rng: RandomNumberGenerator) -> DropEntry:
	var roll := rng.randf() * total
	var last: DropEntry = null
	for entry in table.entries:
		if entry == null:
			continue
		last = entry
		roll -= maxf(0.0, entry.weight)
		if roll <= 0.0:
			return entry
	# Only reachable on floating point crumbs at the very top of the range.
	return last
