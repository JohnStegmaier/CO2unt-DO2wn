class_name FloorPlan
extends RefCounted

## A floor: rooms keyed by grid coordinate.
##
## Keying on Vector2i is what makes room layouts impossible to self-overlap —
## a coordinate either holds a room or it does not, so "walk down, left, then
## up" cannot collide with anything. It just lands on a coord, and that coord
## is either occupied or free.
##
## Built by hand today; FloorGenerator will produce these later. Nothing in
## here touches a node, so it can be exercised without a scene tree.

var rooms: Dictionary[Vector2i, RoomData] = {}
var spawn_coord: Vector2i = Vector2i.ZERO


func has_room(coord: Vector2i) -> bool:
	return rooms.has(coord)


func get_room(coord: Vector2i) -> RoomData:
	return rooms.get(coord)


func size() -> int:
	return rooms.size()


func add_room(data: RoomData) -> void:
	rooms[data.coord] = data


## Open both halves of a door. Doors are always symmetric — a one-way door
## would strand the player, so there is deliberately no way to open just one.
func connect_rooms(coord: Vector2i, side: int) -> void:
	var neighbour: Vector2i = coord + GridDirection.offset(side)
	if not has_room(coord) or not has_room(neighbour):
		push_warning("FloorPlan: cannot connect %v -> %v, one side is missing" % [coord, neighbour])
		return
	get_room(coord).open_door(side)
	get_room(neighbour).open_door(GridDirection.opposite(side))


func neighbour_count(coord: Vector2i) -> int:
	var count := 0
	for side in GridDirection.SIDES:
		if has_room(coord + GridDirection.offset(side)):
			count += 1
	return count


func dead_ends() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for coord in rooms:
		if coord != spawn_coord and get_room(coord).is_dead_end():
			found.append(coord)
	return found


func coord_of_kind(kind: int) -> Vector2i:
	for coord in rooms:
		if get_room(coord).kind == kind:
			return coord
	return Vector2i.MAX


func bounds() -> Rect2i:
	if rooms.is_empty():
		return Rect2i()
	var first := true
	var rect := Rect2i()
	for coord in rooms:
		if first:
			rect = Rect2i(coord, Vector2i.ONE)
			first = false
		else:
			rect = rect.expand(coord)
	# expand() treats the coord as a point on the boundary, so the far row and
	# column end up zero-width. Grow by one to make every cell inclusive.
	return rect.grow_individual(0, 0, 1, 1)


## Debug dump. Two text rows per grid row: the rooms, then the vertical links.
## Reading 20 seeds in a terminal beats walking 20 floors.
func to_ascii() -> String:
	if rooms.is_empty():
		return "(empty floor)"

	var rect := bounds()
	var out := ""

	for y in range(rect.position.y, rect.end.y):
		var room_line := ""
		var link_line := ""
		for x in range(rect.position.x, rect.end.x):
			var coord := Vector2i(x, y)
			if has_room(coord):
				var data := get_room(coord)
				room_line += "[%s]" % data.glyph()
				link_line += " | " if data.has_door(GridDirection.Side.SOUTH) else "   "
			else:
				room_line += "   "
				link_line += "   "

			if x < rect.end.x - 1:
				var links_east: bool = has_room(coord) and get_room(coord).has_door(GridDirection.Side.EAST)
				room_line += "-" if links_east else " "
				link_line += " "

		out += room_line + "\n"
		if y < rect.end.y - 1:
			out += link_line + "\n"

	return out
