extends Node2D

## Standalone harness for the elevator lobby — select this scene and press F6.
##
## It stands in for Game and calls precisely the four things Game calls on a room:
## configure(), spawn_position(), interior_rect() and door_entered, plus the
## lobby's own boarded signal. That is deliberate. If the lobby ever stops
## satisfying Room's contract, this scene breaks first and in isolation, instead
## of two rooms deep into a run.
##
## No HUD: applying the O2 refill is Game's job, so boarding only reports what it
## decided and reloads, which is enough to ride the elevator again without
## restarting.

## Which grid side the harness pretends the lobby was entered from. Change it in
## the inspector to prove the near door reports whichever side the floor plan gave
## it, not the south it physically faces.
@export_enum("north", "east", "south", "west") var arrive_side: int = 0

@onready var _room: ElevatorRoom = $ElevatorRoom
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D


func _ready() -> void:
	_room.configure(GridDirection.bit(arrive_side))
	_room.door_entered.connect(_on_door_entered)
	_room.boarded.connect(_on_boarded)
	_player.warp_to(_room.spawn_position(arrive_side))
	_camera.set_bounds(_room.interior_rect())


func _on_door_entered(side: int) -> void:
	print("ElevatorDebug: would return through %s" % GridDirection.side_name(side))


func _on_boarded(refill_o2: bool) -> void:
	print("ElevatorDebug: boarded (refill_o2=%s)" % refill_o2)
	# Reload rather than free the room: Game replaces the whole floor at this
	# point, and a harness that left an empty screen would only be testable once.
	get_tree().reload_current_scene()
