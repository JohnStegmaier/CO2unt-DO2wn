class_name Enemy
extends CharacterBody2D

## A bad guy.
##
## Sits on the enemy collision layer so the player's bullets can see it,
## forwards damage to its Health component, and reports its own death upward so
## the room can count.
##
## No pathfinding and no line-of-sight checks, deliberately: a room is a hollow
## rectangle with nothing inside it, so a straight seek plus move_and_slide can
## never get stuck and nothing can ever stand between us and the player.

## This one is gone. The Game listens so it can tell when a room is cleared.
signal died

## How this one fights. Declared as an enum for readable call sites but exported
## and passed as a plain int, for the reason in grid_direction.gd.
enum Behaviour { CHASER, SKIRMISHER }

@export_enum("chaser", "skirmisher") var behaviour: int = 0

@export_group("Weapon")
@export var bullet_scene: PackedScene
@export var bullet_damage: int = 8
@export_enum("blunt", "piercing") var bullet_damage_type: int = 0
## Blunt cost of being walked into. Rate-limited by the player's own mercy
## window, so this needs no timer of its own.
@export var contact_damage: int = 6

const FIRE_INTERVAL := 1.6
const FIRE_RANGE := 220.0
## Radians. They are bad guys, not marksmen.
const AIM_SPREAD := 0.12
## No volley on the frame you walk through the door.
const SPAWN_GRACE := 0.8
const MUZZLE_OFFSET := 10.0

const CHASE_SPEED := 70.0
## Exponential smoothing rate, matching player_camera.gd's idiom so acceleration
## is frame-rate independent.
const CHASE_ACCELERATION := 6.0

## How far a skirmisher likes to stand off, and the dead band around it that
## stops it jittering back and forth on the ring.
const PREFERRED_RANGE := 140.0
const RANGE_BAND := 25.0
const STRAFE_SPEED := 55.0
const DODGE_SPEED := 180.0
const DODGE_TIME := 0.22
const DODGE_COOLDOWN := 1.0
## Reversing on a timer as well as on walls, so it neither grinds along a wall
## nor orbits the player hypnotically.
const STRAFE_FLIP_MIN := 1.5
const STRAFE_FLIP_MAX := 3.0

var _target: Node2D
var _fire_cooldown := 0.0
var _strafe_sign := 1.0
var _strafe_flip_in := 0.0
var _dodge_until_msec: int = 0
var _dodge_ready_at_msec: int = 0

@onready var _health: Health = $Health
@onready var _sprite: Sprite2D = $Sprite2D


## Handed in by whoever spawned us, rather than looked up: the spawner already
## holds the player, and a group lookup would make every enemy depend on a
## global name.
func set_target(target: Node2D) -> void:
	_target = target


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	var to_target: Vector2 = _target.global_position - global_position
	velocity = _desired_velocity(to_target, delta)
	move_and_slide()
	_damage_on_contact()

	if not is_zero_approx(velocity.x):
		_sprite.flip_h = velocity.x < 0.0

	_fire_cooldown -= delta
	if _fire_cooldown <= 0.0 and to_target.length() < FIRE_RANGE:
		_fire_cooldown = FIRE_INTERVAL
		_shoot(to_target.normalized())


## Walking into the player costs them air. The player's own mercy window rate
## limits this, so a chaser pressed against them drains steadily rather than
## every frame.
func _damage_on_contact() -> void:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider == _target and collider.has_method("take_damage"):
			collider.take_damage(contact_damage, Damage.Type.BLUNT)
			return


func _shoot(aim: Vector2) -> void:
	if bullet_scene == null:
		return
	var spread := randf_range(-AIM_SPREAD, AIM_SPREAD)
	var direction := aim.rotated(spread)

	var bullet = bullet_scene.instantiate()
	bullet.arm(direction, CollisionLayers.ENEMY_BULLET,
			CollisionLayers.WORLD | CollisionLayers.PLAYER, bullet_damage, bullet_damage_type)
	# Parented to the run container exactly as the player's shots are, so the
	# Game's projectiles sweep stays the single owner of bullet lifetime.
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position + direction * MUZZLE_OFFSET
	bullet.reset_physics_interpolation()


## Each behaviour is a function of its arguments and its own constants and
## nothing else, so when a third and fourth arrive these lift straight out into
## components/steering/ with no untangling.
func _desired_velocity(to_target: Vector2, delta: float) -> Vector2:
	# Mid-dodge we are not steering at all — hold the jump, same shape as the
	# player's own is_dodging early return.
	if Time.get_ticks_msec() < _dodge_until_msec:
		return velocity

	match behaviour:
		Behaviour.SKIRMISHER:
			return _skirmish_velocity(to_target, delta)
		_:
			return _chase_velocity(to_target, delta)


## Run at the player. Meaningfully slower than the player's WALK_SPEED of 150, so
## you can kite them but not ignore them.
##
## No separation steering: enemies mask each other, so move_and_slide pushes them
## apart physically. That is what lets this survive thirty of them unchanged.
func _chase_velocity(to_target: Vector2, delta: float) -> Vector2:
	var desired := to_target.normalized() * CHASE_SPEED
	return velocity.lerp(desired, 1.0 - exp(-CHASE_ACCELERATION * delta))


## Hold a firing range and circle. Closes if too far, backs off if too close, and
## strafes while it is comfortable.
func _skirmish_velocity(to_target: Vector2, delta: float) -> Vector2:
	var distance := to_target.length()
	var toward := to_target.normalized()
	var desired: Vector2

	if distance > PREFERRED_RANGE + RANGE_BAND:
		desired = toward * CHASE_SPEED
	elif distance < PREFERRED_RANGE - RANGE_BAND:
		desired = -toward * CHASE_SPEED
	else:
		_strafe_flip_in -= delta
		if _strafe_flip_in <= 0.0 or is_on_wall():
			_strafe_sign = -_strafe_sign
			_strafe_flip_in = randf_range(STRAFE_FLIP_MIN, STRAFE_FLIP_MAX)
		desired = toward.orthogonal() * STRAFE_SPEED * _strafe_sign

	return velocity.lerp(desired, 1.0 - exp(-CHASE_ACCELERATION * delta))


## A player bullet came within reach. Jump perpendicular to where it is actually
## going — reading its direction rather than its position means a shot that would
## have missed anyway does not provoke a dodge into its path.
func _on_dodge_sensor_area_entered(area: Area2D) -> void:
	if behaviour != Behaviour.SKIRMISHER:
		return
	if Time.get_ticks_msec() < _dodge_ready_at_msec:
		return
	if not "direction" in area:
		return

	var away: Vector2 = area.direction.orthogonal()
	# Break toward whichever side we were already drifting, so a dodge reads as
	# a continuation rather than a twitch.
	if away.dot(velocity) < 0.0:
		away = -away
	velocity = away * DODGE_SPEED
	_dodge_until_msec = Time.get_ticks_msec() + int(DODGE_TIME * 1000.0)
	_dodge_ready_at_msec = Time.get_ticks_msec() + int(DODGE_COOLDOWN * 1000.0)


func _ready() -> void:
	# The single most likely "why do bullets go straight through" failure: player
	# bullets mask ENEMY, so an enemy left on the default layer is invisible to
	# them. Cheap to assert while the feature is young.
	assert(collision_layer == CollisionLayers.ENEMY,
			"Enemy must sit on the ENEMY layer or bullets pass through it")
	_health.damaged.connect(_on_health_damaged)
	_health.died.connect(_on_health_died)
	# Staggered, or a roomful fires in unison forever after.
	_fire_cooldown = SPAWN_GRACE + randf() * FIRE_INTERVAL
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	_strafe_flip_in = randf_range(STRAFE_FLIP_MIN, STRAFE_FLIP_MAX)

	# Only skirmishers watch for incoming fire; a chaser paying for the sensor
	# would be pure cost at thirty of them.
	var sensor: Area2D = $DodgeSensor
	sensor.area_entered.connect(_on_dodge_sensor_area_entered)
	sensor.set_deferred("monitoring", behaviour == Behaviour.SKIRMISHER)


## Bullets duck-type this — see bullet.gd. Damage lands on the body itself
## rather than a hurtbox, then gets handed down to the component that owns it.
func take_damage(amount: int, type: int = Damage.Type.BLUNT) -> void:
	_health.take_damage(amount, type)


func _on_health_damaged(_amount: int, _type: int) -> void:
	# With a single-frame sprite this flash is the only hit confirmation there
	# is, so it is doing an animation's job rather than being polish.
	var flash := create_tween()
	flash.tween_property(_sprite, "modulate", Color(4.0, 4.0, 4.0), 0.04)
	flash.tween_property(_sprite, "modulate", Color.WHITE, 0.08)


func _on_health_died() -> void:
	died.emit()
	# Stop interacting the instant we die, so the corpse cannot block a shot or
	# body-check the player while it plays out.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

	var death := create_tween()
	death.set_parallel(true)
	death.tween_property(_sprite, "scale", Vector2(1.4, 0.6), 0.12)
	death.tween_property(_sprite, "modulate:a", 0.0, 0.12)
	await death.finished
	queue_free()
