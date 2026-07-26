extends SceneTree

## Assert everything [ShopGrid], [ShopStock] and [ShopRegistry] claim.
##
## All three are deliberately pure logic, so the shelf's indexing and the
## selection's wrap can be settled in a terminal instead of by pressing D against
## the edge of a shop and watching. Run it after touching any of them, or after
## changing the grid defaults:
##
##   godot --headless --script tools/check_shop.gd
##
## Exits non-zero when an invariant breaks, so it can gate CI.

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_check_grid_indexing()
	_check_grid_geometry()
	_check_grid_wrap()
	_check_cell_at()
	_check_degenerate_grids()
	_check_stock_fill()
	_check_stock_take()
	_check_stock_navigation()
	_check_sold_out()
	_check_registry_persistence()

	print("ran %d assertions" % _checks)
	if _failures.is_empty():
		print("OK — every invariant held")
		quit(0)
		return

	print("FAILED — %d problems" % _failures.size())
	for failure in _failures:
		print("  " + failure)
	quit(1)


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s — got %s, expected %s" % [message, actual, expected])


## Every index maps to exactly one (row, column) and back again.
func _check_grid_indexing() -> void:
	var grid := _grid(4, 12)
	_equal(grid.capacity(), 48, "4x12 capacity")

	for index in grid.capacity():
		var round_trip: int = grid.index_of(grid.row_of(index), grid.column_of(index))
		_equal(round_trip, index, "index %d round trips" % index)

	_ok(not grid.is_valid(-1), "-1 is not a valid index")
	_ok(not grid.is_valid(48), "48 is out of range on a 48-cell grid")
	_equal(grid.cell_rect(-1), Rect2(), "an invalid index has no rect")


## Cubbies tile left to right and top to bottom without overlapping.
func _check_grid_geometry() -> void:
	var grid := _grid(4, 12)
	var first: Rect2 = grid.cell_rect(0)
	_equal(first.position, grid.origin, "first cubby sits on the origin")
	_equal(first.size, grid.cell_size, "a cubby is cell_size")

	# Neighbours are exactly one stride apart, and the gap between them is the
	# spacing — which is what stops the generated planks overlapping the items.
	var second: Rect2 = grid.cell_rect(1)
	_equal(second.position.x - first.position.x, grid.stride().x, "columns are one stride apart")
	_equal(second.position.x - first.end.x, grid.cell_spacing.x, "the gap is cell_spacing")

	var below: Rect2 = grid.cell_rect(grid.index_of(1, 0))
	_equal(below.position.y - first.position.y, grid.stride().y, "rows are one stride apart")

	# The overall footprint must not trail a spacing gap off its right or bottom
	# edge, or the shelf sits visibly off-centre against the wall.
	var bounds: Rect2 = grid.bounds()
	var last: Rect2 = grid.cell_rect(grid.capacity() - 1)
	_equal(bounds.end, last.end, "bounds end on the last cubby, not past it")
	_equal(grid.row_rect(0).end.x, bounds.end.x, "a plank spans the full shelf width")


## Stepping off an edge wraps within the same row or column, never diagonally.
func _check_grid_wrap() -> void:
	var grid := _grid(4, 12)

	_equal(grid.neighbour(0, 1, 0), 1, "right from the first cubby")
	_equal(grid.neighbour(0, -1, 0), 11, "left from column 0 wraps to column 11")
	_equal(grid.neighbour(11, 1, 0), 0, "right from the last column wraps to column 0")
	_equal(grid.neighbour(0, 0, -1), grid.index_of(3, 0), "up from row 0 wraps to row 3")
	_equal(grid.neighbour(grid.index_of(3, 0), 0, 1), 0, "down from the last row wraps to row 0")

	# The wrap is per axis. Walking off the right of a shelf must NOT drop the
	# selection onto the next shelf down — one press, one axis.
	for row in 4:
		var last_in_row: int = grid.index_of(row, 11)
		var wrapped: int = grid.neighbour(last_in_row, 1, 0)
		_equal(grid.row_of(wrapped), row, "wrapping right stays on row %d" % row)

	# Twelve steps in any direction is a full lap back to where you started.
	var index := 5
	for _step in 12:
		index = grid.neighbour(index, 1, 0)
	_equal(index, 5, "twelve right steps is a full lap")

	_equal(grid.neighbour(-1, 1, 0), -1, "stepping from an invalid index stays invalid")


## Pointing at a cubby, in the gap between two, and off the shelf entirely.
##
## This is what the mouse hover reads, so it has to agree exactly with the rects
## the cubbies are drawn from — a hover that highlights a cell the cursor is not
## visibly inside is worse than no hover at all.
func _check_cell_at() -> void:
	var grid := _grid(4, 12)

	# Every cubby's own centre, and its top-left corner, resolve to itself.
	for index in grid.capacity():
		var rect: Rect2 = grid.cell_rect(index)
		_equal(grid.cell_at(rect.get_center()), index, "centre of cubby %d" % index)
		_equal(grid.cell_at(rect.position), index, "top-left of cubby %d" % index)

	# The gaps are where the planks are drawn. A cursor on a plank points at
	# nothing rather than at whichever cubby happens to be nearest.
	var first: Rect2 = grid.cell_rect(0)
	var gap_x: Vector2 = Vector2(first.end.x + grid.cell_spacing.x * 0.5, first.get_center().y)
	_equal(grid.cell_at(gap_x), -1, "the gap between two columns is nothing")
	var gap_y: Vector2 = Vector2(first.get_center().x, first.end.y + grid.cell_spacing.y * 0.5)
	_equal(grid.cell_at(gap_y), -1, "the gap between two rows is nothing")

	# Off the shelf in every direction.
	_equal(grid.cell_at(grid.origin - Vector2(1, 1)), -1, "above and left of the shelf")
	_equal(grid.cell_at(grid.origin - Vector2(1, 0)), -1, "left of the shelf")
	_equal(grid.cell_at(grid.origin - Vector2(0, 1)), -1, "above the shelf")
	_equal(grid.cell_at(grid.bounds().end + Vector2(1, 1)), -1, "past the far corner")
	_equal(grid.cell_at(Vector2(-500, -500)), -1, "nowhere near it")

	# The far corner of the last cubby is still inside it — the shelf's bounds
	# end on the last cubby rather than a spacing gap past it.
	var last: Rect2 = grid.cell_rect(grid.capacity() - 1)
	_equal(grid.cell_at(last.end), grid.capacity() - 1, "far corner of the last cubby")

	# Round trip: cell_at is the inverse of cell_rect for every centre.
	for index in grid.capacity():
		_equal(grid.cell_at(grid.cell_rect(index).get_center()), index,
				"cell_at inverts cell_rect for %d" % index)

	var empty := _grid(0, 0)
	_equal(empty.cell_at(Vector2.ZERO), -1, "an empty grid contains no point")


## A 1xN or Nx1 shelf still behaves, and a 0-cell one does not divide by zero.
func _check_degenerate_grids() -> void:
	var single := _grid(1, 1)
	_equal(single.capacity(), 1, "1x1 capacity")
	_equal(single.neighbour(0, 1, 0), 0, "the only cubby wraps to itself")
	_equal(single.neighbour(0, 0, 1), 0, "vertically too")

	var strip := _grid(1, 6)
	_equal(strip.neighbour(0, 0, 1), 0, "a one-row shelf cannot move vertically")
	_equal(strip.neighbour(5, 1, 0), 0, "but still wraps horizontally")

	var column := _grid(6, 1)
	_equal(column.neighbour(0, 1, 0), 0, "a one-column shelf cannot move horizontally")
	_equal(column.neighbour(5, 0, 1), 0, "but still wraps vertically")

	var empty := _grid(0, 0)
	_equal(empty.capacity(), 0, "an empty grid holds nothing")
	_ok(not empty.is_valid(0), "and index 0 is not valid on it")
	_equal(empty.neighbour(0, 1, 0), -1, "stepping on an empty grid returns -1")


## Offers land in the first cubbies in order, and a long list is truncated.
func _check_stock_fill() -> void:
	var stock := ShopStock.new(6, [_offer(10), _offer(20)])
	_equal(stock.capacity(), 6, "capacity is the shelf size, not the offer count")
	_equal(stock.count(), 2, "two offers on a six-cubby shelf")
	_equal(stock.offer_at(0).price, 10, "first offer in the first cubby")
	_equal(stock.offer_at(1).price, 20, "second offer in the second")
	_ok(not stock.has_offer_at(2), "the rest are empty")
	_ok(stock.offer_at(99) == null, "reading past the end is null, not a fault")
	_ok(stock.offer_at(-1) == null, "and so is reading before the start")

	# More offers than cubbies is configuration authored elsewhere. A shop with
	# one item too many should open showing three, not fail to open.
	var crowded := ShopStock.new(3, [_offer(1), _offer(2), _offer(3), _offer(4)])
	_equal(crowded.count(), 3, "a too-long list is truncated to the shelf")

	var bare := ShopStock.new(4, [])
	_ok(bare.is_empty(), "a shop with no offers is empty")
	_equal(bare.first_populated(), -1, "and has no first item")


## Taking leaves a hole rather than shuffling, and cannot be done twice.
func _check_stock_take() -> void:
	var stock := ShopStock.new(4, [_offer(10), _offer(20), _offer(30)])

	var taken: ShopOffer = stock.take(1)
	_ok(taken != null, "taking a populated cubby returns the offer")
	_equal(taken.price, 20, "and returns the right one")
	_ok(not stock.has_offer_at(1), "the cubby is now empty")
	_equal(stock.count(), 2, "two left")

	# The hole must stay where it was. If stock shuffled up, the selection frame
	# would jump under the player's hand the instant they bought something.
	_equal(stock.offer_at(0).price, 10, "the cubby before the hole is untouched")
	_equal(stock.offer_at(2).price, 30, "and so is the one after it")

	_ok(stock.take(1) == null, "taking the same cubby twice returns nothing")
	_equal(stock.count(), 2, "and does not change the count")
	_ok(stock.take(99) == null, "taking out of range is null, not a fault")


## The selection skips holes, in both directions.
func _check_stock_navigation() -> void:
	var grid := _grid(2, 4)
	# Cubbies 0, 1, 2 filled on the top row; 3 and the whole bottom row empty.
	var stock := ShopStock.new(grid.capacity(), [_offer(1), _offer(2), _offer(3)])

	_equal(stock.first_populated(), 0, "first populated is the first cubby")

	stock.take(1)
	# From 0, stepping right must skip the hole at 1 and land on 2.
	_equal(stock.next_populated(0, 1, 0, grid), 2, "stepping right skips the hole")
	_equal(stock.next_populated(2, -1, 0, grid), 0, "and stepping left skips it too")

	# Wrapping past the empty tail must come back around to a populated cubby
	# rather than stopping on nothing.
	_equal(stock.next_populated(2, 1, 0, grid), 0, "wrapping past empties finds cubby 0")

	# Vertical movement across a wholly empty row lands back on the same column.
	_equal(stock.next_populated(0, 0, 1, grid), 0, "down through an empty row returns to 0")

	_equal(stock.next_populated(0, 1, 0, null), 0, "a null grid is survivable")


## A sold-out shop must not loop forever looking for something to select.
func _check_sold_out() -> void:
	var grid := _grid(3, 3)
	var stock := ShopStock.new(grid.capacity(), [_offer(5)])
	stock.take(0)

	_ok(stock.is_empty(), "the shop is sold out")
	_equal(stock.first_populated(), -1, "nothing to select")
	# The bound is the whole point: without it this walks the grid forever.
	_equal(stock.next_populated(0, 1, 0, grid), 0, "navigation returns where it started")
	_equal(stock.next_populated(4, 0, -1, grid), 4, "from any cubby, in any direction")


## The same shop hands back the same shelves; different shops do not share.
func _check_registry_persistence() -> void:
	var registry := ShopRegistry.new()
	var provider := StaticShopStockProvider.new()
	provider.offers = [_offer(10), _offer(15)]

	_ok(not registry.knows(0, Vector2i(2, 3)), "an unvisited shop is unknown")

	var first: ShopStock = registry.stock_for(provider, 0, Vector2i(2, 3), 12)
	_equal(first.count(), 2, "the provider stocked it")
	_ok(registry.knows(0, Vector2i(2, 3)), "and it is remembered")

	first.take(0)
	var revisit: ShopStock = registry.stock_for(provider, 0, Vector2i(2, 3), 12)
	_ok(revisit == first, "re-entering returns the same shelves")
	_equal(revisit.count(), 1, "so a bought item stays bought")

	# The provider's own array must not have been emptied by that purchase, or
	# every other shop in the run inherits the hole.
	_equal(provider.offers.size(), 2, "the provider's configuration is untouched")

	# Coordinates repeat between floors. The shop on floor 1 at (2,3) is a
	# different shop from the one on floor 0 at (2,3).
	var next_floor: ShopStock = registry.stock_for(provider, 1, Vector2i(2, 3), 12)
	_ok(next_floor != first, "the same cell on another floor is another shop")
	_equal(next_floor.count(), 2, "and it is fully stocked")

	var elsewhere: ShopStock = registry.stock_for(provider, 0, Vector2i(9, 9), 12)
	_ok(elsewhere != first, "a different cell on the same floor is another shop")

	registry.forget_floor(0)
	_ok(not registry.knows(0, Vector2i(2, 3)), "forgetting a floor drops its shops")
	_ok(registry.knows(1, Vector2i(2, 3)), "and leaves other floors alone")

	# A shop with no provider at all is bare rather than broken.
	var orphan: ShopStock = ShopRegistry.new().stock_for(null, 0, Vector2i.ZERO, 8)
	_equal(orphan.capacity(), 8, "a provider-less shop still has shelves")
	_ok(orphan.is_empty(), "they are just empty")


func _grid(rows: int, columns: int) -> ShopGrid:
	var grid := ShopGrid.new()
	grid.rows = rows
	grid.columns = columns
	return grid


func _offer(price: int) -> ShopOffer:
	var offer := ShopOffer.new()
	offer.price = price
	return offer
