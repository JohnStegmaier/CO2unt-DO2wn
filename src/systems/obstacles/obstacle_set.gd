class_name ObstacleSet
extends Resource

## Which props a floor scatters, how many, and into which rooms.
##
## The inspector slot on game.gd, the same bargain [FloorConfig] makes for a
## run's shape and [DropConfig] for its economy: swapping this file swaps every
## room's furniture without touching a script. Pure data — it holds no RNG and
## places nothing, so reading it cannot change where anything lands.

## The catalogue. Order is for readability only; picking is by weight.
@export var defs: Array[ObstacleDef] = []

@export_group("Count")
## Props per eligible room, inclusive. The ceiling is the placement grid's cell
## count (6), not this — asking for more than six gets you six.
@export var count_min: int = 2
@export var count_max: int = 4

@export_group("Rooms")
## Which kinds of room get props, as a mask over [enum RoomData.Kind]. The flag
## names and their order must match that enum exactly — the same "edit one, edit
## the other" hazard collision_layers.gd warns about against project.godot,
## except this one is checkable, and check_obstacles.gd checks it.
##
## Defaults to NORMAL | BOSS (5).
##
## SHOP is off deliberately and should stay off: that room is being replaced with
## a side-on belt-scroll scene that has no top-down floor to scatter across.
## EXIT is off because the elevator room's floor is a shallow strip — Room
## .obstacle_rect() is what makes ticking it safe rather than a bug.
@export_flags("normal", "spawn", "boss", "shop", "treasure", "exit")
var room_kinds: int = 5


## Does this kind of room get props at all?
func allows_kind(kind: int) -> bool:
	return (room_kinds & (1 << kind)) != 0


## The biggest footprint in the catalogue. What the connectivity proof and the
## placement grid's bounds inset are both stated in terms of.
func max_body_radius() -> float:
	var widest := 0.0
	for def in defs:
		if def != null:
			widest = maxf(widest, def.body_radius)
	return widest


func total_weight() -> float:
	var total := 0.0
	for def in defs:
		if def != null:
			total += maxf(0.0, def.weight)
	return total


## Weighted pick over the catalogue, the same walk FloorGenerator._weighted_pick
## does. Returns null only for an empty or zero-weighted set, which is a
## perfectly ordinary way to say "this floor has no props".
func pick(rng: RandomNumberGenerator) -> ObstacleDef:
	var total := total_weight()
	if is_zero_approx(total):
		return null
	var roll := rng.randf() * total
	var last: ObstacleDef = null
	for def in defs:
		if def == null:
			continue
		last = def
		roll -= maxf(0.0, def.weight)
		if roll <= 0.0:
			return def
	# Only reachable on floating point crumbs at the very top of the range.
	return last


## Deliberately NO apply_overrides() here, unlike [FloorConfig].
##
## Reading GameConfig from a Resource makes that autoload a compile-time
## dependency of the Resource, and of everything that names its type. Nothing
## under systems/ can then be loaded by `godot --headless --script`, because that
## mode starts no autoloads — which is exactly why tools/check_floors.gd does not
## currently run.
##
## So the profile is folded in by game.gd, which is a Node and has the autoloads
## anyway. This file stays what systems/ is supposed to be: pure data that a
## terminal can load. See _apply_obstacle_overrides.
