extends SceneTree

## Assert the shape of a run: six floors, counting down, ending in a Basement.
##
## [FloorLadder] is the only thing standing between an index that counts up and a
## number on the wall that counts down, and getting it wrong is the kind of bug
## that reads fine in code and only shows up as a 6 on a plate that has no 6. It
## is pure logic, so it can be settled in a terminal:
##
##   godot --headless --script tools/check_ladder.gd
##
## Also checks the plates the ride draws those numbers with, because a ladder that
## is right and a plate table that is one short would strand a ride on the last
## floor of the game.

const RIDE := preload("res://src/ui/elevator_ride/elevator_ride.gd")

## What the player should see, floor by floor, top to bottom.
const EXPECTED_LABELS := ["5", "4", "3", "2", "1", "B"]


func _initialize() -> void:
	var failures: Array[String] = []

	if FloorLadder.FLOOR_COUNT != EXPECTED_LABELS.size():
		failures.append("FLOOR_COUNT is %d, but the run is %d floors long"
				% [FloorLadder.FLOOR_COUNT, EXPECTED_LABELS.size()])

	for index in EXPECTED_LABELS.size():
		var want: String = EXPECTED_LABELS[index]
		var got: String = FloorLadder.label(index)
		if got != want:
			failures.append("index %d reads %s, should read %s" % [index, got, want])

	# The Basement is the bottom and nothing above it is.
	for index in FloorLadder.FLOOR_COUNT - 1:
		if FloorLadder.is_basement(index):
			failures.append("index %d thinks it is the Basement" % index)
		if FloorLadder.is_final(index):
			failures.append("index %d thinks the run ends there" % index)
	if not FloorLadder.is_basement(FloorLadder.BASEMENT_INDEX):
		failures.append("the Basement does not know it is the Basement")
	if not FloorLadder.is_final(FloorLadder.BASEMENT_INDEX):
		failures.append("the Basement is not the end of the run")

	# Floor 1 is the gate: its boss is what puts a Basement under the building.
	if FloorLadder.label(FloorLadder.BOSS_GATE_INDEX) != "1":
		failures.append("the boss gate is on floor %s, not floor 1"
				% FloorLadder.label(FloorLadder.BOSS_GATE_INDEX))
	if not FloorLadder.gates_on_boss(FloorLadder.BOSS_GATE_INDEX):
		failures.append("floor 1 does not gate on its boss")
	if not FloorLadder.gates_on_boss(FloorLadder.BASEMENT_INDEX):
		failures.append("the Basement does not gate on its boss")
	for index in FloorLadder.BOSS_GATE_INDEX:
		if FloorLadder.gates_on_boss(index):
			failures.append("index %d gates on its boss and should not" % index)

	# Spoken labels, which is what the ride's caption and the console print use.
	if FloorLadder.long_label(0) != "FLOOR 5":
		failures.append("the first floor is called %s" % FloorLadder.long_label(0))
	if FloorLadder.long_label(FloorLadder.BASEMENT_INDEX) != "BASEMENT":
		failures.append("the last floor is called %s"
				% FloorLadder.long_label(FloorLadder.BASEMENT_INDEX))

	# Out of range clamps rather than faulting — a ride must never be stranded.
	if FloorLadder.label(-1) != "5":
		failures.append("a negative index does not clamp to the top floor")
	if FloorLadder.label(99) != FloorLadder.BASEMENT_LABEL:
		failures.append("an index past the bottom does not clamp to the Basement")

	failures.append_array(_check_plates())

	if failures.is_empty():
		print("OK — %d floors, %s, ending in the Basement"
				% [FloorLadder.FLOOR_COUNT, " ".join(EXPECTED_LABELS)])
		quit(0)
		return

	print("FAILED — %d problems" % failures.size())
	for failure in failures:
		print("  " + failure)
	quit(1)


## One plate per floor, all distinct, none of them the blank. A duplicate here
## would show the wrong number without anything else going wrong.
func _check_plates() -> Array[String]:
	var errors: Array[String] = []
	if RIDE.PLATES.size() != FloorLadder.FLOOR_COUNT:
		errors.append("%d plates for %d floors" % [RIDE.PLATES.size(), FloorLadder.FLOOR_COUNT])

	var seen: Dictionary = {}
	for index in RIDE.PLATES.size():
		var plate: Texture2D = RIDE.PLATES[index]
		if plate == null:
			errors.append("index %d has no plate" % index)
			continue
		if plate == RIDE.PLATE_BLANK:
			errors.append("index %d is drawn with the unlit plate" % index)
		var path: String = plate.resource_path
		if seen.has(path):
			errors.append("index %d and index %d share a plate" % [seen[path], index])
		seen[path] = index
	return errors
