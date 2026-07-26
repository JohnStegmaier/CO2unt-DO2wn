class_name EnemyPlacement
extends RefCounted

## Where to put a room's enemies.
##
## Everything here is room-LOCAL: the caller converts the player's position in
## and hands the results straight to Room.add_entity, so this never has to know
## that a room sits at coord * STRIDE.
##
## Pure maths, no nodes — this is the piece the floor generator will want later,
## and the piece worth a unit test if placement ever misbehaves twice. It has
## one: tools/check_enemies.gd sweeps both entry points over real layouts.

## Keeps a body's edge off the wall.
const SPAWN_MARGIN := 14.0
## Nothing materialises closer than this to the player.
const MIN_PLAYER_DISTANCE := 96.0
## Nor this close to a doorway the player might walk back through.
const DOOR_CLEARANCE := 44.0

## The widest agent the game can put in a room, and the number every claim about
## a room staying crossable is stated in terms of — see the arithmetic in
## [ObstaclePlacement], which proves two props can never close to less than a
## body width using this figure.
##
## Named here because it is now a budget spent by a whole bestiary rather than a
## fact about the one enemy scene that used to exist. An [EnemyDef]'s
## body_radius, times game.gd's boss_size_scale when that def may be promoted,
## must never exceed it; tools/check_enemies.gd is what enforces that, and
## tools/check_obstacles.gd floods real rooms for a body exactly this wide.
##
## It was written as the literal `4.0 * 1.7` in three places before this.
const MAX_AGENT_RADIUS := 6.8

## Margin on top of the widest body, so a spawn stands clear of a prop rather
## than exactly touching one.
const SPAWN_SLACK := 5.2
## And nothing spawns inside a solid prop. Applied to every enemy rather than
## only to the wide ones: a def's size is settled before a spot is chosen, but
## promotion to a boss happens after, so a spot that is only safe for a small one
## is a second thing to get wrong.
const OBSTACLE_CLEARANCE := MAX_AGENT_RADIUS + SPAWN_SLACK

const CELLS_X := 4
const CELLS_Y := 3
## Jitter is confined to the middle of a cell, which puts a hard floor under the
## gap between neighbours without needing a rejection loop.
const CELL_USABLE := 0.7

## Which cells of the grid below touch no wall, as indices into [method cells].
## The 4x3 grid is row-major, so the middle row is 4..7 and the two that are not
## also in the leftmost or rightmost column are 5 and 6.
##
## A const rather than arithmetic at the point of use, because it is the one
## thing [method wall_points] and its check in tools/check_enemies.gd both have
## to agree about, and a checker that recomputed it would be testing its own copy.
const INTERIOR_CELLS: Array[int] = [5, 6]


## The placement grid for a floor, row-major. Public because
## [method wall_points] is a subset of it and the checker asserts against the
## same rects rather than rebuilding them.
static func cells(floor_rect: Rect2) -> Array[Rect2]:
	var usable := floor_rect.grow(-SPAWN_MARGIN)
	var cell_size := Vector2(usable.size.x / CELLS_X, usable.size.y / CELLS_Y)
	var grid: Array[Rect2] = []
	for cy in CELLS_Y:
		for cx in CELLS_X:
			grid.append(Rect2(
				usable.position + Vector2(cx * cell_size.x, cy * cell_size.y),
				cell_size))
	return grid


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
	return _spots_from(cells(floor_rect), count, player_position, door_landings, rng, field)


## The same, but only from cells that touch a wall.
##
## For enemies that are fixtures rather than bodies. A turret's whole appeal is
## that it covers ground and has to be approached, which it cannot do from the
## middle of the floor — one standing in the open is a barrel with a gun, and it
## is also the easiest thing in the game to walk a circle around.
##
## Shares the grid, the clearances, the fallback ladder and the jitter with
## [method points] rather than laying a second scheme that would have to be kept
## in step. Ten cells of the twelve, which is enough that a room asking for two
## or three fixtures is never squeezed.
##
## The prop test matters more here than anywhere else in this file: a body that
## spawns badly walks out of it, and a fixture cannot. One inside a prop is
## unshootable, so the room never unlocks, and on floor 1 the boss gate is the
## only way down.
static func wall_points(
		floor_rect: Rect2,
		count: int,
		player_position: Vector2,
		door_landings: Array[Vector2],
		rng: RandomNumberGenerator,
		field: ObstacleField = null) -> Array[Vector2]:
	var edge: Array[Rect2] = []
	var grid := cells(floor_rect)
	for i in grid.size():
		if not INTERIOR_CELLS.has(i):
			edge.append(grid[i])
	return _spots_from(edge, count, player_position, door_landings, rng, field)


## Pick `count` of `candidates`, then jitter a point inside each.
##
## Extracted so [method points] and [method wall_points] differ only in which
## cells they are handed. The fallback ladder below is the part worth sharing:
## it decides what to give up when a room cannot honour everything, and two
## copies of that decision would eventually disagree about the one thing that
## must never be given up.
static func _spots_from(
		candidates: Array[Rect2],
		count: int,
		player_position: Vector2,
		door_landings: Array[Vector2],
		rng: RandomNumberGenerator,
		field: ObstacleField) -> Array[Vector2]:
	var free_cells: Array[Rect2] = []
	for cell in candidates:
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
		free_cells = candidates.filter(func(c: Rect2) -> bool:
			return _is_unobstructed(c.get_center(), field))
		if free_cells.size() < count:
			free_cells = candidates.duplicate()
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
static func _shuffle(cells_to_shuffle: Array[Rect2], rng: RandomNumberGenerator) -> void:
	for i in range(cells_to_shuffle.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells_to_shuffle[i]
		cells_to_shuffle[i] = cells_to_shuffle[j]
		cells_to_shuffle[j] = tmp
