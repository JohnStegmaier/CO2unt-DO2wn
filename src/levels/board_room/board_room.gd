class_name BoardRoom
extends Room

## The last room in the building: a board room half again as long as an ordinary
## one, with a table down the middle, chairs along both sides, a television on
## the far wall and six men in suits waiting at the table.
##
## Inherits room.tscn, the way [TreasureRoom] does and unlike [ShopRoom] and
## [ElevatorRoom]. This IS the top-down shell — four walls, a doorway, plugs, the
## door slide — just longer, so inheriting means every one of those keeps working
## with no code here and every override below can call super.
##
## [b]It is one cell in the plan and one and a half cells tall on the screen.[/b]
## The room node still sits at coord * STRIDE like any other, and its scene simply
## extends [constant EXTRA_LENGTH] further NORTH than its own cell, into negative
## local y. That is the whole trick, and it is why nothing in [FloorPlan],
## [FloorGenerator] or the grid had to learn about rooms of different sizes: the
## cell it overhangs is empty, and [BasementPlan] is where that is guaranteed.
##
## Note that it reserves the WHOLE cell above while only drawing into half of it.
## Reserving a fraction of a cell is not a thing the grid can express, and it
## would not help if it were — nothing could be put in the other half without
## sharing a wall with this room.
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
## - [code]background_north[/code] is the inherited background again, EXTRA_LENGTH
##   up, and region-cropped to drop its BOTTOM wall — texture rows 0..664, the
##   border below that starting at row 670. Cropped SIX ROWS SHORT of it, not to
##   it: the art draws a hard dark line exactly on that boundary, and a sprite
##   whose last row is that line puts a 1px black rule straight across the floor.
##   It draws over the inherited copy, so
##   in the strip where the two overlap you see this one's floor rather than
##   either one's wall. That is the whole seam treatment, and it only works
##   because the overhang is shorter than the art is tall: at a full STRIDE the
##   two copies did not overlap at all, they left a 42px gap plus two facing
##   walls, and hiding that took a third sprite.
## - The two north wall shapes and all four [code]door_north[/code] nodes move up
##   by EXTRA_LENGTH. The doorway itself is never opened — this room is a dead end
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

## How much further north than its cell this room reaches, as a fraction of one.
##
## Half. A full cell was the first pass and played too long: the walk from the
## door to the table, and from the table to the far wall, were each about as long
## as the table itself, so most of the room was floor with nothing on it. This
## halves both of those gaps.
##
## Kept as a fraction of [constant Room.STRIDE] rather than a pixel count so the
## room stays defined in cells — the grid is what it has to agree with, and
## tools/check_basement.gd reads this number to check the scene against it.
const EXTRA_CELLS := 0.5
const EXTRA_LENGTH := STRIDE.y * EXTRA_CELLS

## Camera clamp, extended north. Derived rather than typed out so it cannot drift
## from the shell it is an extension of.
const INTERIOR_EXTENDED := Rect2(
		INTERIOR.position - Vector2(0.0, EXTRA_LENGTH),
		INTERIOR.size + Vector2(0.0, EXTRA_LENGTH))
## Walkable area, extended the same way. Rect2(49, -94, 343, 330).
const FLOOR_EXTENDED := Rect2(
		FLOOR.position - Vector2(0.0, EXTRA_LENGTH),
		FLOOR.size + Vector2(0.0, EXTRA_LENGTH))

## Where the player stands if they arrive without a door. Not the centre of
## [constant FLOOR_EXTENDED], which is inside the table — see the note on
## [method Room.default_spawn_position], which is about this exact trap.
const ARRIVAL_SPOT := Vector2(221.0, 215.0)

## The table, matching the shapes authored in board_room.tscn.
##
## Sized against the people rather than against the room. The first pass filled a
## third of the floor's width and two thirds of its length, which is honestly how
## big a boardroom table is — and read as comic next to a 30px man, because a
## room drawn at this scale is not a room, it is a diagram of one. This is the
## size that looks like a table with six people at it.
const TABLE_CENTRE := Vector2(221.0, 71.0)
const TABLE_SIZE := Vector2(56.0, 190.0)

## The table as [ObstacleField] holds it: a row of overlapping circles down its
## length — see [method register_solids].
##
## Radius and step are a pair, and both are also bounded from below by
## [constant SEATS]. A circle of this radius reaches sqrt(35² - 19²) ≈ 29px
## sideways at the midpoint between two of them, clearing the table's 28px
## half-width so the run covers the rectangle with no notch for an enemy to walk
## into; and it has to stay under 46px, which is how far a seat sits from the
## table's spine, or the six men spawn inside the thing they are sitting at.
const TABLE_SOLID_RADIUS := 35.0
const TABLE_SOLID_STEP := 38.0
const TABLE_SOLID_COUNT := 6

## Where the six sit.
##
## Three pairs facing each other, on alternate rows. The two southernmost chairs
## are deliberately empty: shortening the room brought the table's near end within
## 75px of where the player walks in, and leaving that row unoccupied is what puts
## the closest suit back out at 104px instead — cheaper than moving the table and
## it reads better anyway, as a board gathered up the far end.
##
## Centred on the chairs board_room.tscn draws, so a suit is IN his seat rather
## than standing beside it — which is where the chairs had to move to, not the
## seats: every one of these has to sit outside all six circles in
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
	Vector2(175.0, -14.0),
	Vector2(267.0, -14.0),
	Vector2(175.0, 54.0),
	Vector2(267.0, 54.0),
	Vector2(175.0, 122.0),
	Vector2(267.0, 122.0),
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
