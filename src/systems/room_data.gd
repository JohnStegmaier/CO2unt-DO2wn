class_name RoomData
extends RefCounted

## One cell of a floor: which doors it has, what kind of room it is, and how far
## it sits from spawn. Pure data — the Room scene is dressed from this, and the
## generator produces it without ever touching a node.

enum Kind { NORMAL, SPAWN, BOSS, SHOP, TREASURE, EXIT }

## Single-character tags for FloorPlan.to_ascii(), indexed by Kind.
const KIND_GLYPHS: Array[String] = [".", "S", "B", "$", "T", "X"]

var coord: Vector2i
## A Kind, typed int for the same reason sides are — see grid_direction.gd.
var kind: int = Kind.NORMAL
var doors: int = 0
## Rooms travelled from spawn. Spawn is 0. In a tree this is the only distance.
var depth: int = 0
## Set by the runtime once the player has been here; drives minimap fog.
var visited: bool = false

## Enemies still standing. -1 until the room is first entered and a count is
## rolled; 0 means cleared, which is why walking back through ground you already
## fought over stays quiet.
##
## An int rather than a `cleared` flag because it also survives a retreat: leave
## with three of six dead and the survivors are freed with the room without ever
## emitting died, so the count is exactly what comes back.
var enemies_remaining: int = -1

## Which of this room's solid props the player has broken, as a bitmask over each
## prop's index in ObstaclePlacement.points().
##
## A mask rather than an array for the same reason `doors` is one: the count is
## small and fixed, and this exists once per cell of every floor.
##
## Indexing by placement order is only sound because that order is reproducible —
## a room is freed and rebuilt on every entry, so a layout that re-rolled would
## come back with the same bits set against different props and resurrect the
## wrong crate. See the note on determinism in obstacle_placement.gd.
var obstacles_destroyed: int = 0

## Has the chest in this cell already been emptied? Only ever true of a TREASURE
## cell.
##
## Here for the same reason obstacles_destroyed is: the room is freed on the way
## out and rebuilt on the way back in, so a chest that remembered its own state
## would forget it at the doorway and pay out again on every visit. The cell
## outlives the room, so the cell remembers.
##
## A plain bool rather than a mask or a cache because there is one chest in a
## treasure room and one thing worth knowing about it. Shops needed a whole
## registry only because their stock is a list that must not come back.
var treasure_opened: bool = false


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
