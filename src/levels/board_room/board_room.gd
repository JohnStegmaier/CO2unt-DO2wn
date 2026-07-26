class_name BoardRoom
extends Room

## The last room in the building: a board room twice the length of an ordinary
## one, with a table down the middle, chairs along both sides, a television on
## the far wall and six men in suits waiting at the table.
##
## Inherits room.tscn, the way [TreasureRoom] does and unlike [ShopRoom] and
## [ElevatorRoom]. This IS the top-down shell — four walls, a doorway, plugs, the
## door slide — just longer, so inheriting means every one of those keeps working
## with no code here and every override below can call super.
##
## [b]It is one cell in the plan and two cells tall on the screen.[/b] The room
## node still sits at coord * STRIDE like any other, and its scene simply extends
## [constant Room.STRIDE].y further NORTH than its own cell, into negative local
## y. That is the whole trick, and it is why nothing in [FloorPlan],
## [FloorGenerator] or the grid had to learn about rooms of different sizes: the
## cell it overhangs is empty, and [BasementPlan] is where that is guaranteed.
##
## Keeping the scene origin at the top-left of the SOUTHERN half — rather than
## re-centring it on the room — is what makes that cheap. The south doorway, its
## LevelDoor, its plug and its two sprites sit at exactly the coordinates
## room.tscn authored, so [method Room.spawn_position] lands the player correctly
## with nothing overridden. Everything the room gained lives above y = 0.
##
## The table and the chairs are placeholder geometry, authored the same way the
## treasure room's dais is. The shapes and the collision are final; dropping real
## art in is a scene edit with no code change here. The television is not a
## placeholder — tv_test_patterns_02.png was already in the repo and referenced
## by nothing, which is exactly the screen this room wanted.
##
## [b]What board_room.tscn does on top of the shell[/b], recorded here because a
## .tscn cannot keep a comment through a resave:
##
## - [code]background_north[/code] is the inherited background again, one STRIDE
##   up. [code]background_join[/code] is a band of the same texture's plain
##   interior laid across the seam between them: two copies of a bordered room
##   stacked a STRIDE apart leave the top one's bottom wall, the bottom one's top
##   wall and the 21px margin either side of both running straight across the
##   middle of the floor, which reads as a wall bisecting the board room. The
##   join is at the same horizontal scale, so the side walls carry through
##   unbroken, and squashed 9% vertically to fit — nothing, on brickwork. It is
##   the last of the three so it draws over both.
## - The two north wall shapes and all four [code]door_north[/code] nodes move up
##   by one STRIDE. The doorway itself is never opened — this room is a dead end
##   with one door, at the south — but the nodes have to exist and be in the
##   right wall, because [method Room._apply_doors] walks all four sides.
## - [code]wall_west_far[/code] and [code]wall_east_far[/code] close the sides of
##   the half the shell never had. One shape each rather than the inherited pair,
##   because there is no doorway up there to leave a gap for.
## - The television is bolted over that plugged north doorway, under Obstacles,
##   which draws after Walls so it covers the plug rather than the other way
##   round. A screen on the one wall that would otherwise have nothing but a plug
##   on it is the right fiction and the right composition: it is the thing at the
##   far end of the table that the camera arrives at last.

## How much further north than its cell this room reaches. One cell exactly —
## "twice as long" is the whole brief, and a room that overhung by some other
## amount would still have to reserve a whole cell to do it.
const EXTRA_LENGTH := STRIDE.y

## Camera clamp, extended north. Derived rather than typed out so it cannot drift
## from the shell it is an extension of.
const INTERIOR_EXTENDED := Rect2(
		INTERIOR.position - Vector2(0.0, EXTRA_LENGTH),
		INTERIOR.size + Vector2(0.0, EXTRA_LENGTH))
## Walkable area, extended the same way. Rect2(49, -237, 343, 473).
const FLOOR_EXTENDED := Rect2(
		FLOOR.position - Vector2(0.0, EXTRA_LENGTH),
		FLOOR.size + Vector2(0.0, EXTRA_LENGTH))

## Where the player stands if they arrive without a door. Not the centre of
## [constant FLOOR_EXTENDED], which is inside the table — see the note on
## [method Room.default_spawn_position], which is about this exact trap.
const ARRIVAL_SPOT := Vector2(221.0, 215.0)

## The table, matching the shapes authored in board_room.tscn.
const TABLE_CENTRE := Vector2(221.0, -2.0)
const TABLE_SIZE := Vector2(94.0, 300.0)

## The table as [ObstacleField] holds it: a row of overlapping circles down its
## length — see [method register_solids].
##
## Radius and step are a pair. A circle of this radius reaches
## sqrt(62² - 37.5²) ≈ 49px sideways at the midpoint between two of them, which
## clears the table's 47px half-width, so the run of circles covers the rectangle
## with no notch between them for an enemy to walk into.
const TABLE_SOLID_RADIUS := 62.0
const TABLE_SOLID_STEP := 75.0
const TABLE_SOLID_COUNT := 5

## Where the six sit, alternating down the table and walking away from the door.
##
## Centred on the chairs board_room.tscn draws, so a suit is IN his seat rather
## than standing beside it — which is where the chairs had to move to, not the
## seats: every one of these has to sit outside all five circles in
## [method register_solids], or a body spawns inside the table it is sitting at
## and is shoved out of the room on the first physics frame.
##
## The nearest is 104px from [constant ARRIVAL_SPOT], which clears
## [constant EnemyPlacement.MIN_PLAYER_DISTANCE] — the player gets the same beat
## before the first shot that any other room in the game gives them.
##
## tools/check_basement.gd holds all of that: on the floor, off the table, and
## far enough from the door.
const SEATS: Array[Vector2] = [
	Vector2(146.0, -147.0),
	Vector2(296.0, -89.0),
	Vector2(146.0, -31.0),
	Vector2(296.0, 27.0),
	Vector2(146.0, 85.0),
	Vector2(296.0, 143.0),
]

## What this room washes itself in: nothing. Same reasoning as
## [constant TreasureRoom.NO_TINT] — [constant Room.KIND_TINTS] is a stand-in for
## rooms with no art of their own, and a red field over the ending is a lighting
## fault rather than a label.
const NO_TINT := Color(0, 0, 0, 0)


## Dress the shell as usual — which is what opens the one doorway this room has
## and plugs the other three — then drop the placeholder wash.
func configure(data: RoomData) -> void:
	super.configure(data)
	_tint.color = NO_TINT


## Both cells' worth. The camera pans up the room as the player walks into it,
## which is the reveal: the table arrives before the far end of it does.
func interior_rect() -> Rect2:
	return Rect2(global_position + INTERIOR_EXTENDED.position, INTERIOR_EXTENDED.size)


func floor_rect() -> Rect2:
	return FLOOR_EXTENDED


## No scattered props. The middle of this floor is spoken for, and an empty rect
## is how a room says "not this one" — the same answer the treasure room gives.
func obstacle_rect() -> Rect2:
	return Rect2()


func default_spawn_position() -> Vector2:
	return global_position + ARRIVAL_SPOT


## The table, so the room's own furniture is something the enemies can see.
##
## Authored as a rectangle in the scene because that is what a board room table
## is, and reported here as circles because that is what [ObstacleField] holds —
## for a good reason, spelled out in [ObstaclePlacement]: the proof that two
## scattered props can never close a room off is Minkowski arithmetic on discs,
## and a rectangle in the catalogue would invalidate it. Nothing in that proof is
## threatened by a room that authors its own furniture and declares the space it
## takes up, which is why the table lives here rather than as an [ObstacleDef].
##
## No id, so nothing can remove it. The table is architecture, not a crate.
func register_solids(field: ObstacleField) -> void:
	var first := TABLE_CENTRE.y - (TABLE_SOLID_COUNT - 1) * TABLE_SOLID_STEP * 0.5
	for i in TABLE_SOLID_COUNT:
		field.add(Vector2(TABLE_CENTRE.x, first + i * TABLE_SOLID_STEP), TABLE_SOLID_RADIUS)


## Six seats at the table, in place of a placement grid.
##
## [EnemyPlacement] would put them somewhere sensible and somewhere different
## every run, which is right for the fourteen rooms above this one and wrong for
## this one. The whole room is a tableau — the reason it is twice as long, the
## reason there is a table in it at all — and men in suits scattered around the
## edges of it is a different picture from six of them sat at the table waiting
## for you.
func authored_spawns() -> Array[Vector2]:
	return SEATS.duplicate()
