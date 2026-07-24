extends Node2D

@onready var global_timer = $"/root/GlobalTimer"

var setup_done = false

func setup() -> void:
	if setup_done:
		return
	await get_tree().create_timer(0.25).timeout
	AudioManager.play_music("60000 light years",1,0,0)
	setup_done = true

func _ready() -> void:
	GlobalTimer.tick.connect(setup)
	GlobalTimer.tick.connect(_on_global_tick)
  
func _on_global_tick() -> void:
	print(global_timer.tickflip)
	AudioManager.play_sfx("tick_trim",1,0,0)
