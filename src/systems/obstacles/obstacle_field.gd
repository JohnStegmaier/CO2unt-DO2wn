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
## This is also the seam the enemy AI will come through. Cover-seeking wants
## "what can I hide behind, and is the player on the other side of it"; breaking
## through wants "what is in my way, and is it soft". Both are questions about
## this object, and both can be added here without placement, the scene, or the
## room learning anything new. They are not written yet — nothing asks them, and
## a port with no adapter is a guess about the future.

## Parallel arrays rather than an array of objects: every query is a distance
## test over all of them, there are at most six, and this keeps the hot loop free
## of property lookups on a RefCounted.
var _positions: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat32Array = PackedFloat32Array()


static func from_plans(plans: Array[ObstaclePlan]) -> ObstacleField:
	var field := ObstacleField.new()
	for plan in plans:
		if plan != null and plan.def != null:
			field.add(plan.position, plan.def.body_radius)
	return field


func add(position: Vector2, radius: float) -> void:
	_positions.append(position)
	_radii.append(radius)


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
