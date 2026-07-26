class_name ObstaclePlacement
extends RefCounted

## Where a room's solid props go.
##
## Room-local throughout, like [EnemyPlacement]: the caller hands the results
## straight to Room.add_obstacle and this never learns that a room sits at
## coord * STRIDE. Pure maths, no nodes — the piece worth settling in a terminal,
## which tools/check_obstacles.gd does.
##
## [b]Deliberately takes no player position.[/b] EnemyPlacement does, and that is
## right for enemies: they are stocked once, and keeping them off the player is
## worth more than reproducibility. Props are the opposite. A room is freed and
## rebuilt on every entry, so anything that depends on where the player came in
## would rearrange the furniture when they backtrack. Everything here is a
## function of (floor seed, coord, doors) alone.
##
## [b]A room can never be walled off, by construction.[/b] Two props in adjacent
## cells can approach each other no closer than cell * (1 - CELL_USABLE):
##
##     horizontal   105.0 * 0.55 = 57.8
##     vertical      79.5 * 0.55 = 43.7
##
## Two props of the maximum radius plus a body between them needs
## 2 * 11 + 2 * 6.8 = 35.6, where 6.8 is the widest agent in the game — an enemy
## scaled by game.gd's boss_size_scale. Both clear it, the tighter by 8.1px. And
## the closest a prop centre can sit to the floor edge leaves 31.9 / 24.9px of
## gap, against the same 13.6 needed. So there is nothing to repair and no retry
## loop: MAX_BODY_RADIUS is the whole guarantee, which is why it is asserted
## rather than clamped. check_obstacles.gd flood-fills real layouts to prove it.
##
## This is the same trade FloorGenerator makes when it keeps a floor a tree by
## construction rather than checking for loops afterwards.

## Borrowed from EnemyPlacement, where they mean exactly the same things —
## referenced rather than copied so the two cannot drift apart.
const SPAWN_MARGIN := EnemyPlacement.SPAWN_MARGIN
const DOOR_CLEARANCE := EnemyPlacement.DOOR_CLEARANCE

## NOT borrowed. Props want a coarser grid than enemies and much tighter jitter,
## and the numbers above are a proof about these three values specifically —
## importing the enemy grid would mean that retuning how enemies spread silently
## moved every barrel in the game and quietly invalidated the guarantee.
##
## Coarser also means decorrelated: these cell centres sit at x 115.5 / 220.5 /
## 325.5, which miss the enemy grid's 102.4 / 181.1 / 259.9 / 338.6 entirely. A
## prop therefore does not systematically knock out an enemy spawn cell.
const CELLS_X := 3
const CELLS_Y := 2
const CELL_USABLE := 0.45

## The cap the paragraph above is a proof about. Raising it means redoing that
## arithmetic, so it is stated once here and asserted at every call.
const MAX_BODY_RADIUS := 11.0

## Distinct from FloorGenerator's SEED_MIX and game.gd's LOOT_SEED_SALT. It has
## to be: FloorPlan.spawn_coord is always Vector2i.ZERO, so sharing the loot salt
## would make the spawn room's props and the floor's drops the same stream.
const SEED_SALT := 0x2545F491
const COORD_X_MIX := 0x27D4EB2D
const COORD_Y_MIX := 0x165667B1
const HASH_MULT := 0x9E3779B1


## One room's props, ordered. The index into this array is how a broken prop is
## remembered — see RoomData.obstacles_destroyed — which is what makes the
## determinism above a correctness requirement and not just an aesthetic one: a
## layout that re-rolled would resurrect the wrong crate.
##
## keep_clear is the door landings plus the room centre; see the note in
## game.gd's _scatter_obstacles on why the centre is always in there.
static func points(
		floor_rect: Rect2,
		set: ObstacleSet,
		keep_clear: Array[Vector2],
		rng: RandomNumberGenerator) -> Array[ObstaclePlan]:
	var plans: Array[ObstaclePlan] = []
	if set == null or floor_rect.has_area() == false:
		return plans

	var count: int = rng.randi_range(set.count_min, set.count_max)
	if count <= 0:
		return plans

	var cells := _cells(floor_rect)
	_shuffle(cells, rng)
	# More props than cells is not an error, it is a profile asking for a
	# cluttered room. One per cell is what keeps the separation proof true.
	count = mini(count, cells.size())

	# Walks every cell rather than only the first `count`, so a cell rejected for
	# sitting on a doorway costs the next cell in the shuffle and not the prop.
	# Taking the first `count` and dropping the failures lost about a third of
	# them, which read as rooms that ignored their own count_min.
	for cell in cells:
		if plans.size() >= count:
			break
		var def := set.pick(rng)
		if def == null:
			continue
		assert(def.body_radius <= MAX_BODY_RADIUS,
				"ObstacleDef '%s' has body_radius %.1f, above the %.1f a room's " \
				% [def.id, def.body_radius, MAX_BODY_RADIUS] \
				+ "connectivity guarantee is proved for — see ObstaclePlacement")

		var spot := _jitter(cell, def, floor_rect, rng)
		# Rejected rather than nudged: a prop shoved off a doorway lands
		# somewhere the separation proof says nothing about, and a room with one
		# fewer barrel is a perfectly good room.
		if not _is_clear(spot, def, keep_clear):
			continue
		plans.append(ObstaclePlan.new(def, spot))
	return plans


## Deterministic per room, per floor, per run.
##
## The two axes are mixed in separately and asymmetrically, so coords (2,3) and
## (3,2) cannot land on the same stream — on a grid that grows in all four
## directions from the origin, both are real rooms on the same floor.
static func seed_for(floor_seed: int, coord: Vector2i) -> int:
	var h: int = floor_seed ^ SEED_SALT
	h = _avalanche(h ^ (coord.x * COORD_X_MIX))
	h = _avalanche(h ^ (coord.y * COORD_Y_MIX))
	return h


## splitmix64's finalizer.
##
## A plain multiply-and-xor is not enough here: coords are small numbers in a
## narrow range, so the products differ only in their low bits, and multiplying
## leaves low bits where they were. That produced a 6% collision rate across one
## floor's rooms — two rooms furnished identically — until this was added.
## The two multipliers are splitmix64's, written signed: GDScript ints are signed
## 64-bit and refuse the 0xBF58… and 0x94D0… literals outright. Same bits.
const AVALANCHE_A := -4658895280553007687
const AVALANCHE_B := -7723592293110705685


static func _avalanche(value: int) -> int:
	var h := value
	h = (h ^ (h >> 30)) * AVALANCHE_A
	h = (h ^ (h >> 27)) * AVALANCHE_B
	return h ^ (h >> 31)


## The grid, row-major. Inset by SPAWN_MARGIN alone; the per-prop radius comes
## off inside _jitter, because it differs per prop.
static func _cells(floor_rect: Rect2) -> Array[Rect2]:
	var usable := floor_rect.grow(-SPAWN_MARGIN)
	var size := Vector2(usable.size.x / CELLS_X, usable.size.y / CELLS_Y)
	var cells: Array[Rect2] = []
	for cy in CELLS_Y:
		for cx in CELLS_X:
			cells.append(Rect2(usable.position + Vector2(cx * size.x, cy * size.y), size))
	return cells


## A point inside the cell's usable middle, then pulled back inside the room by
## the prop's own radius.
##
## SPAWN_MARGIN alone is not enough: it assumes a point-like body, and an 11px
## disc jittered to the edge of the usable rect would push its own solid half
## into the wall face. Two draws, always, whether or not the clamp bites.
static func _jitter(cell: Rect2, def: ObstacleDef, floor_rect: Rect2,
		rng: RandomNumberGenerator) -> Vector2:
	var inset := cell.size * (1.0 - CELL_USABLE) * 0.5
	var spot := Vector2(
			rng.randf_range(cell.position.x + inset.x, cell.end.x - inset.x),
			rng.randf_range(cell.position.y + inset.y, cell.end.y - inset.y))
	var inside := floor_rect.grow(-(SPAWN_MARGIN + def.body_radius))
	return spot.clamp(inside.position, inside.end)


## Off the doorways and off the middle, measured from the prop's edge rather than
## its centre so a bigger prop keeps a bigger berth. Note this tests the final
## jittered point: EnemyPlacement tests cell centres, which is why its 44px is
## really about 11px in the worst case, and this does not inherit that.
static func _is_clear(spot: Vector2, def: ObstacleDef, keep_clear: Array[Vector2]) -> bool:
	for point in keep_clear:
		if spot.distance_to(point) < DOOR_CLEARANCE + def.body_radius:
			return false
	return true


## Array.shuffle() draws from the global RNG, which would make a seeded floor's
## furniture unreproducible. Same Fisher-Yates as EnemyPlacement._shuffle.
static func _shuffle(cells: Array[Rect2], rng: RandomNumberGenerator) -> void:
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := cells[i]
		cells[i] = cells[j]
		cells[j] = swap
