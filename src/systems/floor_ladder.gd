class_name FloorLadder
extends RefCounted

## The run's shape, top to bottom: floor 5 down to the Basement.
##
## The game is a countdown, so the number on the wall goes DOWN. Everything else
## in the codebase counts UP — [member Game._floor_number] is floors descended,
## and it has to be, because [method FloorGenerator.floor_seed_for] and
## [method FloorConfig.room_range] both want a value that grows with depth. This
## is the one place those two directions are reconciled, so nothing else has to
## know that the fifth floor is index zero.
##
##   index:  0    1    2    3    4    5
##   floor:  5    4    3    2    1    B
##
## Pure logic and no textures. The plates that draw these numbers live next to the
## node that draws them (see elevator_ride.gd), the same way nothing else in
## src/systems/ touches a node — which is what lets tools/check_ladder.gd settle
## this file in a terminal.

## The floor the run starts on, and the number of numbered floors.
const TOP_FLOOR := 5
## Descent index of the Basement: the floor the player is not told about.
const BASEMENT_INDEX := 5
## Descent index of floor 1. Its boss is the gate on the Basement — beat it and
## the car will take you somewhere the button panel never advertised.
const BOSS_GATE_INDEX := 4
## Indices in a run, counting the Basement.
const FLOOR_COUNT := BASEMENT_INDEX + 1

## What the Basement's readout shows in place of a digit.
const BASEMENT_LABEL := "B"


## The number on the wall for a given descent index. Out-of-range indices clamp
## rather than fault: a floor that should not exist is a bug worth a warning
## somewhere, not a crash in the middle of a ride.
static func label(index: int) -> String:
	if index >= BASEMENT_INDEX:
		return BASEMENT_LABEL
	return str(TOP_FLOOR - maxi(index, 0))


## The same thing said out loud, for the ride's readout and the console.
static func long_label(index: int) -> String:
	if index >= BASEMENT_INDEX:
		return "BASEMENT"
	return "FLOOR %s" % label(index)


static func is_basement(index: int) -> bool:
	return index >= BASEMENT_INDEX


## Nothing below this floor, so the elevator has nowhere to go. Today that is
## only the Basement, but callers ask the question rather than testing for the
## Basement themselves — a run that gains a sub-basement changes this line alone.
static func is_final(index: int) -> bool:
	return index >= BASEMENT_INDEX


## Must this floor's boss die before the way down opens?
##
## True on floor 1, where killing the boss is what reveals the Basement, and true
## in the Basement itself, where the boss is the end of the game and the car must
## never move again whatever happens.
static func gates_on_boss(index: int) -> bool:
	return index == BOSS_GATE_INDEX or is_basement(index)
