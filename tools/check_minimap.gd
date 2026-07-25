extends SceneTree

## Walk a great many floors and assert the minimap never shows more than it should.
##
## MinimapModel is deliberately pure logic for this reason: whether the fog is
## correct is a question about a dictionary, not about pixels, so it can be
## settled in a terminal instead of by playing until a boss room gives itself
## away. Run it after touching minimap_model.gd:
##
##   godot --headless --script tools/check_minimap.gd
##
## Exits non-zero when an invariant breaks. It also prints how much of a floor a
## player has actually seen by the time they reach the exit, which is the useful
## part when tuning: fog that passes every invariant can still reveal so little
## that the map is useless, or so much that exploring is pointless.

const SEEDS := 250
const FLOOR_NUMBERS := [0, 1, 3, 6]
## Steps of the random walk per floor. Comfortably longer than any floor is
## wide, so the walk doubles back over ground it has already covered.
const WALK_STEPS := 40
## The grid the widget draws, from minimap_style.gd. Asserted here because
## "the whole floor is always visible" is a promise about the generator's
## max_depth, and this is where that promise gets checked.
const WINDOW_CELLS := Vector2i(13, 13)
## Arriving through a door whose far side is already visited, a room can reveal
## at most its other three neighbours.
const MAX_REVEALED_PER_STEP := 3

## Fog states as single characters, indexed by MinimapModel.State.
const STATE_GLYPHS: Array[String] = [" ", "?", "o", "@"]


func _initialize() -> void:
	var config := FloorConfig.new()
	var failures: Array[String] = []
	var seen_after: Dictionary[int, Array] = {1: [], 3: [], 6: []}
	var exit_fractions: Array[float] = []
	var widest := Vector2i.ZERO
	var checked := 0

	for floor_number in FLOOR_NUMBERS:
		for run_seed in SEEDS:
			var floor_seed: int = FloorGenerator.floor_seed_for(run_seed, floor_number)
			var plan := FloorGenerator.generate(config, floor_number, floor_seed)
			checked += 1

			var bounds := plan.bounds()
			widest = Vector2i(maxi(widest.x, bounds.size.x), maxi(widest.y, bounds.size.y))

			for error in _check_floor(plan, floor_seed, seen_after):
				if failures.size() < 20:
					failures.append(error)

			# Fresh plan: the walk above dirtied visited on the one it was given.
			var clean := FloorGenerator.generate(config, floor_number, floor_seed)
			exit_fractions.append(_fraction_seen_reaching_exit(clean))

	for error in _check_blank_and_stray():
		if failures.size() < 20:
			failures.append(error)

	print("checked %d floors across floor numbers %s" % [checked, FLOOR_NUMBERS])
	print("  cells seen after 1 room   %s" % _stats(seen_after[1]))
	print("  cells seen after 3 rooms  %s" % _stats(seen_after[3]))
	print("  cells seen after 6 rooms  %s" % _stats(seen_after[6]))
	print("  floor seen at the exit    %s%%" % _stats_float(exit_fractions, 100.0))
	print("  widest floor              %d x %d (the map draws %d x %d)" \
			% [widest.x, widest.y, WINDOW_CELLS.x, WINDOW_CELLS.y])
	print("")
	print("sample fog (floor 0, run seed 7, six rooms walked):")
	print(_sample_fog(config))

	if failures.is_empty():
		print("OK — the fog held")
		quit(0)
		return

	print("FAILED — %d problems (first %d shown)" % [failures.size(), failures.size()])
	for failure in failures:
		print("  " + failure)
	quit(1)


## Spawn in, then walk the floor at random, re-checking every fog rule at every
## step. Mutates the plan's visited flags exactly as Game._enter_room does.
func _check_floor(plan: FloorPlan, floor_seed: int, seen_after: Dictionary[int, Array]) -> Array[String]:
	var errors: Array[String] = []
	var tag := "seed %d" % floor_seed
	var model := MinimapModel.new()

	if plan.bounds().size.x > WINDOW_CELLS.x or plan.bounds().size.y > WINDOW_CELLS.y:
		errors.append("%s: floor is %v cells, wider than the %v the map draws" \
				% [tag, plan.bounds().size, WINDOW_CELLS])

	var coord: Vector2i = plan.spawn_coord
	plan.get_room(coord).visited = true
	model.set_floor(plan)
	model.set_current(coord)

	# The spawn room has all four doors, so a run opens on itself plus four
	# unexplored neighbours and nothing else.
	if plan.get_room(coord).door_count() != 4:
		errors.append("%s: spawn has %d doors, so the opening fog check is meaningless" \
				% [tag, plan.get_room(coord).door_count()])
	elif model.visible_count() != 5:
		errors.append("%s: a run opens showing %d cells, expected spawn plus its four neighbours" \
				% [tag, model.visible_count()])
	for side in GridDirection.SIDES:
		var neighbour: Vector2i = coord + GridDirection.offset(side)
		if model.state_at(neighbour) != MinimapModel.State.DISCOVERED:
			errors.append("%s: %s of spawn is %s at the start, expected DISCOVERED" \
					% [tag, GridDirection.side_name(side), _state_name(model.state_at(neighbour))])

	errors.append_array(_check_states(model, plan, coord, tag + " / step 0"))

	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed
	var previous_count: int = model.visible_count()

	for step in range(1, WALK_STEPS + 1):
		var sides: Array[int] = plan.get_room(coord).door_sides()
		var side: int = sides[rng.randi_range(0, sides.size() - 1)]
		coord += GridDirection.offset(side)
		plan.get_room(coord).visited = true
		model.set_current(coord)

		var count: int = model.visible_count()
		if count < previous_count:
			errors.append("%s / step %d: the map lost cells, %d down to %d" \
					% [tag, step, previous_count, count])
		if count - previous_count > MAX_REVEALED_PER_STEP:
			errors.append("%s / step %d: one room revealed %d cells, at most %d can be new" \
					% [tag, step, count - previous_count, MAX_REVEALED_PER_STEP])
		previous_count = count

		if seen_after.has(step):
			seen_after[step].append(count)

		errors.append_array(_check_states(model, plan, coord, "%s / step %d" % [tag, step]))

	errors.append_array(_check_reveal(model, plan, coord, tag))
	return errors


## The rules that must hold whatever the player has walked: nothing invented,
## nothing hidden that was earned, and nothing disclosed that was not.
func _check_states(model: MinimapModel, plan: FloorPlan, current: Vector2i, tag: String) -> Array[String]:
	var errors: Array[String] = []
	var currents := 0

	for coord in model.visible_coords():
		# Pins the fog to the generator's "a door never opens onto an empty
		# cell" invariant. If that ever breaks, the map would draw rooms that do
		# not exist, and this is where it gets caught.
		if not plan.has_room(coord):
			errors.append("%s: %v is on the map but there is no room there" % [tag, coord])
			continue

		var state: int = model.state_at(coord)
		var data: RoomData = plan.get_room(coord)

		match state:
			MinimapModel.State.CURRENT:
				currents += 1
				if coord != current:
					errors.append("%s: %v is drawn as the current room but the player is at %v" \
							% [tag, coord, current])
			MinimapModel.State.VISITED:
				if not data.visited:
					errors.append("%s: %v is drawn as visited but was never entered" % [tag, coord])
				if coord == current:
					errors.append("%s: the player's own room %v is not drawn as current" % [tag, coord])
			MinimapModel.State.DISCOVERED:
				if data.visited:
					errors.append("%s: %v was entered but is still drawn as unexplored" % [tag, coord])
				if not _touches_visited(plan, coord):
					errors.append("%s: %v is on the map without a door to anywhere the player has been" \
							% [tag, coord])
				# The whole point of the fog: an unexplored room gives nothing away.
				if model.marker_at(coord) != MinimapModel.NO_MARKER:
					errors.append("%s: unexplored %v discloses that it is a %s room" \
							% [tag, coord, _kind_name(data.kind)])
				if model.door_mask_at(coord) != 0:
					errors.append("%s: unexplored %v discloses its doors" % [tag, coord])
			_:
				errors.append("%s: %v is on the map in state %s" % [tag, coord, _state_name(state)])

	if currents != 1:
		errors.append("%s: %d rooms drawn as current, expected exactly 1" % [tag, currents])

	for coord in plan.rooms:
		var state: int = model.state_at(coord)
		var data: RoomData = plan.get_room(coord)
		if data.visited and state == MinimapModel.State.UNKNOWN:
			errors.append("%s: %v was entered but is missing from the map" % [tag, coord])
		if state == MinimapModel.State.UNKNOWN:
			if _touches_visited(plan, coord):
				errors.append("%s: %v has a door to somewhere the player has been but is not on the map" \
						% [tag, coord])
			if model.marker_at(coord) != MinimapModel.NO_MARKER:
				errors.append("%s: hidden %v discloses that it is a %s room" % [tag, coord, _kind_name(data.kind)])

	return errors


## The dev reveal shows everything, and turning it back off restores the exact
## fog it interrupted — a debug toggle that quietly rewrote the player's map
## would be worse than no toggle.
func _check_reveal(model: MinimapModel, plan: FloorPlan, current: Vector2i, tag: String) -> Array[String]:
	var errors: Array[String] = []
	var before: Dictionary[Vector2i, int] = {}
	for coord in model.visible_coords():
		before[coord] = model.state_at(coord)

	model.set_reveal_all(true)
	if not model.is_revealing_all():
		errors.append("%s: reveal was switched on and did not take" % tag)
	if model.visible_count() != plan.size():
		errors.append("%s: reveal shows %d of %d rooms" % [tag, model.visible_count(), plan.size()])

	var currents := 0
	for coord in plan.rooms:
		var state: int = model.state_at(coord)
		if state == MinimapModel.State.CURRENT:
			currents += 1
		elif state != MinimapModel.State.VISITED:
			errors.append("%s: revealed %v is %s" % [tag, coord, _state_name(state)])
		if model.marker_at(coord) != plan.get_room(coord).kind:
			errors.append("%s: revealed %v does not report its kind" % [tag, coord])
	if currents != 1:
		errors.append("%s: %d current rooms while revealing, expected 1" % [tag, currents])

	model.set_reveal_all(false)
	if model.visible_count() != before.size():
		errors.append("%s: the fog came back as %d cells, was %d before the reveal" \
				% [tag, model.visible_count(), before.size()])
	for coord in before:
		if model.state_at(coord) != before[coord]:
			errors.append("%s: %v came back from the reveal as %s, was %s" \
					% [tag, coord, _state_name(model.state_at(coord)), _state_name(before[coord])])

	# A floor swap is not a reason to lose the dev flag — the runtime rebuilds
	# the model on every descent.
	model.set_reveal_all(true)
	model.set_floor(plan)
	if not model.is_revealing_all() or model.visible_count() != plan.size():
		errors.append("%s: the reveal did not survive a floor change" % tag)
	model.set_reveal_all(false)
	model.set_current(current)
	return errors


## The two states the runtime puts the model in that no floor walk covers: the
## map blanked while a floor is thrown away, and a coordinate off the plan.
func _check_blank_and_stray() -> Array[String]:
	var errors: Array[String] = []
	var config := FloorConfig.new()
	var plan := FloorGenerator.generate(config, 0, FloorGenerator.floor_seed_for(1, 0))
	var model := MinimapModel.new()

	plan.get_room(plan.spawn_coord).visited = true
	model.set_floor(plan)
	model.set_current(plan.spawn_coord)

	model.set_floor(null)
	if model.visible_count() != 0:
		errors.append("blanked: %d cells still on the map" % model.visible_count())
	if model.state_at(Vector2i.ZERO) != MinimapModel.State.UNKNOWN:
		errors.append("blanked: spawn still reports a state")
	if model.marker_at(Vector2i.ZERO) != MinimapModel.NO_MARKER:
		errors.append("blanked: spawn still reports a kind")
	if model.door_mask_at(Vector2i.ZERO) != 0:
		errors.append("blanked: spawn still reports doors")
	if model.origin_coord() != Vector2i.ZERO:
		errors.append("blanked: origin is %v, expected the fallback" % model.origin_coord())

	model.set_floor(plan)
	model.set_current(Vector2i(999, 999))
	for coord in plan.rooms:
		if model.state_at(coord) == MinimapModel.State.CURRENT:
			errors.append("stray: %v drawn as current while the player is off the plan" % coord)
	if model.marker_at(Vector2i(999, 999)) != MinimapModel.NO_MARKER:
		errors.append("stray: a coordinate off the plan reports a kind")
	return errors


func _touches_visited(plan: FloorPlan, coord: Vector2i) -> bool:
	if not plan.has_room(coord):
		return false
	for side in GridDirection.SIDES:
		if not plan.get_room(coord).has_door(side):
			continue
		var neighbour: Vector2i = coord + GridDirection.offset(side)
		if plan.has_room(neighbour) and plan.get_room(neighbour).visited:
			return true
	return false


## How much of the floor a player has seen by the time they walk the shortest
## route to the exit. The tuning number: too low and the map is useless, too
## high and there is nothing left to explore.
func _fraction_seen_reaching_exit(plan: FloorPlan) -> float:
	var exit_coord: Vector2i = plan.coord_of_kind(RoomData.Kind.EXIT)
	if exit_coord == Vector2i.MAX:
		return 0.0

	var model := MinimapModel.new()
	model.set_floor(plan)
	for coord in _route_to(plan, exit_coord):
		plan.get_room(coord).visited = true
		model.set_current(coord)
	return float(model.visible_count()) / float(plan.size())


## Shortest route from spawn to a target, spawn first. The floor is a tree, so
## this is the only route.
func _route_to(plan: FloorPlan, target: Vector2i) -> Array[Vector2i]:
	var parents: Dictionary[Vector2i, Vector2i] = {plan.spawn_coord: plan.spawn_coord}
	var queue: Array[Vector2i] = [plan.spawn_coord]

	while not queue.is_empty():
		var coord: Vector2i = queue.pop_front()
		if coord == target:
			break
		for side in GridDirection.SIDES:
			if not plan.get_room(coord).has_door(side):
				continue
			var neighbour: Vector2i = coord + GridDirection.offset(side)
			if not plan.has_room(neighbour) or parents.has(neighbour):
				continue
			parents[neighbour] = coord
			queue.append(neighbour)

	if not parents.has(target):
		return []

	var route: Array[Vector2i] = []
	var walk: Vector2i = target
	while walk != plan.spawn_coord:
		route.push_front(walk)
		walk = parents[walk]
	route.push_front(plan.spawn_coord)
	return route


## The fog as text, the way FloorPlan.to_ascii() dumps a floor. Lives here rather
## than on the model because it is a debugging convenience, and the model is not
## in the business of presenting anything.
func _sample_fog(config: FloorConfig) -> String:
	var plan := FloorGenerator.generate(config, 0, FloorGenerator.floor_seed_for(7, 0))
	var model := MinimapModel.new()
	var coord: Vector2i = plan.spawn_coord
	plan.get_room(coord).visited = true
	model.set_floor(plan)
	model.set_current(coord)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for step in 6:
		var sides: Array[int] = plan.get_room(coord).door_sides()
		coord += GridDirection.offset(sides[rng.randi_range(0, sides.size() - 1)])
		plan.get_room(coord).visited = true
		model.set_current(coord)

	# Deliberately drawn over the whole floor, not just the visible part, so a
	# leak shows up as a glyph where there should be a blank.
	var rect := plan.bounds()
	var out := "  @ here   o explored   ? seen, not entered   . room the player cannot see\n"
	for y in range(rect.position.y, rect.end.y):
		var line := "  "
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if not plan.has_room(cell):
				line += "  "
			elif model.state_at(cell) == MinimapModel.State.UNKNOWN:
				line += ". "
			else:
				line += STATE_GLYPHS[model.state_at(cell)] + " "
		out += line + "\n"
	return out


func _stats(values: Array) -> String:
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


func _stats_float(values: Array[float], scale: float) -> String:
	if values.is_empty():
		return "(none)"
	var total := 0.0
	var lowest: float = values[0]
	var highest: float = values[0]
	for value in values:
		total += value
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	return "min %.0f  mean %.0f  max %.0f" % [lowest * scale, total / values.size() * scale, highest * scale]


func _state_name(state: int) -> String:
	return MinimapModel.State.keys()[state]


func _kind_name(kind: int) -> String:
	return RoomData.Kind.keys()[kind]
