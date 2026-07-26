class_name GrantTempShotgun
extends ItemEffect

## Swaps the player's gun for a shotgun for a fixed window, then swaps it back.
##
## The window itself — the magazine size, the reload, the texture, what
## happens if a second one is picked up mid-window — is all owned by
## Player.grant_temp_shotgun. This only says how long, the same split
## RestoreOxygen makes with heal() and its own `seconds`.

@export var duration: float = 15.0


func apply(target: Node) -> void:
	if not target.has_method("grant_temp_shotgun"):
		return
	target.grant_temp_shotgun(duration)


func describe() -> String:
	return "shotgun for %.0fs" % duration
