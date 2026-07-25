extends Area2D

@export var speed := 400.0
@export var damage := 10

var direction := Vector2.RIGHT


func _ready() -> void:
	# Bullets are parented to the run container, so they would otherwise follow
	# the player into the next room. The Game clears this group on every swap.
	add_to_group("projectiles")
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)
	get_tree().create_timer(5.0).timeout.connect(queue_free)  # safety net


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
