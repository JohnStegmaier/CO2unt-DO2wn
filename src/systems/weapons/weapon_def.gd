class_name WeaponDef
extends ItemDef

## One gun. Everything about it, in one file.
##
## A weapon is an [ItemDef] that equips itself, which is what keeps it to a
## single form: it already inherits an id, a display name and the whole
## Appearance group, so it drops into a [DropEntry] row exactly like a coin does
## and needs no routing of its own. Where a weapon comes from — an enemy, a
## crate, a chest, a shop shelf, or nowhere at all — is which tables reference
## this file, not anything written here. See docs/WEAPONS.md.
##
## Pure data with pure maths. It touches no node and no autoload, so it loads
## under `godot --headless --script` and tools/check_weapons.gd can exercise
## [method shot_directions] in a terminal instead of by squinting at a muzzle.
## The reason that matters is spelled out at the top of obstacle_set.gd.
##
## Adding a weapon is filling this in. Adding a KIND of weapon — something that
## flies differently rather than shoots differently — is a new projectile scene
## in [member projectile_scene], and still no script edit here.

## How the trigger behaves.
##
## Declared as an enum for readable call sites but exported as a plain int, for
## the reason in grid_direction.gd.
enum FireMode {
	## One shot per press. The pistol, the shotgun, anything with weight.
	SEMI_AUTO,
	## Fires for as long as the trigger is held. The Timmy Gun.
	AUTOMATIC,
}

## How several projectiles from one trigger pull are arranged.
enum SpreadMode {
	## Spaced evenly across [member spread_degrees], so the same pull always
	## reads as one recognisable spread rather than a different clump each time.
	## What a shotgun wants.
	EVEN_FAN,
	## Each projectile rolls its own jitter inside [member spread_degrees]. What
	## a rattling automatic wants.
	RANDOM,
}

@export_group("Equip")
## How long the player keeps this after picking it up, in seconds.
##
## ZERO MEANS PERMANENT, and that is the only thing separating the starting
## pistol from everything else — there is no "is the starter" flag. When the
## window runs out the player falls back to whatever Loadout.starting_weapon is.
##
## Picking the same weapon up again mid-window does not stack; it tops the
## magazine back up and restarts the clock. See Loadout.equip.
@export var equip_seconds: float = 20.0

@export_subgroup("How it is held")
## Swapped onto the player's gun sprite while this is equipped. Usually the same
## texture as [member icon], but it does not have to be — the pistol is drawn
## from a different file than the one its pickup would show.
@export var held_texture: Texture2D
## Uniform scale for [member held_texture] on the gun sprite.
##
## Sprites in this project are authored at wildly different sizes — the pistol is
## 32x32 drawn at 0.75, the shotgun is 14x3 drawn at 1.0 — so this is part of
## how a weapon looks rather than a fudge factor, the same as ItemDef.icon_scale.
@export var held_scale: float = 1.0
## Pushes the sprite away from the hand it pivots around. The pistol's art has
## the grip nowhere near its centre, so it needs a large one; small art usually
## needs none.
@export var held_offset: Vector2 = Vector2.ZERO
## Mirrors the held sprite. Some of the art faces left in its source file.
@export var held_flip_h: bool = false
## Crops the held sprite. Leave at Rect2() for the whole texture, which is what
## every weapon whose art is already the right shape wants — only the pistol,
## drawn from a larger illustration, needs one.
@export var held_region: Rect2 = Rect2()
## Tints the held sprite. White leaves the art alone, which is what pixel art
## that was drawn in its final colours wants; the pistol is lit by one of these
## because its illustration was not.
@export var held_modulate: Color = Color.WHITE

@export_subgroup("How it reads on the HUD")
## Shown in the ammo counter. Falls back to [member held_texture] when empty, so
## most weapons can leave this alone — set it only when the held art is
## unreadable at HUD size.
@export var hud_icon: Texture2D
@export var hud_icon_scale: float = 1.0

@export_group("Firing")
## SEMI_AUTO fires once per press; AUTOMATIC fires while the trigger is held.
@export_enum("semi_auto", "automatic") var fire_mode: int = 0
## Seconds between shots. Lower is faster.
##
## Ignored while [member scales_with_player_stats] is on, which is how the pistol
## gets faster as FIRERATE_LVL rises.
@export var fire_interval: float = 0.14
## Rounds per magazine. Running it dry reloads automatically; the reload input
## tops it up early.
@export var magazine_size: int = 6
## Seconds an empty magazine takes to come back full.
@export var reload_time: float = 1.2

## Whether this gun grows with the player's POWER, FIRERATE and RELOAD_SPEED
## levels.
##
## TRUE for the starting pistol only: it is the player's own gun, so power-ups
## are supposed to be felt through it, and it draws damage, fire interval and
## reload time from Player.BULLET_DAMAGE_VALUES / FIRE_RATE_VALUES /
## RELOAD_SPEED_VALUES instead of from the fields above.
##
## FALSE for everything picked up. Such a weapon keeps its OWN damage and fire
## interval — a shotgun is a different weapon, not the ordinary gun renamed — but
## those numbers are still multiplied by how far the player's POWER and FIRERATE
## levels have come from level 1. So a shotgun found on floor 5 does hit harder
## than one found on floor 1, in proportion, while the gap between a shotgun and
## a timmy gun stays exactly as tuned.
##
## The flag was an all-or-nothing swap until upgrades reached the shop: an
## upgrade bought and then made invisible for the twenty seconds a pickup weapon
## is held reads as a broken purchase, not as weapon identity. Scaling is applied
## in damage_against/interval_against, so this stays the one place to change it.
@export var scales_with_player_stats: bool = false

@export_group("Projectile")
## What one pull of the trigger puts in the air. Any scene whose root implements
## Projectile.arm() — bullet.tscn for anything that flies straight and stops on
## the first thing it hits, chakram.tscn for something that carries on through.
@export var projectile_scene: PackedScene
## Projectiles per trigger pull. Five is a shotgun; one is everything else.
##
## Ammo, cooldown and the shot's sound are spent once per PULL, not once per
## projectile — see Loadout.fire.
@export var projectiles_per_shot: int = 1
## Full width of the spread, in degrees. Zero fires dead straight.
@export var spread_degrees: float = 0.0
## Whether the spread is an even fan or per-projectile jitter. Irrelevant while
## [member spread_degrees] is zero.
@export_enum("even_fan", "random") var spread_mode: int = 0
## Damage per projectile — so a five-pellet shotgun deals five times this when
## every pellet lands, which is what makes point blank worth walking into.
##
## Ignored while [member scales_with_player_stats] is on.
@export var damage: int = 10
## A Damage.Type. BLUNT spends seconds off the oxygen clock; PIERCING raises the
## drain rate instead — see o_2_timer.gd.
@export_enum("blunt", "piercing") var damage_type: int = 0
## Pixels per second.
@export var projectile_speed: float = 400.0

@export_group("Audio")
## Bare key into AudioManager.sounds, the same way ItemDef.pickup_sound is. An
## unknown key is silence rather than a crash, which is the deliberate escape
## hatch for a weapon whose sound has not been delivered yet.
@export var fire_sound: StringName = &"laser_gun_01"
## The shot's pitch is rolled between these on every pull, so a burst does not
## machine-gun the identical sample. Set both to the same number for a weapon
## that should sound exactly alike every time.
@export var fire_pitch_min: float = 0.6
@export var fire_pitch_max: float = 1.5
@export var fire_volume_db: float = -6.0
## Played once as the weapon is equipped, over the pickup's own sound.
@export var equip_sound: StringName


## Whether this weapon is kept for the rest of the run rather than for a window.
## True only of the starting pistol — see [member equip_seconds].
func is_permanent() -> bool:
	return equip_seconds <= 0.0


## Where the projectiles from one trigger pull go.
##
## The whole of the spread, as data in and data out: an aim direction and an RNG
## become N unit vectors. Nothing here touches a node, which is what lets
## check_weapons.gd assert the fan is symmetric and the pellet count is right
## without opening a window.
##
## The RNG is passed in rather than owned so the caller decides what shares a
## seed with what — the same reason LootRoller holds none.
func shot_directions(aim: Vector2, rng: RandomNumberGenerator) -> Array[Vector2]:
	var count := maxi(1, projectiles_per_shot)
	var directions: Array[Vector2] = []
	var spread := deg_to_rad(spread_degrees)

	if is_zero_approx(spread):
		for i in count:
			directions.append(aim)
		return directions

	if spread_mode == SpreadMode.RANDOM:
		for i in count:
			directions.append(aim.rotated(rng.randf_range(-spread * 0.5, spread * 0.5)))
		return directions

	# Even fan. A single projectile sits dead centre rather than at one edge,
	# which is why the count-of-one case cannot share the divisor below.
	for i in count:
		var t: float = 0.0 if count == 1 else float(i) / float(count - 1) - 0.5
		directions.append(aim.rotated(spread * t))
	return directions


## What one projectile from this weapon hits for, given what the player's own gun
## would have hit for and how far their POWER level has come from level 1.
## See [member scales_with_player_stats].
##
## The multiplier defaults to 1.0 so a caller that has no player to ask — a check
## script proving the spread, say — reads the weapon's own printed number.
func damage_against(player_damage: int, power_mult: float = 1.0) -> int:
	if scales_with_player_stats:
		return player_damage
	# Never round a real weapon down to nothing: a multiplier below one is a
	# nerfed run, not a gun that stopped working.
	return maxi(1, roundi(damage * power_mult))


## Seconds between shots, given the player's own current fire rate and how far
## their FIRERATE level has come from level 1. See [member scales_with_player_stats].
func interval_against(player_interval: float, firerate_mult: float = 1.0) -> float:
	if scales_with_player_stats:
		return player_interval
	return fire_interval * firerate_mult


## Seconds an empty magazine takes to come back full, given the player's own
## current reload speed. player_reload_speed is a multiplier rather than a
## seconds value like [param player_interval] above, so scaling divides by it
## instead of substituting it outright. See [member scales_with_player_stats].
func reload_time_against(player_reload_speed: float) -> float:
	return reload_time / player_reload_speed if scales_with_player_stats else reload_time


## Equip on pickup.
##
## Runs any inherited [member effects] first — a weapon that also tops your
## oxygen up is a normal effect in that array — then hands itself over. Overriding
## here rather than shipping every weapon with a stock "equip me" effect is what
## makes a weapon one file instead of a file and a sub-resource you can forget.
##
## Duck-typed exactly like every ItemEffect: the target is a Node and we call a
## method we hope is there, so nothing about a weapon names the player scene.
func grant_to(target: Node) -> void:
	super.grant_to(target)
	if not target.has_method("equip_weapon"):
		return
	target.equip_weapon(self)


## One line for the checker's dump and for the drop-rate table.
func describe() -> String:
	if is_permanent():
		return "%s (permanent)" % id
	return "%s (%.0fs)" % [id, equip_seconds]
