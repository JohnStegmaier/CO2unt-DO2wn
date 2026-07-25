extends Area2D

class_name LevelDoor

@export var destination_room_name: String
@export var destination_door_uuid: String
@export var spawn_direction = "up"

@onready var spawn = $spawn_location

func _on_body_entered(body):
	if body is Player:
		NavigationManager.go_to_level(destination_room_name, destination_door_uuid) # Replace with function body.
