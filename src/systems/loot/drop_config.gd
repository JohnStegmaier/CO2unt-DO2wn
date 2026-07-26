class_name DropConfig
extends Resource

## The whole economy of a run: who drops what, where, and how often.
##
## A Resource rather than constants scattered across the enemy and the rooms so
## that a run's economy is an inspector slot you can swap and tune while the game
## runs — the same bargain [FloorConfig] makes for a run's shape. Pure data: it
## holds no RNG and makes no decisions, so reading it cannot change what drops.
##
## Swapping this file swaps the entire design. The three candidate economies in
## docs/DROPS.md differ almost entirely in which source offers each item, not in
## what the items do, so each is one of these over the same item catalogue.

## Ordered only for readability; resolution is by specificity, not by position.
@export var rules: Array[DropRule] = []


## What the given source drops on the given floor.
##
## Most specific wins: a rule naming this floor beats a rule naming none, and a
## source with no rule at all drops nothing. Deliberately not a merge of the two
## — "floor 3 grunts drop what all grunts drop, plus this" reads well right up
## until you want floor 3 to drop *less*, and a rule you cannot subtract from is
## worse than one you have to write out.
func tables_for(source: StringName, floor_number: int) -> Array[DropTable]:
	var fallback: Array[DropTable] = []
	for rule in rules:
		if rule == null or not rule.matches(source, floor_number):
			continue
		if rule.is_specific():
			return rule.tables
		fallback = rule.tables
	return fallback


## Every source this config has an opinion about. Used by check_drops.gd to dump
## rates without being told what to look for, so a source added to a .tres shows
## up in the report without anyone remembering to list it.
func sources() -> Array[StringName]:
	var seen: Array[StringName] = []
	for rule in rules:
		if rule != null and not seen.has(rule.source):
			seen.append(rule.source)
	return seen
