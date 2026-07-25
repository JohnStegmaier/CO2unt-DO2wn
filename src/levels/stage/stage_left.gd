extends Node2D

func _ready() -> void:
	GlobalTimer.tick.connect(_on_global_tick)
	var spawn_tag := NavigationManager.consume_spawn_door_tag()
	if spawn_tag != "":
		_on_level_spawn(spawn_tag)

func _on_global_tick() -> void:
	AudioManager.play_sfx("tick_trim",1,0,0)

func _on_level_spawn(destination_tag: String):
	var door_path = "Doors/door_" + destination_tag
	var door = get_node_or_null(door_path) as LevelDoor
	if door == null:
		push_warning("stage_left: no door at '%s' for tag '%s'" % [door_path, destination_tag])
		return
	NavigationManager.trigger_player_spawn(door.spawn.global_position, door.spawn_direction)
