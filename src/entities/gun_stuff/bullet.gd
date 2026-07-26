class_name Bullet
extends Projectile

## A shot that stops at the first thing it hits.
##
## The ordinary projectile — the pistol, the shotgun's pellets, the Timmy Gun's
## rattle, and every enemy's return fire all fly this scene. What differs between
## them is the numbers [method Projectile.arm] hands it, which is why there is
## one bullet scene and not six.
##
## Also frees itself the moment it leaves the screen, on top of the base class's
## lifetime net: a bullet that missed is off-camera long before it is stale, and
## a room's worth of them adds up.


func _on_armed() -> void:
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)


func _on_body_entered(body: Node2D) -> void:
	# A dodging player is passed through rather than hit — see
	# Player.is_intangible.
	if _passes_through(body):
		return
	_damage(body)
	# Spent whether or not the thing it hit could take damage: a bullet stops at
	# a wall too.
	queue_free()
