class_name Enemy
extends CharacterBody2D

## A bad guy.
##
## Sits on the enemy collision layer so the player's bullets can see it,
## forwards damage to its Health component, and reports its own death upward so
## the room can count.
##
## No pathfinding and no line-of-sight checks, deliberately. That used to be free:
## a room was a hollow rectangle and a straight seek plus move_and_slide could
## never get stuck. Rooms now have solid props in them, so it is not free any
## more — it is a choice to keep the seek dumb and pay for it with the stuck-guard
## below, which is a few lines against a nav mesh and a rewrite.
##
## What the guard buys is only that a chaser cannot grind against a barrel
## forever. It is not steering and not cover: it does not know a prop from a wall,
## will not take the short way round, and will happily walk back into the thing it
## just left. Using cover, and breaking what is in the way, are a separate job —
## see obstacle_field.gd, which is the surface that job will ask its questions of.

## Which row of the drop table this one's death is looked up under. Not a table
## and not a drop chance: an enemy says what it is and the run's [DropConfig]
## says what that is worth, so the whole economy — every enemy type, every floor
## — is read and tuned in one inspector rather than across every enemy scene.
##
## Overridden by whoever spawns us when they know better; game.gd sets &"boss"
## on the one it just promoted. A source with no rule drops nothing, which is
## what makes an unnamed enemy quiet rather than an error.
@export var loot_source: StringName = &"grunt"

## This one is gone, and where. The Game listens so it can tell when a room is
## cleared and roll for loot — it owns the seeded RNG, so the roll cannot happen
## here without making drops unreproducible from a run seed.
##
## Carries the position because by the time anything acts on this the corpse is
## mid-fade and about to free itself.
signal died(loot_source: StringName, at: Vector2)

## How this one fights. Declared as an enum for readable call sites but exported
## and passed as a plain int, for the reason in grid_direction.gd.
enum Behaviour { CHASER, SKIRMISHER }

@export_enum("chaser", "skirmisher") var behaviour: int = 0

@export_group("Weapon")
@export var bullet_scene: PackedScene
@export var bullet_damage: int = 8
@export_enum("blunt", "piercing") var bullet_damage_type: int = 0
## How fast their shots travel. The single biggest lever on whether a shot is
## dodgeable, and independent of the player's — both sides fire the same scene,
## so this has to live on the shooter to be tunable separately.
@export var bullet_speed := 180.0
## Blunt cost of being walked into. Rate-limited by the player's own mercy
## window, so this needs no timer of its own.
@export var contact_damage: int = 6
@export var fire_interval := 1.6
@export var fire_range := 220.0
## Radians. They are bad guys, not marksmen.
@export var aim_spread := 0.2
## No volley on the frame you walk through the door.
@export var spawn_grace := 0.8

@export_group("Movement")
## Deliberately slower than the player's 150, so you can kite them but not
## ignore them.
@export var chase_speed := 60.0
## Exponential smoothing rate, matching player_camera.gd's idiom so acceleration
## is frame-rate independent.
@export var chase_acceleration := 6.0

@export_group("Skirmisher")
## How far a skirmisher likes to stand off, and the dead band around it that
## stops it jittering back and forth on the ring.
@export var preferred_range := 140.0
@export var range_band := 25.0
@export var strafe_speed := 55.0
@export var dodge_speed := 180.0
@export var dodge_time := 0.22
@export var dodge_cooldown := 1.0

## Where a shot leaves the body. Structural rather than a feel knob.
const MUZZLE_OFFSET := 10.0
## Reversing on a timer as well as on walls, so it neither grinds along a wall
## nor orbits the player hypnotically.
const STRAFE_FLIP_MIN := 1.5
const STRAFE_FLIP_MAX := 3.0

## Physics frames a chaser may spend touching something without gaining ground on
## the player before it counts as wedged rather than fighting. Frames rather than
## seconds so two runs of the same fight make the same decision.
const STUCK_FRAMES := 12
## And how long it walks sideways afterwards. Long enough to clear the widest prop
## at chase_speed, short enough to read as a shove rather than a patrol.
const UNSTICK_FRAMES := 20
## Ground gained per frame below which a chaser counts as gaining none. At
## chase_speed 60 on a 60Hz tick an unobstructed run gains a pixel a frame.
const STUCK_PROGRESS := 0.1
## Inside this a chaser is grinding on the PLAYER, which is the whole job — see
## _damage_on_contact. Never stuckness.
const STUCK_IGNORE_RANGE := 24.0

var _target: Node2D
var _fire_cooldown := 0.0
var _strafe_sign := 1.0
var _strafe_flip_in := 0.0
var _dodge_until_msec: int = 0
var _dodge_ready_at_msec: int = 0
var _stuck_frames: int = 0
var _unstick_frames: int = 0
var _unstick_sign: float = 1.0

## Set by pulse_stagger. Trigger stays jammed until the msec timestamp passes;
## steering holds the knockback velocity until the (much shorter) other one does.
var _fire_suppressed_until_msec: int = 0
var _knockback_until_msec: int = 0

## How long a pulse knockback holds steering off before the enemy starts
## fighting its way back toward the target — long enough to read as a shove,
## short enough that it is not a second, longer stagger stacked on the silence.
const PULSE_KNOCKBACK_HOLD := 0.25

@onready var _health: Health = $Health
@onready var _sprite: Sprite2D = $Sprite2D


## Handed in by whoever spawned us, rather than looked up: the spawner already
## holds the player, and a group lookup would make every enemy depend on a
## global name.
func set_target(target: Node2D) -> void:
	_target = target


## Promote this one to a floor boss: harder to kill, harder to stand next to, and
## big enough that walking into the room tells you which room it is.
##
## Deliberately a buff and not a subclass. A boss with its own attack patterns is
## a different job; what this buys is a fight that reads as a climax using the
## enemy that already exists, and it is the one call to delete when that job is
## done.
##
## Call it BEFORE the node enters the tree, the same window [method set_target]
## and [member behaviour] are set in. Health copies max_hp into hp in its own
## _ready(), so raising the maximum first is all the healing there is to do.
##
## Damage is a separate multiplier from hit points on purpose. The player has no
## health bar — damage is taken out of the O2 countdown — so scaling what a boss
## hits for by what it takes to kill one does not make the fight longer, it makes
## it unsurvivable.
func make_boss(hp_scale: float, damage_scale: float, size_scale: float) -> void:
	var health: Health = $Health
	health.max_hp = maxi(1, roundi(health.max_hp * hp_scale))
	contact_damage = maxi(1, roundi(contact_damage * damage_scale))
	bullet_damage = maxi(1, roundi(bullet_damage * damage_scale))

	var sprite: Sprite2D = $Sprite2D
	sprite.scale *= size_scale

	# The shape is a sub-resource of enemy.tscn and therefore shared by every
	# enemy instanced from it. Resizing the original would inflate the whole room.
	var collider: CollisionShape2D = $CollisionShape2D
	var shape: CapsuleShape2D = collider.shape.duplicate()
	shape.radius *= size_scale
	shape.height *= size_scale
	collider.shape = shape


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	var to_target: Vector2 = _target.global_position - global_position
	velocity = _desired_velocity(to_target, delta)
	var was_at := global_position
	move_and_slide()
	_track_progress(global_position - was_at, to_target)
	_damage_on_contact()

	if not is_zero_approx(velocity.x):
		_sprite.flip_h = velocity.x < 0.0

	_fire_cooldown -= delta
	var trigger_jammed := Time.get_ticks_msec() < _fire_suppressed_until_msec
	if not trigger_jammed and _fire_cooldown <= 0.0 and to_target.length() < fire_range:
		_fire_cooldown = fire_interval
		_shoot(to_target.normalized())


## Did that move actually take us anywhere?
##
## Measured after the fact rather than predicted, because the only thing that
## knows a slide came to nothing is the slide. move_and_slide handles a glancing
## hit by itself; what it cannot handle is a square-on one, where there is no
## tangent left to give and the whole velocity is eaten. That is also the likeliest
## geometry, since a chaser walks straight at the player.
##
## Chasers only. A skirmisher holding its range is not stuck, and its own strafe
## flip already turns it away from anything it runs into.
func _track_progress(moved: Vector2, to_target: Vector2) -> void:
	if _unstick_frames > 0 or behaviour != Behaviour.CHASER:
		return
	# Touching nothing, or close enough that the thing being ground against is the
	# player. Neither is being stuck.
	if get_slide_collision_count() == 0 or to_target.length() < STUCK_IGNORE_RANGE:
		_stuck_frames = 0
		return
	# Ground gained toward the player, not distance travelled: an enemy walking
	# the long way round a crate is moving plenty and is not stuck.
	if moved.dot(to_target.normalized()) > STUCK_PROGRESS:
		_stuck_frames = 0
		return

	_stuck_frames += 1
	if _stuck_frames < STUCK_FRAMES:
		return
	_stuck_frames = 0
	_unstick_frames = UNSTICK_FRAMES
	# Which way round is read off the surface rather than rolled — no RNG, and it
	# picks the side the player is already on, so the detour is the short way.
	var tangent := get_slide_collision(0).get_normal().orthogonal()
	_unstick_sign = -1.0 if tangent.dot(to_target) < 0.0 else 1.0


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
	var spread := randf_range(-aim_spread, aim_spread)
	var direction := aim.rotated(spread)

	var bullet = bullet_scene.instantiate()
	bullet.arm(direction, CollisionLayers.ENEMY_BULLET,
			CollisionLayers.WORLD | CollisionLayers.PLAYER, bullet_damage, bullet_damage_type,
			bullet_speed)
	# Parented to the run container exactly as the player's shots are, so the
	# Game's projectiles sweep stays the single owner of bullet lifetime.
	get_tree().current_scene.add_child(bullet)
	# Same shot sound as the player's gun, pitched and dimmed down so enemy fire
	# reads as duller and doesn't compete with the player's own shots.
	AudioManager.play_sfx("laser_gun_01", 0.7, -6.0)
	bullet.global_position = global_position + direction * MUZZLE_OFFSET
	bullet.reset_physics_interpolation()


## Each behaviour is a function of its arguments and its own constants and
## nothing else, so when a third and fourth arrive these lift straight out into
## components/steering/ with no untangling.
func _desired_velocity(to_target: Vector2, delta: float) -> Vector2:
	# Mid-dodge we are not steering at all — hold the jump, same shape as the
	# player's own is_dodging early return. A pulse knockback holds the same way.
	if Time.get_ticks_msec() < _dodge_until_msec:
		return velocity
	if Time.get_ticks_msec() < _knockback_until_msec:
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
	var toward := to_target.normalized()
	# Wedged against something: walk the tangent for a fixed count instead of
	# steering. Assigned outright rather than lerped, because the collision has
	# already taken the velocity we would otherwise be easing out of, and easing
	# back up from a standstill spends the whole window still pressed against it.
	if _unstick_frames > 0:
		_unstick_frames -= 1
		return toward.orthogonal() * _unstick_sign * chase_speed
	return velocity.lerp(toward * chase_speed, 1.0 - exp(-chase_acceleration * delta))


## Hold a firing range and circle. Closes if too far, backs off if too close, and
## strafes while it is comfortable.
func _skirmish_velocity(to_target: Vector2, delta: float) -> Vector2:
	var distance := to_target.length()
	var toward := to_target.normalized()
	var desired: Vector2

	if distance > preferred_range + range_band:
		desired = toward * chase_speed
	elif distance < preferred_range - range_band:
		desired = -toward * chase_speed
	else:
		_strafe_flip_in -= delta
		# All three, not just is_on_wall: motion mode is grounded, so a body
		# sliding along the top or bottom face of a prop reports floor or ceiling
		# instead, and would grind sideways along a crate forever.
		if _strafe_flip_in <= 0.0 or is_on_wall() or is_on_ceiling() or is_on_floor():
			_strafe_sign = -_strafe_sign
			_strafe_flip_in = randf_range(STRAFE_FLIP_MIN, STRAFE_FLIP_MAX)
		desired = toward.orthogonal() * strafe_speed * _strafe_sign

	return velocity.lerp(desired, 1.0 - exp(-chase_acceleration * delta))


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
	velocity = away * dodge_speed
	_dodge_until_msec = Time.get_ticks_msec() + int(dodge_time * 1000.0)
	_dodge_ready_at_msec = Time.get_ticks_msec() + int(dodge_cooldown * 1000.0)


## Hit by the player's pulse bomb: shoved away from the blast and its trigger
## jammed for silence_duration. Duck-typed the same way take_damage is, so the
## bomb needs nothing more than has_method to reach every enemy on screen.
func pulse_stagger(from: Vector2, force: float, silence_duration: float) -> void:
	var away := global_position - from
	if away.length() < 0.001:
		away = Vector2.RIGHT
	velocity = away.normalized() * force
	_knockback_until_msec = Time.get_ticks_msec() + int(PULSE_KNOCKBACK_HOLD * 1000.0)
	_fire_suppressed_until_msec = Time.get_ticks_msec() + int(silence_duration * 1000.0)


func _ready() -> void:
	# The single most likely "why do bullets go straight through" failure: player
	# bullets mask ENEMY, so an enemy left on the default layer is invisible to
	# them. Cheap to assert while the feature is young.
	assert(collision_layer == CollisionLayers.ENEMY,
			"Enemy must sit on the ENEMY layer or bullets pass through it")
	# So the pulse bomb can reach every enemy on screen without game.gd handing
	# it a list — same trick bullet.gd's "projectiles" group plays for the sweep.
	add_to_group("enemies")
	_health.damaged.connect(_on_health_damaged)
	_health.died.connect(_on_health_died)
	# Staggered, or a roomful fires in unison forever after.
	_fire_cooldown = spawn_grace + randf() * fire_interval
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
	# Reported before the fade rather than after it, so the room unlocks on the
	# killing blow instead of a tenth of a second later. What our death is worth
	# is the run's business, not ours.
	died.emit(loot_source, global_position)
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
