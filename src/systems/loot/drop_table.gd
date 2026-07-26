class_name DropTable
extends Resource

## A weighted pool, rolled a fixed number of times.
##
## This is the unit the three proposed economies are written in — what the design
## notes call a "pool". A source that offers three pools is a [DropRule] holding
## three of these, so nothing new is needed to express them.
##
## A guaranteed drop is a table with no empty row in it; a chance of nothing is a
## row whose item is empty. Both fall out of the same shape, which is why there
## is no separate drop_chance anywhere in this system.
##
## Pure data — it holds no RNG and makes no decisions. [LootRoller] does the
## rolling, so reading a table cannot change what it will produce.

## How many rows to draw. Above one, rows can repeat: this is a pool you dip
## into, not a hand you deal.
@export var rolls: int = 1

@export var entries: Array[DropEntry] = []


## Denominator for a weighted pick. Summed on demand rather than cached, because
## a cached total is a value that goes stale the moment someone edits a weight in
## the inspector, and there is nothing here worth the risk of that.
func total_weight() -> float:
	var total := 0.0
	for entry in entries:
		if entry != null:
			total += maxf(0.0, entry.weight)
	return total


func describe() -> String:
	var total := total_weight()
	if is_zero_approx(total):
		return "(empty table)"
	var parts := PackedStringArray()
	for entry in entries:
		if entry == null:
			continue
		parts.append("%s %.0f%%" % [entry.describe(), entry.weight / total * 100.0])
	var prefix: String = "" if rolls == 1 else "%d rolls of " % rolls
	return prefix + ", ".join(parts)
