class_name Projectile
extends Area2D

## Anything a weapon puts in the air.
##
## The contract every projectile scene has to honour, hoisted out of bullet.gd so
## a [WeaponDef] can name any of them in projectile_scene and the code that fires
## it never has to know which. Subclasses decide what happens on contact and how
## long they live; this owns being armed and travelling.
##
## Two things here are load-bearing beyond this file and must not move:
##
## [member direction] is read off the node by the skirmisher's dodge sensor —
## `if not "direction" in area` at enemy.gd — which fails SILENTLY into "enemies
## never dodge" if it is renamed or made private.
##
## [method arm] is called by enemy.gd as well as by the player's Loadout, so its
## signature belongs to both.
##
## Every scene also needs a "Shadow" child (a small dark Sprite2D, same idea as
## Enemy's) — _ready reaches for it by name to hold it level while the rest of
## the node rotates to face the shot.
##
## Give that Shadow a z_index of 0 or higher, not a negative one. Enemy's own
## Shadow can sit at -1 because Enemy lives under Room's Entities node, which is
## already pushed to +2 — its shadow's effective depth ends up positive. A
## projectile is parented straight onto Game (see arm/_shoot in enemy.gd and
## Loadout), with no such boost, so a negative z_index here does not land it
## behind the bullet — it lands behind Room's own background (z_index -1) and
## disappears entirely.
##
## An "Outline" child is optional. Where present (bullet.tscn), _ready shows it
## on [constant CollisionLayers.ENEMY_BULLET] shots. A ring-shaped
## GradientTexture2D sprite, the same idea as Shadow and Glow, rather than an
## edge-detect shader on the sprite: the source frames are 5x5 px of pure
## soft-edged blur with no silhouette to trace, so what actually reads as "the
## bullet" on screen is almost entirely the Glow sprite underneath it — an
## outline has to be its own shape drawn around that, not a rim traced on a
## texture too small to have one.

## Set per shot by [method arm], not tuned here: one scene serves the player and
## the enemies, so a value set on the scene would move both at once. The exported
## numbers are only what a projectile dropped into a scene by hand starts with.
@export var speed := 400.0
@export var damage := 10
## A Damage.Type. Set per shot by [method arm], for the same reason.
@export_enum("blunt", "piercing") var damage_type: int = 0

## Seconds before this gives up and frees itself, in case it never hits anything
## and never leaves the screen. A safety net, not a range limit.
@export var lifetime := 5.0

var direction := Vector2.RIGHT


## Set up a projectile for whoever fired it, so no caller has to remember which
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
	# Projectiles are parented to the run container, so they would otherwise
	# follow the player into the next room. The Game clears this group on every
	# swap, and so does the player's bomb.
	add_to_group("projectiles")
	rotation = direction.angle()
	# Every projectile scene carries a Shadow child now (see bullet.tscn,
	# chakram.tscn), authored as if the shot travels straight down the screen.
	# Rotating this node to face an arbitrary aim direction drags that child
	# along on both axes — not just spinning the shadow's shape, but orbiting
	# its position around the shot, so a bullet aimed up-left would trail its
	# shadow up-left instead of leaving it straight below. Counter-rotating the
	# local position once, here, cancels the parent transform Godot is about to
	# apply when it draws it; countering rotation the same way keeps the shape
	# from skewing. Simpler than giving Shadow its own per-frame script just to
	# fight this, since rotation never changes again after this line.
	$Shadow.position = $Shadow.position.rotated(-rotation)
	$Shadow.rotation = -rotation
	if collision_layer & CollisionLayers.ENEMY_BULLET:
		modulate = Color.RED
		if has_node("Outline"):
			$Outline.visible = true
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	_on_armed()


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


## Hook for a subclass that needs to set itself up after [method arm] but with
## the tree available — starting a spin, say. The base does nothing.
func _on_armed() -> void:
	pass


## What this does to what it hit. Overridden by every subclass: a bullet stops
## here, a chakram carries on.
func _on_body_entered(_body: Node2D) -> void:
	pass


## Whether this projectile should pass straight through the given body.
##
## Shared because every projectile owes it: a dodging player is passed through
## rather than hit — see Player.is_intangible — and a projectile that forgot to
## ask would make the dodge roll do nothing.
func _passes_through(body: Node2D) -> bool:
	return body.has_method("is_intangible") and body.is_intangible()


## Deal this projectile's damage to a body if it can take any. Returns whether it
## landed, so a piercing projectile can count what it has hit.
func _damage(body: Node2D) -> bool:
	if not body.has_method("take_damage"):
		return false
	body.take_damage(damage, damage_type)
	return true
