class_name Loadout
extends Node

## What its owner is currently holding, and everything that follows from it.
##
## One weapon at a time: the equipped [WeaponDef], the rounds left in it, the
## reload, the gap between shots, and — for anything that is not the starting
## weapon — how long is left before it is handed back.
##
## This is a component rather than part of the player because "what am I holding"
## is a per-node behaviour with no opinion about who is holding it. It names no
## scene and no autoload, and asks its owner for nothing: the two player numbers
## it needs for the starting weapon are pushed in from above (see
## [member player_damage]), and what a shot sounded like is reported rather than
## played. Signals up, calls down.
##
## That is also what makes it testable — tools/check_weapons.gd drives one
## through the whole lifecycle in a terminal, which is only possible because
## nothing has to be started first.
##
## The reason it exists at all: before it, adding a second weapon meant a second
## `_shotgun_active` bool, a second set of exports and a second branch inside
## shoot(). Here a weapon is data, and the number of branches stays at one.

## The weapon fallen back to when a timed one runs out, and the one carried at
## the start of a run. The only weapon that should have equip_seconds of zero.
@export var starting_weapon: WeaponDef

## Where fired projectiles are parented.
##
## Left null for the running scene, which is what stops a shot from following its
## shooter into the next room — the Game clears the "projectiles" group on every
## swap. Settable so that firing does not have to reach through get_tree() for an
## ambient global, which is both the one hidden dependency this component would
## otherwise have and the reason tools/check_weapons.gd can pull the trigger at
## all: a --script run has no scene tree to reach into.
var projectile_parent: Node = null

## Currently held. Never null after _ready.
var weapon: WeaponDef

## Rounds left in the magazine.
var ammo := 0

## True for the whole reload wait, whether it started automatically off an empty
## magazine or early from the reload input. Distinct from being on cooldown,
## which is the ordinary fire-rate gap between shots.
var is_reloading := false

## Set from above out of the tuning profile. Skipping the spend is the whole of
## it: the magazine never reaches zero, so the reload is never entered and the
## counter stays full without needing a second switch for "no reload".
var infinite_ammo := false

## What the owner's own gun would hit for, and how fast it would fire, right now.
## Written from above whenever they change; read only by a weapon with
## scales_with_player_stats on, which is the starting pistol and nothing else.
var player_damage := 10
var player_fire_interval := 0.14

## Fired whenever the magazine count changes, so the HUD never has to poll.
signal ammo_changed(current: int, magazine_size: int)
## Fired at the start and end of a reload, so the HUD can show "RELOADING" even
## when a manual reload starts with rounds still left in the magazine.
signal reloading_changed(reloading: bool)
## Fired when the held weapon changes, carrying the weapon itself rather than a
## flag: the HUD reads its own icon off it, and the player reads how to draw it.
## A HUD that was told `true` could only ever show one alternative gun.
signal weapon_changed(new_weapon: WeaponDef)
## Fired while a timed weapon counts down, so the HUD can show how long is left.
## Emits (0, 0) for a permanent weapon, which is how the HUD knows to hide it.
signal equip_time_changed(remaining: float, total: float)
## The trigger was pulled: what it should sound like, with the pitch already
## rolled.
##
## Reported rather than played, because naming AudioManager here would make that
## autoload a COMPILE-time dependency of this script and of everything that names
## its type — and a --script run starts no autoloads, so tools/check_weapons.gd
## could no longer drive a Loadout at all. Same trap obstacle_set.gd describes.
## Our owner is a Node in a running game and has the autoloads anyway.
signal shot_fired(sound: StringName, pitch: float, volume_db: float)

## Seconds until the next shot is allowed, and until the reload finishes.
##
## Counted down in _physics_process — where the trigger is polled, so a cooldown
## can never be a frame out of step with the input it gates — rather than awaited
## on a SceneTreeTimer, because an awaited timer cannot be cancelled. Swapping
## weapons or freezing for a shop mid-wait would leave a coroutine still running,
## and it would come back and re-arm a gun that is no longer the one being held.
## Same shape as enemy.gd's _fire_cooldown.
var _cooldown := 0.0
var _reload_remaining := 0.0

## Seconds left on a timed weapon, and what it started at — the second is only
## for the HUD, which needs a fraction rather than a number of seconds.
var _equip_remaining := 0.0
var _equip_total := 0.0

## While true nothing ticks: no cooldown, no reload, and above all no equip
## countdown. Set from above whenever the owner is frozen — browsing a shop or
## riding a lift — so a twenty-second weapon is not eaten by a menu.
var _suspended := false

## Spread jitter and shot pitch. One generator rather than a fresh
## RandomNumberGenerator per shot, which is what the old shoot() did.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if starting_weapon != null:
		equip(starting_weapon)


func _physics_process(delta: float) -> void:
	if _suspended:
		return

	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)

	if is_reloading:
		_reload_remaining -= delta
		if _reload_remaining <= 0.0:
			_finish_reload()

	if _equip_remaining > 0.0:
		_equip_remaining = maxf(0.0, _equip_remaining - delta)
		equip_time_changed.emit(_equip_remaining, _equip_total)
		if _equip_remaining <= 0.0:
			# Back to the gun you own. Deliberately not "the previous weapon":
			# picking up three in a row should not leave a stack to unwind.
			equip(starting_weapon)


## Take up a weapon.
##
## Re-equipping what is already held does not stack — it tops the magazine back
## up and restarts the clock, the same bargain gain_bomb makes at the cap.
##
## Any reload or cooldown in flight is dropped, because they belonged to the old
## gun: finishing a shotgun's 1.2s reload by loading thirty rounds into a Timmy
## Gun would be the wrong two halves of two different weapons.
func equip(new_weapon: WeaponDef) -> void:
	if new_weapon == null:
		return

	weapon = new_weapon
	ammo = new_weapon.magazine_size
	_cooldown = 0.0
	_reload_remaining = 0.0

	if is_reloading:
		is_reloading = false
		reloading_changed.emit(false)

	_equip_total = 0.0 if new_weapon.is_permanent() else new_weapon.equip_seconds
	_equip_remaining = _equip_total

	weapon_changed.emit(weapon)
	ammo_changed.emit(ammo, magazine_size())
	equip_time_changed.emit(_equip_remaining, _equip_total)


## Rounds the held weapon holds. Read by the HUD, and the ceiling a manual reload
## tops up to.
func magazine_size() -> int:
	return weapon.magazine_size if weapon != null else 0


## Whether the trigger should fire this frame.
##
## The one place fire_mode means anything: a semi-automatic asks whether the
## trigger was just pulled, an automatic asks whether it is still held. Both
## arguments are passed in rather than polled here so the component stays free of
## the input map, and so the owner can decide a dodge roll means neither.
func should_fire(trigger_held: bool, trigger_pulled: bool) -> bool:
	if weapon == null or is_reloading or _cooldown > 0.0 or _suspended:
		return false
	if weapon.fire_mode == WeaponDef.FireMode.AUTOMATIC:
		return trigger_held
	return trigger_pulled


## Pull the trigger once: projectiles into the air, one round off the magazine,
## one sound, one cooldown.
##
## Everything that happens once per PULL rather than once per projectile lives
## here, which is what lets a five-pellet shotgun cost the same one round a
## pistol does.
func fire(origin: Vector2, aim: Vector2) -> void:
	if weapon == null:
		return

	var damage := weapon.damage_against(player_damage)
	for direction in weapon.shot_directions(aim, _rng):
		_spawn_projectile(direction, damage, origin)

	shot_fired.emit(weapon.fire_sound,
			_rng.randf_range(weapon.fire_pitch_min, weapon.fire_pitch_max),
			weapon.fire_volume_db)

	if not infinite_ammo:
		ammo -= 1
		ammo_changed.emit(ammo, magazine_size())

	if ammo <= 0:
		start_reload()
	else:
		_cooldown = weapon.interval_against(player_fire_interval)


## Reload early, with rounds still in the magazine. Refused when there is nothing
## to gain, so the input cannot be used to cancel a cooldown.
func request_reload() -> void:
	if weapon == null or is_reloading or ammo >= magazine_size():
		return
	start_reload()


## Shared by an empty magazine reloading itself and the reload input. is_reloading
## blocks firing for the whole wait, which is what stops a second reload stacking
## on the first.
func start_reload() -> void:
	if weapon == null or is_reloading:
		return
	is_reloading = true
	_reload_remaining = weapon.reload_time
	_cooldown = 0.0
	reloading_changed.emit(true)


func _finish_reload() -> void:
	is_reloading = false
	_reload_remaining = 0.0
	ammo = magazine_size()
	ammo_changed.emit(ammo, magazine_size())
	reloading_changed.emit(false)


## Freeze or resume every clock this owns. Called from above whenever the owner
## stops being in control of themselves — see Player.is_warping.
func set_suspended(value: bool) -> void:
	_suspended = value


## Seconds left on the held weapon, and what it started at. Zeroes for a
## permanent one. Public so the HUD can sync once when it first connects, the
## same way it primes every other counter — see game.gd.
func equip_time() -> Vector2:
	return Vector2(_equip_remaining, _equip_total)


## One projectile. Layers are the player's because this is the player's loadout;
## an enemy that wanted one of these would need them exported, and enemies fire
## their own way today.
func _spawn_projectile(direction: Vector2, damage: int, origin: Vector2) -> void:
	if weapon.projectile_scene == null:
		push_warning("WeaponDef '%s' has no projectile_scene." % weapon.id)
		return

	var parent: Node = projectile_parent if projectile_parent != null else get_tree().current_scene
	if parent == null:
		push_warning("Loadout: nowhere to put a projectile — see projectile_parent.")
		return

	var projectile := weapon.projectile_scene.instantiate()

	# Armed before it enters the tree, so its layers are settled by the time the
	# physics server sees it.
	projectile.arm(direction, CollisionLayers.PLAYER_BULLET,
			CollisionLayers.WORLD | CollisionLayers.ENEMY, damage, weapon.damage_type,
			weapon.projectile_speed)
	# Parented away from us, so a projectile does not follow its shooter around.
	parent.add_child(projectile)
	projectile.global_position = origin
	projectile.reset_physics_interpolation()
