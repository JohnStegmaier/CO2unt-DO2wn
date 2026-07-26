class_name EnemyPlacement
extends RefCounted

## Where to put a room's enemies.
##
## Everything here is room-LOCAL: the caller converts the player's position in
## and hands the results straight to Room.add_entity, so this never has to know
## that a room sits at coord * STRIDE.
##
## Pure maths, no nodes — this is the piece the floor generator will want later,
## and the piece worth a unit test if placement ever misbehaves twice.

## Keeps a body's edge off the wall.
const SPAWN_MARGIN := 14.0
## Nothing materialises closer than this to the player.
const MIN_PLAYER_DISTANCE := 96.0
## Nor this close to a doorway the player might walk back through.
const DOOR_CLEARANCE := 44.0

## And nothing spawns inside a solid prop. Stated as the widest body in the game —
## an enemy scaled by game.gd's boss_size_scale, 4.0 * 1.7 — plus margin, and
## applied to every enemy rather than only to bosses: make_boss runs after the
## spot has already been chosen, so a spot that is only safe for a small one is a
## second thing to get wrong.
const OBSTACLE_CLEARANCE := 12.0

const CELLS_X := 4
const CELLS_Y := 3
## Jitter is confined to the middle of a cell, which puts a hard floor under the
## gap between neighbours without needing a rejection loop.
const CELL_USABLE := 0.7


## Up to `count` spread-out spots, never near the player or a doorway, and never
## inside a prop.
##
## Cells rather than dart throwing: random points with a minimum-separation rule
## clump at low counts and need a retry loop that can still fail, whereas one
## point per cell is spread by construction and always terminates.
##
## `field` is optional and defaults to nothing in the way, so every call site that
## predates room obstacles reads the same.
static func points(
		floor_rect: Rect2,
		count: int,
		player_position: Vector2,
		door_landings: Array[Vector2],
		rng: RandomNumberGenerator,
		field: ObstacleField = null) -> Array[Vector2]:
	var usable := floor_rect.grow(-SPAWN_MARGIN)
	var cell_size := Vector2(usable.size.x / CELLS_X, usable.size.y / CELLS_Y)

	var cells: Array[Rect2] = []
	for cy in CELLS_Y:
		for cx in CELLS_X:
			cells.append(Rect2(
				usable.position + Vector2(cx * cell_size.x, cy * cell_size.y),
				cell_size))

	var free_cells: Array[Rect2] = []
	for cell in cells:
		if _is_clear(cell.get_center(), player_position, door_landings) \
				and _is_unobstructed(cell.get_center(), field):
			free_cells.append(cell)

	if free_cells.size() < count:
		# Not enough room to honour everything. Give up the player and door
		# clearances — they make a fight worse, not broken — but keep the prop
		# test, because a spot inside a barrel is not a spawn at all. Only if
		# that still comes up short is there nothing left to give.
		#
		# This branch is reachable on the shipped values: swarm.cfg asks for
		# eight and a cluttered room does not have eight clear cells.
		free_cells = cells.filter(func(c: Rect2) -> bool:
			return _is_unobstructed(c.get_center(), field))
		if free_cells.size() < count:
			free_cells = cells.duplicate()
		free_cells.sort_custom(func(a: Rect2, b: Rect2) -> bool:
			return a.get_center().distance_squared_to(player_position) \
					> b.get_center().distance_squared_to(player_position))
		free_cells = free_cells.slice(0, count)
	else:
		_shuffle(free_cells, rng)
		free_cells = free_cells.slice(0, count)

	var spots: Array[Vector2] = []
	for cell in free_cells:
		var inset := cell.size * (1.0 - CELL_USABLE) * 0.5
		var spot := Vector2(
			rng.randf_range(cell.position.x + inset.x, cell.end.x - inset.x),
			rng.randf_range(cell.position.y + inset.y, cell.end.y - inset.y))
		# The clearances above are tested at the cell's centre, but the jitter
		# carries a point up to half a cell away from it — far enough to land in
		# a prop whose centre the cell cleared. Snapped back rather than
		# re-rolled: exactly two draws per cell either way, so adding an obstacle
		# cannot shift the stream for every room after this one.
		if not _is_unobstructed(spot, field):
			spot = cell.get_center()
		spots.append(spot)
	return spots


## Separate from _is_clear because the two are given up at different times: a
## spawn crowding the player is a worse fight, a spawn inside a barrel is a bug.
static func _is_unobstructed(point: Vector2, field: ObstacleField) -> bool:
	return field == null or field.is_clear(point, OBSTACLE_CLEARANCE)


static func _is_clear(point: Vector2, player_position: Vector2, door_landings: Array[Vector2]) -> bool:
	if point.distance_to(player_position) < MIN_PLAYER_DISTANCE:
		return false
	for landing in door_landings:
		if point.distance_to(landing) < DOOR_CLEARANCE:
			return false
	return true


## Array.shuffle() uses the global RNG, which would make placement unreproducible
## once floors are seeded.
static func _shuffle(cells: Array[Rect2], rng: RandomNumberGenerator) -> void:
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
