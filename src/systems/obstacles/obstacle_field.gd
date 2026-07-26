class_name ObstacleField
extends RefCounted

## What is standing in this room, as a thing you can ask questions of.
##
## Built from the props actually placed — a prop the player already broke is not
## in here — and handed to whatever needs to know where the floor is free.
## [EnemyPlacement] takes one so nothing spawns inside a barrel, and game.gd's
## loot spawn takes one so a pickup cannot be entombed in a crate.
##
## Node-free on purpose. Everything a caller needs is position and radius, and
## keeping the nodes out means placement can be settled in a terminal and the
## field can be built from an [ObstaclePlan] list that was never instanced.
##
## This is also the seam the enemy AI comes through, and it now has an adapter.
## [method has_line_of_sight] and [method first_blocker] answer "can I see him,
## and if not what is in the way"; [method avoidance] answers "which way do I
## lean to miss that"; [method cover_point] answers "where do I stand to put a
## barrel between us". [EnemyBehaviour] asks all four and knows nothing else
## about the room. Placement, the obstacle scene and [Room] learned nothing new.
##
## [b]Everything here is ROOM-LOCAL[/b], because that is the space
## [ObstaclePlan] positions arrive in and the space [EnemyPlacement] hands spots
## back in. An [Enemy] lives in global space and a room sits at coord * STRIDE,
## so the two are thousands of pixels apart on any floor bigger than one room —
## see [method Enemy.set_room], which is where the one conversion happens.
## Nothing in this file may be handed a global position.

## Parallel arrays rather than an array of objects: every query is a distance
## test over all of them, there are at most six, and this keeps the hot loop free
## of property lookups on a RefCounted.
var _positions: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat32Array = PackedFloat32Array()

## The prop's index in the room's placement result, carried so a break can find
## it again. Deliberately NOT the field's own index: game.gd skips props the
## player destroyed on an earlier visit when it rebuilds, so from the second
## visit onward the two disagree, and removing by field index would delete a
## crate that is still standing while enemies kept routing around a gap.
var _ids: PackedInt32Array = PackedInt32Array()

## How far a cover point sits off the prop it hides behind. Touching distance
## plus a hair, so a body backed into cover is not permanently wedged in it.
const COVER_GAP := 2.0


static func from_plans(plans: Array[ObstaclePlan]) -> ObstacleField:
	var field := ObstacleField.new()
	for i in plans.size():
		var plan := plans[i]
		if plan != null and plan.def != null:
			field.add(plan.position, plan.def.body_radius, i)
	return field


## `id` defaults to -1, which is "this one can never be removed" — fine for the
## synthetic fields the checkers build, wrong for a real room.
func add(position: Vector2, radius: float, id: int = -1) -> void:
	_positions.append(position)
	_radii.append(radius)
	_ids.append(id)


## That prop is gone. Every enemy in the room holds this field by reference, so
## one call here is the whole room agreeing at once — which is what makes
## shooting your way through cover mean something to the things using it.
##
## Silent on an id that is not here. A prop can only be destroyed once, but the
## signal that reaches this is connected per instance and a room rebuild is not
## a place to be throwing.
func remove_id(id: int) -> void:
	for i in _ids.size():
		if _ids[i] != id:
			continue
		_positions.remove_at(i)
		_radii.remove_at(i)
		_ids.remove_at(i)
		return


func size() -> int:
	return _positions.size()


func is_empty() -> bool:
	return _positions.is_empty()


## Could a body of this radius stand here without overlapping anything?
##
## The caller's radius is added to the prop's rather than tested against the
## centre, so "clear for a boss" and "clear for a pickup" are the same question
## asked with different numbers.
func is_clear(point: Vector2, radius: float = 0.0) -> bool:
	for i in _positions.size():
		if point.distance_to(_positions[i]) < _radii[i] + radius:
			return false
	return true


## The nearest point outside every prop, or the point itself when it is already
## clear. Pushed straight out along the centre line, which for a disc is the
## shortest way out.
##
## Used for loot: a drop rolled under a crate is not a softlock, but it is a
## pickup the player has to walk into a wall to reach.
func nudge_clear(point: Vector2, radius: float = 0.0) -> Vector2:
	var moved := point
	# Twice, because pushing out of one prop can push into its neighbour. Not
	# looped to convergence: the separation rule in ObstaclePlacement means two
	# passes always suffice, and an unbounded loop here would be a hang.
	for _pass in 2:
		for i in _positions.size():
			var away := moved - _positions[i]
			var clearance := _radii[i] + radius
			if away.length() >= clearance:
				continue
			# Dead centre has no direction to leave by; pick one rather than
			# normalising a zero vector.
			var direction := away.normalized() if not away.is_zero_approx() else Vector2.RIGHT
			moved = _positions[i] + direction * clearance
	return moved


## Every prop's centre, for callers that do their own maths — EnemyPlacement
## wants these to keep spawn cells off them.
func positions() -> PackedVector2Array:
	return _positions


func radius_at(index: int) -> float:
	return _radii[index]


## Is there a straight line from here to there that misses every prop?
##
## Segment against disc, which is the whole geometry: props are circles by
## construction — see the Minkowski note on [member ObstacleDef.body_radius] — so
## this is the distance from each centre to the segment, tested against that
## centre's radius. Geometry2D does the clamped projection; hand-rolling it is
## the same four lines with a divide-by-zero in them.
##
## `padding` widens every prop by whatever the asker is carrying, so "can I see
## him" and "will this shot clear the barrel" are one question asked with
## different numbers — the same bargain [method is_clear] makes.
##
## Squared throughout: this runs per enemy per think, and a square root to
## compare against another length is a square root for nothing.
func has_line_of_sight(from: Vector2, to: Vector2, padding: float = 0.0) -> bool:
	for i in _positions.size():
		var closest := Geometry2D.get_closest_point_to_segment(_positions[i], from, to)
		var reach: float = _radii[i] + padding
		if _positions[i].distance_squared_to(closest) < reach * reach:
			return false
	return true


## Which prop is in the way, as an index into this field, or -1 for a clear line.
##
## The NEAREST one to `from`, not the first one the loop happens to reach: an
## enemy deciding whether to shoot or reposition cares about the barrel it is
## standing behind, not the crate on the far side of the room that is also
## nominally on the line.
##
## Returns a field index, deliberately not the placement id [method remove_id]
## takes. Callers ask this to decide where to stand, not to reach for a prop by
## name, and handing out the id would invite exactly the cross-space mix-up the
## two arrays exist to prevent.
func first_blocker(from: Vector2, to: Vector2, padding: float = 0.0) -> int:
	var nearest := -1
	var nearest_distance := INF
	for i in _positions.size():
		var closest := Geometry2D.get_closest_point_to_segment(_positions[i], from, to)
		var reach: float = _radii[i] + padding
		if _positions[i].distance_squared_to(closest) >= reach * reach:
			continue
		var distance := from.distance_squared_to(_positions[i])
		if distance >= nearest_distance:
			continue
		nearest_distance = distance
		nearest = i
	return nearest


## A push away from whatever we are about to walk into, at most one unit long.
##
## Steering, not pathfinding. This cannot route around an L of two barrels and is
## not meant to — what it buys is that a body takes the short way round a single
## prop instead of grinding into it, which is the job [Enemy]'s stuck-guard was
## standing in for on its own. That guard stays: it is what handles a wall, and a
## wall is not in this field.
##
## Weighted by how soon we would reach the prop and how square-on we are to it,
## so one we are already sliding past stops steering us and one dead ahead steers
## us hardest. Summed over every prop and then clamped, rather than taking the
## worst offender: between two barrels the two pushes cancel down the middle,
## which is precisely where the gap is.
func avoidance(at: Vector2, heading: Vector2, radius: float, look_ahead: float) -> Vector2:
	var push := Vector2.ZERO
	if heading.is_zero_approx() or look_ahead <= 0.0:
		return push

	var forward := heading.normalized()
	for i in _positions.size():
		var to_prop: Vector2 = _positions[i] - at
		var along := to_prop.dot(forward)
		# Behind us, or further off than we are planning for.
		if along < 0.0 or along > look_ahead:
			continue
		var clearance: float = _radii[i] + radius
		var perp := to_prop - forward * along
		var offset := perp.length()
		if offset >= clearance:
			continue
		# Dead ahead there is no side to leave by. Taking the orthogonal rather
		# than rolling for one means two enemies on the same line pick the same
		# way and shove each other apart, instead of both dithering in place.
		var away := (-perp).normalized() if not perp.is_zero_approx() else forward.orthogonal()
		push += away * (1.0 - along / look_ahead) * (1.0 - offset / clearance)
	return push.limit_length(1.0)


## Somewhere to stand with a prop between us and `threat`.
##
## The far side of each prop, at touching distance, nearest one wins. Not a
## search and not a scoring function over the floor: there are at most six props,
## so the candidate set is at most six points, and hill-climbing a room would be
## more code and a worse answer.
##
## Returns `at` unchanged when nothing qualifies, so a caller needs no null
## branch and "there is no cover here" and "I am already standing in it" read the
## same at the call site.
##
## `bounds` is passed in rather than looked up because naming [Room] from here
## would compile room.gd, and through it player.gd and four autoloads — which is
## what stops tools/check_floors.gd loading today. Everything under systems/
## stays terminal-loadable; see the closing note on [ObstacleSet].
func cover_point(at: Vector2, threat: Vector2, radius: float, max_travel: float,
		bounds: Rect2) -> Vector2:
	var best := at
	var best_travel := max_travel
	for i in _positions.size():
		var away := (_positions[i] - threat).normalized()
		# A prop the threat is standing on has no far side to speak of.
		if away.is_zero_approx():
			continue
		var spot: Vector2 = _positions[i] + away * (_radii[i] + radius + COVER_GAP)
		spot = spot.clamp(bounds.position, bounds.end)
		var travel := at.distance_to(spot)
		if travel >= best_travel:
			continue
		# Clamping into the room can push a spot back inside the NEXT prop along,
		# and cover you are wedged in is not cover.
		if not is_clear(spot, radius):
			continue
		best = spot
		best_travel = travel
	return best
