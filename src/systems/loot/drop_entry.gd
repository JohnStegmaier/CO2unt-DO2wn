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
	if count_max > count_min:
		return "%d-%d x %s" % [count_min, count_max, what]
	if count_min != 1:
		return "%d x %s" % [count_min, what]
	return what
