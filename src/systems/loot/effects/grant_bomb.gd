class_name GrantBomb
extends ItemEffect

## Hands over one pulse bomb.
##
## The bomb itself — throwing it, the shockwave, the cap on how many you carry —
## belongs to player.gd and is none of this file's business. All this knows is
## the method to call, which is the same thing the deleted bomb_pickup.gd knew.
##
## Worth reading as the worked example in docs/DROPS.md: an item whose mechanic
## already exists somewhere else becomes a drop by writing this much and nothing
## more.


func apply(target: Node) -> void:
	if not target.has_method("gain_bomb"):
		return
	# No clamping here. gain_bomb already refuses to go past max_f_bombs, and
	# duplicating that rule is how the two drift apart.
	target.gain_bomb()


func describe() -> String:
	return "+1 bomb"
