class_name AttackTell
extends Node2D

## A ring closing on the spot an attack is about to arrive from.
##
## The whole point is the shrinking, not the colour. A tell that only brightens
## says "something is happening"; one whose radius runs out says WHEN, and timing
## is the only thing the player actually needs — every attack in the game is
## dodged by moving at the right moment rather than by moving somewhere in
## particular. The ring landing on the core is the frame the shot leaves.
##
## Drawn rather than authored, the same bargain [ReloadIndicator] makes and for
## the same reason: a wind-up frame would need art for every enemy times every
## bearing, which for a sixteen-way turret alone is sixteen drawings that do not
## exist. What this costs instead is one node and no assets.
##
## Sized in the parent's units on purpose. It hangs off the enemy's
## AnimatedSprite2D rather than the body, so [member EnemyDef.sprite_scale] and
## [method Enemy.make_boss] — which multiplies that same scale — both reach it
## without this file knowing either exists. A boss gets a bigger ring for free,
## and there is no pixel constant here that could disagree with the art.
##
## Knows nothing about guns, phases or archetypes: it is handed a number and a
## direction. What is winding up, and whether it is a bullet or a body, is
## [method Enemy._show_attack_tell]'s problem.

## Where the ring starts and where it lands. The outer one is a little wider than
## the widest body so the ring reads as closing ON the enemy rather than as part
## of it, and the inner one is the dot left behind at the moment of the attack.
const OUTER_RADIUS := 11.0
const CORE_RADIUS := 2.0

## How far down the attack's direction the whole thing sits. Enough to say which
## way the shot is going without drifting off the body it belongs to.
const REACH := 9.0

## Hot red-orange, one shade off [constant ReloadIndicator.COLOR]. Deliberately
## the same family as the reload arc rather than a new hue — the palette already
## spends orange on "a timer is running", and this is one.
const DEFAULT_COLOR := Color(1.0, 0.27, 0.18)

## Matching the reload arc, which is the only other thing on screen drawn this
## way. Below about 1.0 the circle breaks up into dashes at this resolution.
const RING_WIDTH := 1.5
const RING_SEGMENTS := 20
## Never fully opaque. This is a hint, not a HUD element.
const RING_ALPHA := 0.85

## What the ring is drawn in, handed down by [method Enemy.configure] from
## [member EnemyDef.telegraph_color].
##
## A property rather than a constant, because a ring has to be legible against the
## body it is drawn on and the bestiary is not one palette — the licker is deep
## red, so the default on that one is a tell that is technically present and
## practically invisible. It is still ONE colour per enemy rather than one per
## kind of attack: what the ring means must not depend on reading its hue.
##
## Alpha here is ignored. The wind-up owns it — see [method _draw].
var color := DEFAULT_COLOR

var _charge := 0.0


## Show a wind-up that is `charge` of the way through, arriving along `direction`.
## Zero — or nowhere to point — takes the ring off screen.
##
## Called every physics frame rather than started and left running, because the
## thing it is drawing can be taken away: a turret swings off target, a player
## breaks line of sight, a pulse bomb jams the trigger. Driving it from the live
## value means a cancelled attack cancels its tell with no second call to forget.
func set_charge(charge: float, direction: Vector2) -> void:
	if charge <= 0.0 or direction.is_zero_approx():
		visible = false
		return
	_charge = clampf(charge, 0.0, 1.0)
	position = direction.normalized() * REACH
	visible = true
	queue_redraw()


func _draw() -> void:
	# Squared rather than linear. The ring is barely there for the first half of
	# the wind-up and only asserts itself at the end, which is what keeps it a
	# readability cue over a whole run instead of four enemies strobing at you.
	# The radius stays linear — that is the part carrying the timing, and easing
	# it would make the ring lie about when it lands.
	var strength := _charge * _charge

	var ring := color
	ring.a = RING_ALPHA * strength
	draw_arc(Vector2.ZERO, lerpf(OUTER_RADIUS, CORE_RADIUS, _charge), 0.0, TAU,
			RING_SEGMENTS, ring, RING_WIDTH, true)

	var core := color
	core.a = strength
	draw_circle(Vector2.ZERO, CORE_RADIUS * _charge, core)
