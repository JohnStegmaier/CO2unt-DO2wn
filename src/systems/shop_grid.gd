class_name ShopGrid
extends Resource

## The cubbies on the shop wall: how many, how big, and where each one sits.
##
## A Resource rather than constants in [ShopRoom] so the shelf is an inspector
## slot you can resize while the game runs. Nothing in the room hand-places a
## cubby — the planks, the holes and the items are all generated from these
## numbers, so changing [member rows] or [member columns] is the whole resize.
##
## Pure geometry and indexing. It holds no items and makes no decisions, so it
## can be exercised without a scene tree — see tools/check_shop.gd.

@export_group("Shape")
## Shelves, top to bottom.
@export var rows: int = 4
## Cubbies per shelf.
@export var columns: int = 12

@export_group("Metrics")
## Room-local top-left of the first cubby.
@export var origin: Vector2 = Vector2(70, 40)
## How big one cubby is. The item sprite is centred in this.
@export var cell_size: Vector2 = Vector2(24, 24)
## Gap between cubbies. The y value is generous because it is also where the
## shelf plank and the price tag are drawn.
@export var cell_spacing: Vector2 = Vector2(2, 8)

## Extra width inserted at the middle of every row, splitting the shelf into two
## banks with a space between them.
##
## That space is where the shopkeeper stands, so the shelf reads as a stall with
## product either side of him rather than as a wall he happens to be in front of.
## Zero puts the columns back in one unbroken run, which is what every non-shop
## use of this grid wants and what the geometry assertions assume.
##
## Purely a matter of where cubbies are DRAWN. The index space is untouched, so
## [method neighbour] still steps from the last column of the left bank to the
## first of the right without anything special.
@export var center_gap: float = 0.0


## How many items this shelf can hold.
func capacity() -> int:
	return maxi(rows, 0) * maxi(columns, 0)


func is_valid(index: int) -> bool:
	return index >= 0 and index < capacity()


func row_of(index: int) -> int:
	return index / maxi(columns, 1)


func column_of(index: int) -> int:
	return index % maxi(columns, 1)


func index_of(row: int, column: int) -> int:
	return row * maxi(columns, 1) + column


## Distance from one cubby's left edge to the next one's.
func stride() -> Vector2:
	return cell_size + cell_spacing


## Columns in the left-hand bank. The right bank takes the remainder, so an odd
## column count puts the extra one on the right.
func left_columns() -> int:
	return maxi(columns, 0) / 2


## How far a column is pushed right by the centre gap: nothing in the left bank,
## the whole gap in the right.
func _gap_before(column: int) -> float:
	return center_gap if column >= left_columns() else 0.0


## Where a cubby sits, in room-local space.
func cell_rect(index: int) -> Rect2:
	if not is_valid(index):
		return Rect2()
	var step: Vector2 = stride()
	var column: int = column_of(index)
	return Rect2(
		origin + Vector2(column * step.x + _gap_before(column), row_of(index) * step.y),
		cell_size
	)


## Where a whole row sits, end to end — including the centre gap if there is one.
func row_rect(row: int) -> Rect2:
	var step: Vector2 = stride()
	var width: float = maxi(columns, 0) * step.x - cell_spacing.x + center_gap
	return Rect2(
		origin + Vector2(0.0, row * step.y),
		Vector2(width, cell_size.y)
	)


## Where one bank of one row sits — bank 0 is left of the centre gap, bank 1 is
## right of it.
##
## This rather than [method row_rect] is what a shelf plank is drawn from: a
## single plank spanning the whole row would run straight through the gap and
## behind the shopkeeper, which is the one place there is deliberately no shelf.
## With no centre gap, bank 0 is the whole row and bank 1 is empty.
func bank_rect(row: int, bank: int) -> Rect2:
	var step: Vector2 = stride()
	var left: int = left_columns()
	var start_column: int = 0 if bank == 0 else left
	var count: int = left if bank == 0 else maxi(columns, 0) - left
	if count <= 0:
		return Rect2()
	return Rect2(
		origin + Vector2(start_column * step.x + _gap_before(start_column), row * step.y),
		Vector2(count * step.x - cell_spacing.x, cell_size.y)
	)


## The whole shelf's footprint, for placing it against the wall.
func bounds() -> Rect2:
	var step: Vector2 = stride()
	return Rect2(origin, Vector2(
		maxi(columns, 0) * step.x - cell_spacing.x + center_gap,
		maxi(rows, 0) * step.y - cell_spacing.y
	))


## Which cubby contains this point, or -1 for none.
##
## Takes a point in the same space [method cell_rect] returns, so a caller works
## in the shelf's local coordinates and does not have to know how the grid is
## laid out. Deliberately returns -1 for the spacing between cubbies rather than
## the nearest one: the gaps are where the planks are drawn, and a cursor resting
## on a plank is not pointing at anything.
func cell_at(point: Vector2) -> int:
	if capacity() <= 0:
		return -1
	var local: Vector2 = point - origin
	var step: Vector2 = stride()
	if local.x < 0.0 or local.y < 0.0 or step.x <= 0.0 or step.y <= 0.0:
		return -1

	# Undo the centre gap before the column arithmetic. A point that lands inside
	# the gap itself falls short of the right bank once the gap is removed, which
	# is how the space the shopkeeper stands in reports as pointing at nothing.
	if center_gap > 0.0:
		var split: float = left_columns() * step.x
		if local.x >= split:
			local.x -= center_gap
			if local.x < split:
				return -1

	var column: int = int(local.x / step.x)
	var row: int = int(local.y / step.y)
	if column < 0 or column >= columns or row < 0 or row >= rows:
		return -1
	# Inside the cell's slot, but is it inside the cell or in the gap after it?
	if local.x - column * step.x > cell_size.x:
		return -1
	if local.y - row * step.y > cell_size.y:
		return -1
	return index_of(row, column)


## Step one cubby in a direction, wrapping at the edges.
##
## Wraps per axis — walking off the right of a shelf returns to the left of the
## SAME shelf rather than dropping to the next one. Reading-order wrap would move
## the selection two ways at once for one press, which is exactly the thing that
## makes a grid feel like it is fighting you.
func neighbour(index: int, dx: int, dy: int) -> int:
	if not is_valid(index):
		return -1
	var cols: int = maxi(columns, 1)
	var rws: int = maxi(rows, 1)
	# posmod, not %: GDScript's % keeps the sign of the dividend, so stepping
	# left from column 0 would land on -1 rather than the last column.
	var column: int = posmod(column_of(index) + dx, cols)
	var row: int = posmod(row_of(index) + dy, rws)
	return index_of(row, column)
