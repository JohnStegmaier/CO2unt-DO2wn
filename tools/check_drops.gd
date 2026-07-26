extends SceneTree

## Validate every drop config, then roll them a great many times and print what
## actually comes out.
##
## The loot path is deliberately pure logic — [LootRoller] owns no RNG and
## [DropConfig] makes no decisions — so what a table produces can be settled in a
## terminal instead of by killing things until something drops. Run it after
## editing anything under src/config/:
##
##   godot --headless --script tools/check_drops.gd
##
## Exits non-zero when a config is malformed, so it can gate CI. The rate table
## it prints is the useful part when tuning: a config that passes every check can
## still be miserly, and the only way to see that otherwise is to play.

const CONFIG_DIR := "res://src/config/drops"
const ITEM_DIR := "res://src/config/items"

const ROLLS := 100_000
const SAMPLE_SEED := 20260726

## The economy PR #49 shipped, which src/config/drops/default.tres is a port of
## rather than a re-tune. Asserted so the port stays honest as the file is
## edited — change these when you mean to change the game.
const DEFAULT_RATES := {
	"oxygen_small": 0.30,
	"bomb": 0.30,
}
## Percentage points of slack on the above. Generous enough that 100k samples
## never flake, tight enough to catch a fat-fingered weight.
const RATE_TOLERANCE := 0.01


func _initialize() -> void:
	var failures: Array[String] = []

	var items := _load_all(ITEM_DIR)
	failures.append_array(_check_items(items))

	var configs := _load_all(CONFIG_DIR)
	if configs.is_empty():
		failures.append("no drop configs found in %s" % CONFIG_DIR)

	for path in configs:
		var config := configs[path] as DropConfig
		if config == null:
			failures.append("%s did not load as a DropConfig" % path)
			continue
		failures.append_array(_check_config(config, path))

	failures.append_array(_check_coins())

	print("")
	for path in configs:
		if configs[path] is DropConfig:
			failures.append_array(_report_rates(configs[path], path))

	if failures.is_empty():
		print("")
		print("OK — %d items, %d configs, every check held" % [items.size(), configs.size()])
		quit(0)
		return

	print("")
	print("FAILED — %d problems" % failures.size())
	for failure in failures:
		print("  " + failure)
	quit(1)


## Every .tres in a directory, keyed by path. Derived rather than listed, so an
## item added to the folder is checked without anyone remembering to name it.
func _load_all(dir: String) -> Dictionary:
	var loaded := {}
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		var path := "%s/%s" % [dir, file]
		loaded[path] = load(path)
	return loaded


func _check_items(items: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var ids: Array[StringName] = []

	for path in items:
		var item := items[path] as ItemDef
		if item == null:
			errors.append("%s did not load as an ItemDef" % path)
			continue
		if item.id.is_empty():
			errors.append("%s has no id" % path)
		elif ids.has(item.id):
			# Ids are what save data and shop stock will key on, so a duplicate is
			# a bug that surfaces months later as the wrong item being granted.
			errors.append("%s reuses the id '%s'" % [path, item.id])
		else:
			ids.append(item.id)
		if item.icon == null:
			errors.append("%s has no icon — it would be an invisible pickup" % path)
		if item.effects.is_empty():
			errors.append("%s has no effects — picking it up would do nothing" % path)
		for effect in item.effects:
			if effect == null:
				errors.append("%s has an empty effect slot" % path)
	return errors


func _check_config(config: DropConfig, path: String) -> Array[String]:
	var errors: Array[String] = []

	if config.rules.is_empty():
		errors.append("%s has no rules — nothing would ever drop" % path)

	for rule in config.rules:
		if rule == null:
			errors.append("%s has an empty rule slot" % path)
			continue
		var tag := "%s / %s" % [path.get_file(), rule.source]
		if rule.source.is_empty():
			errors.append("%s: a rule has no source" % path)
		if rule.tables.is_empty():
			errors.append("%s: no tables, so the rule does nothing" % tag)
		for floor_number in rule.floors:
			if floor_number < 0 or floor_number > FloorLadder.BASEMENT_INDEX:
				errors.append("%s: floor %d is outside the run (0..%d)"
						% [tag, floor_number, FloorLadder.BASEMENT_INDEX])
		errors.append_array(_check_tables(rule.tables, tag))

	# Every source has to resolve on every floor, or an enemy on some floor is
	# silently worthless. Cheap to prove exhaustively — there are six floors.
	for source in config.sources():
		for floor_number in FloorLadder.FLOOR_COUNT:
			if config.tables_for(source, floor_number).is_empty():
				errors.append("%s: '%s' resolves to nothing on floor %d"
						% [path.get_file(), source, floor_number])
	return errors


func _check_tables(tables: Array[DropTable], tag: String) -> Array[String]:
	var errors: Array[String] = []
	for table in tables:
		if table == null:
			errors.append("%s: an empty table slot" % tag)
			continue
		if table.rolls < 1:
			errors.append("%s: a table rolls %d times" % [tag, table.rolls])
		if table.entries.is_empty():
			errors.append("%s: an empty table" % tag)
		if is_zero_approx(table.total_weight()):
			errors.append("%s: a table whose weights sum to zero" % tag)
		for entry in table.entries:
			if entry == null:
				errors.append("%s: an empty entry slot" % tag)
				continue
			if entry.weight < 0.0:
				errors.append("%s: negative weight %f" % [tag, entry.weight])
			if entry.count_min < 1:
				errors.append("%s: count_min %d" % [tag, entry.count_min])
			if entry.count_max < entry.count_min:
				errors.append("%s: count_max %d below count_min %d"
						% [tag, entry.count_max, entry.count_min])
	return errors


## Autoloads registered in project.godot are not started for a --script run, and
## player.gd names three of them, so it will not even compile without this. Stood
## up by hand and registered under the names the scripts expect.
##
## Deliberately not a general fixture: a check that needs the whole game running
## has stopped being a check. This is the smallest thing that lets one real node
## be instanced, and check_floors.gd needs none of it.
func _register_autoloads() -> void:
	const AUTOLOADS := {
		"GameConfig": "res://src/autoload/game_config.gd",
		"GlobalTimer": "res://src/autoload/global_timer.tscn",
		"AudioManager": "res://src/autoload/audio_manager.tscn",
		"NavigationManager": "res://src/autoload/navigation_manager.gd",
	}
	for singleton_name in AUTOLOADS:
		var resource := load(AUTOLOADS[singleton_name])
		# The scene, where there is one: the script alone is missing the child
		# nodes its @onready vars reach for.
		var node: Node = resource.instantiate() if resource is PackedScene else resource.new()
		node.name = singleton_name
		root.add_child(node)
		Engine.register_singleton(singleton_name, node)


## Exercise Player.coins directly. It ships on this branch with no caller — the
## shop is what will spend it — so without this the arithmetic would go unproven
## until another branch depended on it being right.
##
## Loaded rather than preloaded: player.gd cannot compile until the autoloads
## above exist, and a preload would try at parse time.
func _check_coins() -> Array[String]:
	var errors: Array[String] = []
	_register_autoloads()

	var scene := load("res://src/entities/player/player.tscn") as PackedScene
	if scene == null:
		errors.append("could not load player.tscn — coins went unchecked")
		return errors
	var player := scene.instantiate()
	root.add_child(player)

	var seen: Array[int] = []
	player.coins_changed.connect(func(value: int) -> void: seen.append(value))

	player.add_coins(10)
	if player.coins != 10:
		errors.append("add_coins(10) left %d coins" % player.coins)

	if player.spend_coins(25):
		errors.append("spend_coins(25) succeeded on a balance of 10")
	if player.coins != 10:
		errors.append("a refused purchase changed the balance to %d" % player.coins)

	if not player.spend_coins(4):
		errors.append("spend_coins(4) failed on a balance of 10")
	if player.coins != 6:
		errors.append("spend_coins(4) left %d coins, expected 6" % player.coins)

	# Twice, not three times: the refused purchase must say nothing.
	if seen.size() != 2:
		errors.append("coins_changed fired %d times, expected 2" % seen.size())

	player.queue_free()
	return errors


## Roll every source on every floor and print what came out, plus assert the
## shipped config still pays what it did before this system existed.
func _report_rates(config: DropConfig, path: String) -> Array[String]:
	var errors: Array[String] = []
	print("%s" % path)
	var rng := RandomNumberGenerator.new()

	for source in config.sources():
		for floor_number in FloorLadder.FLOOR_COUNT:
			var tables := config.tables_for(source, floor_number)
			# Only report a floor that differs from the one above it, or six
			# identical lines per source bury the one floor that was tuned.
			if floor_number > 0 and tables == config.tables_for(source, floor_number - 1):
				continue

			rng.seed = SAMPLE_SEED
			var counts := {}
			for i in ROLLS:
				for item in LootRoller.roll(tables, rng):
					counts[item.id] = counts.get(item.id, 0) + 1

			# Both numbers: the index is what a rule's `floors` array is written
			# in, the label is what the sign on the wall says. See FloorLadder.
			print("  %-12s index %d (%s)" % [source, floor_number,
					FloorLadder.long_label(floor_number)])
			if counts.is_empty():
				print("      nothing")
			for id in counts:
				print("      %-14s %6.2f per 100 kills" % [id, counts[id] / float(ROLLS) * 100.0])
			errors.append_array(_check_default_rates(path, source, counts))
	print("")
	return errors


## The shipped tables are a port of what enemy.gd rolled before this system
## existed, not a re-tune, and this is what keeps that claim true as the file
## gets edited. A deliberate change to the economy fails here once and is meant
## to: updating DEFAULT_RATES is how you say you meant it.
func _check_default_rates(path: String, source: StringName, counts: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if path.get_file() != "default.tres":
		return errors
	for id in DEFAULT_RATES:
		var rate: float = counts.get(id, 0) / float(ROLLS)
		if absf(rate - DEFAULT_RATES[id]) > RATE_TOLERANCE:
			errors.append("default.tres: '%s' from %s drops at %.3f, expected %.3f — retune or update DEFAULT_RATES"
					% [id, source, rate, DEFAULT_RATES[id]])
	return errors
