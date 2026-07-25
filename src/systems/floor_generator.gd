class_name FloorGenerator
extends RefCounted

## Grows a [FloorPlan]: a tree of rooms on the grid with the special rooms at
## its tips.
##
## Two properties the algorithm gets structurally, rather than by generating
## something and then checking it:
##
## [b]It cannot overlap itself.[/b] Rooms are keyed by [Vector2i], so walking
## down, then left, then up lands on a coordinate that is either free or taken.
## There is no geometry to collide, and so nothing to detect.
##
## [b]It cannot loop.[/b] A room is only ever accepted in a cell that exactly
## one placed room touches, so every step adds one room and one door pair. A
## graph that gains a vertex and an edge together is a tree — no cycles, and
## exactly one route between any two rooms.
##
## Nothing here touches a node, so a floor can be generated and inspected
## without a scene tree. See [code]tools/check_floors.gd[/code].

## Tried in this order against the dead ends a floor happens to have. EXIT
## leads because it is the only one a floor cannot ship without.
const SPECIAL_ORDER: Array[int] = [
	RoomData.Kind.EXIT,
	RoomData.Kind.BOSS,
	RoomData.Kind.SHOP,
	RoomData.Kind.TREASURE,
]

## A floor is grown and then judged. Growth is cheap and most attempts pass, so
## rerolling a floor whose dead ends landed badly beats trying to patch one —
## patching would mean adding a room where a loop could close.
const MAX_ATTEMPTS := 40

## 32-bit fraction of the golden ratio, the usual choice for spreading
## sequential values across the seed space.
const SEED_MIX := 0x9E3779B9


## Build one floor. [param floor_number] is 0 for the first floor and only
## affects how many rooms are aimed for; [param floor_seed] makes the result
## reproducible, which is what lets a bad layout be re-examined from a printed
## number instead of walked to again.
static func generate(config: FloorConfig, floor_number: int = 0, floor_seed: int = 0) -> FloorPlan:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed

	for _attempt in MAX_ATTEMPTS:
		var plan := _grow(config, floor_number, rng)
		if _assign_specials(plan, config, rng):
			return plan

	# Every attempt produced a floor too cramped to house all four specials.
	# Ship one anyway with the depth rules relaxed: a floor with a shallow exit
	# is playable, a floor with no exit is a dead end for the whole run.
	push_warning("FloorGenerator: no layout in %d attempts housed every special room; relaxing depth rules" % MAX_ATTEMPTS)
	var fallback := _grow(config, floor_number, rng)
	_assign_specials(fallback, config, rng, true)
	return fallback


## Per-floor seed derived from one run seed, so a single printed number
## reproduces every floor of a run rather than only its first.
static func floor_seed_for(run_seed: int, floor_number: int) -> int:
	return run_seed ^ ((floor_number + 1) * SEED_MIX)


static func _grow(config: FloorConfig, floor_number: int, rng: RandomNumberGenerator) -> FloorPlan:
	var plan := FloorPlan.new()
	plan.add_room(RoomData.new(Vector2i.ZERO, RoomData.Kind.SPAWN, 0))

	# Spawn always offers all four directions. Placed before any random growth
	# because it has to be unconditional: once the neighbours of those cells
	# exist, adding a fourth arm might be the room that closes a loop, and the
	# growth rule would refuse it.
	for side in GridDirection.SIDES:
		plan.add_room(RoomData.new(GridDirection.offset(side), RoomData.Kind.NORMAL, 1))
		plan.connect_rooms(Vector2i.ZERO, side)

	var span := config.room_range(floor_number)
	var target: int = rng.randi_range(span.x, span.y)
	while plan.size() < target and _grow_once(plan, config, rng):
		pass
	return plan


## Attach one room to the floor. False when nothing can be added — every room is
## either at the depth ceiling or boxed in by its own neighbours. A smaller floor
## is the correct answer there; the only way to fit more would be a loop.
static func _grow_once(plan: FloorPlan, config: FloorConfig, rng: RandomNumberGenerator) -> bool:
	var parents: Array[Vector2i] = []
	var weights: Array[float] = []
	var total := 0.0

	for coord in plan.rooms:
		var data := plan.get_room(coord)
		if data.depth >= config.max_depth:
			continue
		if _free_sides(plan, coord).is_empty():
			continue
		# Deep rooms pull harder, so the floor stretches instead of pooling
		# around spawn. This is the whole difference between a blob and a maze.
		var weight: float = pow(data.depth + 1, config.depth_bias)
		parents.append(coord)
		weights.append(weight)
		total += weight

	if parents.is_empty():
		return false

	var parent: Vector2i = parents[_weighted_pick(weights, total, rng)]
	var sides := _free_sides(plan, parent)
	var side: int = sides[rng.randi_range(0, sides.size() - 1)]
	var depth: int = plan.get_room(parent).depth + 1

	plan.add_room(RoomData.new(parent + GridDirection.offset(side), RoomData.Kind.NORMAL, depth))
	plan.connect_rooms(parent, side)
	return true


## Sides of [param coord] a new room may be attached to.
##
## The cell must be empty and must touch exactly one placed room — [param coord]
## itself. Touching two would mean the new room joins the tree in two places,
## which is precisely a loop, so this single test is the whole cycle check.
static func _free_sides(plan: FloorPlan, coord: Vector2i) -> Array[int]:
	var sides: Array[int] = []
	for side in GridDirection.SIDES:
		var candidate: Vector2i = coord + GridDirection.offset(side)
		if plan.has_room(candidate):
			continue
		if plan.neighbour_count(candidate) != 1:
			continue
		sides.append(side)
	return sides


## Dress the tips of the tree as special rooms.
##
## Dead ends are the only sane home for them: a room with a single door can be a
## shop or a boss arena without the player having to cross it to get anywhere.
## Returns false when the floor could not house all of [constant SPECIAL_ORDER],
## which is [method generate]'s cue to reroll.
static func _assign_specials(plan: FloorPlan, config: FloorConfig, rng: RandomNumberGenerator, relax: bool = false) -> bool:
	var min_depth: int = 0 if relax else config.special_min_depth
	var available: Array[Vector2i] = []
	for coord in plan.dead_ends():
		if plan.get_room(coord).depth >= min_depth:
			available.append(coord)
	if available.is_empty():
		return false

	# Shuffled first so that ties in depth break randomly, then ordered by
	# depth: the exit should be the longest walk on the floor.
	_shuffle(available, rng)
	available.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return plan.get_room(a).depth > plan.get_room(b).depth)

	var exit_coord: Vector2i = available.pop_front()
	if not relax and plan.get_room(exit_coord).depth < config.exit_min_depth:
		return false
	plan.get_room(exit_coord).kind = RoomData.Kind.EXIT

	# The rest land on random dead ends rather than the next-deepest ones, so
	# two floors of the same shape still surprise you.
	_shuffle(available, rng)
	var placed := 1
	for i in range(1, SPECIAL_ORDER.size()):
		if available.is_empty():
			break
		plan.get_room(available.pop_back()).kind = SPECIAL_ORDER[i]
		placed += 1

	return placed == SPECIAL_ORDER.size()


static func _weighted_pick(weights: Array[float], total: float, rng: RandomNumberGenerator) -> int:
	var roll: float = rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return weights.size() - 1


## Fisher-Yates against the floor's own RNG. Array.shuffle() draws from the
## global generator, which would make a seeded floor unreproducible.
static func _shuffle(items: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Vector2i = items[i]
		items[i] = items[j]
		items[j] = swap
