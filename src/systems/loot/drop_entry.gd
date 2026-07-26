class_name DropEntry
extends Resource

## One row of a [DropTable]: an item, how likely it is, and how many.

## Left empty on purpose for the "nothing drops" row. A table that wants a 40%
## chance of no drop says so as a row weighted 0.4, rather than as a separate
## drop_chance sitting beside the table — which is what stops the two from
## disagreeing and what makes the weights add up to something you can read.
@export var item: ItemDef

## Relative, not a percentage. A row at 2.0 comes up twice as often as one at
## 1.0, whatever else is in the table, so adding a row never means retyping the
## others.
@export var weight: float = 1.0

## What this costs where a source charges for it. Zero is free, which is what
## every enemy and chest row is.
##
## Here rather than on [ItemDef] because a price is not a property of a thing —
## the same oxygen canister is a free drop on floor 5 and costs coins in a shop,
## and an item that carried its own price could only ever have one. Putting it on
## the row means the [DropRule] that routes an item to a source also says what
## that source charges, which is the whole point of the source keying described
## in docs/DROPS.md.
##
## Dead weight on rows that are never sold, and deliberately so: one row saying
## both what an item is and what it costs beats a second table to keep in step.
@export var price: int = 0

@export_group("Count")
@export var count_min: int = 1
@export var count_max: int = 1


## How many of this to drop. The only place in the loot path that needs the RNG
## besides picking the row itself.
func roll_count(rng: RandomNumberGenerator) -> int:
	if count_max <= count_min:
		return count_min
	return rng.randi_range(count_min, count_max)


func describe() -> String:
	var what: String = item.describe() if item != null else "nothing"
	if price > 0:
		what = "%s @ %d" % [what, price]
	if count_max > count_min:
		return "%d-%d x %s" % [count_min, count_max, what]
	if count_min != 1:
		return "%d x %s" % [count_min, what]
	return what
