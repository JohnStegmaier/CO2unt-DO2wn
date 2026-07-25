extends Node2D

## Standalone harness for the elevator lobby — select this scene and press F6.
##
## It stands in for Game and calls precisely the things Game calls on a room:
## configure(), spawn_position(), interior_rect(), door_entered and
## elevator_entered. That is deliberate. If the lobby ever stops satisfying Room's
## contract, this scene breaks first and in isolation, instead of a floor deep into
## a run.
##
## No HUD and no ride: the O2 refill, the descent overlay and the next floor are
## all Game's job. Boarding just says so and reloads, which is enough to ride the
## elevator again without restarting.

## Which grid side the harness pretends the lobby was entered from. Change it in
## the inspector to prove the near door reports whichever side the floor plan gave
## it, not the south it physically faces.
@export_enum("north", "east", "south", "west") var arrive_side: int = 0

@onready var _room: ElevatorRoom = $ElevatorRoom
@onready var _player: Player = $Player
@onready var _camera: Camera2D = $Player/Camera2D


func _ready() -> void:
	# A stand-in for the cell the floor plan would hand over: an exit room whose one
	# doorway is on arrive_side. Built here rather than taken from a generator so
	# the harness stays independent of how floors are made.
	var data := RoomData.new(Vector2i.ZERO, RoomData.Kind.EXIT)
	data.doors = GridDirection.bit(arrive_side)

	_room.configure(data)
	_room.door_entered.connect(_on_door_entered)
	_room.elevator_entered.connect(_on_elevator_entered)
	_player.warp_to(_room.spawn_position(arrive_side))
	_camera.set_bounds(_room.interior_rect())


func _on_door_entered(side: int) -> void:
	print("ElevatorDebug: would return through %s" % GridDirection.side_name(side))


func _on_elevator_entered() -> void:
	print("ElevatorDebug: boarded — Game would play the ride and build the next floor")
	# Reload rather than free the room: Game replaces the whole floor at this
	# point, and a harness that left an empty screen would only be testable once.
	get_tree().reload_current_scene()
