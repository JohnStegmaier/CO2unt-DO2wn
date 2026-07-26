extends SceneTree

## Prove the bestiary is fightable before anyone has to walk into a room.
##
## Everything under src/systems/enemies/ is pure by construction — an
## [EnemyBehaviour] holds knobs and functions, its state lives in the caller's
## [SteeringContext], and neither names a node or an autoload. That is what makes
## this possible at all:
##
##   godot --headless --script tools/check_enemies.gd
##
## Unlike tools/check_drops.gd this needs no autoload fixture, because nothing it
## loads reaches for one. If that ever stops being true, this file stops loading
## and the reason will not be obvious — see the closing note on [EnemySet].
##
## Three things here are worth more than the rest. The geometry check is the one
## that stops a def quietly making a room uncrossable. The placement sweep is the
## one that stops a turret spawning inside a barrel, which is unkillable, which
## means the room never unlocks, which on floor 1 means the run cannot be
## finished. And stepping every behaviour six hundred ticks is the one that
## catches a phase machine that never leaves its first state.
##
## Exits non-zero when an invariant breaks, so it can gate CI.

## Only the shipped bestiary. There is deliberately no second one to check
## against: [member EnemyDef.weight] lives on the def, and the defs are shared by
## reference, so a second EnemySet pointing at the same four files would be a
## byte-for-byte copy of this one pretending to be a knob. A profile that wants a
## different mix raises the counts — see enemy_zoo.cfg — or points
## `[enemies] set` at a bestiary with defs of its own.
const ENEMY_SET := "res://src/config/enemies/default.tres"
const OBSTACLE_SET := "res://src/config/obstacles/default.tres"
const GAME_SCRIPT := "res://src/screens/game/game.gd"

## Copy of Room.FLOOR, and copied for the reason check_obstacles.gd sets out at
## length: naming [Room] here would compile room.gd, then player.gd, then four
## autoloads, and `--script` starts none of them. check_obstacles.gd already
## verifies this copy against the real thing, so it is checked once rather than
## in both files.
const FLOOR := Rect2(49, 49, 343, 187)

## Matches check_obstacles.gd's sweep, so a placement bug and a connectivity bug
## are found over the same layouts.
const SEEDS := 60
const COORD_SPAN := 7

## Ticks each behaviour is stepped for. Ten seconds at 60Hz — long enough that a
## charger with a sane telegraph completes several full cycles, so "never reached
## this phase" means the threshold is wrong rather than that the window was short.
const TICKS := 600
const TICK_DELTA := 1.0 / 60.0

## Draws used for the weight histogram, matching check_drops.gd's rate idiom.
const WEIGHT_DRAWS := 100000

## Deliberately no "how far from a wall" tolerance here.
##
## The obvious test — a fixture must land within N pixels of the floor edge —
## cannot be written, because the 4x3 grid's cells are wider than the gap between
## an edge cell's far side and an interior cell's near side: a jittered top-row
## spot and a jittered middle spot overlap in distance-to-edge, so any threshold
## either passes interior spots or fails legitimate edge ones.
##
## What IS exactly true is that a fixture must never land in one of
## [constant EnemyPlacement.INTERIOR_CELLS], so that is what is asserted, against
## the same rects [method EnemyPlacement.cells] hands the placement itself.

var _failures: Array[String] = []


func _initialize() -> void:
	print("\n=== enemies ===\n")

	var boss_scale := _boss_size_scale()
	var set: EnemySet = load(ENEMY_SET)
	if set == null:
		_fail("could not load %s" % ENEMY_SET)
		_report()
		return

	_check_catalogue(set, "default", boss_scale)
	_check_weights(set)
	_check_art(set)
	_check_facing_formula()
	_check_field_queries()
	_check_behaviours(set)
	_check_placement(set, boss_scale)
	_report()


## game.gd's boss_size_scale, read as text.
##
## Parsed rather than named, because naming game.gd pulls in the whole screen and
## its autoloads. The same trick check_obstacles.gd plays on room.gd, and it has
## the same weakness: if the export is renamed this silently falls back, so the
## fallback is loud.
func _boss_size_scale() -> float:
	var source := FileAccess.get_file_as_string(GAME_SCRIPT)
	var regex := RegEx.create_from_string(r"boss_size_scale\s*:\s*float\s*=\s*([\d.]+)")
	var found := regex.search(source)
	if found == null:
		_fail("could not read boss_size_scale out of %s — the geometry budget below"
				% GAME_SCRIPT + " is being checked against a guess")
		return 1.7
	return found.get_string(1).to_float()


## Every def has to be spawnable, killable, and inside the width the room's
## connectivity proof is stated for.
func _check_catalogue(set: EnemySet, label: String, boss_scale: float) -> void:
	print("-- catalogue (%s) --" % label)
	if set.defs.is_empty():
		_fail("%s: bestiary is empty — every room would stock nothing" % label)
		return
	if set.is_empty():
		_fail("%s: every def has weight 0, so nothing can ever be picked" % label)

	# A run whose bestiary has no promotable def cannot clear a boss room, and on
	# floor 1 the boss gate is the only way down.
	if not set.has_boss_eligible():
		_fail("%s: no def is boss_eligible — the boss gate can never be cleared" % label)

	var seen := {}
	for i in set.defs.size():
		var def: EnemyDef = set.defs[i]
		if def == null:
			_fail("%s: row %d is empty" % [label, i])
			continue
		print("   %s" % def.describe())

		if def.id == &"":
			_fail("%s: row %d has no id" % [label, i])
		elif seen.has(def.id):
			_fail("%s: duplicate id %s" % [label, def.id])
		seen[def.id] = true

		if def.behaviour == null:
			_fail("%s/%s: no behaviour — it would stand still and never shoot"
					% [label, def.id])
		if def.frames == null:
			_fail("%s/%s: no SpriteFrames" % [label, def.id])
		if def.weight < 0.0:
			_fail("%s/%s: negative weight %.2f" % [label, def.id, def.weight])
		if def.max_hp < 1:
			_fail("%s/%s: max_hp %d — it would be dead on arrival"
					% [label, def.id, def.max_hp])

		# The gun and the trigger have to agree. A behaviour that fires with an
		# empty bullet_scene is silent — Enemy._shoot returns early — and reads
		# as a whole archetype that is broken for no visible reason.
		if def.behaviour != null:
			if def.behaviour.fires() and def.bullet_scene == null:
				_fail("%s/%s: behaviour fires but bullet_scene is empty, so it never"
						% [label, def.id] + " shoots and nothing says why")
			if not def.behaviour.fires() and def.bullet_scene != null:
				_fail("%s/%s: carries a bullet_scene its behaviour can never fire"
						% [label, def.id])

			# The wind-up is spent out of the interval, so one longer than the
			# interval clamps the remainder at zero and the def quietly fires every
			# telegraph_seconds instead of every fire_interval. Nothing breaks; it
			# just stops being possible to read the rate of fire off the row.
			if def.telegraph_seconds > def.fire_interval:
				_fail("%s/%s: telegraph_seconds %.2f is longer than its fire_interval"
						% [label, def.id, def.telegraph_seconds]
						+ " %.2f, so the def no longer states its own rate of fire"
						% def.fire_interval)

		# THE geometry invariant. A boss-eligible def spends its width times the
		# promotion scale, because game.gd can make it that wide; one that can
		# never be promoted spends it once. Exceed the cap and the flood fill in
		# check_obstacles.gd is proving something about a body that no longer
		# exists — a room it calls crossable may not be.
		var widest := def.widest_radius(boss_scale)
		if widest > EnemyPlacement.MAX_AGENT_RADIUS:
			_fail("%s/%s: body_radius %.1f%s = %.2f exceeds MAX_AGENT_RADIUS %.2f — rooms"
					% [label, def.id, def.body_radius,
					(" x %.2f boss scale" % boss_scale) if def.boss_eligible else "",
					widest, EnemyPlacement.MAX_AGENT_RADIUS]
					+ " may become uncrossable")

		# A fixture cannot walk out of a bad spot, so it must never be the widest
		# thing placed — and it must never be promoted, or a boss room becomes a
		# shooting gallery with no way to finish it.
		if def.is_fixture() and def.boss_eligible:
			_fail("%s/%s: a wall fixture must not be boss_eligible — a boss that"
					% [label, def.id] + " cannot move is a target, not a fight")
	print("")


## The weights actually produce the spread they claim. A bestiary that has quietly
## collapsed onto one enemy still passes every check above.
func _check_weights(set: EnemySet) -> void:
	print("-- pick rates over %d draws --" % WEIGHT_DRAWS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260726
	var counts := {}
	for _i in WEIGHT_DRAWS:
		var def: EnemyDef = set.pick(rng)
		if def == null:
			_fail("pick() returned null on a non-empty bestiary")
			break
		counts[def.id] = counts.get(def.id, 0) + 1

	var total := set.total_weight()
	for def in set.defs:
		if def == null:
			continue
		var actual := float(counts.get(def.id, 0)) / WEIGHT_DRAWS
		var expected := def.weight / total
		print("   %-10s %5.1f%%  (expected %.1f%%)" % [def.id, actual * 100.0,
				expected * 100.0])
		if absf(actual - expected) > 0.02:
			_fail("%s comes up %.1f%% of the time but its weight says %.1f%%"
					% [def.id, actual * 100.0, expected * 100.0])

	# Boss rooms draw from the same list with the fixtures taken out. If that
	# narrowing ever empties the list, boss rooms silently stock nothing.
	var boss_rng := RandomNumberGenerator.new()
	boss_rng.seed = 20260727
	for _i in 1000:
		var def: EnemyDef = set.pick(boss_rng, true)
		if def == null:
			_fail("pick(boss_only) returned null despite has_boss_eligible()")
			break
		if not def.boss_eligible:
			_fail("pick(boss_only) returned %s, which is not boss_eligible" % def.id)
			break
	print("")


## Every def's SpriteFrames must carry exactly the animations its facing mode
## asks for. A missing one is silent: AnimatedSprite2D.play on a name it does not
## have leaves it on whatever it was showing, which reads as a stuck enemy.
func _check_art(set: EnemySet) -> void:
	for def in set.defs:
		if def == null or def.frames == null:
			continue
		for name in EnemyFacing.required_animations(def.facing):
			if not def.frames.has_animation(name):
				_fail("%s: SpriteFrames has no animation %s, required by its facing mode"
						% [def.id, name])
				continue
			if def.frames.get_frame_count(name) < 1:
				_fail("%s: animation %s has no frames" % [def.id, name])

		# A rotation def indexes frames by bearing, so every bearing has to land
		# on a frame that exists. Sampled rather than reasoned about, because the
		# failure is an out-of-range read at runtime.
		if def.facing != EnemyFacing.Mode.ROTATION:
			continue
		if not def.frames.has_animation(&"move"):
			continue
		var count := def.frames.get_frame_count(&"move")
		for step in 720:
			var heading := Vector2.RIGHT.rotated(TAU * step / 720.0)
			var frame := EnemyFacing.frame_for(def.facing, heading, count,
					def.facing_offset_degrees)
			if frame < 0 or frame >= count:
				_fail("%s: bearing %d° maps to frame %d of %d"
						% [def.id, step / 2, frame, count])
				break


## The one formula every facing mode goes through, checked against the bearings a
## reader would expect. Getting the handedness wrong swaps up and down on every
## four-way enemy, which looks like an art bug and is not one.
func _check_facing_formula() -> void:
	var four := EnemyFacing.Mode.FOUR_WAY
	var expected := {
		Vector2.RIGHT: &"move_right",
		Vector2.DOWN: &"move_down",
		Vector2.LEFT: &"move_left",
		Vector2.UP: &"move_up",
	}
	for heading in expected:
		var got := EnemyFacing.animation_for(four, heading, 0.0)
		if got != expected[heading]:
			_fail("facing: %v should play %s, played %s" % [heading, expected[heading], got])

	# Sectors are centred on their bearing rather than starting at it, so a body
	# walking dead right must not flicker between right and down.
	for degrees in [-40.0, -20.0, 0.0, 20.0, 40.0]:
		var heading := Vector2.RIGHT.rotated(deg_to_rad(degrees))
		if EnemyFacing.animation_for(four, heading, 0.0) != &"move_right":
			_fail("facing: %.0f° off due right should still be move_right" % degrees)

	# A standing body keeps its last animation rather than snapping to due right.
	if EnemyFacing.sector(Vector2.ZERO, 16, 0.0) != 0:
		_fail("facing: a zero heading must fall back to sector 0")

	# Sixteen frames is 22.5° a step, which is what makes the turret art line up.
	if EnemyFacing.sector(Vector2.DOWN, 16, 0.0) != 4:
		_fail("facing: due down should be frame 4 of 16, got %d"
				% EnemyFacing.sector(Vector2.DOWN, 16, 0.0))
	if EnemyFacing.sector(Vector2.UP, 16, 0.0) != 12:
		_fail("facing: due up should be frame 12 of 16, got %d"
				% EnemyFacing.sector(Vector2.UP, 16, 0.0))


## The four queries the AI steers on. Unit tests in the ordinary sense, which is
## only possible because ObstacleField holds no nodes.
func _check_field_queries() -> void:
	var field := ObstacleField.new()
	var prop := Vector2(100, 0)
	field.add(prop, 10.0, 7)

	var left := Vector2(0, 0)
	var right := Vector2(200, 0)

	if field.has_line_of_sight(left, right):
		_fail("field: a prop dead on the line should block sight")
	if field.first_blocker(left, right) != 0:
		_fail("field: first_blocker should return the prop on the line")
	if not field.has_line_of_sight(Vector2(0, 100), Vector2(200, 100)):
		_fail("field: a line clear of every prop should not be blocked")

	# Removal is by placement id, not field index — the two disagree the moment a
	# room is re-entered with something already broken.
	field.remove_id(7)
	if not field.has_line_of_sight(left, right):
		_fail("field: sight should be clear once the prop is removed")
	if field.first_blocker(left, right) != -1:
		_fail("field: first_blocker should be -1 with nothing in the way")
	if field.size() != 0:
		_fail("field: remove_id left %d props behind" % field.size())

	# The nearest blocker, not the first one the loop reaches.
	var two := ObstacleField.new()
	two.add(Vector2(150, 0), 10.0, 1)
	two.add(Vector2(50, 0), 10.0, 0)
	if two.first_blocker(Vector2.ZERO, Vector2(200, 0)) != 1:
		_fail("field: first_blocker should pick the prop nearest `from`")

	var avoid := ObstacleField.new()
	avoid.add(Vector2(40, 0), 10.0, 0)
	var push := avoid.avoidance(Vector2.ZERO, Vector2.RIGHT, 4.0, 60.0)
	if push.is_zero_approx():
		_fail("field: walking straight at a prop should produce a push")
	if push.length() > 1.0001:
		_fail("field: avoidance returned %.3f, longer than one unit" % push.length())
	if is_nan(push.x) or is_nan(push.y):
		_fail("field: avoidance returned NaN")
	if not avoid.avoidance(Vector2.ZERO, Vector2.LEFT, 4.0, 60.0).is_zero_approx():
		_fail("field: a prop behind us should not steer us")
	if not ObstacleField.new().avoidance(Vector2.ZERO, Vector2.RIGHT, 4.0, 60.0).is_zero_approx():
		_fail("field: an empty field should never steer")

	var cover := ObstacleField.new()
	cover.add(Vector2(100, 0), 10.0, 0)
	var bounds := Rect2(-200, -200, 400, 400)
	var threat := Vector2(0, 0)
	var spot := cover.cover_point(Vector2(100, 60), threat, 4.0, 200.0, bounds)
	if spot.x <= 100.0:
		_fail("field: cover should be on the far side of the prop from the threat")
	if not cover.is_clear(spot, 4.0):
		_fail("field: a cover point must not be inside a prop")
	if not bounds.has_point(spot):
		_fail("field: a cover point must be inside the room")
	if cover.has_line_of_sight(threat, spot, 4.0):
		_fail("field: standing in cover should break the threat's line")
	var nowhere := ObstacleField.new().cover_point(Vector2(5, 5), threat, 4.0, 200.0, bounds)
	if not nowhere.is_equal_approx(Vector2(5, 5)):
		_fail("field: with no props, cover_point should return where we already are")


## Step every archetype for ten seconds against a target that will not sit still,
## and insist the result stays finite, stays inside its own declared ceiling, and
## that a phase machine actually turns over.
func _check_behaviours(set: EnemySet) -> void:
	print("-- behaviour steps (%d ticks each) --" % TICKS)
	for def in set.defs:
		if def == null or def.behaviour == null:
			continue

		var field := ObstacleField.new()
		field.add(Vector2(220, 150), 10.0, 0)
		field.add(Vector2(140, 190), 8.0, 1)

		var ctx := SteeringContext.new()
		ctx.here = Vector2(100, 100)
		ctx.radius = def.body_radius
		ctx.field = field
		ctx.bounds = FLOOR
		def.behaviour.on_spawn(ctx, 0.37)

		var ceiling: float = def.behaviour.top_speed()
		var phases := {}
		var peak_windup := 0.0
		for tick in TICKS:
			# Advancing the clocks by hand is the whole reason phases count down
			# from delta instead of comparing against Time.get_ticks_msec() —
			# see [member SteeringContext.phase_remaining].
			ctx.tick(TICK_DELTA)
			# Orbiting rather than parked, so a behaviour that only ever triggers
			# on a stationary target does not pass by accident.
			var angle := TAU * tick / 180.0
			ctx.target = Vector2(220, 150) + Vector2(70, 45).rotated(angle)
			# Touching for a stretch in the middle, which is the only way a lunge
			# or a strafe flip can be seen to end on contact.
			ctx.touching = tick > 200 and tick < 230

			var velocity: Vector2 = def.behaviour.steer(ctx)
			if is_nan(velocity.x) or is_nan(velocity.y):
				_fail("%s: steer returned NaN on tick %d" % [def.id, tick])
				break
			if velocity.length() > ceiling * 1.01 + 0.001:
				_fail("%s: steer returned %.1f px/s on tick %d, over its declared top_speed %.1f"
						% [def.id, velocity.length(), tick, ceiling])
				break

			var aim: Vector2 = def.behaviour.aim(ctx)
			if aim != Vector2.ZERO and not def.behaviour.fires():
				_fail("%s: aimed a shot but fires() says it never shoots" % def.id)
				break

			var look: Vector2 = def.behaviour.facing(ctx)
			if is_nan(look.x) or is_nan(look.y):
				_fail("%s: facing returned NaN on tick %d" % [def.id, tick])
				break

			# AttackTell lerps a radius across this, so anything outside 0..1 draws
			# a ring that inverts or expands out of the room rather than closing.
			var charge: float = def.behaviour.windup(ctx)
			if is_nan(charge) or charge < 0.0 or charge > 1.0:
				_fail("%s: windup returned %f on tick %d, outside 0..1"
						% [def.id, charge, tick])
				break
			peak_windup = maxf(peak_windup, charge)

			phases[ctx.phase] = true
			ctx.velocity = velocity
			ctx.here += velocity * TICK_DELTA
			# Kept on the floor, or a lunge walks it out of the room and every
			# range test afterwards is measured from somewhere it cannot be.
			ctx.here = ctx.here.clamp(FLOOR.position, FLOOR.end)

		var visited: Array = phases.keys()
		visited.sort()
		# The wind-up is printed rather than asserted for everything, because zero
		# is a legal answer for three of the four: a shooter's tell is
		# EnemyDef.telegraph_seconds and Enemy holds that clock, so nothing here can
		# see it. What this column catches is the archetype whose tell is its own.
		print("   %-10s %s reached phases %s, peak windup %.2f" % [def.id,
				"stationary" if is_zero_approx(ceiling) else "%.0f px/s max" % ceiling,
				str(visited), peak_windup])
		_check_phase_coverage(def, phases)
		_check_windup_coverage(def, peak_windup)
	print("")


## Two archetypes carry their own wind-up rather than the def's: a charger,
## because its attack is a lunge and [member EnemyDef.telegraph_seconds] belongs
## to a gun it does not have; and a turret, because its tell is per BEARING and
## the def's is per shot. One that never reaches it looks exactly like an attack
## arriving out of nowhere, which is the bug this feature exists to remove — so
## it is worth a check of its own rather than being covered by "the phase was
## visited", which passes on a threshold that lets the phase run for a frame.
##
## Named archetypes here for the same reason [method _check_phase_coverage] does:
## what a behaviour promises about itself is not something the base class can say.
func _check_windup_coverage(def: EnemyDef, peak_windup: float) -> void:
	var owns_its_tell: bool = def.behaviour is ChargeBehaviour \
			or def.behaviour is TurretBehaviour
	if not owns_its_tell:
		return
	# Near 1 rather than merely above 0: a ring that stops closing short of the
	# attack is a countdown that ends early, which is worse than none.
	if peak_windup < 0.99:
		_fail("%s: peaked at %.2f in %d ticks — its tell would never finish closing"
				% [def.id, peak_windup, TICKS])


## A phased archetype that never leaves its first state is a threshold typo, and
## it looks exactly like an enemy standing there doing nothing.
func _check_phase_coverage(def: EnemyDef, phases: Dictionary) -> void:
	var expected := 0
	if def.behaviour is ChargeBehaviour:
		expected = ChargeBehaviour.Phase.size()
	elif def.behaviour is TurretBehaviour:
		expected = TurretBehaviour.Phase.size()
	if expected == 0:
		return
	if phases.size() < expected:
		_fail("%s: visited only %d of its %d phases in %d ticks — check its thresholds"
				% [def.id, phases.size(), expected, TICKS])


## The run-ending one. Both placement calls, over real layouts, for every door
## mask: nothing may land inside a prop, and a fixture must actually end up
## against a wall.
func _check_placement(set: EnemySet, boss_scale: float) -> void:
	print("-- placement over %d seeds x 15 door masks --" % SEEDS)
	var obstacles: ObstacleSet = load(OBSTACLE_SET)
	if obstacles == null:
		_fail("could not load %s" % OBSTACLE_SET)
		return

	var widest: float = set.max_body_radius(boss_scale)
	var checked := 0
	var fixtures := 0
	for seed_index in SEEDS:
		for mask in range(1, 16):
			var coord := Vector2i(seed_index % COORD_SPAN - 3, seed_index / COORD_SPAN - 3)
			var rng := RandomNumberGenerator.new()
			rng.seed = ObstaclePlacement.seed_for(seed_index * 7919, coord)
			var plans := ObstaclePlacement.points(FLOOR, obstacles, _landings(mask), rng)
			var field := ObstacleField.from_plans(plans)

			var spot_rng := RandomNumberGenerator.new()
			spot_rng.seed = seed_index * 104729 + mask
			var player := FLOOR.get_center()

			for spot in EnemyPlacement.points(FLOOR, 6, player, _landings(mask), spot_rng, field):
				checked += 1
				if not field.is_clear(spot, widest):
					_fail("seed %d mask %d: a roamer spawned inside a prop at %v"
							% [seed_index, mask, spot])

			for spot in EnemyPlacement.wall_points(FLOOR, 3, player, _landings(mask),
					spot_rng, field):
				checked += 1
				fixtures += 1
				# A fixture cannot walk out of a bad spot. This is the assertion
				# that stands between a bad roll and an unfinishable run.
				if not field.is_clear(spot, widest):
					_fail("seed %d mask %d: a FIXTURE spawned inside a prop at %v —"
							% [seed_index, mask, spot] + " unkillable, room never unlocks")
				if _is_interior(spot):
					_fail("seed %d mask %d: a fixture landed at %v, in an interior cell"
							% [seed_index, mask, spot] + " — that is the open floor")

	print("   %d spots checked, %d of them fixtures, widest body %.2f\n"
			% [checked, fixtures, widest])


## Did this land in one of the two cells that touch no wall?
func _is_interior(point: Vector2) -> bool:
	var grid := EnemyPlacement.cells(FLOOR)
	for index in EnemyPlacement.INTERIOR_CELLS:
		if grid[index].has_point(point):
			return true
	return false


## Door landings for a mask, copied from check_obstacles.gd's table.
func _landings(mask: int) -> Array[Vector2]:
	const ALL: Array[Vector2] = [
		Vector2(221, 57), Vector2(384, 143), Vector2(221, 228), Vector2(57, 143),
	]
	var open: Array[Vector2] = []
	for side in 4:
		if (mask & (1 << side)) != 0:
			open.append(ALL[side])
	return open


func _fail(message: String) -> void:
	# Capped: one bad constant fails every layout, and ten thousand identical
	# lines buries the one that differs.
	if _failures.size() < 40:
		_failures.append(message)
	elif _failures.size() == 40:
		_failures.append("... further failures suppressed")


func _report() -> void:
	if _failures.is_empty():
		print("✓ enemies OK — every def spawnable, every archetype turns over\n")
		quit(0)
		return
	print("-".repeat(70))
	print("  ✗ %d FAILURE(S):" % _failures.size())
	print("-".repeat(70))
	for failure in _failures:
		print("  %s" % failure)
	print("")
	quit(1)
