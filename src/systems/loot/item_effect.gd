class_name ItemEffect
extends Resource

## One thing an item does to whoever picked it up.
##
## The base of a small family — see src/systems/loot/effects/. An [ItemDef] holds
## an array of these rather than a single kind, so an item that does two things
## ("move speed up AND oxygen drain up") is two effects in a row rather than a
## special case in whatever applies them.
##
## That array is also what keeps this open to new items without reopening old
## code: a weapon, a temporary buff or a shield is a new script beside this one
## and a new .tres, and nothing that already works has to be edited to make room.
##
## Effects duck-type their target the way bullet.gd duck-types take_damage — the
## argument is a Node and the effect calls a method it hopes is there. No effect
## names Player, so none of this depends on the player scene.


## Do the thing. Overridden by every subclass; the base is deliberately loud
## rather than silently doing nothing, because an effect that applies to nobody
## is a .tres someone forgot to finish.
func apply(_target: Node) -> void:
	push_warning("ItemEffect: %s has no apply() of its own." % resource_path)


## What this reads like in the drop-rate table check_drops.gd prints. Overridden
## so a config dump says "15s oxygen" rather than the class name eight times.
func describe() -> String:
	return get_script().resource_path.get_file().get_basename()
