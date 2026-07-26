class_name BombPickup
extends Area2D

## Dropped by enemies — see enemy.gd's bomb_pickup_drop_chance. Grants one
## pulse bomb on contact and is gone; duck-types the player the same way
## oxygen_pickup.gd does, so this has no dependency on Player beyond the
## method existing.

@export_group("Hover")
@export var hover_amplitude := 3.0
@export var hover_speed := 3.0

## The orb and the bomb icon layered inside it move as one unit, so they never
## drift apart during the bob.
@onready var _visual: Node2D = $Visual
## The shadow stays put on the ground; only the visual bobs above it.
var _visual_base_y := 0.0
var _time := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual_base_y = _visual.position.y


func _process(delta: float) -> void:
	_time += delta
	_visual.position.y = _visual_base_y + sin(_time * hover_speed) * hover_amplitude


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("gain_bomb"):
		body.gain_bomb()
		queue_free()
