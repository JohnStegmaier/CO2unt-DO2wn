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

const CELLS_X := 4
const CELLS_Y := 3
## Jitter is confined to the middle of a cell, which puts a hard floor under the
## gap between neighbours without needing a rejection loop.
const CELL_USABLE := 0.7


## Up to `count` spread-out spots, never near the player or a doorway.
##
## Cells rather than dart throwing: random points with a minimum-separation rule
## clump at low counts and need a retry loop that can still fail, whereas one
## point per cell is spread by construction and always terminates.
static func points(
		floor_rect: Rect2,
		count: int,
		player_position: Vector2,
		door_landings: Array[Vector2],
		rng: RandomNumberGenerator) -> Array[Vector2]:
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
		if _is_clear(cell.get_center(), player_position, door_landings):
			free_cells.append(cell)

	if free_cells.size() < count:
		# Only reachable if the player stands dead centre with every door open.
		# Fall back to the farthest cells rather than returning short.
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
		spots.append(Vector2(
			rng.randf_range(cell.position.x + inset.x, cell.end.x - inset.x),
			rng.randf_range(cell.position.y + inset.y, cell.end.y - inset.y)))
	return spots


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
