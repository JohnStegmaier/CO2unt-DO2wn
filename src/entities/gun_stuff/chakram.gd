class_name Chakram
extends Projectile

## A spinning blade that carries on through whatever it hits.
##
## The counterpart to [Bullet], and the reason [Projectile] exists: everything
## about firing one is identical — the same arm(), the same weapon config, the
## same Loadout — and only what happens on contact differs. Adding it needed no
## change to the code that fires weapons, which is the whole test of that split.
##
## Slower and heavier than a bullet by design. It travels far enough to be worth
## lining a corridor up with, and a room packed with enemies is where it pays.


## Everything already cut, so passing along a body does not saw it repeatedly on
## every physics frame the shapes happen to overlap.
##
## Keyed by instance id rather than holding the nodes themselves: a chakram
## outlives the enemies it kills, and a list of freed references is a crash
## waiting for the next overlap to check it.
var _already_hit: Dictionary = {}


func _on_armed() -> void:
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)
	$AnimatedSprite2D.play("spin")


func _on_body_entered(body: Node2D) -> void:
	if _passes_through(body):
		return

	var id := body.get_instance_id()
	if _already_hit.has(id):
		return
	_already_hit[id] = true

	# Piercing means piercing things that can BLEED. Anything that cannot take
	# damage is scenery — a wall — and a blade that sails through a wall and off
	# into the void reads as one that went nowhere. This is what stops it, and it
	# is why _damage reports whether it landed rather than returning nothing.
	if not _damage(body):
		queue_free()
