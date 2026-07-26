class_name DecalSet
extends Resource

## Which cosmetic floor dressing a floor scatters, how many, and into which
## rooms.
##
## [ObstacleSet]'s exact shape, minus everything that exists only to keep that
## resource's connectivity proof honest: no body radius, no cap on it. Swapping
## this file swaps every room's dressing without touching a script, the same
## bargain ObstacleSet makes for props.

## The weighted catalogue. Order is for readability only; picking is by weight.
## [member guaranteed_def] is deliberately not in here — see it.
@export var defs: Array[DecalDef] = []

@export_group("Count")
## Placed once in every eligible room, before the weighted pool below and
## exempt from count_min/count_max — "1 torch per room" is a fact about the
## room, not something a draw could come up short on. Null means no guaranteed
## decal, the same way a null [member ObstacleDef.behaviour] is not offered here
## as a knob because nothing needs it yet.
##
## Best-effort, not absolute: a room whose doors leave no cell clear of
## DOOR_CLEARANCE gets none, the same as any other rejected spot — see
## DecalPlacement.points. That is rare at the grid sizes this project ships.
@export var guaranteed_def: DecalDef
## Extra decals per eligible room, inclusive, on top of and NOT counting
## [member guaranteed_def]'s one.
@export var count_min: int = 0
@export var count_max: int = 3

@export_group("Rooms")
## Same mask, same enum, same order as [member ObstacleSet.room_kinds] — see
## its comment for why SHOP and EXIT are off. Defaults to the same NORMAL |
## BOSS (5): there is no reason for decals to try rooms props do not.
@export_flags("normal", "spawn", "boss", "shop", "treasure", "exit")
var room_kinds: int = 5


## Does this kind of room get decals at all?
func allows_kind(kind: int) -> bool:
	return (room_kinds & (1 << kind)) != 0


func total_weight() -> float:
	var total := 0.0
	for def in defs:
		if def != null:
			total += maxf(0.0, def.weight)
	return total


## Weighted pick over the catalogue — the same walk [method ObstacleSet.pick]
## does. Returns null only for an empty or zero-weighted set.
func pick(rng: RandomNumberGenerator) -> DecalDef:
	var total := total_weight()
	if is_zero_approx(total):
		return null
	var roll := rng.randf() * total
	var last: DecalDef = null
	for def in defs:
		if def == null:
			continue
		last = def
		roll -= maxf(0.0, def.weight)
		if roll <= 0.0:
			return def
	# Only reachable on floating point crumbs at the very top of the range.
	return last


## Deliberately NO apply_overrides() here, unlike FloorConfig — see
## ObstacleSet's identical note. game.gd folds a profile in instead, because
## that keeps this file loadable by `godot --headless --script`.
