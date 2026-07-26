extends SceneTree

## Generate a great many floors and assert every invariant FloorGenerator claims.
##
## The generator is deliberately pure logic, so its correctness can be settled in
## a terminal instead of by walking floors and hoping. Run it after touching
## floor_generator.gd or the FloorConfig defaults:
##
##   godot --headless --script tools/check_floors.gd
##
## Exits non-zero when an invariant breaks, so it can gate CI. It also prints
## shape statistics, which is the useful part when tuning: a floor that passes
## every invariant can still be a boring blob.

const SEEDS := 250
## Floor 0 is the first of a run. Later ones are checked too because room count
## grows with depth, and a bigger floor is a different shape problem. Stops at the
## Basement because a run does too — see FloorLadder.
const FLOOR_NUMBERS := [0, 1, 3, FloorLadder.BASEMENT_INDEX]


func _initialize() -> void:
	var config := FloorConfig.new()
	var failures: Array[String] = []
	var sizes: Array[int] = []
	var depths: Array[int] = []
	var dead_ends: Array[int] = []
	var exit_depths: Array[int] = []
	var checked := 0

	for floor_number in FLOOR_NUMBERS:
		for run_seed in SEEDS:
			var floor_seed: int = FloorGenerator.floor_seed_for(run_seed, floor_number)
			var plan := FloorGenerator.generate(config, floor_number, floor_seed)
			checked += 1

			var errors := _check(plan, config, floor_number, floor_seed)
			for error in errors:
				if failures.size() < 20:
					failures.append(error)

			sizes.append(plan.size())
			dead_ends.append(plan.dead_ends().size())
			depths.append(_max_depth(plan))
			var exit_coord: Vector2i = plan.coord_of_kind(RoomData.Kind.EXIT)
			if exit_coord != Vector2i.MAX:
				exit_depths.append(plan.get_room(exit_coord).depth)

	_report_determinism(config, failures)

	print("checked %d floors across floor numbers %s" % [checked, FLOOR_NUMBERS])
	print("  rooms      %s" % _stats(sizes))
	print("  max depth  %s" % _stats(depths))
	print("  dead ends  %s" % _stats(dead_ends))
	print("  exit depth %s" % _stats(exit_depths))
	print("")
	print("sample floor (floor 0, run seed 7):")
	print(FloorGenerator.generate(config, 0, FloorGenerator.floor_seed_for(7, 0)).to_ascii())

	if failures.is_empty():
		print("OK — every invariant held")
		quit(0)
		return

	print("FAILED — %d problems (first %d shown)" % [failures.size(), failures.size()])
	for failure in failures:
		print("  " + failure)
	quit(1)


## Every property the generator's doc comment promises, checked against a real
## floor. Returns one string per violation.
func _check(plan: FloorPlan, config: FloorConfig, floor_number: int, floor_seed: int) -> Array[String]:
	var errors: Array[String] = []
	var tag := "floor %d / seed %d" % [floor_number, floor_seed]

	var spawn: RoomData = plan.get_room(plan.spawn_coord)
	if spawn == null:
		errors.append("%s: no room at the spawn coordinate" % tag)
		return errors
	if spawn.kind != RoomData.Kind.SPAWN:
		errors.append("%s: spawn room is kind %s" % [tag, _kind_name(spawn.kind)])
	if spawn.door_count() != 4:
		errors.append("%s: spawn has %d doors, the brief requires all four" % [tag, spawn.door_count()])

	for coord in plan.rooms:
		if plan.get_room(coord).coord != coord:
			errors.append("%s: room filed at %v thinks it is at %v" % [tag, coord, plan.get_room(coord).coord])

	errors.append_array(_check_doors(plan, tag))
	errors.append_array(_check_reachability(plan, config, tag))
	errors.append_array(_check_specials(plan, config, tag))
	return errors


## Doors come in symmetric pairs, and the pair count proves the floor is a tree.
func _check_doors(plan: FloorPlan, tag: String) -> Array[String]:
	var errors: Array[String] = []
	var edges := 0

	for coord in plan.rooms:
		for side in GridDirection.SIDES:
			if not plan.get_room(coord).has_door(side):
				continue
			# Counted only from a pair's west or north end, so each connection is
			# tallied exactly once and there is no halving to get wrong. Sound
			# because the symmetry check below would have caught a lone half.
			if side == GridDirection.Side.EAST or side == GridDirection.Side.SOUTH:
				edges += 1
			var neighbour: Vector2i = coord + GridDirection.offset(side)
			if not plan.has_room(neighbour):
				errors.append("%s: %v has a %s door onto an empty cell" % [tag, coord, GridDirection.side_name(side)])
			elif not plan.get_room(neighbour).has_door(GridDirection.opposite(side)):
				errors.append("%s: the door %v -> %v is one-way" % [tag, coord, neighbour])

	# A connected graph with exactly one fewer edge than vertices is a tree, so
	# this single comparison is the no-loops check. Connectivity is proven below.
	if edges != plan.size() - 1:
		errors.append("%s: %d rooms joined by %d door pairs — a tree needs %d, so the floor loops or is split" \
				% [tag, plan.size(), edges, plan.size() - 1])
	return errors


## Every room reachable from spawn, and the depth each room recorded is the real
## distance — the generator sets depth while growing, so it could drift.
func _check_reachability(plan: FloorPlan, config: FloorConfig, tag: String) -> Array[String]:
	var errors: Array[String] = []
	var distance := {plan.spawn_coord: 0}
	var queue: Array[Vector2i] = [plan.spawn_coord]

	while not queue.is_empty():
		var coord: Vector2i = queue.pop_front()
		for side in GridDirection.SIDES:
			if not plan.get_room(coord).has_door(side):
				continue
			var neighbour: Vector2i = coord + GridDirection.offset(side)
			if not plan.has_room(neighbour) or distance.has(neighbour):
				continue
			distance[neighbour] = int(distance[coord]) + 1
			queue.append(neighbour)

	if distance.size() != plan.size():
		errors.append("%s: %d of %d rooms cannot be walked to from spawn" \
				% [tag, plan.size() - distance.size(), plan.size()])

	for coord in distance:
		var walked: int = distance[coord]
		var recorded: int = plan.get_room(coord).depth
		if recorded != walked:
			errors.append("%s: %v records depth %d but is %d rooms from spawn" % [tag, coord, recorded, walked])
		if walked > config.max_depth:
			errors.append("%s: %v is %d rooms from spawn, past the cap of %d" % [tag, coord, walked, config.max_depth])
	return errors


## One of each special, each at a dead end, each far enough from spawn.
func _check_specials(plan: FloorPlan, config: FloorConfig, tag: String) -> Array[String]:
	var errors: Array[String] = []

	for kind in FloorGenerator.SPECIAL_ORDER:
		var found: Array[Vector2i] = []
		for coord in plan.rooms:
			if plan.get_room(coord).kind == kind:
				found.append(coord)
		if found.size() != 1:
			errors.append("%s: %d %s rooms, expected exactly 1" % [tag, found.size(), _kind_name(kind)])
			continue

		var data: RoomData = plan.get_room(found[0])
		if not data.is_dead_end():
			errors.append("%s: the %s room at %v has %d doors, so it is a corridor" \
					% [tag, _kind_name(kind), data.coord, data.door_count()])
		var floor_for_kind: int = config.exit_min_depth if kind == RoomData.Kind.EXIT else config.special_min_depth
		if data.depth < floor_for_kind:
			errors.append("%s: the %s room is %d rooms from spawn, closer than the %d allowed" \
					% [tag, _kind_name(kind), data.depth, floor_for_kind])
	return errors


## The same seed must produce the same floor, or a reported seed is worthless for
## reproducing a layout someone complained about.
func _report_determinism(config: FloorConfig, failures: Array[String]) -> void:
	for run_seed in 25:
		var floor_seed: int = FloorGenerator.floor_seed_for(run_seed, 2)
		var first := FloorGenerator.generate(config, 2, floor_seed).to_ascii()
		var second := FloorGenerator.generate(config, 2, floor_seed).to_ascii()
		if first != second and failures.size() < 20:
			failures.append("seed %d generated two different floors" % floor_seed)


func _max_depth(plan: FloorPlan) -> int:
	var deepest := 0
	for coord in plan.rooms:
		deepest = maxi(deepest, plan.get_room(coord).depth)
	return deepest


func _stats(values: Array[int]) -> String:
	if values.is_empty():
		return "(none)"
	var total := 0
	var lowest: int = values[0]
	var highest: int = values[0]
	for value in values:
		total += value
		lowest = mini(lowest, value)
		highest = maxi(highest, value)
	return "min %d  mean %.1f  max %d" % [lowest, float(total) / values.size(), highest]


func _kind_name(kind: int) -> String:
	return RoomData.Kind.keys()[kind]
