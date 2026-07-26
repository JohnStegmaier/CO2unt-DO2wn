class_name SkirmishBehaviour
extends EnemyBehaviour

## Hold a firing range, circle, and duck behind things. Dodge and snipe.
##
## Closes if too far, backs off if too close, and strafes while it is
## comfortable — that much is what this archetype always did. What is new is that
## it now treats the room's props as cover: on its think clock it looks for
## somewhere with a barrel between it and the player, goes there, and holds fire
## while it is behind one, because it cannot see out either. Coming back out to
## shoot and ducking back in is not scripted; it falls out of the two phases and
## the fact that [method aim] refuses a blocked line.
##
## In a room with no props [method ObstacleField.cover_point] returns where it is
## already standing, [member Phase.COVER] is never entered, and this behaves
## exactly as it did before obstacles existed. That is deliberate — the cover
## logic is an addition to the ring, not a replacement for it.

## COVER is "walking to a spot I picked", not "hiding": by the time it arrives it
## is usually already back in HOLD. The phase is what stops it re-deciding its
## destination every frame and walking the average of all of them, which is
## nowhere.
enum Phase { HOLD, COVER }

## How far it likes to stand off, and the dead band around that which stops it
## jittering back and forth across the ring.
@export_range(20.0, 400.0, 5.0) var preferred_range: float = 140.0
@export_range(5.0, 100.0, 1.0) var range_band: float = 25.0
@export_range(10.0, 200.0, 1.0) var speed: float = 60.0
@export_range(10.0, 200.0, 1.0) var strafe_speed: float = 55.0
@export_range(1.0, 20.0, 0.5) var acceleration: float = 6.0
## How far away it will still take a shot. Wider than preferred_range so backing
## off does not silence it.
@export_range(20.0, 600.0, 5.0) var fire_range: float = 220.0

@export_group("Dodging")
@export_range(20.0, 400.0, 5.0) var dodge_speed: float = 180.0
## How long the jump holds before steering resumes. Steering is suspended
## outright for this, the same shape as the player's own is_dodging early return.
@export_range(0.05, 1.0, 0.01) var dodge_time: float = 0.22
@export_range(0.0, 5.0, 0.05) var dodge_cooldown: float = 1.0

@export_group("Cover")
## How far it will walk to get behind something. Zero switches cover-seeking off
## entirely and leaves the plain ring behaviour, which is what this was before.
@export_range(0.0, 300.0, 5.0) var cover_travel: float = 110.0
## How long it commits to a chosen spot before it is allowed to change its mind.
@export_range(0.1, 8.0, 0.1) var cover_time: float = 1.6
## How often it reconsiders cover and line of sight. Not a frame-time saving —
## six discs is nothing — but an enemy re-deciding sixty times a second reads as
## twitching rather than thinking.
@export_range(0.05, 2.0, 0.05) var think_interval: float = 0.35

@export_group("Obstacles")
@export_range(0.0, 120.0, 1.0) var look_ahead: float = 36.0
@export_range(0.0, 2.0, 0.05) var avoidance: float = 0.7

## Reversing on a timer as well as on contact, so it neither grinds along a wall
## nor orbits the player hypnotically.
const STRAFE_FLIP_MIN := 1.5
const STRAFE_FLIP_MAX := 3.0
## A cover point nearer than this is where it is already standing — either the
## field is empty or every prop is behind it — and walking there is a no-op that
## would still cost it a phase.
const COVER_WORTH_TAKING := 12.0


func steer(ctx: SteeringContext) -> Vector2:
	if ctx.phase == Phase.COVER:
		return _steer_to_cover(ctx)

	if ctx.may_think(think_interval):
		_consider_cover(ctx)
		if ctx.phase == Phase.COVER:
			return _steer_to_cover(ctx)

	return _hold_the_ring(ctx)


## Is there somewhere better to stand than in the open?
##
## Only worth asking when the player can actually see us — cover we are already
## behind is cover, and walking to a second barrel while safe behind the first is
## how an enemy ends up permanently in transit and never shooting.
func _consider_cover(ctx: SteeringContext) -> void:
	if ctx.field == null or cover_travel <= 0.0 or not ctx.can_see_target():
		return
	var spot: Vector2 = ctx.field.cover_point(ctx.here, ctx.target, ctx.radius,
			cover_travel, ctx.bounds)
	if ctx.here.distance_to(spot) < COVER_WORTH_TAKING:
		return
	ctx.goal = spot
	ctx.enter(Phase.COVER, cover_time)


## Arrived, or ran out of patience, or the thing we were hiding behind got shot
## out from under us — all three end the same way, back to holding the ring.
func _steer_to_cover(ctx: SteeringContext) -> Vector2:
	var to_goal := ctx.goal - ctx.here
	if ctx.phase_over() or to_goal.length() < COVER_WORTH_TAKING:
		ctx.phase = Phase.HOLD
		return _hold_the_ring(ctx)
	return ctx.steer_toward(to_goal, speed, acceleration, look_ahead, avoidance)


func _hold_the_ring(ctx: SteeringContext) -> Vector2:
	var distance := ctx.distance_to_target()
	var toward := ctx.to_target().normalized()

	if distance > preferred_range + range_band:
		return ctx.steer_toward(toward, speed, acceleration, look_ahead, avoidance)
	if distance < preferred_range - range_band:
		return ctx.steer_toward(-toward, speed, acceleration, look_ahead, avoidance)

	# Comfortable: circle. Flipped on contact as well as on the clock, because
	# motion mode is grounded — a body sliding along the top or bottom face of a
	# prop reports floor or ceiling rather than wall, and without this it grinds
	# sideways along a crate forever.
	if ctx.touching or ctx.phase_over():
		ctx.side = -ctx.side
		ctx.enter(Phase.HOLD, randf_range(STRAFE_FLIP_MIN, STRAFE_FLIP_MAX))
	return ctx.steer_toward(toward.orthogonal() * ctx.side, strafe_speed, acceleration,
			look_ahead, avoidance)


## In range, and with a line that does not end in a barrel. The second test is
## what stops a skirmisher patiently feeding its own cover for the whole fight.
func aim(ctx: SteeringContext) -> Vector2:
	if ctx.distance_to_target() > fire_range or not ctx.can_see_target():
		return Vector2.ZERO
	return ctx.to_target().normalized()


func fires() -> bool:
	return true


## Facing the player while sidestepping, rather than facing the walk. The art is
## four-way and this one is aiming: a guard that turns its back to strafe reads
## as fleeing, which is the opposite of what it is doing.
func facing(ctx: SteeringContext) -> Vector2:
	if ctx.distance_to_target() <= fire_range:
		return ctx.to_target()
	return ctx.velocity


## Jump perpendicular to where the shot is actually going. Reading its direction
## rather than its position means a bullet that would have missed anyway does not
## provoke a dodge into its path.
func dodge(ctx: SteeringContext, bullet_direction: Vector2) -> Vector2:
	var away := bullet_direction.orthogonal()
	# Break toward whichever side we were already drifting, so it reads as a
	# continuation rather than a twitch.
	if away.dot(ctx.velocity) < 0.0:
		away = -away
	return away * dodge_speed


func watches_bullets() -> bool:
	return true


func dodge_hold_seconds() -> float:
	return dodge_time


func dodge_cooldown_seconds() -> float:
	return dodge_cooldown


## Never on purpose. This one wants the barrel intact and between the two of you;
## shooting away its own cover would be self-defeating, and shoving it apart is
## the same mistake at walking pace.
func breaks_on_contact(_ctx: SteeringContext) -> bool:
	return false


func on_spawn(ctx: SteeringContext, roll: float) -> void:
	ctx.side = 1.0 if roll < 0.5 else -1.0
	ctx.enter(Phase.HOLD, randf_range(STRAFE_FLIP_MIN, STRAFE_FLIP_MAX))


## Both legs of the ring are capped by steer_toward, so the fastest it can ask
## for is the larger of the two — plus the dodge, which is assigned outright and
## bypasses the smoothing entirely.
func top_speed() -> float:
	return maxf(maxf(speed, strafe_speed), dodge_speed)


func describe() -> String:
	return "skirmish (ring %.0f±%.0f, fire %.0f, cover %.0f)" % [
			preferred_range, range_band, fire_range, cover_travel]
