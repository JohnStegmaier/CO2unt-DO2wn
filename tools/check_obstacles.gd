extends SceneTree

## Prove that a room full of solid props is still a room you can walk across.
##
## Placement is deliberately pure logic — [ObstaclePlacement] owns no RNG and
## [ObstacleSet] makes no decisions — so where the furniture lands can be settled
## in a terminal instead of by walking into rooms until one traps you:
##
##   godot --headless --script tools/check_obstacles.gd
##
## The interesting part is the flood fill. ObstaclePlacement claims a room can
## never be walled off, and argues it from the grid arithmetic; this is where that
## claim is actually tested, against real layouts, for every door mask, with a body
## the size of the widest thing in the game. The arithmetic has been wrong before.
##
## Exits non-zero when an invariant breaks, so it can gate CI.

const OBSTACLE_SET := "res://src/config/obstacles/default.tres"

## Every seed is crossed with all 15 door masks, so this is 15x this many layouts,
## each flood-filled over ~4000 cells. Sized to stay a few seconds rather than a
## coffee break — the failures this catches are systematic, not rare.
const SEEDS := 60
## Coord range sampled. Negative on purpose — floors grow in all four directions
## from the origin, so obstacle seeding has to survive a negative coord.
const COORD_SPAN := 7

## The widest agent that has to fit anywhere the player can reach.
##
## Read off [EnemyPlacement] rather than written as a literal here. It was
## `4.0 * 1.7` — the one enemy scene's collider times game.gd's boss_size_scale —
## back when there was one enemy to measure. Enemies now come from a bestiary of
## [EnemyDef]s with bodies of their own, so the figure is a budget they spend
## rather than a fact about a scene, and a copy of it here would go stale the
## first time somebody widened a def. tools/check_enemies.gd asserts the whole
## catalogue fits inside it; this file is where that width is actually flooded
## for. Naming EnemyPlacement costs nothing — it is pure static maths under
## systems/ and names no autoload, which is the property this checker depends on.
const BOSS_RADIUS := EnemyPlacement.MAX_AGENT_RADIUS

## Flood-fill resolution. Well under the 13.6px gap a boss needs, so a passage
## cannot fall between samples.
const FILL_CELL := 4.0

## Copies of Room.FLOOR and the door landings.
##
## Copied rather than read off [Room], and that is not laziness. Naming Room here
## would compile room.gd, which compiles elevator.gd, which compiles player.gd,
## which names the AudioManager autoload — and `--script` starts no autoloads, so
## the whole checker would fail to load. That is precisely why check_floors.gd
## does not currently run.
##
## Copies drift, so _check_room_constants reads the real values out of the source
## files as text and fails if these disagree. Text, because parsing is the one way
## to look at room.gd without compiling it.
const FLOOR := Rect2(49, 49, 343, 187)

## Room's door node positions pulled inward by LevelDoor.spawn_inset, one per
## GridDirection.Side, in Side order: north, east, south, west.
const LANDINGS: Array[Vector2] = [
	Vector2(221, 57),
	Vector2(384, 143),
	Vector2(221, 228),
	Vector2(57, 143),
]

const ROOM_SCRIPT := "res://src/levels/room/room.gd"
const ROOM_SCENE := "res://src/levels/room/room.tscn"
const DOOR_SCRIPT := "res://src/components/level_door.gd"
## Door node names in room.tscn, in GridDirection.Side order.
const DOOR_NODES: Array[String] = ["door_north", "door_east", "door_south", "door_west"]
## Which way each door's landing is pulled, being the inward normal of that wall.
const INWARD: Array[Vector2] = [
	Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)
]

var _failures: Array[String] = []
var _layouts := 0
var _props := 0
var _histogram := {}
var _by_kind := {}


func _initialize() -> void:
	print("\n=== obstacle placement ===\n")

	var set: ObstacleSet = load(OBSTACLE_SET)
	if set == null:
		_fail("could not load %s" % OBSTACLE_SET)
		_report()
		return

	_check_room_constants()
	_check_catalogue(set)
	_check_room_kind_flags()
	_check_seeding()
	_check_layouts(set, "shipped")

	# And again at the ceiling. cluttered.cfg raises the count to the grid's cell
	# count, which is the density the connectivity guarantee is tightest at — a
	# profile must not be able to wall a room off that the shipped values cannot.
	var packed: ObstacleSet = set.duplicate()
	packed.count_min = 6
	packed.count_max = 6
	_check_layouts(packed, "cluttered")

	_report()


## The copies at the top of this file must still match the real thing.
##
## Read as text, never loaded: see the note on FLOOR. If room.tscn moves a door or
## room.gd resizes the floor, every clearance tested below would be measured
## against the wrong geometry and would keep passing — which is the worst kind of
## check to have.
func _check_room_constants() -> void:
	var room_source := _read(ROOM_SCRIPT)
	var floor_rect: Variant = _parse_rect(room_source, "FLOOR")
	if floor_rect == null:
		_fail("could not find Room.FLOOR in %s" % ROOM_SCRIPT)
	elif floor_rect != FLOOR:
		_fail("Room.FLOOR is %s, this checker assumes %s" % [floor_rect, FLOOR])

	var inset: Variant = _parse_float(_read(DOOR_SCRIPT), "spawn_inset")
	if inset == null:
		_fail("could not find LevelDoor.spawn_inset in %s" % DOOR_SCRIPT)
		return

	var scene_source := _read(ROOM_SCENE)
	for side in DOOR_NODES.size():
		var door: Variant = _parse_node_position(scene_source, DOOR_NODES[side])
		if door == null:
			_fail("could not find %s in %s" % [DOOR_NODES[side], ROOM_SCENE])
			continue
		var landing: Vector2 = door + INWARD[side] * float(inset)
		if landing != LANDINGS[side]:
			_fail("%s landing is %v, this checker assumes %v" \
					% [DOOR_NODES[side], landing, LANDINGS[side]])
	print("  room geometry matches: FLOOR %s, landings %s\n" % [FLOOR, LANDINGS])


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


## `@export var name: float = 22.0`, or a plain assignment.
func _parse_float(source: String, name: String) -> Variant:
	var regex := RegEx.create_from_string(name + r"\s*(?::\s*float\s*)?:?=\s*([\d.-]+)")
	var found := regex.search(source)
	return null if found == null else found.get_string(1).to_float()


## The `position = Vector2(x, y)` line under a named node in a .tscn.
func _parse_node_position(source: String, node_name: String) -> Variant:
	var regex := RegEx.create_from_string(
			r'\[node name="' + node_name \
			+ r'"[^\]]*\][^\[]*?position = Vector2\(\s*([\d.-]+),\s*([\d.-]+)\s*\)')
	var found := regex.search(source)
	if found == null:
		return null
	return Vector2(found.get_string(1).to_float(), found.get_string(2).to_float())


## Every prop must be inside the cap the connectivity proof is stated for, and
## must be able to hurt or explicitly refuse to.
func _check_catalogue(set: ObstacleSet) -> void:
	if set.defs.is_empty():
		_fail("catalogue is empty")
		return
	for def in set.defs:
		if def == null:
			_fail("catalogue has a null row")
			continue
		if def.texture == null:
			_fail("%s has no texture" % def.id)
		if def.body_radius <= 0.0:
			_fail("%s has body_radius %.1f" % [def.id, def.body_radius])
		if def.body_radius > ObstaclePlacement.MAX_BODY_RADIUS:
			_fail("%s body_radius %.1f exceeds MAX_BODY_RADIUS %.1f — the room " \
					% [def.id, def.body_radius, ObstaclePlacement.MAX_BODY_RADIUS] \
					+ "connectivity proof does not hold for it")
		if not def.indestructible and def.max_hp <= 0:
			_fail("%s is destructible with %d hp" % [def.id, def.max_hp])
		print("  %s" % def.describe())
	print("")


## ObstacleSet.room_kinds is a flag mask over RoomData.Kind, and nothing but this
## stops the two drifting apart. Same hazard collision_layers.gd warns about
## against project.godot, except this one is checkable.
func _check_room_kind_flags() -> void:
	var hint := ""
	for property in ObstacleSet.new().get_property_list():
		if property.name == "room_kinds":
			hint = property.hint_string
			break
	if hint.is_empty():
		_fail("ObstacleSet.room_kinds has no flag hint to check")
		return

	var flags := hint.split(",")
	var kinds := RoomData.Kind.keys()
	if flags.size() != kinds.size():
		_fail("room_kinds has %d flags, RoomData.Kind has %d" % [flags.size(), kinds.size()])
		return
	for i in kinds.size():
		if flags[i] != String(kinds[i]).to_lower():
			_fail("room_kinds flag %d is '%s', RoomData.Kind %d is '%s'" \
					% [i, flags[i], i, kinds[i]])
	print("  room_kinds flags match RoomData.Kind (%s)\n" % hint)


## The stream must be reproducible, must differ between neighbouring rooms, and
## must not collide with the loot stream — spawn_coord is always Vector2i.ZERO, so
## sharing game.gd's LOOT_SEED_SALT would make a floor's first room's furniture
## and its drops the same numbers.
func _check_seeding() -> void:
	const LOOT_SEED_SALT := 0x9E3779B9
	var seen := {}
	var collisions := 0
	for s in 50:
		var floor_seed: int = 1000 + s * 7919
		if ObstaclePlacement.seed_for(floor_seed, Vector2i.ZERO) == (floor_seed ^ LOOT_SEED_SALT):
			_fail("obstacle seed collides with the loot stream at floor_seed %d" % floor_seed)
		for x in range(-COORD_SPAN, COORD_SPAN):
			for y in range(-COORD_SPAN, COORD_SPAN):
				var coord := Vector2i(x, y)
				var value := ObstaclePlacement.seed_for(floor_seed, coord)
				if ObstaclePlacement.seed_for(floor_seed, coord) != value:
					_fail("seed_for is not a pure function at %v" % coord)
				var key := "%d:%d" % [floor_seed, value]
				if seen.has(key):
					collisions += 1
				seen[key] = true
	# Transposition is the collision that would actually bite — (2,3) and (3,2)
	# are both real coords on the same floor.
	for s in 20:
		var floor_seed: int = 500 + s * 104729
		for a in range(1, 6):
			for b in range(a + 1, 7):
				if ObstaclePlacement.seed_for(floor_seed, Vector2i(a, b)) \
						== ObstaclePlacement.seed_for(floor_seed, Vector2i(b, a)):
					_fail("seed_for(%d,%d) aliases its transpose" % [a, b])
	if collisions > 0:
		_fail("%d seed collisions across the sampled coord range" % collisions)
	print("  seeding: %d distinct room seeds, no transposition aliases\n" % seen.size())


func _check_layouts(set: ObstacleSet, label: String) -> void:
	var widest := set.max_body_radius()
	_layouts = 0
	_props = 0
	_histogram = {}
	_by_kind = {}

	for s in SEEDS:
		var floor_seed: int = 31 + s * 2654435761
		for doors in range(1, 16):
			var coord := Vector2i(s % COORD_SPAN - 3, (s / COORD_SPAN) % COORD_SPAN - 3)
			var keep_clear := _landings_for(doors)
			keep_clear.append(FLOOR.get_center())

			var rng := RandomNumberGenerator.new()
			rng.seed = ObstaclePlacement.seed_for(floor_seed, coord)
			var plans := ObstaclePlacement.points(FLOOR, set, keep_clear, rng)

			_layouts += 1
			_props += plans.size()
			_histogram[plans.size()] = _histogram.get(plans.size(), 0) + 1
			for plan in plans:
				var kind := String(plan.def.id)
				_by_kind[kind] = _by_kind.get(kind, 0) + 1

			_check_one(plans, keep_clear, doors, floor_seed, coord, set, widest)

	var mean := float(_props) / maxf(1.0, float(_layouts))
	print("  %s: %d layouts, %d props, %.2f per room" % [label, _layouts, _props, mean])
	var counts := _histogram.keys()
	counts.sort()
	for n in counts:
		print("    %d props: %d rooms" % [n, _histogram[n]])
	# An even split is what equal weights should give. A catalogue that has
	# quietly collapsed onto one prop still passes every geometric check above and
	# still makes every room look the same, so it is worth printing.
	var kinds := _by_kind.keys()
	kinds.sort()
	for kind in kinds:
		print("    %-8s %d (%.0f%%)" % [kind, _by_kind[kind],
				100.0 * float(_by_kind[kind]) / maxf(1.0, float(_props))])
	print("")


func _check_one(plans: Array[ObstaclePlan], keep_clear: Array[Vector2], doors: int,
		floor_seed: int, coord: Vector2i, set: ObstacleSet, widest: float) -> void:
	var where := "seed %d coord %v doors %d" % [floor_seed, coord, doors]

	if plans.size() > set.count_max:
		_fail("%s: %d props, count_max is %d" % [where, plans.size(), set.count_max])

	for plan in plans:
		# Inside the walls, measured from the prop's edge.
		var inside := FLOOR.grow(-plan.radius())
		if not inside.has_point(plan.position):
			_fail("%s: %s at %v pokes outside the floor" % [where, plan.def.id, plan.position])
		# Off every doorway and off the middle.
		for point in keep_clear:
			if plan.position.distance_to(point) < ObstaclePlacement.DOOR_CLEARANCE:
				_fail("%s: %s at %v is %.1f from a kept-clear point %v" \
						% [where, plan.def.id, plan.position,
						plan.position.distance_to(point), point])

	# Two props must always leave a body-sized gap between them. This is the rule
	# that stops a column of them becoming a wall.
	for i in plans.size():
		for j in range(i + 1, plans.size()):
			var gap: float = plans[i].position.distance_to(plans[j].position) \
					- plans[i].radius() - plans[j].radius()
			if gap < BOSS_RADIUS * 2.0:
				_fail("%s: %s and %s leave a %.1fpx gap, a boss needs %.1f" \
						% [where, plans[i].def.id, plans[j].def.id, gap, BOSS_RADIUS * 2.0])

	# Flooded once and shared: it is the expensive part, and both questions below
	# are about the same free space.
	var reached := _flood(plans)
	_check_connected(reached, where)
	_check_enemies_reachable(plans, reached, doors, where, floor_seed)

	# Reproducibility: the same room, entered again, must furnish identically.
	var again := RandomNumberGenerator.new()
	again.seed = ObstaclePlacement.seed_for(floor_seed, coord)
	var replay := ObstaclePlacement.points(FLOOR, set, keep_clear, again)
	if replay.size() != plans.size():
		_fail("%s: replayed to %d props, not %d" % [where, replay.size(), plans.size()])
		return
	for i in plans.size():
		if replay[i].position != plans[i].position or replay[i].def != plans[i].def:
			_fail("%s: prop %d replayed as %s at %v, was %s at %v" \
					% [where, i, replay[i].def.id, replay[i].position,
					plans[i].def.id, plans[i].position])


## Configuration-space flood fill: inflate every prop by the widest body in the
## game, then check the free space is one piece.
##
## Inflating is what makes this a test of "can a boss get through" rather than
## "is the centre of this cell inside a barrel", which would call a 4px slot a
## corridor. 4-connected, because a diagonal step through a corner is a passage
## no body can actually use.
func _check_connected(reached: Dictionary, where: String) -> void:
	# Every landing, not only the open ones: a layout that is only safe on the
	# doors this room happens to have is one generator change away from being
	# wrong, and checking all four costs nothing.
	for side in GridDirection.SIDES:
		if not reached.has(_key(LANDINGS[side])):
			_fail("%s: %s landing is walled off" % [where, GridDirection.side_name(side)])
	if not reached.has(_key(FLOOR.get_center())):
		_fail("%s: the middle of the room is walled off" % where)


## The one that would actually end a run: a boss penned behind indestructible
## rocks can never be reached or shot, enemies_remaining never falls to zero, the
## doors never unlock, and on floor 1 the boss gate is the only way down. The room
## being "connected" is not enough — the enemies have to be on the player's side
## of it.
func _check_enemies_reachable(plans: Array[ObstaclePlan], reached: Dictionary,
		doors: int, where: String, floor_seed: int) -> void:
	var field := ObstacleField.from_plans(plans)
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed
	var landings := _landings_for(doors)
	var spots := EnemyPlacement.points(FLOOR, 6, FLOOR.get_center(),
			landings, rng, field)

	for spot in spots:
		if not field.is_clear(spot, BOSS_RADIUS):
			_fail("%s: enemy spot %v is inside a prop" % [where, spot])
		elif not reached.has(_key(spot)):
			_fail("%s: enemy spot %v is cut off from the doors" % [where, spot])


## Reachable cells, keyed by grid coordinate, seeded from every landing and the
## room centre.
func _flood(plans: Array[ObstaclePlan]) -> Dictionary:
	var inflated := FLOOR.grow(-BOSS_RADIUS)
	var open := {}
	var frontier: Array[Vector2i] = []

	var seeds: Array[Vector2] = LANDINGS.duplicate()
	seeds.append(FLOOR.get_center())
	for seed_point in seeds:
		# Clamped: the west and north landings sit exactly on the inflated
		# boundary, and an unclamped seed would report every room disconnected.
		var start := seed_point.clamp(inflated.position, inflated.end)
		var cell := _key(start)
		if not open.has(cell) and _passable(cell, plans, inflated):
			open[cell] = true
			frontier.append(cell)

	const STEPS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in STEPS:
			var next: Vector2i = cell + step
			if open.has(next):
				continue
			if not _passable(next, plans, inflated):
				continue
			open[next] = true
			frontier.append(next)
	return open


## Conservative on purpose: a cell counts as blocked if its centre is within the
## prop's radius plus a body plus half a cell diagonal, so a passage is never
## reported wider than it is.
func _passable(cell: Vector2i, plans: Array[ObstaclePlan], inflated: Rect2) -> bool:
	var point := Vector2(cell) * FILL_CELL
	if not inflated.has_point(point):
		return false
	var slack := FILL_CELL * 0.5 * sqrt(2.0)
	for plan in plans:
		if point.distance_to(plan.position) < plan.radius() + BOSS_RADIUS + slack:
			return false
	return true


func _key(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x / FILL_CELL), roundi(point.y / FILL_CELL))


func _landings_for(doors: int) -> Array[Vector2]:
	var landings: Array[Vector2] = []
	for side in GridDirection.SIDES:
		if (doors & GridDirection.bit(side)) != 0:
			landings.append(LANDINGS[side])
	return landings


func _fail(message: String) -> void:
	# Capped: one broken constant fails every layout, and ten thousand identical
	# lines buries the one that differs.
	if _failures.size() < 40:
		_failures.append(message)
	elif _failures.size() == 40:
		_failures.append("... further failures suppressed")


func _report() -> void:
	if _failures.is_empty():
		print("✓ obstacles OK — every sampled room crossable by a boss\n")
		quit(0)
		return
	print("-".repeat(70))
	print("  ✗ %d FAILURE(S):" % _failures.size())
	print("-".repeat(70))
	for failure in _failures:
		print("  %s" % failure)
	print("")
	quit(1)
