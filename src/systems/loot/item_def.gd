class_name ItemDef
extends Resource

## One thing that can be picked up, bought, or dropped.
##
## Pure data: what it is called, how it is drawn, and what it does to whoever
## takes it. It says nothing about where it comes from or what it is worth —
## a [DropTable] decides the first and the shop decides the second, so the same
## oxygen canister is a free drop on floor 5 and a priced offer in a shop
## without existing twice.
##
## This is the whole reason there is no oxygen_pickup.tscn and no
## bomb_pickup.tscn any more: an item is a .tres, not a scene. Adding one is
## filling in this form. See docs/DROPS.md.

## Stable identity, used by save data, by shop stock and by the checker's
## uniqueness assertion. Not shown to the player — display_name is.
@export var id: StringName

@export var display_name: String = ""

@export_group("Appearance")
## Drawn on top. Every item has one.
@export var icon: Texture2D
## Sprites in this project are authored much larger than they are drawn, so the
## scale is part of how an item looks rather than a fudge factor — the orb sits
## at 0.265 and the bomb icon at 0.3.
@export var icon_scale: float = 1.0
## Drawn behind the icon, usually the Drop_orb glow. Left empty for items whose
## icon is already a complete picture, which is why this is nullable rather than
## a bool plus a texture.
@export var backdrop: Texture2D
@export var backdrop_scale: float = 0.265

@export_group("")

## Bare file name under assets/audio/sfx/, the way AudioManager.play_sfx wants
## it. Data rather than a call in item_pickup.gd so that "what noise does a coin
## make" is tuned in the same inspector as everything else about the coin, and
## an item that should be silent is one that left this empty.
##
## [member pickup_sound] is the player collecting it; [member drop_sound] is it
## hitting the floor. Two separate moments, so two separate fields — a coin
## announces itself on landing and again when you take it.
@export var pickup_sound: StringName
@export var drop_sound: StringName

## Applied in order on pickup. More than one is normal — see [ItemEffect].
@export var effects: Array[ItemEffect] = []


## Hand this item to whoever just walked into it.
##
## Lives here rather than in item_pickup.gd so that the shop, which has no
## pickup scene at all, grants an item by exactly the same path a drop does.
func grant_to(target: Node) -> void:
	for effect in effects:
		if effect == null:
			push_warning("ItemDef '%s' has an empty effect slot." % id)
			continue
		effect.apply(target)


## One line for the checker's dump and for error messages. An item with no
## effects is legal here and rejected by check_drops.gd, so this has to be able
## to describe one.
func describe() -> String:
	if effects.is_empty():
		return "%s (does nothing)" % id
	var parts := PackedStringArray()
	for effect in effects:
		parts.append(effect.describe() if effect != null else "<empty>")
	return "%s (%s)" % [id, ", ".join(parts)]
