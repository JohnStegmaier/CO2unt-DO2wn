class_name SteeringContext
extends RefCounted

## One enemy's view of the fight, and one enemy's memory of it.
##
## Exists because an [EnemyBehaviour] is a .tres shared by every enemy of its
## type — one object, a roomful of bodies. A strafe sign or a charge phase stored
## on the behaviour would be stored once for all of them, and the bug that
## follows does not look like a missing call: it looks like the AI being weirdly
## synchronised, twelve lickers lunging on the same frame forever. Splitting the
## knobs (shared, on disk, tuned in the inspector) from the state (one per body,
## rewritten every frame) is what makes that impossible rather than merely
## avoided.
##
## The other half of the bargain is that it leaves every behaviour a pure
## function of its arguments, which is what lets tools/check_enemies.gd run one
## for six hundred ticks against a synthetic context in a terminal — no scene, no
## physics server, no autoloads. That is the same trade [ObstacleField] makes by
## staying node-free.
##
## [b]Everything here is in [ObstacleField] space, which is ROOM-LOCAL.[/b] An
## [Enemy] lives in global space; the single conversion happens in
## [method Enemy.set_room] and is applied once per frame in
## _physics_process, not once per query. A behaviour never learns that rooms have
## positions.

# -- The world. Rewritten by Enemy every physics frame; never written from here.

## Where we are.
var here: Vector2
## Where the player is. Enemies have exactly one target and it is handed to them.
var target: Vector2
## What we were doing last frame, which is what the smoothing eases away from.
var velocity: Vector2
var delta: float
## Our own body's radius, so the field queries below can be asked "for me" —
## [method ObstacleField.is_clear] and friends all take the asker's size.
var radius: float
## Shared by reference with every other enemy in the room, and with game.gd,
## which is what makes a prop breaking mid-fight visible to all of them on the
## next frame rather than the next room. Read-only from in here.
var field: ObstacleField
## move_and_slide hit something last frame. What a lunge ends on, and the only
## way a behaviour can tell "I am pressed against a wall" from "I am walking".
var touching: bool
## The walkable floor, room-local. Cover points are clamped into it, because a
## spot behind a barrel that happens to be inside a wall is not somewhere to
## stand.
var bounds: Rect2

# -- Our own memory. Which of these mean anything is the behaviour's business:
#    a chaser touches none of them, and each behaviour reads `phase` against an
#    enum it declares itself.

var phase: int = 0
## Seconds left in it. Counted down from [member delta] rather than compared
## against Time.get_ticks_msec(), which is what the rest of this entity does for
## its dodge and knockback windows.
##
## Wall-clock is wrong for anything that spans frames of gameplay. It keeps
## running while the game is paused, so a licker paused mid-telegraph resumes
## already committed to a lunge it never wound up for; and it cannot be stepped,
## so tools/check_enemies.gd could not drive a phase machine at all — six hundred
## simulated ticks finish in about twenty milliseconds of real time and no phase
## would ever expire. That is exactly how this was found.
var phase_remaining: float = 0.0
## Which way round we are going — the skirmisher's strafe, and which way a turret
## sweeps. A float rather than a bool so it multiplies a vector directly.
var side: float = 1.0
## Where we are pointed, as opposed to where we are going. A turret does not move
## and a lunging charger has stopped steering, so for both of those this is the
## only thing the sprite can be drawn from — see [method EnemyBehaviour.facing].
var heading: Vector2 = Vector2.RIGHT
## Somewhere we have decided to be: the skirmisher's chosen cover. Remembered
## rather than recomputed, because an enemy that re-picks its destination every
## frame walks the average of all of them, which is nowhere.
var goal: Vector2
## Cover and line-of-sight are re-decided on this clock rather than every frame.
## Not for the frame time — six discs is nothing — but because an enemy
## re-evaluating cover sixty times a second reads as twitching, not thinking.
var think_remaining: float = 0.0


## Advance both clocks. Called once per physics frame by [Enemy], before the
## behaviour is asked anything, so a phase that ran out last frame has already
## ended by the time [method phase_over] is read.
func tick(seconds: float) -> void:
	delta = seconds
	phase_remaining -= seconds
	think_remaining -= seconds


func to_target() -> Vector2:
	return target - here


func distance_to_target() -> float:
	return here.distance_to(target)


## Is the player standing somewhere we could actually shoot?
##
## Padded by our own radius so a line that only clears a barrel because we are
## treated as a point does not count — that is the shot that hits the barrel.
func can_see_target() -> bool:
	return field == null or field.has_line_of_sight(here, target, radius)


func phase_over() -> bool:
	return phase_remaining <= 0.0


## Move to `new_phase` for `seconds`. Pass a long duration for a phase that ends
## on something other than the clock — a lunge ends on [member touching] — rather
## than adding a second "does this one time out" flag.
func enter(new_phase: int, seconds: float) -> void:
	phase = new_phase
	phase_remaining = seconds


## True at most once per `interval_seconds`, and it books the next slot itself.
## Called from inside a steer(), so it has to be the thing that both asks and
## records — a caller that had to remember to stamp the clock afterwards would
## eventually forget in one branch of one behaviour.
func may_think(interval_seconds: float) -> bool:
	if think_remaining > 0.0:
		return false
	think_remaining = interval_seconds
	return true


## The steering everything that walks shares: point at `desired`, lean away from
## whatever is in the way, and ease into it.
##
## Here rather than repeated in three behaviours because the alternative is three
## copies of an exponential smooth that have to agree about frame-rate
## independence. Behaviours that do not walk — the turret — never call it.
##
## The lean is added to a unit direction and the sum clamped back to one, so the
## result can never exceed `speed`. That is what lets
## [method EnemyBehaviour.top_speed] be a number the checker can assert against
## rather than an estimate.
func steer_toward(desired: Vector2, speed: float, acceleration: float,
		look_ahead: float, strength: float) -> Vector2:
	var direction := desired.normalized()
	if field != null and not direction.is_zero_approx():
		direction = (direction + field.avoidance(here, direction, radius, look_ahead)
				* strength).limit_length(1.0)
	# Exponential smoothing, matching player_camera.gd's idiom so acceleration is
	# frame-rate independent.
	return velocity.lerp(direction * speed, 1.0 - exp(-acceleration * delta))
