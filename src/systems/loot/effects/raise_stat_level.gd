class_name RaiseStatLevel
extends ItemEffect

## Bumps one of the player's four stat levels.
##
## The levels themselves, the seven-entry value tables behind them and the clamp
## at either end all live on player.gd. This only says which one and by how much,
## which is why it reads the current level back off the player rather than
## carrying a target: two speed pickups in a row have to stack, and an item that
## named an absolute level would make the second one a no-op or a downgrade.
##
## Declared as an enum for readable call sites but exported and passed as a plain
## int, for the reason in grid_direction.gd.
enum Stat { POWER, SPEED, FIRERATE, RELOAD }

@export_enum("power", "speed", "firerate", "reload") var stat: int = 0
## Levels gained. Negative is legal and is how a penalty item would be written.
@export var steps: int = 1

## Parallel to Stat, so the setter and the level to read are looked up by the
## same index rather than by two match statements that could disagree.
const _SETTERS: Array[StringName] = [
	&"set_power_level", &"set_speed_lvl", &"set_firerate_lvl", &"set_reload_speed_lvl",
]
const _LEVELS: Array[StringName] = [
	&"POWER_LVL", &"SPEED_LVL", &"FIRERATE_LVL", &"RELOAD_SPEED_LVL",
]
const _NAMES: Array[String] = ["power", "speed", "fire rate", "reload speed"]


func apply(target: Node) -> void:
	var setter: StringName = _SETTERS[stat]
	if not target.has_method(setter):
		# Loud, unlike grant_bomb's identical guard. A bomb that fails to land is
		# a counter that did not move; this is a permanent upgrade, and
		# item_pickup.gd frees the pickup and plays the collection jingle whether
		# or not anything happened — so a silent return here is indistinguishable
		# in play from a stat that levelled. That is the whole reason this was
		# hard to pin down.
		push_warning("RaiseStatLevel: %s has no %s — %s went nowhere."
				% [target.name, setter, describe()])
		return
	# The setter clamps to MIN_STAT_LVL/MAX_STAT_LVL and emits its own changed
	# signal, so a pickup at max level is wasted rather than an error — the same
	# bargain gain_bomb makes.
	target.call(setter, int(target.get(_LEVELS[stat])) + steps)


func describe() -> String:
	return "%+d %s" % [steps, _NAMES[stat]]
