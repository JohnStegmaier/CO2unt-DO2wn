extends SceneTree

## Prove the decal catalogue is sane and that DecalPlacement keeps its own two
## promises: nothing lands off the floor, and no two decals land inside each
## other's clearance_radius.
##
##   godot --headless --script tools/check_decals.gd
##
## Deliberately NOT check_obstacles.gd's shape. That file flood-fills real
## layouts because ObstaclePlacement claims a room can never be walled off —
## a claim worth proving against real geometry. Nothing here blocks a step, so
## there is no connectivity claim to test, and no BOSS_RADIUS-sized body to
## flood-fill for. This checks the two claims DecalPlacement actually makes.
##
## Exits non-zero when an invariant breaks, so it can gate CI.

const DECAL_SET := "res://src/config/decals/default.tres"

## Copy of Room.FLOOR — see check_obstacles.gd's identical note on why this is
## copied as a literal rather than loaded from Room: naming it would compile
## room.gd, then player.gd, then the autoloads, and `--script` starts none.
const FLOOR := Rect2(49, 49, 343, 187)

## Room's door node landings, one per GridDirection.Side, north/east/south/west
## — see check_obstacles.gd's LANDINGS for the same copy.
const LANDINGS: Array[Vector2] = [
	Vector2(221, 57), Vector2(384, 143), Vector2(221, 228), Vector2(57, 143),
]

const SEEDS := 60
const COORD_SPAN := 7

var _failures: Array[String] = []
var _layouts := 0
var _decals := 0
var _histogram := {}


func _initialize() -> void:
	print("\n=== decal placement ===\n")

	var set: DecalSet = load(DECAL_SET)
	if set == null:
		_fail("could not load %s" % DECAL_SET)
		_report()
		return

	_check_catalogue(set)
	_check_room_kind_flags()
	_check_layouts(set)
	_report()


func _check_catalogue(set: DecalSet) -> void:
	if set.defs.is_empty() and set.guaranteed_def == null:
		_fail("catalogue is empty and there is no guaranteed_def either")
		return

	var seen := {}
	for def in set.defs:
		if def == null:
			_fail("catalogue has a null row")
			continue
		_check_def(def, seen)
		print("  %s" % def.describe())

	# Not in defs — see DecalSet.guaranteed_def — so it gets no weight check
	# (pick() never reads it) but everything else about it still has to hold.
	if set.guaranteed_def != null:
		_check_def(set.guaranteed_def, seen)
		print("  %s (guaranteed)" % set.guaranteed_def.describe())
	print("")


func _check_def(def: DecalDef, seen: Dictionary) -> void:
	if def.id == &"":
		_fail("a row has no id")
	elif seen.has(def.id):
		_fail("duplicate id %s" % def.id)
	seen[def.id] = true

	if def.texture == null and def.sprite_frames == null:
		_fail("%s has neither a texture nor sprite_frames — nothing to draw" % def.id)
	if def.sprite_frames != null and not def.sprite_frames.has_animation(def.animation):
		_fail("%s: sprite_frames has no animation %s" % [def.id, def.animation])
	if def.clearance_radius <= 0.0:
		_fail("%s has clearance_radius %.1f" % [def.id, def.clearance_radius])
	if def.weight < 0.0:
		_fail("%s has negative weight %.2f" % [def.id, def.weight])
	if def.opacity < 0.0 or def.opacity > 1.0:
		_fail("%s has opacity %.2f, outside 0..1" % [def.id, def.opacity])


## DecalSet.room_kinds is a flag mask over RoomData.Kind, the same hazard
## ObstacleSet.room_kinds has — see check_obstacles.gd's identical check.
func _check_room_kind_flags() -> void:
	var hint := ""
	for property in DecalSet.new().get_property_list():
		if property.name == "room_kinds":
			hint = property.hint_string
			break
	if hint.is_empty():
		_fail("DecalSet.room_kinds has no flag hint to check")
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


## Every seed crossed with all 15 door masks: every decal stays on the floor,
## clear of the doorways it was asked to avoid, and clear of every other decal
## in the same room by their combined clearance_radius.
func _check_layouts(set: DecalSet) -> void:
	print("-- layouts over %d seeds x 15 door masks --" % SEEDS)
	for seed_index in SEEDS:
		for mask in range(1, 16):
			var coord := Vector2i(seed_index % COORD_SPAN - 3, seed_index / COORD_SPAN - 3)
			var rng := RandomNumberGenerator.new()
			rng.seed = DecalPlacement.seed_for(seed_index * 7919, coord)

			var keep_clear := _landings(mask)
			keep_clear.append(FLOOR.get_center())

			var plans := DecalPlacement.points(FLOOR, set, keep_clear, rng)
			_layouts += 1
			_decals += plans.size()
			_histogram[plans.size()] = _histogram.get(plans.size(), 0) + 1

			# +1 for guaranteed_def, which sits outside count_min/count_max by
			# design — see DecalSet.guaranteed_def.
			var ceiling: int = set.count_max + (1 if set.guaranteed_def != null else 0)
			if plans.size() > ceiling:
				_fail("seed %d mask %d: %d decals, above count_max %d (+1 guaranteed)"
						% [seed_index, mask, plans.size(), set.count_max])

			for i in plans.size():
				var plan := plans[i]
				if not FLOOR.has_point(plan.position):
					_fail("seed %d mask %d: decal %d landed at %v, off the floor"
							% [seed_index, mask, i, plan.position])
				for point in keep_clear:
					if plan.position.distance_to(point) < DecalPlacement.DOOR_CLEARANCE:
						_fail(("seed %d mask %d: decal %d landed at %v, inside door " \
								% [seed_index, mask, i, plan.position]) \
								+ ("clearance of %v" % point))
				for j in range(i + 1, plans.size()):
					var other := plans[j]
					var needed: float = plan.def.clearance_radius + other.def.clearance_radius
					if plan.position.distance_to(other.position) < needed:
						_fail("seed %d mask %d: decals %d and %d overlap — %.1fpx apart, " \
								% [seed_index, mask, i, j,
								plan.position.distance_to(other.position)] \
								+ "need %.1f" % needed)

	print("   %d layouts, %d decals placed" % [_layouts, _decals])
	var counts: Array = _histogram.keys()
	counts.sort()
	for count in counts:
		print("   %d decal(s): %d room(s)" % [count, _histogram[count]])
	print("")


func _landings(mask: int) -> Array[Vector2]:
	var open: Array[Vector2] = []
	for side in 4:
		if (mask & (1 << side)) != 0:
			open.append(LANDINGS[side])
	return open


func _fail(message: String) -> void:
	if _failures.size() < 40:
		_failures.append(message)
	elif _failures.size() == 40:
		_failures.append("... further failures suppressed")


func _report() -> void:
	if _failures.is_empty():
		print("✓ decals OK — catalogue sane, every sampled layout clear\n")
		quit(0)
		return
	print("-".repeat(70))
	print("  ✗ %d FAILURE(S):" % _failures.size())
	print("-".repeat(70))
	for failure in _failures:
		print("  %s" % failure)
	print("")
	quit(1)
