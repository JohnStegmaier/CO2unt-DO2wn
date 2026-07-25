class_name Health
extends Node

## Hit points for anything that can be killed.
##
## The player deliberately does NOT have one of these — their O2 countdown is
## their health bar, so damage aimed at them is routed to the HUD instead. See
## Player.take_damage.
##
## Note the host must forward damage to us from its own CharacterBody2D, not
## from an Area2D hurtbox: bullet.gd connects body_entered and not area_entered,
## so a hurtbox would instance perfectly and silently never register a hit.
##
## Damage type is carried through untouched. Nothing here resists or amplifies a
## type yet, but the signal exposes it so armour can arrive without changing a
## single call site.

signal damaged(amount: int, type: int)
signal died

@export var max_hp: int = 30

var hp: int


func _ready() -> void:
	hp = max_hp


func take_damage(amount: int, type: int = Damage.Type.BLUNT) -> void:
	# Two bullets landing on the same physics frame would otherwise emit died
	# twice, and the host would queue_free() twice.
	if hp <= 0:
		return

	hp = maxi(hp - amount, 0)
	damaged.emit(amount, type)
	if hp == 0:
		died.emit()


func is_alive() -> bool:
	return hp > 0
