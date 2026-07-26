class_name DecalPlacement
extends RefCounted

## Where a room's cosmetic floor dressing goes — blood splats, torches, and
## anything else with no collision and no bearing on whether a room can be
## crossed.
##
## Room-local and a pure function of (floor seed, coord, doors), for the exact
## reason [ObstaclePlacement] gives: a room is freed and rebuilt on every
## entry, so anything that depended on where the player came in would
## rearrange the dressing when they backtracked.
##
## Its own grid rather than [ObstaclePlacement]'s, for the reason that file
## gives for not borrowing [EnemyPlacement]'s: sharing cells would mean
## retuning how many rocks a room gets silently moves every torch with it, and
## it would make a decal land on the same six spots a rock might, which reads
## as the floor repeating itself rather than as two independent layers.
##
## No connectivity proof here, on purpose. Nothing built from this blocks a
## step, a bullet, or a flood fill, so there is no MAX_BODY_RADIUS kind of
## promise to keep — only [DecalPlacement]'s own accounting that two decals do
## not land inside each other's [member DecalDef.clearance_radius].

## Borrowed from EnemyPlacement, where they mean exactly the same things —
## referenced rather than copied so the two cannot drift apart. See
## ObstaclePlacement's identical note.
const SPAWN_MARGIN := EnemyPlacement.SPAWN_MARGIN
const DOOR_CLEARANCE := EnemyPlacement.DOOR_CLEARANCE

## Decorrelated from both EnemyPlacement's grid and ObstaclePlacement's 3x2 —
## four cells rather than six, so a decal's candidate spots do not line up with
## either a prop's or an enemy's.
const CELLS_X := 2
const CELLS_Y := 2
const CELL_USABLE := 0.5

## Distinct from FloorGenerator's SEED_MIX, game.gd's LOOT_SEED_SALT and
## ObstaclePlacement's own SEED_SALT — murmur3's constants rather than
## splitmix64's, borrowed for the same reason ObstaclePlacement borrows
## splitmix64's finalizer below: any well-mixed constant works, and reusing a
## named one beats inventing a fifth.
const SEED_SALT := 0x1B873593
const COORD_X_MIX := 0xCC9E2D51
const COORD_Y_MIX := 0xE6546B64


## One room's decals. Unordered — nothing remembers a decal by index the way
## RoomData.obstacles_destroyed remembers a prop, because nothing ever breaks
## one.
##
## keep_clear is the door landings plus the room centre, same as
## ObstaclePlacement.points.
##
## set.guaranteed_def, if any, claims a cell before the weighted pool gets a
## look at any of them — see [member DecalSet.guaranteed_def]. Everything
## after that point, including the pool's own cell budget, works exactly as it
## did before that field existed.
static func points(
		floor_rect: Rect2,
		set: DecalSet,
		keep_clear: Array[Vector2],
		rng: RandomNumberGenerator) -> Array[DecalPlan]:
	var plans: Array[DecalPlan] = []
	if set == null or not floor_rect.has_area():
		return plans

	var cells := _cells(floor_rect)
	_shuffle(cells, rng)
	var next_cell := 0

	# Best-effort: walks forward through the shuffle until a cell is clear,
	# same as the pool loop below, and simply has none if it runs out.
	if set.guaranteed_def != null:
		while next_cell < cells.size():
			var spot := _jitter(cells[next_cell], rng)
			next_cell += 1
			if _is_clear(spot, set.guaranteed_def, keep_clear, plans):
				plans.append(DecalPlan.new(set.guaranteed_def, spot))
				break

	var count: int = rng.randi_range(set.count_min, set.count_max)
	var placed := 0

	# Walks every remaining cell rather than only the first `count`, the same
	# reason ObstaclePlacement does: a cell rejected for sitting on a doorway
	# costs the next cell in the shuffle rather than the decal outright.
	while next_cell < cells.size() and placed < count:
		var cell := cells[next_cell]
		next_cell += 1
		var def := set.pick(rng)
		if def == null:
			continue

		var spot := _jitter(cell, rng)
		if not _is_clear(spot, def, keep_clear, plans):
			continue
		plans.append(DecalPlan.new(def, spot))
		placed += 1
	return plans


## Deterministic per room, per floor, per run — see ObstaclePlacement.seed_for.
static func seed_for(floor_seed: int, coord: Vector2i) -> int:
	var h: int = floor_seed ^ SEED_SALT
	h = _avalanche(h ^ (coord.x * COORD_X_MIX))
	h = _avalanche(h ^ (coord.y * COORD_Y_MIX))
	return h


## splitmix64's finalizer — see ObstaclePlacement's note on why a plain
## multiply-and-xor is not enough for small coordinate values.
const AVALANCHE_A := -4658895280553007687
const AVALANCHE_B := -7723592293110705685


static func _avalanche(value: int) -> int:
	var h := value
	h = (h ^ (h >> 30)) * AVALANCHE_A
	h = (h ^ (h >> 27)) * AVALANCHE_B
	return h ^ (h >> 31)


## The grid, row-major. Inset by SPAWN_MARGIN alone — a decal has no radius of
## its own to pull back by, unlike a prop's _jitter.
static func _cells(floor_rect: Rect2) -> Array[Rect2]:
	var usable := floor_rect.grow(-SPAWN_MARGIN)
	var size := Vector2(usable.size.x / CELLS_X, usable.size.y / CELLS_Y)
	var cells: Array[Rect2] = []
	for cy in CELLS_Y:
		for cx in CELLS_X:
			cells.append(Rect2(usable.position + Vector2(cx * size.x, cy * size.y), size))
	return cells


## A point inside the cell's usable middle. No second clamp against the room
## edge, unlike ObstaclePlacement._jitter — nothing here has a solid half to
## push into a wall face.
static func _jitter(cell: Rect2, rng: RandomNumberGenerator) -> Vector2:
	var inset := cell.size * (1.0 - CELL_USABLE) * 0.5
	return Vector2(
			rng.randf_range(cell.position.x + inset.x, cell.end.x - inset.x),
			rng.randf_range(cell.position.y + inset.y, cell.end.y - inset.y))


## Off the doorways and off the middle, and off every decal already placed this
## pass. The keep_clear check is flat DOOR_CLEARANCE rather than
## ObstaclePlacement's DOOR_CLEARANCE + radius: a decal has no edge to keep off
## the threshold, only a centre to keep off it. The pairwise check does add
## both radii, because that one IS about two sprites visibly overlapping.
static func _is_clear(spot: Vector2, def: DecalDef, keep_clear: Array[Vector2],
		placed: Array[DecalPlan]) -> bool:
	for point in keep_clear:
		if spot.distance_to(point) < DOOR_CLEARANCE:
			return false
	for plan in placed:
		if spot.distance_to(plan.position) < def.clearance_radius + plan.def.clearance_radius:
			return false
	return true


## Array.shuffle() draws from the global RNG, which would make a seeded floor's
## dressing unreproducible. Same Fisher-Yates as ObstaclePlacement._shuffle.
static func _shuffle(cells: Array[Rect2], rng: RandomNumberGenerator) -> void:
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := cells[i]
		cells[i] = cells[j]
		cells[j] = swap
