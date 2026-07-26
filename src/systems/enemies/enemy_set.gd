class_name EnemySet
extends Resource

## Which bad guys a run fields, and how often each.
##
## The inspector slot on game.gd, the same bargain [ObstacleSet] makes for a
## room's furniture, [FloorConfig] for a run's shape and [DropConfig] for its
## economy: swapping this file swaps the whole bestiary without touching a
## script. Pure data — it holds no RNG and spawns nothing, so reading it cannot
## change what a room stocks.
##
## This is what replaced a hardcoded scene preload and a single
## `randf() < skirmisher_chance` coin flip. Two archetypes could be a chance;
## four cannot, because a set of chances that has to sum to one is a thing you
## retype every time you add a row. Weights do not have that problem, which is
## why [member ObstacleDef.weight] and [member DropEntry.weight] are weights too.

## The bestiary. Order is for readability only; picking is by weight.
@export var defs: Array[EnemyDef] = []


## Does this set field anything at all? An empty or entirely zero-weighted set is
## a perfectly ordinary way to say "this run has no enemies" — peaceful.cfg gets
## there by asking for zero of them instead, but both must work, because a room
## that stocks nothing must not lock itself.
func is_empty() -> bool:
	return is_zero_approx(total_weight())


func total_weight() -> float:
	var total := 0.0
	for def in defs:
		if def != null:
			total += maxf(0.0, def.weight)
	return total


## Weighted pick over the bestiary, the same walk [method ObstacleSet.pick] and
## FloorGenerator._weighted_pick do.
##
## `boss_only` narrows the list to defs that may be promoted rather than running
## a second algorithm, so there is one picking rule to get right. Returns null
## when nothing qualifies — an empty set, or a boss room in a run whose bestiary
## is all turrets — and every caller has to handle that, because the alternative
## is a boss room that silently stocks a fixture and can never be cleared.
func pick(rng: RandomNumberGenerator, boss_only: bool = false) -> EnemyDef:
	var total := 0.0
	for def in defs:
		if def != null and (not boss_only or def.boss_eligible):
			total += maxf(0.0, def.weight)
	if is_zero_approx(total):
		return null

	var roll := rng.randf() * total
	var last: EnemyDef = null
	for def in defs:
		if def == null or (boss_only and not def.boss_eligible):
			continue
		last = def
		roll -= maxf(0.0, def.weight)
		if roll <= 0.0:
			return def
	# Only reachable on floating point crumbs at the very top of the range.
	return last


## The widest body this set can put in a room, already scaled for promotion. What
## the connectivity proof and [constant EnemyPlacement.MAX_AGENT_RADIUS] are both
## stated in terms of — see [member EnemyDef.body_radius].
func max_body_radius(boss_size_scale: float = 1.0) -> float:
	var widest := 0.0
	for def in defs:
		if def != null:
			widest = maxf(widest, def.widest_radius(boss_size_scale))
	return widest


## Can a boss room be stocked at all? A run where this is false cannot clear its
## boss gate, and on floor 1 that gate is the only way down — so this is a
## run-ending misconfiguration, not a quiet one, and tools/check_enemies.gd
## fails on it.
func has_boss_eligible() -> bool:
	for def in defs:
		if def != null and def.boss_eligible:
			return true
	return false


## By name, for tools/check_enemies.gd and for anything that later wants to place
## a specific enemy rather than roll for one. Null when there is no such row.
func by_id(id: StringName) -> EnemyDef:
	for def in defs:
		if def != null and def.id == id:
			return def
	return null


## How many of `picks` want a spot against a wall. Here rather than counted at
## the call site because game.gd has to divide the floor between fixtures and
## roamers before it places either, and that split is the one piece of arithmetic
## the two placement calls have to agree about.
static func fixture_count(picks: Array[EnemyDef]) -> int:
	var total := 0
	for def in picks:
		if def != null and def.is_fixture():
			total += 1
	return total


## Deliberately NO apply_overrides() here, unlike [FloorConfig].
##
## Reading GameConfig from a Resource makes that autoload a compile-time
## dependency of the Resource, and of everything that names its type. Nothing
## under systems/ can then be loaded by `godot --headless --script`, because that
## mode starts no autoloads — which is exactly why tools/check_floors.gd does not
## currently run, and exactly what tools/check_enemies.gd would lose.
##
## So the profile is folded in by game.gd, which is a Node and has the autoloads
## anyway. See _apply_enemy_overrides.
