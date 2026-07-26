extends Node2D

func _ready() -> void:
	var enemy_scene: PackedScene = preload("res://src/entities/enemy/enemy.tscn")

	var oxygen_only := 0
	var bomb_only := 0
	var both := 0
	var neither := 0
	const TRIALS := 300

	for i in TRIALS:
		var enemy = enemy_scene.instantiate()
		# High, overlapping chances so both branches fire often across trials —
		# the point is to prove they never fire TOGETHER on the same death.
		enemy.pickup_drop_chance = 0.5
		enemy.bomb_pickup_drop_chance = 0.5
		add_child(enemy)
		enemy.global_position = Vector2(100, 100)
		await get_tree().process_frame

		enemy._health.take_damage(99999, 0)
		await get_tree().process_frame  # let the deferred _spawn_drop calls land

		var has_oxygen := false
		var has_bomb := false
		for child in get_children():
			var script = child.get_script()
			if script == null:
				continue
			if script.resource_path.ends_with("oxygen_pickup.gd"):
				has_oxygen = true
			elif script.resource_path.ends_with("bomb_pickup.gd"):
				has_bomb = true

		if has_oxygen and has_bomb:
			both += 1
		elif has_oxygen:
			oxygen_only += 1
		elif has_bomb:
			bomb_only += 1
		else:
			neither += 1

		# Clean up this trial's nodes before the next one.
		for child in get_children():
			child.queue_free()
		await get_tree().process_frame

	print("oxygen_only=", oxygen_only, " bomb_only=", bomb_only, " both=", both, " neither=", neither)
	assert(both == 0, "an enemy should never drop both pickups on the same death")
	assert(oxygen_only > 0 and bomb_only > 0, "sanity: both drop types should still occur across many trials")
	print("ALL SINGLE-DROP TESTS PASSED")
	get_tree().quit()
