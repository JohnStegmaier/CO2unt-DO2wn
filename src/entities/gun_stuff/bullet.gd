extends Area2D

var speed := 800.0
var direction := Vector2.RIGHT
var damage := 10

func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)
	# Requires a VisibleOnScreenNotifier2D child, signal connected below
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
