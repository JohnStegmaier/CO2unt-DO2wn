extends Node

signal on_trigger_player_spawn(position: Vector2, direction: String)

var _spawn_door_tag := ""

func go_to_level(scene_path: String, destination_tag: String):
	if scene_path.is_empty():
		push_warning("NavigationManager: door has no destination_scene set")
		return
	_spawn_door_tag = destination_tag
	get_tree().change_scene_to_file(scene_path)

## Returns the door tag the player arrived through, then clears it.
## Returns "" when the level was opened directly rather than through a door.
func consume_spawn_door_tag() -> String:
	var tag := _spawn_door_tag
	_spawn_door_tag = ""
	return tag

func trigger_player_spawn(position: Vector2, direction: String):
	on_trigger_player_spawn.emit(position, direction)
