extends Node2D

## Where a run ends.
##
## PLACEHOLDER: two text options and a caret, no art. The selection is a plain
## index driven by ui_up/ui_down/ui_accept rather than Buttons, matching the main
## menu — the project has no Theme and no Control-based menu, and a bare Label
## is the easiest thing to swap for a sprite when the art lands.
##
## The mouse drives the same index rather than a parallel path: hovering an option
## selects it and clicking one confirms it, so the caret always agrees with what a
## click is about to do. Labels default to MOUSE_FILTER_IGNORE, so the scene sets
## these two to STOP — without that they are invisible to the mouse.

const GAME_SCENE := "res://src/screens/game/game.tscn"
const MAIN_MENU_SCENE := "res://src/screens/main_menu/main_menu.tscn"

const SELECTED := Color(1.0, 0.451, 0.0, 1.0)
const UNSELECTED := Color(0.667, 0.947, 1.0, 1.0)

const CAPTIONS := ["REPLAY", "MAIN MENU"]

@onready var _options: Array[Label] = [$CanvasLayer/Replay, $CanvasLayer/MainMenu]
@onready var _last_frame: TextureRect = $CanvasLayer/LastFrame
@onready var _scrim: ColorRect = $CanvasLayer/Scrim

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
	_show_last_frame(NavigationManager.take_payload())
	for i in _options.size():
		var option: Label = _options[i]
		option.mouse_entered.connect(_on_option_hovered.bind(i))
		option.gui_input.connect(_on_option_gui_input.bind(i))
	_update_options()


## The frame the player died on, so the body stays exactly where they left it on
## screen. Null when this screen is reached any other way — run straight from the
## editor, say — in which case the plain background is all there is.
func _show_last_frame(payload: Variant) -> void:
	var frame := payload as Texture2D
	_last_frame.texture = frame
	_last_frame.visible = frame != null
	_scrim.visible = frame != null


func _process(_delta: float) -> void:
	if _leaving:
		return

	var step := int(Input.is_action_just_pressed("ui_down")) - int(Input.is_action_just_pressed("ui_up"))
	if step != 0:
		_selection = wrapi(_selection + step, 0, _options.size())
		_update_options()

	if Input.is_action_just_pressed("ui_accept"):
		_confirm()


func _on_option_hovered(index: int) -> void:
	if _leaving or _selection == index:
		return
	_selection = index
	_update_options()


## Click selects and confirms in one go — moving the caret and making the player
## click a second time would be the same trap as a menu that ignores the mouse.
func _on_option_gui_input(event: InputEvent, index: int) -> void:
	if _leaving:
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	_options[index].accept_event()
	_selection = index
	_update_options()
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
