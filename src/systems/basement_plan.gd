class_name BasementPlan
extends RefCounted

## The Basement, drawn by hand.
##
## Every other floor is grown by [FloorGenerator] — fourteen to eighteen rooms
## rolled from a seed, with the specials dressed onto whichever dead ends came
## out. That is right for a floor the player is meant to explore and wrong for
## the one they are meant to arrive at. The Basement is the run's one secret and
## it has exactly one thing to say, so it is two rooms and always the same two:
##
##     [B]      the board room — six men in suits around a table
##      |
##     [S]      where the lift puts you down. One doorway, nothing in it.
##
## Kept out of FloorGenerator deliberately. That file's job is seeded growth with
## retries and invariants; a fixed two-room layout is not generation, and folding
## it in would mean every claim the generator makes about its output growing a
## "unless it is the Basement" clause. Game asks for a plan and this answers for
## one floor; nothing else changes.
##
## Node-free like the rest of src/systems/, so tools/check_basement.gd can settle
## it in a terminal.

## Where the lift puts the player down, and the plan's spawn.
const ARRIVAL := Vector2i.ZERO
## The board room, north of it.
const BOARD_ROOM := Vector2i(0, -1)

## The cell the board room's far half is drawn into, which must stay empty.
##
## The board room is ONE cell in this plan and two cells tall on the screen: it
## sits at BOARD_ROOM like any other room and draws 286px further north than its
## own cell, into here — see board_room.gd. Nothing in FloorPlan knows that, and
## nothing needs to, as long as this coordinate never holds a room. Put one here
## and the two would be drawn on top of each other.
const OVERHANG := Vector2i(0, -2)


## The floor, ready to walk into. Takes no seed and no config: there is one
## Basement and it is the same every run, which is what makes it a place rather
## than a roll.
static func build() -> FloorPlan:
	var plan := FloorPlan.new()
	plan.spawn_coord = ARRIVAL

	plan.add_room(RoomData.new(ARRIVAL, RoomData.Kind.SPAWN, 0))
	# BOSS rather than a kind of its own. Everything that ends the game already
	# hangs off this one — Game stocks a boss room, counts its dead, and calls
	# _clear_boss_gate when the last of them falls, which on the bottom floor is
	# what wins the run. A new Kind would have bought a tint in an array and a
	# glyph on the map, and cost a second path through the ending.
	plan.add_room(RoomData.new(BOARD_ROOM, RoomData.Kind.BOSS, 1))

	plan.connect_rooms(ARRIVAL, GridDirection.Side.NORTH)
	return plan
