class_name TurretBehaviour
extends EnemyBehaviour

## Bolted down. Fires along a heading, turns, fires along the next one, forever.
##
## It never chases and never aims at you, which is the whole design. A turret
## alone is a puzzle you walk around — lots of hit points, no threat once you
## have read the sweep. Put one behind a room of chasers and the room stops being
## about killing bad guys and starts being about where you are standing while you
## do it, which is what the other three archetypes cannot ask on their own.
##
## Deliberately NOT a tracker. A turret that led its target would be a skirmisher
## that cannot walk, and the fixed sweep is what makes it readable enough to be
## fair at six hundred hit points.
##
## Two phases and no steering: [method steer] returns ZERO always, so the body
## never moves and [member EnemyDef.placement] puts it against a wall where its
## arc covers ground instead of the middle of the floor where it is a barrel with
## a gun.

## AIM fires; TURN is the swing between stops, and holds fire so a shot never
## leaves at an angle nothing was aiming down.
enum Phase { AIM, TURN }

## How far it swings between stops. 22.5° is one frame of the sixteen-frame art,
## so the sweep lands exactly on a drawn facing rather than between two of them —
## see [EnemyFacing]. Anything that does not divide 360 evenly still works, it
## just rounds to the nearest frame.
@export_range(5.0, 180.0, 2.5) var step_degrees: float = 22.5
## Seconds spent firing at each stop. The number of shots is this divided by
## [member EnemyDef.fire_interval], so the two are tuned together — a long aim
## and a slow interval is one heavy shot per bearing, a short aim and a fast one
## is a burst.
@export_range(0.1, 6.0, 0.1) var aim_time: float = 0.9
## Seconds the swing itself takes. Long enough to see it coming, which is the
## difference between a hazard and an ambush.
@export_range(0.05, 4.0, 0.05) var turn_time: float = 0.45

@export_group("Targeting")
## Hold fire when a prop is in the way. Off by default: bullets already stop dead
## on props, so a blind sweep gives the player cover that works without the
## turret being polite about it, and a turret that goes quiet is a turret you
## stop tracking. Tick it to save the noise in a very cluttered room.
@export var respects_cover: bool = false
## Stop firing beyond this. Generous by default — a turret's shots crossing the
## whole room is the point of putting one against a wall.
@export_range(50.0, 1000.0, 10.0) var fire_range: float = 400.0


## Bolted down, so this only ever returns ZERO — but it is also the sweep,
## because steer() is the one call [Enemy] makes exactly once per physics frame.
## Advancing the phase clock from facing() instead would put the whole rotation
## at the mercy of how often something asked which way the sprite points.
##
## Runs off the phase clock rather than accumulating an angle per frame, so the
## stops land on the same bearings whatever the frame rate did — a turret that
## drifts a degree a second ends up sweeping a different room than the one it was
## placed in.
func steer(ctx: SteeringContext) -> Vector2:
	if ctx.phase_over():
		if ctx.phase == Phase.AIM:
			ctx.enter(Phase.TURN, turn_time)
			# Rotated on entering the turn rather than on leaving it, so the art
			# swings to the new bearing across the swing instead of snapping to
			# it on the frame the shooting starts.
			ctx.heading = ctx.heading.rotated(deg_to_rad(step_degrees) * ctx.side)
		else:
			ctx.enter(Phase.AIM, aim_time)
	return Vector2.ZERO


func facing(ctx: SteeringContext) -> Vector2:
	return ctx.heading


func aim(ctx: SteeringContext) -> Vector2:
	if ctx.phase != Phase.AIM:
		return Vector2.ZERO
	if ctx.distance_to_target() > fire_range:
		return Vector2.ZERO
	if respects_cover and not ctx.can_see_target():
		return Vector2.ZERO
	# Down the barrel, not at the player. Everything else in this file exists to
	# make that sentence true.
	return ctx.heading


func fires() -> bool:
	return true


## Nothing to break: it does not move, so it never walks into anything, and its
## contact damage is whatever the player gets for standing on it.
func breaks_on_contact(_ctx: SteeringContext) -> bool:
	return false


## Both the starting bearing and which way round it sweeps, off one roll. Two
## turrets in a room sweeping opposite ways from different bearings is what makes
## a pair read as placed rather than duplicated.
func on_spawn(ctx: SteeringContext, roll: float) -> void:
	ctx.side = 1.0 if roll < 0.5 else -1.0
	ctx.heading = Vector2.RIGHT.rotated(deg_to_rad(step_degrees) * roundi(roll * 16.0))
	ctx.enter(Phase.AIM, aim_time * roll)


func top_speed() -> float:
	return 0.0


func describe() -> String:
	return "turret (%.1f° every %.1fs+%.1fs, fire %.0f)" % [
			step_degrees, aim_time, turn_time, fire_range]
