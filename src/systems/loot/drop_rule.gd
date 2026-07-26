class_name DropRule
extends Resource

## What one source drops, optionally only on certain floors.
##
## The row of the routing table. Keeping the source and the floors on the rule
## rather than on the enemy is what makes the whole economy legible in one
## place: you answer "what does a grunt drop on floor 3" by reading down a list,
## not by opening three scenes.

## Who or what this is the loot for. Free-form by design — &"grunt",
## &"skirmisher", &"boss", and later &"chest" and &"shop". A StringName rather
## than an enum so that adding an enemy type or a new kind of container is a
## .tres edit and not a script edit; the cost is that a typo resolves to nothing,
## which is exactly what check_drops.gd is for.
@export var source: StringName

## Descent indices this applies to — 0 is the top floor, see [FloorLadder].
## Empty means every floor, which is how the baseline row for a source is
## written. A rule naming floors beats one that names none, so tuning floor 3
## does not mean copying the whole table.
@export var floors: Array[int] = []

## Rolled together, in order. Several tables is how "a guaranteed coin AND a
## chance of something good" is expressed, and how the proposed config 3's three
## shop pools will be.
@export var tables: Array[DropTable] = []


func matches(for_source: StringName, floor_number: int) -> bool:
	return source == for_source and (floors.is_empty() or floors.has(floor_number))


## True when this rule names its floors explicitly, and so outranks a rule that
## applies to all of them. See [method DropConfig.tables_for].
func is_specific() -> bool:
	return not floors.is_empty()
