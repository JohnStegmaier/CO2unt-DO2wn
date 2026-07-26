class_name Obstacle
extends StaticBody2D

## A solid prop: a barrel, a crate, a pile of rocks.
##
## Sits on the WORLD layer, which is the whole trick — walls are on WORLD too, so
## this blocks the player, blocks enemies, and stops bullets without a line
## changing in bullet.gd or a bit being added to collision_layers.gd. What it
## adds over a wall is take_damage.
##
## A StaticBody2D and not an Area2D, and this is not a preference: bullet.gd
## connects body_entered and never area_entered, so a prop built on an Area2D
## would instance perfectly, look right, and silently never register a hit. The
## same trap health.gd warns its hosts about.
##
## One scene for all three props. What they are is an [ObstacleDef], applied in
## configure() before this enters the tree.

## Broken, and which one. The index is into the room's placement result, which is
## what game.gd records so it stays broken when the player comes back — see
## RoomData.obstacles_destroyed.
##
## Reported upward rather than written from here: this knows nothing about floors
## or rooms, and should not start now.
signal destroyed(index: int)

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collider: CollisionShape2D = $CollisionShape2D
@onready var _health: Health = $Health

var def: ObstacleDef
var index: int = -1


## Dress this prop and give it its place in the room's list.
##
## Call it BEFORE the node enters the tree, the same window Enemy.make_boss and
## set_target are set in: Health copies max_hp into hp in its own _ready, so the
## maximum has to be right before then or every crate ships with a barrel's hit
## points.
func configure(p_def: ObstacleDef, p_index: int) -> void:
	def = p_def
	index = p_index


func _ready() -> void:
	assert(def != null, "Obstacle needs configure() before it enters the tree")

	_sprite.texture = def.texture
	_sprite.offset = def.offset
	_sprite.scale = Vector2(def.sprite_scale, def.sprite_scale)

	# The shape is a sub-resource of obstacle.tscn and therefore shared by every
	# prop instanced from it. Resizing the original would resize the whole room —
	# the same duplicate Enemy.make_boss has to make for the same reason.
	var shape: CircleShape2D = _collider.shape.duplicate()
	shape.radius = def.body_radius
	_collider.shape = shape

	_health.max_hp = def.max_hp
	_health.hp = def.max_hp
	_health.died.connect(_on_health_died)


## Bullets duck-type this, the same way they duck-type Enemy.take_damage — which
## is why an indestructible prop still has the method rather than dropping it.
## bullet.gd frees itself on any body it touches whether or not the body can be
## hurt, so a shot at a rock is absorbed identically either way; the difference is
## only that the rock does not care. This is also where a spark and a clank go.
func take_damage(amount: int, type: int = Damage.Type.BLUNT) -> void:
	if def.indestructible:
		return
	_health.take_damage(amount, type)


func _on_health_died() -> void:
	# Reached from bullet.gd's body_entered, so this runs inside a physics query
	# flush. The signal is emitted straight away because it is bookkeeping and the
	# room has to know now; only the collision change is deferred, which is the
	# same split game.gd makes when an enemy dies.
	destroyed.emit(index)

	# Hiding a body does not stop it colliding, and the fade below takes a moment.
	# Deferred because the physics server rejects this mid-flush.
	set_deferred("collision_layer", 0)

	# The Sprite2D, never self: physics interpolation is on project-wide, and
	# tweening a body's own transform smears it. enemy.gd fades its sprite for
	# exactly this reason.
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.18)
	tween.tween_property(_sprite, "scale", _sprite.scale * 1.25, 0.18)
	tween.chain().tween_callback(queue_free)
