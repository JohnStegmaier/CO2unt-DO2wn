extends Node

## Screen-level navigation: menu to game, game to game over.
##
## Room-to-room movement is NOT here. Rooms are swapped inside the Game scene
## without a scene change, so nothing has to be carried across one.

## Handed to the next screen, and cleared the moment it is taken.
##
## The game over screen shows the frame the player died on, and an autoload is
## the only thing that outlives the scene swap that carries it there. Deliberately
## one anonymous slot rather than a growing bag of named state: if a second
## screen ever needs something, that is the point to stop and give screens real
## arguments instead of widening this.
var _payload: Variant = null


func go_to_screen(scene_path: String, payload: Variant = null) -> void:
	if scene_path.is_empty():
		push_warning("NavigationManager: empty scene path")
		return
	_payload = payload
	get_tree().change_scene_to_file(scene_path)


## Read once. A screen reached any other way — run directly from the editor, or
## navigated to twice — gets null rather than a stale frame from a past run.
func take_payload() -> Variant:
	var payload: Variant = _payload
	_payload = null
	return payload
