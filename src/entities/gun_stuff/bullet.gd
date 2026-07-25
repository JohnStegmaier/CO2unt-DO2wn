extends Area2D

## Set per shot by arm(), for the same reason as damage_type: the player and the
## enemies share this scene, so a value tuned here would move both at once. The
## exported number is only what a bullet dropped into a scene by hand starts with.
@export var speed := 400.0
@export var damage := 10
## A Damage.Type. Set per shot by arm(), because one bullet scene serves both the
## player and the enemies.
@export_enum("blunt", "piercing") var damage_type: int = 0

var direction := Vector2.RIGHT


## Set up a bullet for whoever fired it, so no caller has to remember which
## properties belong to the shooter rather than to the scene. Call this BEFORE
## add_child: layers on a node that is not yet in the tree cannot be rejected by
## the physics server the way an in-tree change can, so this needs none of the
## set_deferred care room.gd takes.
func arm(p_direction: Vector2, layer: int, mask: int, p_damage: int, p_damage_type: int,
		p_speed: float) -> void:
	direction = p_direction
	collision_layer = layer
	collision_mask = mask
	damage = p_damage
	damage_type = p_damage_type
	speed = p_speed


func _ready() -> void:
	# Bullets are parented to the run container, so they would otherwise follow
	# the player into the next room. The Game clears this group on every swap.
	add_to_group("projectiles")
	rotation = direction.angle()
	if collision_layer & CollisionLayers.ENEMY_BULLET:
		modulate = Color.RED
	body_entered.connect(_on_body_entered)
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)
	get_tree().create_timer(5.0).timeout.connect(queue_free)  # safety net


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage, damage_type)
	queue_free()
