extends Node

## Screen-level navigation: menu to game, game to game over.
##
## Room-to-room movement is NOT here. Rooms are swapped inside the Game scene
## without a scene change, so nothing has to be carried across one.

func go_to_screen(scene_path: String) -> void:
	if scene_path.is_empty():
		push_warning("NavigationManager: empty scene path")
		return
	get_tree().change_scene_to_file(scene_path)
