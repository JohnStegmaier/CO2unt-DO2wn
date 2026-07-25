extends Node

const stage = preload("res://src/levels/stage/stage.tscn")
const stage_left = preload("res://src/levels/stage/stage_left.tscn")

signal on_trigger_player_spawn(position: Vector2, direction: String)

var spawn_door_tag

func go_to_level(level_tag, destination_tag):
	var scene_to_load
	
	match level_tag:
		"stage":
			scene_to_load = stage
		"stage_left":
			scene_to_load = stage_left
			
	if scene_to_load != null:
		spawn_door_tag = destination_tag
		get_tree().change_scene_to_packed(scene_to_load)
		
func trigger_player_spawn(position: Vector2, direction: String):
	on_trigger_player_spawn.emit(position, direction)