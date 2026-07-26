class_name MinimapModel
extends RefCounted

## What the player is allowed to know about the floor they are standing on.
##
## The fog rules live here rather than in the widget so they can be settled in a
## terminal — see tools/check_minimap.gd. Nothing in here touches a node, and
## nothing in here knows how a room is drawn; it answers "may the player see
## this, and how much of it" and stops.
##
## The governing rule is that the map must never disclose anything exploration
## has not earned: not the floor's extent, not its shape, and not which unopened
## door leads to the boss. Every leak of that kind would be a leak from THIS
## file, which is why marker_at() and door_mask_at() refuse to answer for a room
## the player has only glimpsed.

## Fog states, worst-known to best-known. UNKNOWN is never stored — a coordinate
## the player knows nothing about is simply absent from _states.
##
## Passed around as plain int, like Kind and Side: GDScript does not unify an
## enum type across script boundaries. See the note in grid_direction.gd.
enum State { UNKNOWN, DISCOVERED, VISITED, CURRENT }

## Returned by marker_at() when a cell must not disclose what kind of room it is.
## Not a Kind value, deliberately — there is no "unknown room type", there is
## only the map declining to say.
const NO_MARKER := -1

var _plan: FloorPlan
var _current: Vector2i = Vector2i.ZERO
var _reveal_all: bool = false
## Coordinate -> State, holding only the cells the player may see. Rebuilt whole
## on every change rather than patched, because a patch has to know what the
## previous state was and the whole map is a few dozen dictionary writes.
var _states: Dictionary[Vector2i, int] = {}


## Point the model at a floor. Pass null to blank it — the runtime does exactly
## that when it throws a floor away, so the model does not keep the dead plan
## alive.
##
## The focus resets with the floor. Left alone it would carry the last floor's
## coordinate into this one, and if that coordinate happens to exist here too it
## would be marked as somewhere the player has stood and its neighbours revealed
## — fog lifted off a floor nobody has walked a step of. The runtime does call
## set_current straight after today, but a leak that depends on two calls staying
## adjacent in another file is a leak waiting to happen.
func set_floor(plan: FloorPlan) -> void:
	_plan = plan
	_current = plan.spawn_coord if plan != null else Vector2i.ZERO
	_refresh()


## The player is now standing here. Reveals this room's unvisited neighbours,
## and demotes whichever room was CURRENT back to VISITED.
##
## Does NOT set visited on the room — the runtime already does that at the same
## choke point, and a model that wrote to the plan would be a second author of
## the same fact.
func set_current(coord: Vector2i) -> void:
	_current = coord
	_refresh()


## Dev cheat: drop the fog and show the whole floor, kinds and all. Survives a
## floor change on its own, because set_floor() only swaps the plan.
func set_reveal_all(reveal: bool) -> void:
	if _reveal_all == reveal:
		return
	_reveal_all = reveal
	_refresh()


func is_revealing_all() -> bool:
	return _reveal_all


## What the view centres its grid on. The spawn coordinate rather than the
## player's, so the map is nailed in place and a room keeps the same cell for a
## whole floor. Safe to expose: the player starts there, so it tells them
## nothing they do not already know.
func origin_coord() -> Vector2i:
	return _plan.spawn_coord if _plan != null else Vector2i.ZERO


func current_coord() -> Vector2i:
	return _current


func state_at(coord: Vector2i) -> int:
	return _states.get(coord, State.UNKNOWN)


## The room's Kind, or NO_MARKER when the map must not say.
##
## This is the line that keeps the boss a surprise. A room the player has merely
## seen the door of is reported as unmarked, so on the map it is indistinguishable
## from any other unexplored room — which is the whole point of walking into it.
func marker_at(coord: Vector2i) -> int:
	var state: int = state_at(coord)
	if state != State.VISITED and state != State.CURRENT:
		return NO_MARKER
	return _plan.get_room(coord).kind


## The room's door mask, or 0 when the map must not say.
##
## Zero for a merely-discovered room for the same reason as above: the player has
## seen the one door they are standing at, and drawing the other three would sketch
## out the floor's shape ahead of them.
func door_mask_at(coord: Vector2i) -> int:
	var state: int = state_at(coord)
	if state != State.VISITED and state != State.CURRENT:
		return 0
	return _plan.get_room(coord).doors


func visible_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord in _states:
		coords.append(coord)
	return coords


func visible_count() -> int:
	return _states.size()


## Rebuild the fog from scratch.
##
## Discovery is derived from visited plus the door masks rather than stored as a
## flag of its own. A stored flag would be a second source of truth that whoever
## sets visited has to remember to keep in step, and it would buy nothing, since
## a room is never un-discovered.
##
## The derivation is only sound because doors are symmetric and never open onto
## an empty cell — both invariants the generator guarantees and check_floors.gd
## asserts. check_minimap.gd re-asserts the second one through this model, so if
## that ever changes the map fails loudly instead of drawing rooms that are not
## there.
func _refresh() -> void:
	_states.clear()
	if _plan == null:
		return

	if _reveal_all:
		for coord in _plan.rooms:
			_states[coord] = State.VISITED
	else:
		for coord in _plan.rooms:
			if _plan.get_room(coord).visited:
				_states[coord] = State.VISITED

		# Standing in a room counts as having been in it, whether or not the
		# runtime has stamped visited yet. It does stamp it first today, but the
		# order of two calls in another file should not decide whether this
		# room's neighbours appear on the map.
		if _plan.has_room(_current):
			_states[_current] = State.VISITED

		# keys() is a copy, so the frontier can be added to while walking it.
		for coord in _states.keys():
			for side in GridDirection.SIDES:
				if not _plan.get_room(coord).has_door(side):
					continue
				var neighbour: Vector2i = coord + GridDirection.offset(side)
				# Guarded rather than assigned, so a room already visited is
				# never demoted to DISCOVERED by a neighbour looking outward.
				if not _states.has(neighbour):
					_states[neighbour] = State.DISCOVERED

	# Stamped last, and unconditionally. That single write is what makes "the
	# room you just left goes back to a plain visited room" fall out for free —
	# it was only ever CURRENT because _current pointed at it.
	if _plan.has_room(_current):
		_states[_current] = State.CURRENT
