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
	if collision_layer & CollisionLayers.ENEMY_BULLET:
		modulate = Color.RED
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
