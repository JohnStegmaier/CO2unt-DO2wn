class_name Enemy
extends CharacterBody2D

## A bad guy — any of them.
##
## One scene for the whole bestiary, dressed at spawn from an [EnemyDef]: art,
## body, gun, hit points and which [EnemyBehaviour] drives it all arrive in
## [method configure]. Adding a fifth kind of enemy is a .tres and touches
## nothing here, which is the same bargain [Obstacle] makes with [ObstacleDef].
##
## This file owns the things only a node can own — the collider, the sprite, the
## slide collisions, the bullet, the two timing windows that suspend steering —
## and delegates every decision about where to go and what to shoot. It does not
## contain the name of a single archetype.
##
## Still no pathfinding, and that is still a choice, but it is no longer the same
## choice. It steers: [ObstacleField] answers what is in the way, what can be
## seen, and where there is cover, and the behaviours lean on those. What that
## buys is a chaser taking the short way round a barrel and a guard putting one
## between itself and you. What it does not buy is routing — six discs and a
## look-ahead cannot solve an L of two crates, and are not meant to. The
## stuck-guard below is what covers the rest, and covers walls, which are not in
## the field at all.

## This one is gone, and where. The Game listens so it can tell when a room is
## cleared and roll for loot — it owns the seeded RNG, so the roll cannot happen
## here without making drops unreproducible from a run seed.
##
## Carries the position because by the time anything acts on this the corpse is
## mid-fade and about to free itself.
signal died(loot_source: StringName, at: Vector2)

## Which row of the drop table this one's death is looked up under. Not a table
## and not a drop chance: an enemy says what it is and the run's [DropConfig]
## says what that is worth, so the whole economy — every enemy type, every floor
## — is read and tuned in one inspector rather than across every def.
##
## Filled from the [EnemyDef] by [method configure]. Left public because game.gd
## overwrites it with &"boss" on the one it just promoted, which is what lets a
## single boss drop row serve every archetype instead of needing four of them. A
## source with no rule drops nothing, which is what makes a new enemy quiet
## rather than an error.
var loot_source: StringName = &"grunt"

## Physics frames a chaser may spend touching something without gaining ground on
## the player before it counts as wedged rather than fighting. Frames rather than
## seconds so two runs of the same fight make the same decision.
const STUCK_FRAMES := 12
## And how long it walks sideways afterwards. Long enough to clear the widest prop
## at chase speed, short enough to read as a shove rather than a patrol.
const UNSTICK_FRAMES := 20
## Ground gained per frame below which an enemy counts as gaining none. At 60 px/s
## on a 60Hz tick an unobstructed run gains a pixel a frame.
const STUCK_PROGRESS := 0.1
## Inside this it is grinding on the PLAYER, which is the whole job — see
## _damage_on_contact. Never stuckness.
const STUCK_IGNORE_RANGE := 24.0

## How long a pulse knockback holds steering off before the enemy starts
## fighting its way back toward the target — long enough to read as a shove,
## short enough that it is not a second, longer stagger stacked on the silence.
const PULSE_KNOCKBACK_HOLD := 0.25

## Seconds between one body's hits on the same prop. The player's own mercy
## window rate-limits contact damage TO the player; a crate has no such window,
## so without this a booger pressed against a barrel would delete it in two
## frames rather than chew through it.
const BREAK_INTERVAL := 0.3

var _def: EnemyDef
var _behaviour: EnemyBehaviour
var _ctx := SteeringContext.new()
var _target: Node2D
## Room-local minus global. [ObstacleField] is room-local and we are not; this is
## the whole of the conversion, applied once a frame — see [method set_room].
var _field_origin := Vector2.ZERO

## Boss scaling lives on the node rather than being written back into the def.
## The def is a shared .tres: buffing it in place would promote every enemy of
## that type for the rest of the run, on every floor after this one. -1 means
## "not a boss, use the def's own number".
var _boss_contact_damage: int = -1
var _boss_bullet_damage: int = -1

var _fire_cooldown := 0.0
## Seconds left of the wind-up before a shot we have already committed to. The
## window that did not exist before [AttackTell] needed something to draw — see
## [method _maybe_shoot].
var _windup := 0.0
## Where the behaviour wanted to shoot this frame, kept rather than asked for
## twice. [method EnemyBehaviour.aim] is not free: it runs
## [method SteeringContext.can_see_target] over every prop in the room, and the
## tell needs the same answer [method _maybe_shoot] just got.
var _aim := Vector2.ZERO
var _break_cooldown := 0.0
var _stuck_frames: int = 0
var _unstick_frames: int = 0
var _unstick_sign: float = 1.0

## Steering is suspended outright while either of these is running, the same
## shape as the player's own is_dodging early return. Seconds rather than msec
## timestamps so they pause when the game does, matching
## [member SteeringContext.phase_remaining].
var _dodge_hold := 0.0
var _dodge_cooldown := 0.0
var _knockback_hold := 0.0
## Set by pulse_stagger. The trigger stays jammed for the whole silence, which is
## much longer than the shove.
var _fire_suppressed := 0.0

@onready var _health: Health = $Health
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collider: CollisionShape2D = $CollisionShape2D
## Under the sprite rather than the body, so it inherits both
## [member EnemyDef.sprite_scale] and the boss multiplier [method make_boss]
## applies to the same node. A ring sized in absolute pixels would be right on
## exactly one enemy.
@onready var _tell: AttackTell = $AnimatedSprite2D/AttackTell


## Become one particular kind of bad guy.
##
## Call it BEFORE the node enters the tree, the same window [method set_target]
## and [method make_boss] are used in: [Health] copies max_hp into hp in its own
## _ready(), and _ready() arms the dodge sensor off the behaviour, so both have to
## already be right by then.
func configure(def: EnemyDef) -> void:
	_def = def
	_behaviour = def.behaviour

	# The capsule is a sub-resource of enemy.tscn and therefore shared by every
	# enemy instanced from it. Resizing the original would resize the whole room,
	# which is the bug make_boss used to carry this duplicate() to avoid — it now
	# happens here, once, for everyone, and make_boss only scales what it is given.
	var shape := CapsuleShape2D.new()
	shape.radius = def.body_radius
	shape.height = def.body_height
	$CollisionShape2D.shape = shape

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	sprite.sprite_frames = def.frames
	sprite.position = def.sprite_offset
	sprite.scale = Vector2.ONE * def.sprite_scale
	sprite.speed_scale = def.frame_rate

	$Shadow.position = def.shadow_offset

	# Reached through the tree rather than through _tell, for the same reason the
	# collider, the sprite and the shadow above are: this runs BEFORE the node
	# enters it, and the @onready has not resolved yet.
	$AnimatedSprite2D/AttackTell.color = def.telegraph_color

	$Health.max_hp = def.max_hp
	_ctx.radius = def.body_radius
	loot_source = def.loot_source


## Handed in by whoever spawned us, rather than looked up: the spawner already
## holds the player, and a group lookup would make every enemy depend on a
## global name.
func set_target(target: Node2D) -> void:
	_target = target


## Everything about the room we are fighting in, in one call because the three
## are useless apart.
##
## [ObstacleField] is room-local — every position in it came from an
## [ObstaclePlan] — and a room sits at coord * STRIDE, so on any floor bigger
## than one room a global position is thousands of pixels from the space the
## field answers in. `origin` is that room's global position, and subtracting it
## once per frame in _physics_process is the entire conversion. No behaviour ever
## learns that rooms have positions.
##
## `floor_rect` is handed in for the same reason it is handed to
## [method ObstacleField.cover_point] rather than looked up: reading Room.FLOOR
## from here would compile room.gd, and through it elevator.gd and player.gd, for
## one Rect2. The caller already holds it.
##
## The field is held by reference and shared with game.gd and every other enemy
## in the room, which is what makes a prop being shot out visible to all of them
## on the next frame rather than the next visit.
func set_room(field: ObstacleField, origin: Vector2, floor_rect: Rect2) -> void:
	_ctx.field = field
	_ctx.bounds = floor_rect
	_field_origin = origin


## Promote this one to a floor boss: harder to kill, harder to stand next to, and
## big enough that walking into the room tells you which room it is.
##
## Deliberately a buff and not a subclass. A boss with its own attack patterns is
## a different job; what this buys is a fight that reads as a climax using the
## enemies that already exist, and it is the one call to delete when that job is
## done.
##
## Call it AFTER [method configure] and before the node enters the tree. The
## collider it scales is the per-instance one configure() built, so there is
## nothing shared left to be careful of.
##
## Damage is a separate multiplier from hit points on purpose. The player has no
## health bar — damage is taken out of the O2 countdown — so scaling what a boss
## hits for by what it takes to kill one does not make the fight longer, it makes
## it unsurvivable.
##
## Only ever reaches a def with boss_eligible set, so nothing bolted to a wall is
## promoted — see [method EnemySet.pick].
func make_boss(hp_scale: float, damage_scale: float, size_scale: float) -> void:
	var health: Health = $Health
	health.max_hp = maxi(1, roundi(health.max_hp * hp_scale))
	_boss_contact_damage = maxi(1, roundi(_def.contact_damage * damage_scale))
	_boss_bullet_damage = maxi(1, roundi(_def.bullet_damage * damage_scale))

	$AnimatedSprite2D.scale *= size_scale

	var collider: CollisionShape2D = $CollisionShape2D
	var shape: CapsuleShape2D = collider.shape
	shape.radius *= size_scale
	shape.height *= size_scale
	_ctx.radius = shape.radius

	var shadow: Sprite2D = $Shadow
	shadow.scale *= size_scale
	shadow.position *= size_scale


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

	# Undressed. Killable and inert rather than throwing on the first frame —
	# _physics_process returns early with no behaviour — but loud, because the
	# only way to get here is a spawner that skipped configure(), and a silently
	# motionless enemy reads as an AI bug rather than a missing call.
	if _def == null:
		push_warning("Enemy entered the tree with no EnemyDef — see Enemy.configure")
		return

	# One roll, handed to the behaviour, which spends it on whatever it staggers.
	# A roomful sharing a spawn frame otherwise acts in unison forever after.
	var roll := randf()
	_fire_cooldown = _def.spawn_grace + roll * _def.fire_interval
	if _behaviour != null:
		_behaviour.on_spawn(_ctx, roll)

	# Only the archetypes that react to incoming fire pay for the sensor; a
	# roomful of chasers each carrying an Area2D that never fires a signal is
	# pure cost.
	var sensor: Area2D = $DodgeSensor
	sensor.area_entered.connect(_on_dodge_sensor_area_entered)
	sensor.set_deferred("monitoring", _behaviour != null and _behaviour.watches_bullets())


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _behaviour == null:
		return

	_tick_timers(delta)
	_refresh_context(delta)

	var to_target: Vector2 = _target.global_position - global_position
	velocity = _desired_velocity()
	var was_at := global_position
	move_and_slide()
	_track_progress(global_position - was_at, to_target)
	_damage_on_contact()

	_draw_facing()
	_maybe_shoot(delta)
	# After the shot, not before it, so the ring comes off on the same frame the
	# bullet appears rather than lingering a frame behind it.
	_show_attack_tell()


func _tick_timers(delta: float) -> void:
	_dodge_hold = maxf(0.0, _dodge_hold - delta)
	_dodge_cooldown = maxf(0.0, _dodge_cooldown - delta)
	_knockback_hold = maxf(0.0, _knockback_hold - delta)
	_fire_suppressed = maxf(0.0, _fire_suppressed - delta)
	_break_cooldown = maxf(0.0, _break_cooldown - delta)


## Rewrite the behaviour's view of the world, in the field's space.
##
## The one place global and room-local meet. Everything downstream of here —
## every behaviour, every field query — is room-local, and everything upstream is
## global.
func _refresh_context(delta: float) -> void:
	_ctx.tick(delta)
	_ctx.here = global_position - _field_origin
	_ctx.target = _target.global_position - _field_origin
	_ctx.velocity = velocity
	_ctx.touching = get_slide_collision_count() > 0


## What the behaviour wants, unless something is overriding it.
##
## Three things suspend steering outright, and they are all "a force was applied
## to this body and it is still playing out": a dodge, a pulse knockback, and the
## unstick shove. The first two hold the velocity they were given; the third is
## the only one that still has a direction of its own to walk.
func _desired_velocity() -> Vector2:
	if _dodge_hold > 0.0 or _knockback_hold > 0.0:
		return velocity
	if _unstick_frames > 0:
		_unstick_frames -= 1
		# Assigned outright rather than eased, because the collision has already
		# taken the velocity we would otherwise be easing out of, and easing back
		# up from a standstill spends the whole window still pressed against it.
		var toward := (_target.global_position - global_position).normalized()
		return toward.orthogonal() * _unstick_sign * _behaviour.top_speed()
	return _behaviour.steer(_ctx)


## Did that move actually take us anywhere?
##
## Measured after the fact rather than predicted, because the only thing that
## knows a slide came to nothing is the slide. move_and_slide handles a glancing
## hit by itself; what it cannot handle is a square-on one, where there is no
## tangent left to give and the whole velocity is eaten.
##
## Kept even though the behaviours now steer around props, because it answers a
## different question. Avoidance is a lean applied to where we WANT to go; this
## is what happens when we are already wedged, and the commonest thing to be
## wedged on is a wall, which is not in [ObstacleField] at all.
##
## Skipped for anything that does not move under its own steam — a turret is not
## stuck, it is bolted down.
func _track_progress(moved: Vector2, to_target: Vector2) -> void:
	if _unstick_frames > 0 or is_zero_approx(_behaviour.top_speed()):
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


## Everything we shoved this frame, and what that costs it.
##
## One walk over the slide collisions rather than two: the player takes contact
## damage and anything else that can be hurt takes break damage, and splitting
## them would mean looping the same collisions twice to answer the same question.
##
## break_damage defaults to 0 on an [EnemyDef], which is what keeps a shooter
## inert — it bumps a crate and nothing happens, exactly as every enemy did
## before this. The behaviour gets the last word on whether this particular frame
## counts, which is how a licker smashes things only mid-lunge.
##
## An indestructible prop needs no test here: [method Obstacle.take_damage]
## returns early on one, so a booger chewing a rock is already a silent no-op.
func _damage_on_contact() -> void:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider == null or not collider.has_method("take_damage"):
			continue
		if collider == _target:
			collider.take_damage(_contact_damage(), Damage.Type.BLUNT)
			continue
		if _def == null or _def.break_damage <= 0 or _break_cooldown > 0.0:
			continue
		if not _behaviour.breaks_on_contact(_ctx):
			continue
		_break_cooldown = BREAK_INTERVAL
		collider.take_damage(_def.break_damage, Damage.Type.BLUNT)


func _draw_facing() -> void:
	if _def == null or _sprite.sprite_frames == null:
		return
	var look: Vector2 = _behaviour.facing(_ctx)
	var animation := EnemyFacing.animation_for(_def.facing, look, _def.facing_offset_degrees)
	if _sprite.animation != animation:
		_sprite.play(animation)

	# Art whose frames ARE its bearings is held on one of them rather than played.
	# The -1 is what keeps the word "rotation" out of this file entirely — see
	# [method EnemyFacing.frame_for].
	var frame := EnemyFacing.frame_for(_def.facing, look,
			_sprite.sprite_frames.get_frame_count(animation), _def.facing_offset_degrees)
	if frame < 0:
		return
	_sprite.pause()
	_sprite.frame = frame


## The behaviour says whether it would fire; the def says how often. Splitting it
## that way is what lets a turret's sweep decide WHEN without also owning the
## weapon's rate of fire.
##
## The wind-up sits between the two and belongs to neither, which is why it is
## held here as a second clock rather than folded into the cooldown. A shot can
## only ever leave at the END of a full one, and that is the property worth having
## — a tell that is sometimes skipped is worse than no tell at all, because the
## player has by then learned to wait for it. The guard that has been out of range
## for ten seconds, with a cooldown long since gone negative, now winds up when it
## re-acquires you instead of firing on the frame it sees you.
##
## [member EnemyDef.spawn_grace] is untouched: the roll in front of the first shot
## still staggers a roomful, and the wind-up lands after it rather than instead.
func _maybe_shoot(delta: float) -> void:
	_fire_cooldown -= delta

	_aim = _behaviour.aim(_ctx)
	# A shot the behaviour has stopped wanting takes its tell back with it — you
	# stepped out of range, a barrel closed the line, the pulse bomb jammed the
	# trigger. A ring that closes onto nothing is worse than none, because it
	# teaches the player that rings do not mean anything.
	if _aim.is_zero_approx() or _fire_suppressed > 0.0:
		_windup = 0.0
		return

	if _windup > 0.0:
		_windup = maxf(0.0, _windup - delta)
		if _windup <= 0.0:
			_fire()
		return

	if _fire_cooldown > 0.0:
		return

	_windup = _def.telegraph_seconds
	if _windup <= 0.0:
		_fire()


## Spending the wind-up out of the interval rather than after it is what keeps a
## telegraph a warning instead of a nerf: the cooldown restarts short by exactly
## the tell that is about to be paid in front of the next shot, so one shot to the
## next is still [member EnemyDef.fire_interval] to the frame. Adding it on top
## would have quietly cut every shooter's rate of fire by the length of its own
## tell, which is a balance change wearing a readability change's clothes.
func _fire() -> void:
	_fire_cooldown = maxf(0.0, _def.fire_interval - _def.telegraph_seconds)
	_shoot(_aim.normalized())


## Which wind-up is running, and where it points.
##
## Two of them, because two different things know an attack is coming and they are
## not the same thing: this node owns the clock in front of a SHOT, because it
## owns the fire cooldown, and a behaviour owns the clock in front of anything it
## invented for itself — see [method EnemyBehaviour.windup]. Collapsing them into
## one would mean either the behaviour setting its own rate of fire or a charger
## pretending to have a gun.
##
## The shot wins where both could answer. Nothing overrides both today, and if
## something ever does, the shot is the one with a bullet behind it.
func _show_attack_tell() -> void:
	if _windup > 0.0 and _def.telegraph_seconds > 0.0:
		_tell.set_charge(1.0 - _windup / _def.telegraph_seconds, _aim)
		return
	# facing() rather than aim(): a charger has no aim vector at all, and mid
	# wind-up its facing is already the player — see [method ChargeBehaviour.facing].
	_tell.set_charge(_behaviour.windup(_ctx), _behaviour.facing(_ctx))


func _shoot(aim: Vector2) -> void:
	if _def == null or _def.bullet_scene == null:
		return
	var direction := aim.rotated(randf_range(-_def.aim_spread, _def.aim_spread))

	var bullet: Area2D = _def.bullet_scene.instantiate()
	bullet.arm(direction, CollisionLayers.ENEMY_BULLET,
			CollisionLayers.WORLD | CollisionLayers.PLAYER, _bullet_damage(),
			_def.bullet_damage_type, _def.bullet_speed)
	# Parented to the run container exactly as the player's shots are, so the
	# Game's projectiles sweep stays the single owner of bullet lifetime.
	get_tree().current_scene.add_child(bullet)
	# Same shot sound as the player's gun, pitched and dimmed down so enemy fire
	# reads as duller and doesn't compete with the player's own shots.
	AudioManager.play_sfx("laser_gun_01", 0.7, -6.0)
	bullet.global_position = global_position + direction * _def.muzzle_offset
	bullet.reset_physics_interpolation()


## A player bullet came within reach, and this one is the sort that reacts. The
## jump itself is the behaviour's — reading the bullet's direction rather than
## its position means a shot that would have missed anyway does not provoke a
## dodge into its path, and that judgement belongs with the archetype.
func _on_dodge_sensor_area_entered(area: Area2D) -> void:
	if _behaviour == null or _dodge_cooldown > 0.0:
		return
	if not "direction" in area:
		return
	var jump: Vector2 = _behaviour.dodge(_ctx, area.direction)
	if jump.is_zero_approx():
		return
	velocity = jump
	_dodge_hold = _behaviour.dodge_hold_seconds()
	_dodge_cooldown = _behaviour.dodge_cooldown_seconds()


## Hit by the player's pulse bomb: shoved away from the blast and its trigger
## jammed for silence_duration. Duck-typed the same way take_damage is, so the
## bomb needs nothing more than has_method to reach every enemy on screen.
func pulse_stagger(from: Vector2, force: float, silence_duration: float) -> void:
	var away := global_position - from
	if away.length() < 0.001:
		away = Vector2.RIGHT
	velocity = away.normalized() * force
	_knockback_hold = PULSE_KNOCKBACK_HOLD
	_fire_suppressed = silence_duration


## Bullets duck-type this — see bullet.gd. Damage lands on the body itself
## rather than a hurtbox, then gets handed down to the component that owns it.
func take_damage(amount: int, type: int = Damage.Type.BLUNT) -> void:
	_health.take_damage(amount, type)


## The def's number unless make_boss overrode it. Both of these are only ever
## reached from a frame that already has a def — _physics_process returns early
## without one — so neither needs a null branch.
func _contact_damage() -> int:
	return _boss_contact_damage if _boss_contact_damage >= 0 else _def.contact_damage


func _bullet_damage() -> int:
	return _boss_bullet_damage if _boss_bullet_damage >= 0 else _def.bullet_damage


func _on_health_damaged(_amount: int, _type: int) -> void:
	var flash := create_tween()
	flash.tween_property(_sprite, "modulate", Color(4.0, 4.0, 4.0), 0.04)
	flash.tween_property(_sprite, "modulate", Color.WHITE, 0.08)
	# Pitch-varied, or a shotgun spread landing on four bodies on one frame is a
	# single loud click rather than four hits.
	AudioManager.play_sfx("enemy_take_damage", randf_range(0.92, 1.08), -8.0)


func _on_health_died() -> void:
	# Reported before the fade rather than after it, so the room unlocks on the
	# killing blow instead of a tenth of a second later. What our death is worth
	# is the run's business, not ours.
	died.emit(loot_source, global_position)
	AudioManager.play_sfx("enemy_death", randf_range(0.94, 1.06), -4.0)
	# Stop interacting the instant we die, so the corpse cannot block a shot or
	# body-check the player while it plays out.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

	# Still a tween rather than a death animation: none of the four sets shipped
	# with death frames. When they land, this becomes _sprite.play("death").
	var death := create_tween()
	death.set_parallel(true)
	death.tween_property(_sprite, "scale", _sprite.scale * Vector2(1.4, 0.6), 0.12)
	death.tween_property(_sprite, "modulate:a", 0.0, 0.12)
	await death.finished
	queue_free()
