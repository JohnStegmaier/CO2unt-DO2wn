class_name OxygenPickup
extends Area2D

## Dropped by enemies — see enemy.gd's pickup_drop_chance. Restores air on
## contact and is gone; duck-types the player the same way bullet.gd does,
## so this has no dependency on Player beyond the method existing.
@export var oxygen_seconds := 15.0

@export_group("Hover")
@export var hover_amplitude := 3.0
@export var hover_speed := 3.0

@onready var _sprite: Sprite2D = $Sprite2D
## The shadow stays put on the ground; only the sprite bobs above it.
var _sprite_base_y := 0.0
var _time := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_sprite_base_y = _sprite.position.y

func _process(delta: float) -> void:
	_time += delta
	_sprite.position.y = _sprite_base_y + sin(_time * hover_speed) * hover_amplitude

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("heal"):
		body.heal(oxygen_seconds)
		queue_free()
