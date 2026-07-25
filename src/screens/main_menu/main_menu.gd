extends Node2D

const STAGE_SCENE := "res://src/levels/stage/stage.tscn"

@onready var arrow = $Arrow

var arrow_left = true
var selection = 1


func _ready() -> void:
	GlobalTimer.tick.connect(_on_global_tick)
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
		AudioManager.stop_music()
		get_tree().change_scene_to_file(STAGE_SCENE)
