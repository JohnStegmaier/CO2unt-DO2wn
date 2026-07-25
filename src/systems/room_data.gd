class_name RoomData
extends RefCounted

## One cell of a floor: which doors it has, what kind of room it is, and how far
## it sits from spawn. Pure data — the Room scene is dressed from this, and the
## generator produces it without ever touching a node.

enum Kind { NORMAL, SPAWN, BOSS, SHOP, TREASURE, EXIT }

## Single-character tags for FloorPlan.to_ascii(), indexed by Kind.
const KIND_GLYPHS: Array[String] = [".", "S", "B", "$", "T", "X"]

var coord: Vector2i
var kind: Kind = Kind.NORMAL
var doors: int = 0
## Rooms travelled from spawn. Spawn is 0. In a tree this is the only distance.
var depth: int = 0
## Set by the runtime once the player has been here; drives minimap fog.
var visited: bool = false


## kind is a Kind, and side arguments are a GridDirection.Side, but both are
## typed int here — see the note in grid_direction.gd on enums across scripts.
func _init(p_coord: Vector2i = Vector2i.ZERO, p_kind: int = Kind.NORMAL, p_depth: int = 0) -> void:
	coord = p_coord
	kind = p_kind
	depth = p_depth


func has_door(side: int) -> bool:
	return (doors & GridDirection.bit(side)) != 0


func open_door(side: int) -> void:
	doors |= GridDirection.bit(side)


func door_sides() -> Array[int]:
	var sides: Array[int] = []
	for side in GridDirection.SIDES:
		if has_door(side):
			sides.append(side)
	return sides


func door_count() -> int:
	var count := 0
	for side in GridDirection.SIDES:
		if has_door(side):
			count += 1
	return count


## A dead end has exactly one door — the classic "is this a power of two" test.
func is_dead_end() -> bool:
	return doors != 0 and (doors & (doors - 1)) == 0


func glyph() -> String:
	return KIND_GLYPHS[kind]
