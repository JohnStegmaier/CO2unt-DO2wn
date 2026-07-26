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


## Where a cubby sits, in room-local space.
func cell_rect(index: int) -> Rect2:
	if not is_valid(index):
		return Rect2()
	var step: Vector2 = stride()
	return Rect2(
		origin + Vector2(column_of(index) * step.x, row_of(index) * step.y),
		cell_size
	)


## Where a whole shelf plank sits — the full width of the grid, under one row.
func row_rect(row: int) -> Rect2:
	var step: Vector2 = stride()
	var width: float = maxi(columns, 0) * step.x - cell_spacing.x
	return Rect2(
		origin + Vector2(0.0, row * step.y),
		Vector2(width, cell_size.y)
	)


## The whole shelf's footprint, for placing it against the wall.
func bounds() -> Rect2:
	var step: Vector2 = stride()
	return Rect2(origin, Vector2(
		maxi(columns, 0) * step.x - cell_spacing.x,
		maxi(rows, 0) * step.y - cell_spacing.y
	))


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
