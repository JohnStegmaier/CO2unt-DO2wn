class_name ShopStock
extends RefCounted

## What one shop still has on its shelves.
##
## Slot-addressed rather than a plain list: a bought item leaves a hole where it
## was instead of everything shuffling up, so the shelf reads as picked-over and
## the selection frame does not jump under the player's hand mid-purchase.
##
## Owned by [ShopRegistry] for the length of a run, NOT by the room. Rooms are
## freed when the player walks out, so stock held on the room node would restock
## itself on every re-entry.

## Empty slot. Named because `null` at a call site reads as "no answer" rather
## than "nothing on this shelf".
const EMPTY: ShopOffer = null

var _slots: Array[ShopOffer] = []


## Lay a provider's offers out on a shelf of the given size.
##
## Filled in order from the first cubby, and quietly truncated if the provider
## returns more than the shelf holds. Truncating rather than faulting is
## deliberate: the provider is configuration authored elsewhere, and a shop with
## one item too many should show eleven of them, not fail to open.
func _init(capacity: int, offers: Array = []) -> void:
	_slots.resize(maxi(capacity, 0))
	for i in mini(offers.size(), _slots.size()):
		_slots[i] = offers[i]


func capacity() -> int:
	return _slots.size()


func offer_at(index: int) -> ShopOffer:
	if index < 0 or index >= _slots.size():
		return EMPTY
	return _slots[index]


func has_offer_at(index: int) -> bool:
	return offer_at(index) != EMPTY


## How many cubbies still have something in them.
func count() -> int:
	var total: int = 0
	for slot in _slots:
		if slot != EMPTY:
			total += 1
	return total


func is_empty() -> bool:
	return count() == 0


## Lift an item off the shelf. Returns what was there, or null if the slot was
## already empty — so a double-press cannot sell the same thing twice.
func take(index: int) -> ShopOffer:
	var offer: ShopOffer = offer_at(index)
	if offer == EMPTY:
		return EMPTY
	_slots[index] = EMPTY
	return offer


## The first cubby with something in it, or -1 on a sold-out shop.
func first_populated() -> int:
	for i in _slots.size():
		if _slots[i] != EMPTY:
			return i
	return -1


## Step from one cubby toward the next one that has something in it.
##
## Skipping the holes is the whole point: after a few purchases a naive step
## lands the frame on empty cubbies and the player has to press through nothing.
## Bounded by the shelf size so a sold-out shop returns the slot it started on
## rather than looping forever.
func next_populated(from: int, dx: int, dy: int, grid: ShopGrid) -> int:
	if grid == null or grid.capacity() <= 0:
		return from
	var index: int = from
	for _step in grid.capacity():
		index = grid.neighbour(index, dx, dy)
		if index < 0:
			return from
		if has_offer_at(index):
			return index
	return from
