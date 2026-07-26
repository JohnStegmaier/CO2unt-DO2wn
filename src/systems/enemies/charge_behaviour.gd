class_name ChargeBehaviour
extends EnemyBehaviour

## Stalk, wind up, and throw itself at where you were standing.
##
## The archetype that makes the room's furniture matter most. It commits to a
## heading at the moment it lunges and cannot steer afterwards, so ducking behind
## a crate does not merely break line of sight — it puts something solid where
## the lunge is already going, and the lunge pays for it. That is also the only
## deliberate prop-breaking in the game: see [method breaks_on_contact].
##
## Four phases, and the tell is the whole fight. STALK is slow enough to walk
## away from; TELEGRAPH is a dead stop long enough to read; LUNGE is far faster
## than the player and completely blind; RECOVER is the window you kill it in.
## Shortening TELEGRAPH is the single cruellest knob in the file.

## LUNGE ends on contact as well as on the clock, which is why its duration is a
## ceiling rather than a schedule — see [method _lunge].
enum Phase { STALK, TELEGRAPH, LUNGE, RECOVER }

@export_group("Stalking")
## Slower than the player, and slower than a chaser: this one is not supposed to
## catch you by walking.
@export_range(10.0, 200.0, 1.0) var stalk_speed: float = 45.0
@export_range(1.0, 20.0, 0.5) var acceleration: float = 5.0
## How close it gets before it winds up. Well inside the room, so a lunge crosses
## a believable distance rather than the whole floor.
@export_range(20.0, 400.0, 5.0) var trigger_range: float = 130.0

@export_group("Lunging")
## The dead stop before it goes. The player's whole warning, and the reason this
## is fair — at 0.1 it is a coin flip, at 0.5 it is free to walk away from.
@export_range(0.05, 2.0, 0.05) var telegraph_time: float = 0.45
## Far faster than the player's WALK_SPEED of 150. It has to out-run a dodge to
## be worth telegraphing.
@export_range(50.0, 800.0, 10.0) var lunge_speed: float = 320.0
## Ceiling on the lunge, not its length: it normally ends early against whatever
## it hits. This is what stops one that misses everything crossing three rooms.
@export_range(0.05, 2.0, 0.05) var lunge_time: float = 0.42
## Face down and helpless. The window the whole archetype is balanced around.
@export_range(0.05, 4.0, 0.05) var recover_time: float = 0.7

@export_group("Obstacles")
## Only used while stalking. A lunge does not steer — that is the point of it.
@export_range(0.0, 120.0, 1.0) var look_ahead: float = 44.0
@export_range(0.0, 2.0, 0.05) var avoidance: float = 0.9


func steer(ctx: SteeringContext) -> Vector2:
	match ctx.phase:
		Phase.TELEGRAPH:
			return _telegraph(ctx)
		Phase.LUNGE:
			return _lunge(ctx)
		Phase.RECOVER:
			return _recover(ctx)
		_:
			return _stalk(ctx)


## Close in, leaning around props, until the player is near enough AND actually
## visible. The line-of-sight test is what stops it winding up at a barrel: with
## no steering left mid-lunge, committing to a blocked heading is committing to
## hitting the barrel.
func _stalk(ctx: SteeringContext) -> Vector2:
	if ctx.distance_to_target() <= trigger_range and ctx.can_see_target():
		ctx.enter(Phase.TELEGRAPH, telegraph_time)
		return Vector2.ZERO
	return ctx.steer_toward(ctx.to_target(), stalk_speed, acceleration, look_ahead, avoidance)


## A dead stop, and the heading locked on the last frame of it rather than the
## first. Reading the player's position at the end of the wind-up is what makes
## the tell honest: sidestep during the telegraph and it still tracks you, but
## sidestep after it commits and it cannot.
func _telegraph(ctx: SteeringContext) -> Vector2:
	if ctx.phase_over():
		ctx.heading = ctx.to_target().normalized()
		if ctx.heading.is_zero_approx():
			ctx.heading = Vector2.RIGHT
		ctx.enter(Phase.LUNGE, lunge_time)
	return Vector2.ZERO


## Assigned outright, never eased and never steered. Easing into a lunge would
## spend the telegraph's whole promise on acceleration, and steering out of one
## would take back the commitment the player just dodged.
func _lunge(ctx: SteeringContext) -> Vector2:
	if ctx.touching or ctx.phase_over():
		ctx.enter(Phase.RECOVER, recover_time)
		return Vector2.ZERO
	return ctx.heading * lunge_speed


func _recover(ctx: SteeringContext) -> Vector2:
	if ctx.phase_over():
		ctx.phase = Phase.STALK
	return Vector2.ZERO


## Melee. The empty bullet_scene on its def is the other half of this, and
## tools/check_enemies.gd checks the two agree.
func fires() -> bool:
	return false


## Where it is going while it stalks, where it is committed while it does not.
## During TELEGRAPH and RECOVER the body is stationary, so drawing it from
## velocity would leave it facing whatever direction it happened to stop in.
func facing(ctx: SteeringContext) -> Vector2:
	if ctx.phase == Phase.STALK:
		return ctx.velocity
	if ctx.phase == Phase.TELEGRAPH:
		return ctx.to_target()
	return ctx.heading


## Only mid-lunge. The same body drifting into a crate while it stalks should
## leave it alone — a charger that dissolved the room by walking through it would
## clear its own cover and the player's in the time it took to line up one jump.
func breaks_on_contact(ctx: SteeringContext) -> bool:
	return ctx.phase == Phase.LUNGE


## Staggered, or a pack of them winds up in unison and the room becomes one
## unavoidable wall of lunges rather than four you read separately.
func on_spawn(ctx: SteeringContext, roll: float) -> void:
	ctx.enter(Phase.RECOVER, recover_time * roll)


func top_speed() -> float:
	return maxf(stalk_speed, lunge_speed)


func describe() -> String:
	return "charge (stalk %.0f, lunge %.0f for %.2fs, tell %.2fs)" % [
			stalk_speed, lunge_speed, lunge_time, telegraph_time]
