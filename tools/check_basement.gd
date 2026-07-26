extends SceneTree

## Assert the shape of the Basement: two rooms, one doorway, and a board room
## drawn twice as long as the cell it stands in.
##
##   godot --headless --script tools/check_basement.gd
##
## The Basement is the one floor that is not generated, so none of the sweeps in
## check_floors.gd say anything about it. It is also the floor nobody walks: it
## is behind five floors and a boss, which makes it the last place a mistake gets
## noticed and the first place one gets made.
##
## Two kinds of claim are settled here.
##
## [b]The plan[/b], which is real code and can simply be run — [BasementPlan] is
## pure data with no nodes in it, like everything else in src/systems/.
##
## [b]The room[/b], which cannot. board_room.tscn and board_room.gd both describe
## the same geometry from different ends: the script derives its rects from
## [Room]'s constants and follows them automatically, and the scene has the
## numbers typed into it and does not. Change [constant Room.STRIDE] and the
## script is still right while the scene has a wall across the middle of the
## floor. So the scene is read as TEXT and checked against room.tscn — text,
## because naming Room from here pulls in the elevator, which pulls in the
## player, which names AudioManager, and `--headless --script` starts no
## autoloads. Same trick, and same reason, as tools/check_obstacles.gd.

const ROOM_SCRIPT := "res://src/levels/room/room.gd"
const ROOM_SCENE := "res://src/levels/room/room.tscn"
const BOARD_SCRIPT := "res://src/levels/board_room/board_room.gd"
const BOARD_SCENE := "res://src/levels/board_room/board_room.tscn"
const GAME_SCRIPT := "res://src/screens/game/game.gd"
const ENEMY_SET := "res://src/config/enemies/default.tres"

## Nodes board_room.tscn moves into the far wall. Every one must sit exactly one
## STRIDE north of where room.tscn puts it — the doorway is never opened, but
## [method Room._apply_doors] walks all four sides and a plug left behind in the
## middle of the floor is a chunk of wall standing in the open.
const MOVED_NORTH: Array[String] = [
	"wall_north_west",
	"wall_north_east",
	"plug_north",
	"door_north",
	"door_north_open",
	"door_north_shut",
]

## How finely the table is sampled when checking the circles cover it.
const COVER_STEP := 4.0
## Slack on top of a body's radius when asking whether a seat is clear of the
## table. A suit sitting exactly tangent to it is a suit shoved out of its chair
## on the first physics frame.
const SEAT_SLACK := 6.0

var _failures: Array[String] = []


func _initialize() -> void:
	print("\n=== the Basement ===\n")

	var room_source := _read(ROOM_SCRIPT)
	var board_source := _read(BOARD_SCRIPT)
	var stride: Variant = _parse_vector(room_source, "STRIDE")
	var room_floor: Variant = _parse_rect(room_source, "FLOOR")
	if stride == null or room_floor == null:
		_fail("could not read STRIDE and FLOOR out of %s" % ROOM_SCRIPT)
		_report()
		return

	_check_plan()
	_check_scene_offsets(stride)
	_check_side_walls(stride)
	var table := _check_table(board_source)
	_check_seats(board_source, table, _extended(room_floor, stride))
	_check_cast(board_source)

	_report()


## Two rooms, connected, with the board room's overhang left empty.
func _check_plan() -> void:
	var plan := BasementPlan.build()

	if plan.size() != 2:
		_fail("the Basement has %d rooms, and is meant to have 2" % plan.size())
	if plan.spawn_coord != BasementPlan.ARRIVAL:
		_fail("the lift puts the player down at %v, not at ARRIVAL %v"
				% [plan.spawn_coord, BasementPlan.ARRIVAL])

	var arrival := plan.get_room(BasementPlan.ARRIVAL)
	var board := plan.get_room(BasementPlan.BOARD_ROOM)
	if arrival == null or board == null:
		_fail("the plan is missing ARRIVAL or BOARD_ROOM")
		return

	if arrival.kind != RoomData.Kind.SPAWN:
		_fail("the arrival cell is kind %d, not SPAWN" % arrival.kind)
	# BOSS, and it has to be: everything that ends the game hangs off Game
	# stocking a boss room and counting its dead. A board room of some other kind
	# is a board room the player can clear without winning.
	if board.kind != RoomData.Kind.BOSS:
		_fail("the board room is kind %d, not BOSS — the ending will never fire" % board.kind)

	# One doorway each. The arrival cell is meant to be a blank room with a single
	# way on, and the board room is drawn around being entered from its short end.
	if not arrival.is_dead_end():
		_fail("the arrival cell has %d doors, and is meant to have one" % arrival.door_count())
	if not board.is_dead_end():
		_fail("the board room has %d doors, and is meant to have one" % board.door_count())
	if not arrival.has_door(GridDirection.Side.NORTH):
		_fail("the arrival cell's doorway is not on its north wall")
	if not board.has_door(GridDirection.Side.SOUTH):
		_fail("the board room is not entered from the south, which is the end it is drawn for")

	# The whole trick, and the one thing about this floor that is not obvious from
	# looking at it: the board room stands in BOARD_ROOM and DRAWS into the cell
	# above. Put a room there and the two are painted on top of each other.
	var above: Vector2i = BasementPlan.BOARD_ROOM + GridDirection.offset(GridDirection.Side.NORTH)
	if BasementPlan.OVERHANG != above:
		_fail("OVERHANG is %v but the board room overhangs %v" % [BasementPlan.OVERHANG, above])
	if plan.has_room(BasementPlan.OVERHANG):
		_fail("something is standing in %v, which is where the board room's far half is drawn"
				% BasementPlan.OVERHANG)

	print("  plan: %d rooms, arrival at %v, board room at %v, overhang %v clear"
			% [plan.size(), BasementPlan.ARRIVAL, BasementPlan.BOARD_ROOM, BasementPlan.OVERHANG])


## Every node board_room.tscn lifts into the far wall sits exactly one STRIDE
## above room.tscn's copy of it, and the second background is one STRIDE above
## the first.
func _check_scene_offsets(stride: Vector2) -> void:
	var room_scene := _read(ROOM_SCENE)
	var board_scene := _read(BOARD_SCENE)
	var lift := Vector2(0.0, -stride.y)

	for node_name in MOVED_NORTH:
		var base: Variant = _parse_node_position(room_scene, node_name)
		var moved: Variant = _parse_node_position(board_scene, node_name)
		if base == null:
			_fail("could not find %s in %s" % [node_name, ROOM_SCENE])
			continue
		if moved == null:
			_fail("board_room.tscn does not move %s into the far wall" % node_name)
			continue
		if moved != base + lift:
			_fail("%s is at %v in the board room; one STRIDE above room.tscn is %v"
					% [node_name, moved, base + lift])

	var background: Variant = _parse_node_position(room_scene, "background")
	var north: Variant = _parse_node_position(board_scene, "background_north")
	if background == null or north == null:
		_fail("could not compare the two backgrounds")
	elif north != background + lift:
		_fail("background_north is at %v; one STRIDE above the inherited background is %v"
				% [north, background + lift])

	print("  scene: %d nodes lifted one STRIDE (%.0fpx) into the far wall"
			% [MOVED_NORTH.size(), stride.y])


## The side walls of the half the shell never had meet the ones it did, with no
## gap for the player to walk out of the room through.
func _check_side_walls(stride: Vector2) -> void:
	var room_scene := _read(ROOM_SCENE)
	var board_scene := _read(BOARD_SCENE)

	var inherited: Variant = _parse_shape_size(room_scene, "RectangleShape2D_wall_v")
	var far: Variant = _parse_shape_size(board_scene, "RectangleShape2D_wall_far")
	if inherited == null or far == null:
		_fail("could not read the side wall shapes")
		return

	# The far shape has to reach from the north wall down to the top of the
	# inherited pair. One shape rather than two, because there is no doorway up
	# there to leave a gap for — so its length is the whole overhang.
	if not is_equal_approx(far.y, stride.y):
		_fail("the far side walls are %.1fpx long; the overhang is %.0fpx" % [far.y, stride.y])

	for side in ["west", "east"]:
		var base: Variant = _parse_node_position(room_scene, "wall_%s_north" % side)
		var extra: Variant = _parse_node_position(board_scene, "wall_%s_far" % side)
		if base == null or extra == null:
			_fail("could not find the %s side walls" % side)
			continue
		if not is_equal_approx(extra.x, base.x):
			_fail("wall_%s_far is at x %.1f, the wall it continues is at x %.1f"
					% [side, extra.x, base.x])
		var joins_at: float = extra.y + far.y * 0.5
		var inherited_top: float = base.y - inherited.y * 0.5
		if not is_equal_approx(joins_at, inherited_top):
			_fail("wall_%s_far ends at y %.1f and the wall below it starts at y %.1f — %.1fpx of open wall"
					% [side, joins_at, inherited_top, absf(inherited_top - joins_at)])

	print("  walls: the far half is closed on both sides, flush with the near half")


## The circles [method BoardRoom.register_solids] hands the enemy AI actually
## cover the table the scene draws.
##
## This is the claim in that method's docstring, and it is the one worth testing:
## the radius and the step are a pair, and a table made longer by dragging its
## ColorRect leaves a hole for six men in suits to walk through the middle of.
func _check_table(board_source: String) -> ObstacleField:
	var field := ObstacleField.new()
	var centre: Variant = _parse_vector(board_source, "TABLE_CENTRE")
	var size: Variant = _parse_vector(board_source, "TABLE_SIZE")
	var radius: Variant = _parse_float(board_source, "TABLE_SOLID_RADIUS")
	var step: Variant = _parse_float(board_source, "TABLE_SOLID_STEP")
	var count: Variant = _parse_float(board_source, "TABLE_SOLID_COUNT")
	if centre == null or size == null or radius == null or step == null or count == null:
		_fail("could not read the table out of %s" % BOARD_SCRIPT)
		return field

	var circles := int(count)
	var first: float = centre.y - (circles - 1) * step * 0.5
	for i in circles:
		field.add(Vector2(centre.x, first + i * step), radius)

	# The scene's rectangle and the script's constants must agree, or the circles
	# cover something that is not where the table is drawn.
	var shape: Variant = _parse_shape_size(_read(BOARD_SCENE), "RectangleShape2D_table")
	var body: Variant = _parse_node_position(_read(BOARD_SCENE), "Table")
	if shape != null and shape != size:
		_fail("the table collides as %v and BoardRoom.TABLE_SIZE says %v" % [shape, size])
	if body != null and body != centre:
		_fail("the table stands at %v and BoardRoom.TABLE_CENTRE says %v" % [body, centre])

	var rect := Rect2(centre - size * 0.5, size)
	var holes := 0
	var y: float = rect.position.y
	while y <= rect.end.y:
		var x: float = rect.position.x
		while x <= rect.end.x:
			if field.is_clear(Vector2(x, y), 0.0):
				holes += 1
			x += COVER_STEP
		y += COVER_STEP
	if holes > 0:
		_fail("%d points on the table are not covered by any of its %d circles — "
				% [holes, circles] + "radius %.0f and step %.0f do not overlap" % [radius, step])

	print("  table: %d circles of r=%.0f cover all %v of it" % [circles, radius, size])
	return field


## Six seats, all of them on the floor, none of them inside the table, and none
## of them in the player's lap.
func _check_seats(board_source: String, table: ObstacleField, floor_rect: Rect2) -> void:
	var seats := _parse_vector_array(board_source, "SEATS")
	var arrival: Variant = _parse_vector(board_source, "ARRIVAL_SPOT")
	if seats.is_empty():
		_fail("could not read BoardRoom.SEATS out of %s" % BOARD_SCRIPT)
		return
	if arrival == null:
		_fail("could not read BoardRoom.ARRIVAL_SPOT out of %s" % BOARD_SCRIPT)
		return

	var suit := _suit()
	var body: float = EnemyPlacement.MAX_AGENT_RADIUS if suit == null else suit.body_radius
	var standing := floor_rect.grow(-(body + EnemyPlacement.SPAWN_MARGIN))

	for i in seats.size():
		var seat: Vector2 = seats[i]
		if not standing.has_point(seat):
			_fail("seat %d at %v is outside the room — the floor a body may stand in is %s"
					% [i, seat, standing])
		if not table.is_clear(seat, body + SEAT_SLACK):
			_fail("seat %d at %v is inside the table" % [i, seat])

	# Where the player is put down if they arrive without a door. Not tested
	# against the doorway landing, which is the way they actually get here — that
	# one is room.tscn's and unchanged — but against the fallback, which is the
	# one this room had to override because FLOOR's centre is now under the table.
	if not floor_rect.has_point(arrival):
		_fail("ARRIVAL_SPOT %v is not on the floor" % arrival)
	if not table.is_clear(arrival, body):
		_fail("ARRIVAL_SPOT %v is inside the table" % arrival)

	var nearest := INF
	for seat in seats:
		nearest = minf(nearest, arrival.distance_to(seat))
	if nearest < EnemyPlacement.MIN_PLAYER_DISTANCE:
		_fail("the nearest suit is %.0fpx from where the player walks in; every other room "
				% nearest + "in the game keeps them %.0fpx back" % EnemyPlacement.MIN_PLAYER_DISTANCE)

	print("  seats: %d, all clear of the table, nearest %.0fpx from the door"
			% [seats.size(), nearest])


## There are as many men in suits as there are chairs for them, and the shipped
## bestiary still has the one the room is written around.
func _check_cast(board_source: String) -> void:
	var game_source := _read(GAME_SCRIPT)
	var wanted: Variant = _parse_float(game_source, "basement_suit_count")
	var seats := _parse_vector_array(board_source, "SEATS")
	if wanted == null:
		_fail("could not read basement_suit_count out of %s" % GAME_SCRIPT)
		return

	var count := int(wanted)
	# Not fatal — Game falls back to the placement grid for anybody left standing
	# — but it means the room is no longer the picture it was drawn as.
	if count > seats.size():
		_fail("%d suits are stocked and the board room has %d seats, so %d of them "
				% [count, seats.size(), count - seats.size()]
				+ "will be scattered around the room instead of sat at the table")

	var suit := _suit()
	if suit == null:
		_fail("the shipped bestiary has no def with the id basement_suit_id names — "
				+ "the last fight will fall back to an ordinary draw")
		return
	print("  cast: %d x '%s' for %d seats" % [count, suit.id, seats.size()])


## The def Game will look up for the board room, out of the shipped bestiary.
func _suit() -> EnemyDef:
	var id := _parse_string_name(_read(GAME_SCRIPT), "basement_suit_id")
	if id.is_empty():
		return null
	var set: EnemySet = load(ENEMY_SET)
	return null if set == null else set.by_id(StringName(id))


## [constant Room.FLOOR] grown north by one cell, which is what
## [constant BoardRoom.FLOOR_EXTENDED] derives.
func _extended(floor_rect: Rect2, stride: Vector2) -> Rect2:
	return Rect2(floor_rect.position - Vector2(0.0, stride.y),
			floor_rect.size + Vector2(0.0, stride.y))


# -- Reading source as text ----------------------------------------------------


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("could not read %s" % path)
		return ""
	return file.get_as_text()


## `const NAME := Rect2(a, b, c, d)`
func _parse_rect(source: String, name: String) -> Variant:
	var regex := RegEx.create_from_string(
			name + r"\s*:?=\s*Rect2\(\s*([\d.-]+),\s*([\d.-]+),\s*([\d.-]+),\s*([\d.-]+)\s*\)")
	var found := regex.search(source)
	if found == null:
		return null
	return Rect2(found.get_string(1).to_float(), found.get_string(2).to_float(),
			found.get_string(3).to_float(), found.get_string(4).to_float())


## `const NAME := Vector2(x, y)`
func _parse_vector(source: String, name: String) -> Variant:
	var regex := RegEx.create_from_string(
			name + r"\s*:?=\s*Vector2\(\s*([\d.-]+),\s*([\d.-]+)\s*\)")
	var found := regex.search(source)
	if found == null:
		return null
	return Vector2(found.get_string(1).to_float(), found.get_string(2).to_float())


## `const NAME := 62.0`, or an @export with a type hint on it.
func _parse_float(source: String, name: String) -> Variant:
	var regex := RegEx.create_from_string(
			name + r"\s*(?::\s*(?:float|int)\s*)?:?=\s*([\d.-]+)")
	var found := regex.search(source)
	return null if found == null else found.get_string(1).to_float()


## `var name: StringName = &"guard"`
func _parse_string_name(source: String, name: String) -> String:
	var regex := RegEx.create_from_string(name + r"\s*(?::\s*StringName\s*)?:?=\s*&\"([^\"]*)\"")
	var found := regex.search(source)
	return "" if found == null else found.get_string(1)


## Every `Vector2(x, y)` in `const NAME: Array[Vector2] = [ ... ]`.
##
## Anchored on the `= [` rather than on the first bracket after the name, because
## the first bracket after the name is the one in the type hint.
func _parse_vector_array(source: String, name: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var block := RegEx.create_from_string(
			name + r"\s*(?::\s*Array\[Vector2\]\s*)?:?=\s*\[([^\]]*)\]")
	var found := block.search(source)
	if found == null:
		return out
	var pair := RegEx.create_from_string(r"Vector2\(\s*([\d.-]+),\s*([\d.-]+)\s*\)")
	for match in pair.search_all(found.get_string(1)):
		out.append(Vector2(match.get_string(1).to_float(), match.get_string(2).to_float()))
	return out


## The `position = Vector2(x, y)` line under a named node in a .tscn.
func _parse_node_position(source: String, node_name: String) -> Variant:
	var regex := RegEx.create_from_string(
			r'\[node name="' + node_name \
			+ r'"[^\]]*\][^\[]*?position = Vector2\(\s*([\d.-]+),\s*([\d.-]+)\s*\)')
	var found := regex.search(source)
	if found == null:
		return null
	return Vector2(found.get_string(1).to_float(), found.get_string(2).to_float())


## The `size = Vector2(x, y)` line under a named sub_resource in a .tscn.
func _parse_shape_size(source: String, id: String) -> Variant:
	var regex := RegEx.create_from_string(
			r'\[sub_resource[^\]]*id="' + id \
			+ r'"\][^\[]*?size = Vector2\(\s*([\d.-]+),\s*([\d.-]+)\s*\)')
	var found := regex.search(source)
	if found == null:
		return null
	return Vector2(found.get_string(1).to_float(), found.get_string(2).to_float())


# -- Reporting -----------------------------------------------------------------


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("\n✓ Basement OK — two rooms, a long board room, and six seats at the table\n")
		quit(0)
		return
	print("")
	print("-".repeat(70))
	print("  ✗ %d FAILURE(S):" % _failures.size())
	print("-".repeat(70))
	for failure in _failures:
		print("  %s" % failure)
	print("")
	quit(1)
