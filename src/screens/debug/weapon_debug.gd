extends Node2D

## Fire every weapon at a real enemy and print what actually landed.
##
## The question this exists to answer is "is this weapon damaging anything at
## all", which is the one question tools/check_weapons.gd cannot: hits are a
## physics event, and a --script run has no scene tree to run physics in. So this
## is a scene, F6-runnable, and everything in it is the real thing — the real
## enemy scene configured with a real EnemyDef, the real Loadout, the real
## projectiles — because a probe against a stand-in proves nothing about the
## layers and masks that are the usual reason a shot passes through.
##
##     godot --headless src/screens/debug/weapon_debug.tscn
##
## Prints and exits. Deliberately NOT a check with a pass/fail: what a weapon
## should hit for is a tuning decision, and the useful output is the comparison
## between the rows. A weapon on 0 is the bug worth chasing.
##
## Same spirit as shop_debug.gd — the smallest thing that puts a real subsystem
## on screen without a full run.

## Far enough that spread and travel time matter, close enough to be a shot you
## would actually take. A shotgun landing every pellet here would mean the fan
## was doing nothing.
const RANGE_PX := 200.0
## Long enough for the slowest projectile to cross RANGE_PX with room to spare.
const SETTLE_SECONDS := 1.5
## Big enough that nothing dies mid-probe and stops taking hits.
const DUMMY_HP := 1_000_000

const WEAPON_DIR := "res://src/config/weapons"
const TARGET_DEF := "res://src/config/enemies/defs/guard.tres"

var _target: CharacterBody2D
var _health: Health


func _ready() -> void:
	_target = preload("res://src/entities/enemy/enemy.tscn").instantiate()
	_target.configure(load(TARGET_DEF))
	add_child(_target)
	_target.global_position = Vector2(RANGE_PX, 0.0)

	_health = _target.get_node("Health")
	_health.max_hp = DUMMY_HP
	_health.hp = DUMMY_HP

	_probe.call_deferred()


func _probe() -> void:
	var rows: Array[String] = []

	for file in DirAccess.get_files_at(WEAPON_DIR):
		if not file.ends_with(".tres"):
			continue
		var weapon := load("%s/%s" % [WEAPON_DIR, file]) as WeaponDef
		if weapon == null:
			continue

		var loadout := Loadout.new()
		loadout.starting_weapon = weapon
		# Ours rather than the running scene, so the probe cleans up after itself.
		loadout.projectile_parent = self
		add_child(loadout)
		loadout.equip(weapon)

		var before := _health.hp
		loadout.fire(Vector2.ZERO, Vector2.RIGHT)
		await get_tree().create_timer(SETTLE_SECONDS).timeout

		rows.append("  %-12s %4d damage from one trigger pull at %dpx"
				% [weapon.id, before - _health.hp, int(RANGE_PX)])
		loadout.queue_free()

	print("")
	print("=== one pull at a %s, %dpx away ===" % [TARGET_DEF.get_file().get_basename(), RANGE_PX])
	for row in rows:
		print(row)
	print("")
	print("A weapon on 0 never reached the target — check its collision mask and")
	print("that its projectile_scene root implements Projectile.arm().")
	get_tree().quit(0)
