extends SceneTree

## Validate every weapon, exercise its spread maths, and print where each one can
## actually be found.
##
## A [WeaponDef] is pure data with pure maths — it touches no node and no
## autoload — so whether a five-pellet fan really is five pellets, symmetric and
## centred on the aim, can be settled in a terminal instead of by firing at a
## wall and squinting. Run it after editing anything under src/config/weapons:
##
##   godot --headless --script tools/check_weapons.gd
##
## Exits non-zero when a weapon is malformed, so it can gate CI.
##
## The routing report at the end is the useful part when tuning. A weapon that
## passes every check can still be unreachable — offered by no enemy, no prop, no
## chest and no shop — and a config file that is never referenced looks exactly
## like one that is. See docs/WEAPONS.md.

const WEAPON_DIR := "res://src/config/weapons"
const CONFIG_DIR := "res://src/config/drops"

const ROLLS := 100_000
const SAMPLE_SEED := 20260726

## How far off centre a fan is allowed to be before it counts as lopsided, in
## radians. Floating point noise, not a tuning allowance.
const FAN_TOLERANCE := 0.0001


func _initialize() -> void:
	var failures: Array[String] = []

	var weapons := _load_all(WEAPON_DIR)
	if weapons.is_empty():
		failures.append("no weapons found in %s" % WEAPON_DIR)

	for path in weapons:
		var weapon := weapons[path] as WeaponDef
		if weapon == null:
			failures.append("%s did not load as a WeaponDef" % path)
			continue
		failures.append_array(_check_weapon(weapon, path))

	failures.append_array(_check_ids(weapons))
	failures.append_array(_check_spread(weapons))
	failures.append_array(_check_starting_weapon())
	failures.append_array(_check_lifecycle())

	var configs := _load_all(CONFIG_DIR)
	_report_routing(weapons, configs)

	if failures.is_empty():
		print("")
		print("OK — %d weapons, every check held" % weapons.size())
		quit(0)
		return

	print("")
	print("FAILED — %d problems" % failures.size())
	for failure in failures:
		print("  " + failure)
	quit(1)


## Every .tres in a directory, keyed by path. Derived rather than listed, so a
## weapon added to the folder is checked without anyone remembering to name it.
func _load_all(dir: String) -> Dictionary:
	var loaded := {}
	if not DirAccess.dir_exists_absolute(dir):
		return loaded
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		var path := "%s/%s" % [dir, file]
		loaded[path] = load(path)
	return loaded


func _check_weapon(weapon: WeaponDef, path: String) -> Array[String]:
	var errors: Array[String] = []
	var tag := path.get_file()

	if weapon.id.is_empty():
		errors.append("%s has no id" % tag)
	if weapon.icon == null:
		errors.append("%s has no icon — its pickup would be invisible" % tag)
	if weapon.held_texture == null:
		errors.append("%s has no held_texture — holding it would empty the player's hands" % tag)
	if weapon.projectile_scene == null:
		errors.append("%s has no projectile_scene — pulling the trigger would do nothing" % tag)
	if weapon.magazine_size < 1:
		errors.append("%s holds %d rounds — it could never fire"
				% [tag, weapon.magazine_size])
	if weapon.reload_time < 0.0:
		errors.append("%s has a negative reload_time" % tag)
	if weapon.projectiles_per_shot < 1:
		errors.append("%s fires %d projectiles per shot"
				% [tag, weapon.projectiles_per_shot])
	if weapon.equip_seconds < 0.0:
		errors.append("%s has a negative equip_seconds — use 0 for permanent" % tag)
	if weapon.spread_degrees < 0.0:
		errors.append("%s has a negative spread_degrees — width is not a direction" % tag)
	if weapon.projectile_speed <= 0.0:
		errors.append("%s fires at %.1f px/s — the shot would never leave the muzzle"
				% [tag, weapon.projectile_speed])
	if weapon.fire_pitch_min > weapon.fire_pitch_max:
		errors.append("%s has fire_pitch_min above fire_pitch_max" % tag)

	# Only checked for a weapon that sets its own numbers: one that scales with
	# the player reads both off the player and its own are ignored.
	if not weapon.scales_with_player_stats:
		if weapon.fire_interval <= 0.0:
			errors.append("%s has a fire_interval of %.3f — it would fire every frame"
					% [tag, weapon.fire_interval])
		if weapon.damage <= 0:
			errors.append("%s deals %d damage per projectile" % [tag, weapon.damage])

	return errors


func _check_ids(weapons: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var seen: Array[StringName] = []
	for path in weapons:
		var weapon := weapons[path] as WeaponDef
		if weapon == null or weapon.id.is_empty():
			continue
		# Ids are what save data and shop stock key on, so a duplicate surfaces
		# months later as the wrong weapon being handed over.
		if seen.has(weapon.id):
			errors.append("%s reuses the id '%s'" % [path.get_file(), weapon.id])
		else:
			seen.append(weapon.id)
	return errors


## Exactly one weapon should be permanent, and it should be the one the player
## starts with — a second one would be a pickup that never hands itself back.
func _check_starting_weapon() -> Array[String]:
	var errors: Array[String] = []
	var scene := load("res://src/entities/player/player.tscn") as PackedScene
	if scene == null:
		return ["player.tscn did not load — cannot tell what the run starts with"]

	var state := scene.get_state()
	var starting: WeaponDef = null
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"starting_weapon":
				starting = state.get_node_property_value(i, p) as WeaponDef

	if starting == null:
		errors.append("player.tscn has no Loadout.starting_weapon — the run would begin unarmed")
	elif not starting.is_permanent():
		errors.append("the starting weapon '%s' expires after %.0fs — it would time out into itself"
				% [starting.id, starting.equip_seconds])
	return errors


## Drive a real [Loadout] through the whole weapon lifecycle.
##
## This is the play-test that would otherwise cost a run each time: equip, fire,
## run dry, reload, freeze, re-equip mid-window, and time out. All of it is a
## state machine over floats, so all of it can be settled here.
##
## Only possible because Loadout names no autoload — it reports what a shot
## sounded like rather than playing it, so nothing has to be started for it to
## run. See its shot_fired.
##
## The node is driven by hand rather than by the tree: a --script run never
## delivers a frame, so _ready never fires and _physics_process is never called.
## That is why the starting weapon is equipped explicitly below.
func _check_lifecycle() -> Array[String]:
	var errors: Array[String] = []

	var pistol := load("res://src/config/weapons/pistol.tres") as WeaponDef
	var shotgun := load("res://src/config/weapons/shotgun.tres") as WeaponDef
	var timmy := load("res://src/config/weapons/timmy_gun.tres") as WeaponDef
	if pistol == null or shotgun == null or timmy == null:
		return ["could not load the shipped weapons — the lifecycle went unchecked"]

	# A --script run has no scene tree at all — root is not attached, so no node
	# added here is ever "in the tree" and _ready never fires. Hence the explicit
	# equip below, the hand-called _physics_process, and somewhere of our own for
	# the projectiles to land.
	var stage := Node.new()
	var loadout := Loadout.new()
	loadout.starting_weapon = pistol
	loadout.projectile_parent = stage
	stage.add_child(loadout)

	# --- equipping ----------------------------------------------------------
	loadout.equip(pistol)
	if loadout.ammo != pistol.magazine_size:
		errors.append("equipping the pistol gave %d rounds, expected %d"
				% [loadout.ammo, pistol.magazine_size])
	if not is_equal_approx(loadout.equip_time().y, 0.0):
		errors.append("the permanent pistol reports a countdown of %.1fs"
				% loadout.equip_time().y)

	# --- the trigger, both ways ---------------------------------------------
	if not loadout.should_fire(true, true):
		errors.append("the pistol refused a fresh trigger pull")
	if loadout.should_fire(true, false):
		errors.append("the semi-automatic pistol fired on a merely HELD trigger")

	loadout.equip(timmy)
	if not loadout.should_fire(true, false):
		errors.append("the automatic timmy gun refused a HELD trigger")
	if loadout.should_fire(false, false):
		errors.append("the timmy gun fired with the trigger released")

	# --- one round per PULL, however many projectiles leave ------------------
	loadout.equip(shotgun)
	loadout.fire(Vector2.ZERO, Vector2.RIGHT)
	if loadout.ammo != shotgun.magazine_size - 1:
		errors.append("a %d-pellet blast spent %d rounds, expected 1"
				% [shotgun.projectiles_per_shot, shotgun.magazine_size - loadout.ammo])

	# --- the cooldown gates the next shot ------------------------------------
	if loadout.should_fire(true, true):
		errors.append("fired again with no cooldown elapsed at all")
	loadout._physics_process(shotgun.fire_interval + 0.001)
	if not loadout.should_fire(true, true):
		errors.append("the cooldown never expired")

	# --- an empty magazine reloads itself and comes back full ----------------
	loadout.equip(shotgun)
	for i in shotgun.magazine_size:
		loadout.fire(Vector2.ZERO, Vector2.RIGHT)
	if not loadout.is_reloading:
		errors.append("running the magazine dry did not start a reload")
	if loadout.should_fire(true, true):
		errors.append("fired during a reload")
	loadout._physics_process(shotgun.reload_time + 0.001)
	if loadout.is_reloading:
		errors.append("the reload never finished")
	if loadout.ammo != shotgun.magazine_size:
		errors.append("the reload left %d rounds, expected %d"
				% [loadout.ammo, shotgun.magazine_size])

	# --- suspending freezes every clock, including the window ----------------
	loadout.equip(shotgun)
	var before: float = loadout.equip_time().x
	loadout.set_suspended(true)
	loadout._physics_process(5.0)
	if not is_equal_approx(loadout.equip_time().x, before):
		errors.append("the equip countdown ran while suspended: %.1f -> %.1f"
				% [before, loadout.equip_time().x])
	loadout.set_suspended(false)
	loadout._physics_process(5.0)
	if loadout.equip_time().x >= before:
		errors.append("the equip countdown never resumed")

	# --- a second pickup supersedes rather than being cut short by the first --
	loadout.equip(shotgun)
	loadout._physics_process(shotgun.equip_seconds * 0.5)
	loadout.equip(timmy)
	if not is_equal_approx(loadout.equip_time().x, timmy.equip_seconds):
		errors.append("re-equipping did not restart the clock: %.1fs left of %.1f"
				% [loadout.equip_time().x, timmy.equip_seconds])
	loadout._physics_process(shotgun.equip_seconds * 0.5 + 0.1)
	if loadout.weapon != timmy:
		errors.append("the FIRST weapon's timer ended the second window early")

	# --- expiry hands back the STARTING weapon, not the previous pickup ------
	loadout.equip(shotgun)
	loadout.equip(timmy)
	loadout._physics_process(timmy.equip_seconds + 0.1)
	if loadout.weapon != pistol:
		errors.append("expiry left '%s' equipped, expected the starting weapon"
				% loadout.weapon.id)
	if loadout.ammo != pistol.magazine_size:
		errors.append("the starting weapon came back with %d rounds" % loadout.ammo)

	# --- and a permanent weapon never expires --------------------------------
	loadout._physics_process(600.0)
	if loadout.weapon != pistol:
		errors.append("the permanent starting weapon timed out")

	# --- granting is the same path a drop, a chest and a shop all take -------
	var target := Loadout.new()
	target.starting_weapon = pistol
	target.projectile_parent = stage
	stage.add_child(target)
	target.equip(pistol)
	var holder := _WeaponHolder.new()
	holder.loadout = target
	shotgun.grant_to(holder)
	if target.weapon != shotgun:
		errors.append("WeaponDef.grant_to did not reach equip_weapon")

	# Freed rather than queue_free'd: there is no frame coming to collect it.
	holder.free()
	stage.free()
	return errors


## The smallest thing a [WeaponDef] can be granted to: something with an
## equip_weapon. Proves grant_to duck-types its target rather than naming the
## player, which is what lets a shop purchase and a pickup share one path.
class _WeaponHolder extends Node:
	var loadout: Loadout

	func equip_weapon(weapon: WeaponDef) -> void:
		loadout.equip(weapon)


## The spread maths, proved rather than eyeballed.
##
## Every projectile leaves as a unit vector, the right number leave, none leaves
## further from the aim than half the spread, and an even fan is symmetric about
## the aim rather than hanging off one side of it — the off-by-one that turns a
## shotgun into a gun that shoots slightly to the right.
func _check_spread(weapons: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = SAMPLE_SEED
	var aim := Vector2.RIGHT

	for path in weapons:
		var weapon := weapons[path] as WeaponDef
		if weapon == null:
			continue
		var tag: String = path.get_file()
		var directions := weapon.shot_directions(aim, rng)
		var half_spread := deg_to_rad(weapon.spread_degrees) * 0.5

		if directions.size() != maxi(1, weapon.projectiles_per_shot):
			errors.append("%s: asked for %d projectiles, got %d"
					% [tag, weapon.projectiles_per_shot, directions.size()])
			continue

		var angle_sum := 0.0
		for direction in directions:
			if not is_equal_approx(direction.length(), 1.0):
				errors.append("%s: a shot direction is not a unit vector (length %.4f)"
						% [tag, direction.length()])
			var offset: float = absf(aim.angle_to(direction))
			if offset > half_spread + FAN_TOLERANCE:
				errors.append("%s: a projectile leaves %.2f° off aim, outside the %.1f° spread"
						% [tag, rad_to_deg(offset), weapon.spread_degrees])
			angle_sum += aim.angle_to(direction)

		if weapon.spread_mode == WeaponDef.SpreadMode.EVEN_FAN \
				and absf(angle_sum) > FAN_TOLERANCE:
			errors.append("%s: the fan is lopsided — it averages %.3f° off the aim"
					% [tag, rad_to_deg(angle_sum / directions.size())])

	return errors


## Where each weapon can actually be found, across every drop config.
##
## Not a check, because "offered nowhere" is a legitimate thing for a weapon to
## be — a gun parked in the folder while it is tuned, or one deliberately held
## back. It is only worth saying out loud, because an unreferenced config file
## looks exactly like a referenced one.
func _report_routing(weapons: Dictionary, configs: Dictionary) -> void:
	for path in configs:
		var config := configs[path] as DropConfig
		if config == null:
			continue

		print("")
		print("%s — where weapons come from" % path.get_file())

		for weapon_path in weapons:
			var weapon := weapons[weapon_path] as WeaponDef
			if weapon == null:
				continue
			var routes := _routes_to(weapon, config)
			if not routes.is_empty():
				print("  %-12s %s" % [weapon.id, ", ".join(routes)])
			elif weapon.is_permanent():
				# The starting weapon is carried, not found. Reported so it is not
				# missing from the list, but not as a problem.
				print("  %-12s carried from the start" % weapon.id)
			else:
				print("  %-12s NOWHERE — offered by no source" % weapon.id)


## Every way a weapon reaches the player under one config, as readable phrases.
##
## Rolled rather than derived from the weights, so what is reported is what the
## same LootRoller the game uses actually produces — a rule that resolves to
## nothing, or a row shadowed by a more specific rule, shows up here as an absent
## route rather than as a weight that looked fine.
func _routes_to(weapon: WeaponDef, config: DropConfig) -> Array[String]:
	var routes: Array[String] = []

	for source in config.sources():
		var seen_floors: Array[int] = []
		var priced := 0
		var hits := 0

		for floor_number in FloorLadder.FLOOR_COUNT:
			var tables := config.tables_for(source, floor_number)
			if tables.is_empty():
				continue

			# A shelf offers every row at once rather than sampling, so a price is
			# the whole story and rolling it would say nothing.
			var price := _price_of(weapon, tables)
			if price > 0:
				priced = price
				seen_floors.append(floor_number)
				continue

			var rng := RandomNumberGenerator.new()
			rng.seed = SAMPLE_SEED + floor_number
			var count := 0
			for i in ROLLS:
				for item in LootRoller.roll(tables, rng):
					if item == weapon:
						count += 1
			if count > 0:
				hits = maxi(hits, count)
				seen_floors.append(floor_number)

		if seen_floors.is_empty():
			continue
		var floors := "" if seen_floors.size() == FloorLadder.FLOOR_COUNT \
				else " on floors %s" % str(seen_floors)
		if priced > 0:
			routes.append("%s @ %d coins%s" % [source, priced, floors])
		else:
			routes.append("%s %.1f%%%s" % [source, 100.0 * hits / float(ROLLS), floors])

	return routes


## What a source charges for a weapon, or zero where it is free.
func _price_of(weapon: WeaponDef, tables: Array[DropTable]) -> int:
	for table in tables:
		for entry in table.entries:
			if entry != null and entry.item == weapon and entry.price > 0:
				return entry.price
	return 0
