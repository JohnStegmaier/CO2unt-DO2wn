extends Node2D

const GAME_SCENE := "res://src/screens/game/game.tscn"

## The "Play" art is a Sprite2D, so there is nothing for the mouse to hit: sprites
## take no part in the viewport's GUI picking, only Controls do. PlayButton is a
## transparent Control sized to the opaque pixels of play.png and it is the
## clickable half of the option — if the sprite moves, move it too.
const PLAY_IDLE := Color(0.78289706, 0.37850663, 0.11038349, 1.0)
const PLAY_HOVER := Color(1.0, 0.54, 0.18, 1.0)

@onready var arrow = $Arrow
@onready var _play: Sprite2D = $Play
@onready var _play_button: Control = $PlayButton

var arrow_left = true
var selection = 1
## Set once we are on our way out, so a second click or Enter landing during the
## scene change cannot fire a second change_scene_to_file.
var _leaving := false


func _ready() -> void:
	GlobalTimer.tick.connect(_on_global_tick)
	_play_button.gui_input.connect(_on_play_gui_input)
	_play_button.mouse_entered.connect(_on_play_hover.bind(true))
	_play_button.mouse_exited.connect(_on_play_hover.bind(false))
	await get_tree().create_timer(0.6).timeout
	AudioManager.play_music("main_menu", 1, 0, 0)


func _on_global_tick() -> void:
	var tween = create_tween()
	if arrow_left:
		tween.tween_property(arrow, "rotation_degrees", arrow.rotation_degrees + 45.0, 0.2)
	else:
		tween.tween_property(arrow, "rotation_degrees", arrow.rotation_degrees - 45.0, 0.2)
	arrow_left = not arrow_left


func _process(_delta: float) -> void:
	if selection == 1 and Input.is_action_just_pressed("ui_accept"):
		_start_game()


func _on_play_hover(hovered: bool) -> void:
	if _leaving:
		return
	_play.self_modulate = PLAY_HOVER if hovered else PLAY_IDLE


func _on_play_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	# The left button is also bound to `shoot`; swallow it here so a click that
	# starts the run cannot also be read as the first shot of it.
	_play_button.accept_event()
	_start_game()


func _start_game() -> void:
	if _leaving:
		return
	_leaving = true
	AudioManager.stop_music()
	NavigationManager.go_to_screen(GAME_SCENE)
