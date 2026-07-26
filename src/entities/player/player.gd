extends CharacterBody2D

class_name Player

## Where a shot leaves the gun, relative to the gun sprite: along the aim, and
## across it. What is fired from there — and how fast, how hard and how often —
## belongs to the held [WeaponDef], not here. See src/components/loadout.
@export var muzzle_offset := 20
@export var muzzle_y_offset := 0

@export_group("Stats")
## Global multiplier on top of every level's table value below — one knob to
## buff or nerf every stat at once without touching the tables themselves.
@export var STAT_SCALE := 1.0

## Damage per POWER_LVL, index 0 is level 1.
@export var BULLET_DAMAGE_VALUES: Array[int] = [10, 14, 18, 22, 26, 30, 35]
## Walk speed per SPEED_LVL, index 0 is level 1.
@export var WALK_SPEED_VALUES: Array[int] = [150, 200, 250, 300, 350, 375, 400]
## Seconds between shots per FIRERATE_LVL — lower is faster, index 0 is level 1.
@export var FIRE_RATE_VALUES: Array[float] = [0.14, 0.12, 0.11, 0.10, 0.09, 0.08, 0.07]

const MIN_STAT_LVL := 1
const MAX_STAT_LVL := 7

var POWER_LVL := 1
var SPEED_LVL := 1
var FIRERATE_LVL := 1

## Derived from POWER_LVL/BULLET_DAMAGE_VALUES by set_power_level() — see _ready().
var bullet_damage: int
## Derived from FIRERATE_LVL/FIRE_RATE_VALUES by set_firerate_lvl() — see _ready().
var fire_rate: float
## Derived from SPEED_LVL/WALK_SPEED_VALUES by set_speed_lvl() — see _ready().
var WALK_SPEED: float

## Fired whenever a stat level changes, so the HUD never has to poll for it.
signal power_level_changed(lvl: int)
signal speed_lvl_changed(lvl: int)
signal firerate_lvl_changed(lvl: int)

## Money carried. Uncapped — unlike ammo and bombs there is no magazine or carry
## limit here.
##
## Held on the player rather than in a wallet of its own because every
## [ItemEffect] is apply(player) — putting the balance anywhere else would force
## one effect to reach for the run container and break the uniform signature that
## lets effects compose. The player also already survives room changes, which is
## the only other thing a separate owner would have bought.
##
## Starts at zero. A run that should begin with money says so at run start rather
## than here, so the shipped number stays the honest one.
var coins := 0

## Fired whenever the coin count changes, so the HUD never has to poll for it.
## A refused purchase changes nothing and so says nothing — see
## [method spend_coins].
signal coins_changed(current: int)


func add_coins(amount: int) -> void:
	if amount == 0:
		return
	coins = maxi(0, coins + amount)
	coins_changed.emit(coins)


## Take payment. False means the balance was short and nothing was taken, which
## is the whole reason this returns anything: a caller must not be able to hand
## over the goods and then discover it was not paid.
##
## Deliberately silent on a refusal rather than pushing an error — being unable
## to afford something is an ordinary thing for a player to do, and the shop is
## what says so out loud.
func spend_coins(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true


@export_group("Bombs")
## How many bombs the player can carry unless something raises the cap.
@export var max_f_bombs := 3
## Bombs carried right now. Starts at 1 rather than max_f_bombs — a fresh run
## begins under capacity, same as Isaac.
var f_bombs := 1

## How hard the pulse shoves every enemy on screen, and how long it jams their
## trigger afterward. Exported rather than constants so the blast can be tuned
## from the inspector alongside max_f_bombs.
@export var pulse_knockback_force := 260.0
@export var pulse_silence_duration := 2.0

## Fired whenever the bomb count changes, so the HUD never has to poll for it.
signal bombs_changed(current: int, max_bombs: int)

## One coin, the way the pickup this replaced granted them. Kept as a one-line
## alias of [method add_coins] so anything written against it still works.
##
## The money_jingle_1 that used to play here now lives on the coin's
## ItemDef.pickup_sound, where which noise an item makes is a tuning decision in
## the same inspector as the rest of it rather than a line of code.
func gain_coin() -> void:
	add_coins(1)


## Emergency pulse: spends one bomb, wipes every projectile on screen (same
## group-wide sweep game.gd uses on a room change or death — so this clears the
## player's own bullets too, not just the enemies'), and staggers every enemy
## on screen — knocked back and trigger-jammed for pulse_silence_duration.
func use_bomb() -> void:
	if f_bombs <= 0 or _is_dead:
		return
	f_bombs -= 1
	bombs_changed.emit(f_bombs, max_f_bombs)
	get_tree().call_group("projectiles", "queue_free")
	AudioManager.play_sfx("bomb_air_burst", 2.0,-2)
	AudioManager.play_sfx("pulse_02")
	AudioManager.play_sfx("explosion_01",1,3)

	# Duck-typed rather than cast to Enemy: the "enemies" group is the contract,
	# the same way bullet.gd only ever asks a body for take_damage.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("pulse_stagger"):
			enemy.pulse_stagger(global_position, pulse_knockback_force, pulse_silence_duration)

	_spawn_pulse()


## A quick expanding ring so the wipe reads as an event rather than bullets
## silently vanishing. Built from a radial gradient rather than a new asset,
## same trick as the bullet glow and the pickup's drop shadow.
func _spawn_pulse() -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.4, 0.9, 1.0, 0.6), Color(0.4, 0.9, 1.0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128

	var pulse := Sprite2D.new()
	pulse.texture = texture
	pulse.z_index = 5
	pulse.scale = Vector2(0.1, 0.1)
	get_tree().current_scene.add_child(pulse)
	pulse.global_position = global_position

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "scale", Vector2(4.0, 4.0), 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(pulse.queue_free)

@onready var sprite = $AnimatedSprite2D
@onready var gun: Sprite2D = $BigGunBTransparent
@onready var _reload_indicator: Node2D = $ReloadIndicator
## What we are holding. Everything about firing lives in there; we own the input
## that pulls the trigger and the arm the gun is drawn on, and nothing else.
@onready var _loadout: Loadout = $Loadout

const DODGE_SPEED = 200
const DODGE_DURATION = 0.6

var input_vector := Vector2.ZERO
var last_direction = "down"
var can_move = true
var is_dodging = false
var dodge_direction := Vector2.ZERO
var dodge_timer := 0.0
var gun_default_position: Vector2
## What the gun sprite is scaled to for the weapon currently held. Re-derived on
## every weapon change rather than captured once, because the dodge roll tweens
## the gun down to a fifth of it and back — a value captured before a swap would
## put the wrong gun back at the wrong size.
var gun_default_scale: Vector2
## How we are authored to look. Captured once so that anything which borrows our
## appearance — a room drawn in a perspective of its own, say — never has to
## remember what it changed. See reset_presentation.
var _sprite_default_scale: Vector2
var _sprite_default_position: Vector2

## Right-stick deflection below this counts as the stick being at rest. Also the
## threshold for believing a joypad event means the player actually picked a pad
## up — sticks emit a constant trickle of noise even untouched.
const AIM_DEADZONE := 0.25

## The magazine, read straight off whatever is held. Kept here as well so the HUD
## can prime itself from the player the way it does for coins and bombs, without
## having to know a Loadout exists.
var ammo: int:
	get: return _loadout.ammo
var magazine_size: int:
	get: return _loadout.magazine_size()
var is_reloading: bool:
	get: return _loadout.is_reloading

## Debug switches, set from the active tuning profile in _ready and false in any
## normal run. Deliberately NOT @export: an inspector checkbox is something you
## can tick, save into player.tscn and commit, which is the exact accident tuning
## profiles exist to prevent. See docs/TUNING_PROFILES.md.
var infinite_ammo := false
var invulnerable := false

## Re-emitted from the Loadout, unchanged.
##
## Forwarded rather than letting the HUD connect to the component directly, so
## that "what does the player tell the world" stays one list on one node, and
## swapping how weapons work never rewires game.gd. Signals up, calls down.
signal ammo_changed(current: int, magazine_size: int)
signal reloading_changed(reloading: bool)
## Carries the weapon itself, so the HUD reads its own icon off it rather than
## being told a flag it would have to translate.
signal weapon_changed(weapon: WeaponDef)
## How long is left on a timed weapon, and what it started at. Both zero for the
## permanent starting weapon, which is how the HUD knows to show nothing.
signal equip_time_changed(remaining: float, total: float)
## World-space aim, whichever device supplied it. Bullets and the gun sprite
## both read this, so neither has to know how the player is aiming.
var gun_direction := Vector2.RIGHT
## How hard the right stick is pushed, 0..1. Zero while aiming with a mouse —
## the camera derives its own strength from cursor distance in that case.
var aim_deflection := 0.0
## Which device last supplied aim. Both can be plugged in, so the most recent
## one wins and the player can swap mid-run without touching a settings screen.
var aiming_with_gamepad := false

## Per-axis multiplier on how fast we move, for rooms that are not drawn top-down.
##
## The belt-scroll lobby squashes the vertical axis: there, up and down are depth
## rather than a second direction to run in, and its walkable band is a fraction
## of a room's height. At full speed the whole thing is crossed in a third of a
## second, which turns walking into the lift into a twitch input.
##
## Vector2.ONE everywhere else, so a room that says nothing gets today's movement.
## Whoever sets it owns putting it back — see elevator_room.gd.
var move_scale := Vector2.ONE

## True while the Game is moving us between rooms. Physics is handed over to the
## transition for the duration — a dodge finishing mid-slide would otherwise
## re-enable can_move and fight the tween for control of our position.
##
## Also the flag rooms use to freeze us for something that is not a transition at
## all — browsing a shop, riding a lift — because shoot, reload and bomb are all
## polled outside the can_move block. That second use is why this has a setter:
## everything the Loadout is counting down has to stop with us, or a
## twenty-second weapon is spent reading price tags. Whoever sets it owns
## clearing it, exactly as before; nothing at any call site changes.
var is_warping := false:
	set(value):
		is_warping = value
		if _loadout != null:
			_loadout.set_suspended(value)

## Something landed a hit. We deliberately hold no health of our own — the O2
## countdown is the health bar — so this reports upward and lets the run decide
## what a hit costs. Signals up, calls down: the player never touches the HUD.
signal damaged(amount: int, type: int)

## An oxygen pickup landed on us. Same shape as damaged — reports up rather than
## touching the O2 timer directly, so the player still knows nothing about the
## HUD.
signal healed(seconds: float)

## The body has finished dying. Emitted after the animation, so a listener can
## hold the camera on us before the screen goes anywhere. The decision that we
## died is not ours — the O2 timer makes it and the run calls die().
signal died

## Seconds of mercy after a hit. Without it a stream of bullets lands several
## times a second and a roomful of enemies empties the tank in moments.
@export var invulnerable_time := 0.6

var _invulnerable_until_msec: int = 0

## Fires-once guard on die(), so a death sequence cannot be started twice.
var _is_dead := false


func _ready() -> void:
	gun_default_position = gun.position
	gun_default_scale = gun.scale
	_sprite_default_scale = sprite.scale
	_sprite_default_position = sprite.position
	infinite_ammo = GameConfig.get_value("player", "infinite_ammo", infinite_ammo)
	invulnerable = GameConfig.get_value("player", "invulnerable", invulnerable)

	# Straight through, unchanged — see the signal declarations above.
	_loadout.ammo_changed.connect(func(a, m): ammo_changed.emit(a, m))
	_loadout.reloading_changed.connect(_on_reloading_changed)
	_loadout.weapon_changed.connect(_on_weapon_changed)
	_loadout.equip_time_changed.connect(func(r, t): equip_time_changed.emit(r, t))
	# The Loadout says what a shot sounded like; making the noise is ours, so that
	# it never names an autoload — see its shot_fired.
	_loadout.shot_fired.connect(func(s, pitch, db): AudioManager.play_sfx(s, pitch, db))
	_loadout.infinite_ammo = infinite_ammo

	set_power_level(POWER_LVL)
	set_speed_lvl(SPEED_LVL)
	set_firerate_lvl(FIRERATE_LVL)

	# A child's _ready runs before its parent's, so the Loadout has ALREADY
	# equipped the starting weapon and emitted for it — into nothing, because the
	# connections above did not exist yet. This is that first swap being applied
	# by hand, and it is why the player is not drawn empty-handed for a frame.
	_on_weapon_changed(_loadout.weapon)


func set_power_level(lvl: int) -> void:
	POWER_LVL = clampi(lvl, MIN_STAT_LVL, MAX_STAT_LVL)
	bullet_damage = roundi(BULLET_DAMAGE_VALUES[POWER_LVL - 1] * STAT_SCALE)
	_loadout.player_damage = bullet_damage
	power_level_changed.emit(POWER_LVL)


func set_speed_lvl(lvl: int) -> void:
	SPEED_LVL = clampi(lvl, MIN_STAT_LVL, MAX_STAT_LVL)
	WALK_SPEED = WALK_SPEED_VALUES[SPEED_LVL - 1] * STAT_SCALE
	speed_lvl_changed.emit(SPEED_LVL)


func set_firerate_lvl(lvl: int) -> void:
	FIRERATE_LVL = clampi(lvl, MIN_STAT_LVL, MAX_STAT_LVL)
	fire_rate = FIRE_RATE_VALUES[FIRERATE_LVL - 1] * STAT_SCALE
	_loadout.player_fire_interval = fire_rate
	firerate_lvl_changed.emit(FIRERATE_LVL)


## Last device to speak wins. Joypad motion is filtered by deadzone because an
## untouched stick still emits events — without the filter a pad sitting on the
## desk would take aim back from the mouse every frame.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		aiming_with_gamepad = false
	elif event is InputEventJoypadButton:
		aiming_with_gamepad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > AIM_DEADZONE:
		aiming_with_gamepad = true


func _process(_delta: float) -> void:
	if is_dodging or _is_dead:
		return

	if aiming_with_gamepad:
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		aim_deflection = minf(stick.length(), 1.0)
		# Releasing the stick holds the last aim rather than snapping the gun to
		# some default the player never chose.
		if aim_deflection > 0.0:
			gun_direction = stick / stick.length()
	else:
		aim_deflection = 0.0
		var to_cursor: Vector2 = get_global_mouse_position() - gun.global_position
		if not to_cursor.is_zero_approx():
			gun_direction = to_cursor.normalized()

	gun.rotation = gun_direction.angle()
	gun.flip_v = gun_direction.x < 0


func _physics_process(delta: float) -> void:
	if is_warping or _is_dead:
		return

	if is_dodging:
		dodge_timer += delta
		var t: float = clamp(dodge_timer / DODGE_DURATION, 0.0, 1.0)
		var speed_multiplier: float = 1.0 if t < 0.5 else (1.0 - ((t - 0.5) / 0.5))
		# Scaled like the walk below. An undamped roll is 200px/s and would clear a
		# depth-squashed room in one press, straight past whatever is at the far end.
		velocity = dodge_direction * DODGE_SPEED * speed_multiplier * move_scale
		move_and_slide()
		return

	if can_move:
		input_vector.x = Input.get_axis("ui_left", "ui_right")
		input_vector.y = Input.get_axis("ui_up", "ui_down")
		input_vector = input_vector.normalized()

		# Scaled after normalising, so the input still reads as a direction and only
		# the world decides what a step along each axis is worth.
		velocity = input_vector * WALK_SPEED * move_scale
		update_animation(input_vector)
		move_and_slide()

	if Input.is_action_just_pressed("dodge"):
		if can_move and velocity != Vector2.ZERO:
			var dodge_dir := get_dodge_direction(input_vector)
			if dodge_dir != Vector2.ZERO:
				dodge(dodge_dir)

	# Both trigger readings are handed over rather than one: which of them counts
	# is the held weapon's business, and an automatic that only ever saw
	# just_pressed would fire once per click like everything else.
	if not is_dodging and _loadout.should_fire(
			Input.is_action_pressed("shoot"), Input.is_action_just_pressed("shoot")):
		_loadout.fire(_muzzle_position(gun_direction), gun_direction)

	if Input.is_action_just_pressed("reload") and not is_dodging:
		_loadout.request_reload()

	if Input.is_action_just_pressed("bomb"):
		use_bomb()


## Take a hit. Damage type is passed straight through — what blunt and piercing
## actually cost is the O2 timer's business, not ours.
##
## Invulnerability is measured against the wall clock rather than counted down in
## _physics_process, because _physics_process returns early while is_warping and
## a countdown there would freeze mid-transition.
## True while a hit should have no effect at all. A dodge roll is meant to feel
## like passing through an attack rather than merely surviving it — bullets
## check this and skip themselves entirely instead of just being told to deal
## no damage, which is why this is its own method rather than folded into
## take_damage.
## Whether the death sequence has started. Public because dying changes what
## everything else is allowed to do to us — die() tweens the sprite into a
## flattened pose, so anything driving our appearance has to stand down rather
## than fight it for the same properties every frame.
func is_dead() -> bool:
	return _is_dead


## Put our appearance back the way the scene authored it.
##
## Owned here rather than by whoever changed it. A room that borrows the player's
## look has to give it back, and a room can be freed at any moment — mid
## transition, mid death, mid anything — so "remember what you overwrote and undo
## it on the way out" is a rule that only has to be missed once to leave a player
## permanently shrunk or holding no gun for the rest of a run. Asking us instead
## means there is nothing to remember and nothing to get wrong.
##
## Deliberately does nothing while dead: die() is mid-tween on these same
## properties and a reset would stand the corpse back up.
func reset_presentation() -> void:
	if _is_dead:
		return
	move_scale = Vector2.ONE
	sprite.scale = _sprite_default_scale
	sprite.position = _sprite_default_position
	gun.visible = true
	# Re-drawn from what is actually held rather than from a remembered texture:
	# a weapon window can start, end or be replaced while a room has the gun
	# hidden, and putting the pistol back would be putting back the wrong gun.
	_apply_weapon_look()


func is_intangible() -> bool:
	return is_dodging


func take_damage(amount: int, type: int = Damage.Type.BLUNT) -> void:
	if is_warping or is_dodging or _is_dead:
		return
	# Before the invulnerability stamp, so a profile's god mode also spares us the
	# hit flash — a body flickering red while nothing happens reads as a bug.
	if invulnerable:
		return
	if Time.get_ticks_msec() < _invulnerable_until_msec:
		return
	_invulnerable_until_msec = Time.get_ticks_msec() + int(invulnerable_time * 1000.0)
	damaged.emit(amount, type)
	_flash_hit()
	AudioManager.play_sfx("gas_escapes")
	AudioManager.play_sfx("damage_taken_0%d" % [1 if randf() < 0.5 else 2], randf_range(1.3,1.4))


## Called by RestoreOxygen on contact. Duck-typed the same way bullet.gd calls
## take_damage — the effect does not need to know it is a Player.
func heal(seconds: float) -> void:
	healed.emit(seconds)


## Called by GrantBomb on contact. Clamped rather than ignored past the cap,
## same as gain_seconds clamping oxygen to a full tank — a pickup at max bombs
## is just wasted, not an error.
func gain_bomb() -> void:
	f_bombs = mini(f_bombs + 1, max_f_bombs)
	bombs_changed.emit(f_bombs, max_f_bombs)


## Called by a [WeaponDef] on contact — from a pickup, a chest, or a shop
## purchase, all of which grant an item by the same path. Duck-typed exactly like
## gain_bomb and heal: nothing about a weapon names this scene.
##
## Every rule about the swap — what happens to the magazine, what a second pickup
## mid-window does, when it hands back — belongs to the Loadout, which is why
## this is one line. See Loadout.equip.
func equip_weapon(weapon: WeaponDef) -> void:
	_loadout.equip(weapon)


## Currently held. Public so the HUD can sync once when it first connects, the
## same way it primes every other counter — see game.gd.
func equipped_weapon() -> WeaponDef:
	return _loadout.weapon


## Seconds left on the held weapon and what it started at, as (remaining, total).
## Both zero for the permanent starting weapon.
func equip_time() -> Vector2:
	return _loadout.equip_time()


func _on_weapon_changed(weapon: WeaponDef) -> void:
	_apply_weapon_look()
	if weapon != null and weapon.equip_sound != &"":
		AudioManager.play_sfx(weapon.equip_sound)
	weapon_changed.emit(weapon)


## Draw whatever is currently held.
##
## The gun sprite is ours, so putting a weapon's art on it is ours too — the
## Loadout says what is held and never touches a node of ours to prove it. The
## art in this project is authored at wildly different sizes, so a weapon brings
## its own scale, offset and crop rather than being squeezed into the pistol's.
##
## Reads the weapon back out of the Loadout rather than taking it as an argument,
## so that redrawing after something else borrowed the gun — see
## reset_presentation — cannot put back a weapon we are no longer holding.
func _apply_weapon_look() -> void:
	if _loadout == null or _loadout.weapon == null:
		return
	var weapon: WeaponDef = _loadout.weapon
	gun.texture = weapon.held_texture
	gun.scale = Vector2(weapon.held_scale, weapon.held_scale)
	gun.offset = weapon.held_offset
	gun.flip_h = weapon.held_flip_h
	gun.region_enabled = weapon.held_region.has_area()
	gun.region_rect = weapon.held_region
	# Not touched while dying: die() is mid-tween on the gun's alpha and this
	# would stand it back up at full opacity.
	if not _is_dead:
		gun.modulate = weapon.held_modulate
	# What the dodge roll's tween pulls the gun back to. Re-read here rather than
	# captured once in _ready, so a swap mid-roll still ends up the right size.
	gun_default_scale = gun.scale


func _on_reloading_changed(reloading: bool) -> void:
	_reload_indicator.visible = reloading
	reloading_changed.emit(reloading)


## Out of air. Hand over control and play out.
##
## PLACEHOLDER ANIMATION: a squash-and-fade, borrowed from the enemy death at
## enemy.gd:_on_health_died, because no death frames exist yet. When they land,
## replace the tween with sprite.play("death") and await animation_finished —
## everything around this stays as it is.
##
## Unlike an enemy we do NOT queue_free: the body has to stay on screen for the
## vignette to close over it.
func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	can_move = false
	is_dodging = false
	velocity = Vector2.ZERO
	# The trigger is already dead — _physics_process returns on _is_dead before it
	# is ever read — but the equip countdown is not, and a corpse whose weapon
	# times out under the vignette would swap guns while the screen closes.
	_loadout.set_suspended(true)

	# Stop interacting the instant we die, so a stray bullet or a still-moving
	# enemy cannot shove the corpse around under the vignette.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

	var death := create_tween()
	death.set_parallel(true)
	death.tween_property(sprite, "scale", Vector2(1.4, 0.5), 0.35).set_ease(Tween.EASE_OUT)
	death.tween_property(sprite, "modulate", Color(0.6, 0.7, 0.9, 0.65), 0.35)
	death.tween_property(gun, "modulate:a", 0.0, 0.2)
	await death.finished
	died.emit()


## Brief red flash, so a hit reads even when the only feedback is a number in the
## corner ticking down faster.
func _flash_hit() -> void:
	var flash := create_tween()
	flash.tween_property(sprite, "modulate", Color(1.0, 0.4, 0.4), 0.05)
	flash.tween_property(sprite, "modulate", Color.WHITE, invulnerable_time - 0.05)


## Move instantly, without the renderer drawing the trip. Physics interpolation
## is on project-wide, so without the reset a warp between rooms smears across
## a frame.
func warp_to(target: Vector2) -> void:
	global_position = target
	reset_physics_interpolation()


## Where a shot leaves the gun. The muzzle sits along the aim and, for art whose
## barrel is off the centre line, across it — mirrored with the sprite so the
## offset stays on the barrel when the gun is drawn facing left.
##
## Clamped against the world before it is handed over, because the muzzle reaches
## 20px out while the player's own body is only 3 across: standing at a wall and
## firing into it puts the raw muzzle inside the wall, or past it. The gun hangs
## inside the player, so it is always somewhere she could legally stand and is
## therefore a safe place to measure from.
func _muzzle_position(direction: Vector2) -> Vector2:
	var perpendicular := direction.orthogonal()
	var flip_sign := -1.0 if direction.x < 0 else 1.0
	var muzzle := gun.global_position + direction * muzzle_offset \
			+ perpendicular * muzzle_y_offset * flip_sign
	return Projectile.clear_muzzle(
			get_world_2d().direct_space_state, gun.global_position, muzzle)


## Maps current movement input to one of the eight dodge directions we have
## animations for.
func get_dodge_direction(v: Vector2) -> Vector2:
	if v.y > 0:
		if v.x > 0:
			return Vector2(1, 1).normalized()   # down-right
		elif v.x < 0:
			return Vector2(-1, 1).normalized()  # down-left
		return Vector2.DOWN
	elif v.y < 0:
		if v.x > 0:
			return Vector2(1, -1).normalized()  # up-right
		elif v.x < 0:
			return Vector2(-1, -1).normalized() # up-left
		return Vector2.UP
	elif v.x > 0:
		return Vector2.RIGHT
	elif v.x < 0:
		return Vector2.LEFT
	return Vector2.ZERO


## Dodge in the given direction. "dodge_right" covers right and down-right,
## mirrored via flip_h for left and down-left; "dodge_up_right" does the same
## for up-right and up-left. Straight down and straight up get their own
## animations since they aren't just a mirror of anything.
func dodge(direction: Vector2) -> void:
	can_move = false
	is_dodging = true
	dodge_direction = direction
	dodge_timer = 0.0
	AudioManager.play_sfx("player_grunt_01", randf_range(1.3,1.8))

	if direction == Vector2.DOWN:
		last_direction = "down"
		sprite.play("dodge_down")
	elif direction == Vector2.UP:
		last_direction = "up"
		sprite.play("dodge_up")
	elif direction.y < 0:
		last_direction = "up"
		sprite.flip_h = direction.x < 0
		sprite.play("dodge_up_right")
	else:
		last_direction = "right"
		sprite.flip_h = direction.x < 0
		sprite.play("dodge_right")

	var pull_tween := create_tween()
	pull_tween.set_parallel(true)
	pull_tween.tween_property(gun, "position", Vector2.ZERO, 0.1).set_ease(Tween.EASE_OUT)
	pull_tween.tween_property(gun, "scale", gun_default_scale * 0.2, 0.1).set_ease(Tween.EASE_OUT)

	return_gun()

	await sprite.animation_finished
	is_dodging = false
	can_move = true


func return_gun() -> void:
	await get_tree().create_timer(0.35, false).timeout
	var return_tween := create_tween()
	return_tween.set_parallel(true)
	return_tween.tween_property(gun, "position", gun_default_position, 0.15).set_ease(Tween.EASE_OUT)
	return_tween.tween_property(gun, "scale", gun_default_scale, 0.15).set_ease(Tween.EASE_OUT)


func update_animation(_input_vector):
	if velocity == Vector2.ZERO:
		sprite.play("idle_" + last_direction)
		return
	if Input.is_action_pressed('ui_right'):
		last_direction = "right"
		sprite.flip_h = false
	elif Input.is_action_pressed('ui_left'):
		last_direction = "right"
		sprite.flip_h = true
	elif Input.is_action_pressed('ui_up'):
		last_direction = "up"
	elif Input.is_action_pressed('ui_down'):
		last_direction = "down"
	sprite.play("walk_" + last_direction)
