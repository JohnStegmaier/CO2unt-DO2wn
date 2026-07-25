extends Node2D

## Where a run ends.
##
## PLACEHOLDER: two text options and a caret, no art. The selection is a plain
## index driven by ui_up/ui_down/ui_accept rather than Buttons, matching the main
## menu — the project has no Theme and no Control-based menu, and a bare Label
## is the easiest thing to swap for a sprite when the art lands.

const GAME_SCENE := "res://src/screens/game/game.tscn"
const MAIN_MENU_SCENE := "res://src/screens/main_menu/main_menu.tscn"

const SELECTED := Color(1.0, 0.451, 0.0, 1.0)
const UNSELECTED := Color(0.667, 0.947, 1.0, 1.0)

const CAPTIONS := ["REPLAY", "MAIN MENU"]

@onready var _options: Array[Label] = [$CanvasLayer/Replay, $CanvasLayer/MainMenu]

var _selection := 0
## Set once we have navigated away, so a second Enter during the scene change
## cannot fire a second change_scene_to_file.
var _leaving := false


func _ready() -> void:
	# Whatever killed the player left the tree paused or the music running only
	# if something went wrong upstream — but this screen is also reachable by
	# running the scene directly, so make no assumptions.
	get_tree().paused = false
	AudioManager.stop_music()
	_update_options()


func _process(_delta: float) -> void:
	if _leaving:
		return

	var step := int(Input.is_action_just_pressed("ui_down")) - int(Input.is_action_just_pressed("ui_up"))
	if step != 0:
		_selection = wrapi(_selection + step, 0, _options.size())
		_update_options()

	if Input.is_action_just_pressed("ui_accept"):
		_confirm()


func _confirm() -> void:
	_leaving = true
	NavigationManager.go_to_screen(GAME_SCENE if _selection == 0 else MAIN_MENU_SCENE)


func _update_options() -> void:
	for i in _options.size():
		var option: Label = _options[i]
		var chosen: bool = i == _selection
		option.modulate = SELECTED if chosen else UNSELECTED
		option.text = ("> %s <" if chosen else "  %s  ") % CAPTIONS[i]
