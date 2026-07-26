class_name RestoreOxygen
extends ItemEffect

## Puts seconds back in the tank.
##
## The player holds no health — the O2 countdown is the health bar — so this is
## both the healing item and the food item. It calls heal(), which the player
## forwards to the timer; see player.gd.

@export var seconds: float = 15.0


func apply(target: Node) -> void:
	if not target.has_method("heal"):
		return
	target.heal(seconds)


func describe() -> String:
	return "+%.0fs air" % seconds
