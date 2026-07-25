class_name GridDirection
extends RefCounted

## Cardinal sides of a room on the floor grid.
##
## Ordered clockwise so the opposite side is always (side + 2) % 4. The door
## pairing maths relies on that, so do not reorder without fixing opposite().
##
## Sides are passed around as plain int, not as Side. GDScript does not unify an
## enum type across script boundaries — a value typed Side here arrives as
## GridDirection.Side elsewhere and the parser rejects it, and Array[Side] fails
## outright. The enum stays for readable call sites; the signatures stay int.

enum Side { NORTH, EAST, SOUTH, WEST }

const SIDES: Array[int] = [Side.NORTH, Side.EAST, Side.SOUTH, Side.WEST]

## Grid is y-down, matching screen space: NORTH is -y.
const OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

const NAMES: Array[String] = ["north", "east", "south", "west"]


static func offset(side: int) -> Vector2i:
	return OFFSETS[side]


static func opposite(side: int) -> int:
	return (side + 2) % 4


## Bit for this side in a RoomData door mask.
static func bit(side: int) -> int:
	return 1 << side


static func side_name(side: int) -> String:
	return NAMES[side]
