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
## The Area2D's own shape is what ACTORS are hit with, and it is deliberately
## generous — radius 8 around a 5px bullet sprite. Solid geometry is not tested
## that way; see [method _sweep].

## How far back from a surface a clamped muzzle sits. Enough that the first sweep
## starts outside what it is about to hit rather than exactly on it.
const MUZZLE_BACKOFF := 1.0

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

## The part of the mask [method arm] was given that names solid geometry. Kept
## apart from collision_mask because the two are tested in different ways — see
## [method _sweep].
var _world_mask: int = 0


## Set up a projectile for whoever fired it, so no caller has to remember which
## properties belong to the shooter rather than to the scene. Call this BEFORE
## add_child: layers on a node that is not yet in the tree cannot be rejected by
## the physics server the way an in-tree change can, so this needs none of the
## set_deferred care room.gd takes.
func arm(p_direction: Vector2, layer: int, mask: int, p_damage: int, p_damage_type: int,
		p_speed: float) -> void:
	direction = p_direction
	collision_layer = layer
	# The world half of the mask is swept as a ray instead of overlapped as a
	# disc, so it is held back from the Area rather than given to it. Callers
	# still pass one mask and do not need to know the difference — see _sweep.
	_world_mask = mask & CollisionLayers.WORLD
	collision_mask = mask & ~CollisionLayers.WORLD
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
	var step := direction * speed * delta
	var hit := _sweep(step)
	if hit.is_empty():
		global_position += step
		return
	# Stopped ON the surface rather than at the far end of the step, so a
	# subclass that survives the contact carries on from where it truly touched
	# and an impact effect would have somewhere honest to sit.
	global_position = hit["position"]
	_on_body_entered(hit["collider"])


## Cast this tick's travel against solid geometry. Returns the ray hit, or an
## empty dictionary when the way is clear.
##
## Swept as a ray rather than overlapped as a disc, and that is the fix for a bug
## worth remembering. A projectile's collider is much wider than the body that
## fired it — radius 8 against the player's radius of 3 — so a shot fired while
## pressed against a wall was born already overlapping it and died on its first
## frame, with no bullet ever appearing. As a point it has nothing to clip, and
## the generous disc still does its real job of hitting actors.
##
## Sweeping also means a projectile cannot pass through a wall between two ticks,
## however fast a weapon is later tuned. Overlapping only ever worked because
## nothing yet outruns a 16px wall in one frame.
func _sweep(step: Vector2) -> Dictionary:
	if _world_mask == 0:
		return {}
	var world := get_world_2d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(
			global_position, global_position + step, _world_mask)
	# False, unlike the muzzle clamp: a piercing projectile that is inside what
	# it pierced has to be able to leave, not hit it again from within every
	# tick until it stops.
	query.hit_from_inside = false
	return world.direct_space_state.intersect_ray(query)


## Where a shot fired from [param origin] toward [param muzzle] can actually
## start: the muzzle itself, or the first solid thing between the two.
##
## A muzzle sits further out than the body that owns it — 20px against the
## player's radius of 3 — and a room wall is only 17 deep, so an unclamped muzzle
## can land inside a wall, or clean through it and put a live shot outside the
## room. Clamping means a projectile always begins somewhere it could legally be,
## which is also the assumption [method _sweep] relies on.
##
## Static so the player and the enemies share one answer rather than each growing
## physics-query code of its own. Both call it from _physics_process, which is
## the only place a space state may be read.
static func clear_muzzle(space: PhysicsDirectSpaceState2D, origin: Vector2,
		muzzle: Vector2) -> Vector2:
	if space == null:
		return muzzle
	var query := PhysicsRayQueryParameters2D.create(
			origin, muzzle, CollisionLayers.WORLD)
	# True, unlike the travel sweep: a shooter shoved into geometry should have
	# its shot stopped where it stands, not read as a clear line and fired out
	# through the wall it is standing in.
	query.hit_from_inside = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return muzzle
	return hit["position"] - (muzzle - origin).normalized() * MUZZLE_BACKOFF


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
