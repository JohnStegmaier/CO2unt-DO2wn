class_name EnemyBehaviour
extends Resource

## How one kind of bad guy fights, as pure data plus pure functions.
##
## A Resource hierarchy rather than an enum and a `match`, which is what this
## replaces. The enum version worked at two behaviours and was already leaking at
## two: every skirmisher knob — preferred range, strafe speed, dodge cooldown —
## showed up in the inspector on a chaser that ignored all six of them, and a
## third archetype would have added its own to the same undifferentiated pile.
## Godot shows the exports of the resource's actual script, so the slot on
## [member EnemyDef.behaviour] is what makes a turret's row show a sweep speed
## and no strafe distance. Adding a fifth archetype is a new file and a .tres,
## and touches nothing that already works.
##
## Pure on purpose, in both directions. It names no autoload and touches no node,
## so it loads under `godot --headless --script` — see the closing note on
## [ObstacleSet] for why everything under systems/ has to. And it holds no state:
## a .tres is one object shared by every enemy of its type, so the strafe sign
## and the charge phase live in the caller's [SteeringContext]. Do not reach for
## AudioManager, get_tree(), or a member variable that changes, in here.
##
## tools/check_enemies.gd steps every subclass six hundred ticks against a
## synthetic context and asserts the result is finite and inside
## [method top_speed]. That is only possible because of the paragraph above.

## What we want to be doing this frame, as a velocity and not a direction.
##
## The smoothing belongs to the behaviour rather than the caller, because a lunge
## is assigned outright and a chase is eased into, and [Enemy] cannot know which
## it is holding. [method SteeringContext.steer_toward] is there for the ones
## that ease.
func steer(_ctx: SteeringContext) -> Vector2:
	return Vector2.ZERO


## Where to put a shot this frame, or ZERO for "hold fire".
##
## ZERO rather than a bool and a vector so a behaviour that never shoots
## overrides nothing at all. Rate is not decided here — [Enemy] owns the cooldown
## and [member EnemyDef.fire_interval] sets it, so this only ever answers
## "would I, right now".
func aim(_ctx: SteeringContext) -> Vector2:
	return Vector2.ZERO


## How committed we are to an attack this behaviour is running itself: 0 for not
## winding up, rising to 1 on the frame it lands. What [AttackTell] draws.
##
## Presentation only. Nothing here changes what the attack does or when — it
## reports a wind-up that already exists rather than creating one, which is why a
## behaviour that returns a number it does not act on is a bug in this method and
## not a balance change.
##
## Separate from the wind-up before a SHOT, which [Enemy] owns because [Enemy]
## owns the fire cooldown — see [method Enemy._maybe_shoot]. This is for the
## attacks a behaviour invented for itself, and today that is exactly one: the
## charger's lunge, which has had a wind-up phase and no way to show it since it
## was written.
func windup(_ctx: SteeringContext) -> float:
	return 0.0


## Whether this archetype ever pulls a trigger, independent of where it is
## standing. Only for tools/check_enemies.gd, which uses it to catch a def
## carrying a gun it can never fire and a shooter with an empty bullet_scene —
## the second of which is silent at runtime, because [method Enemy._shoot]
## returns early, and presents as a whole archetype that looks broken for no
## visible reason.
func fires() -> bool:
	return false


## Where the sprite points, which is NOT always where the body is going: a turret
## never moves, and a lunging charger stopped steering the moment it committed.
func facing(ctx: SteeringContext) -> Vector2:
	return ctx.velocity


## A player bullet came within reach. Return the jump, or ZERO to stand still and
## take it.
func dodge(_ctx: SteeringContext, _bullet_direction: Vector2) -> Vector2:
	return Vector2.ZERO


## Whether to arm the DodgeSensor at all. A roomful of chasers each paying for an
## Area2D that never fires a signal is pure cost, which is why the sensor was
## conditional before this file existed.
func watches_bullets() -> bool:
	return false


## How long a dodge suspends steering, and how long before another is allowed.
##
## Read by [Enemy] rather than applied here, because holding a velocity across
## frames is exactly the per-body state a shared .tres cannot keep. Zero from the
## base is what makes a non-dodger's jump end on the frame it started, which
## costs nothing since it never returns one.
func dodge_hold_seconds() -> float:
	return 0.0


func dodge_cooldown_seconds() -> float:
	return 0.0


## Does walking into a prop right now break it?
##
## Asked per frame rather than read off the def, because a charger only smashes
## things on the lunge — the same body drifting into a crate while it stalks
## should leave it alone. What it costs is [member EnemyDef.break_damage]; this
## only says whether to spend it.
func breaks_on_contact(_ctx: SteeringContext) -> bool:
	return true


## Staggered start, so a roomful does not act in unison forever after.
##
## Takes the roll rather than calling randf() itself. Enemy behaviour is not
## reproducible under fixed_seed.cfg today — the old enemy.gd seeded its fire
## stagger from the global generator, and only enemy PLACEMENT was ever seeded —
## so this changes nothing yet. It is a parameter so that plumbing the run's
## stream through later is one edit at the call site rather than four here.
func on_spawn(_ctx: SteeringContext, _roll: float) -> void:
	pass


## The fastest this behaviour may ever ask to move. What tools/check_enemies.gd
## asserts six hundred ticks of [method steer] against, which is how a typo that
## makes a lunge two thousand pixels a second gets caught in a terminal instead
## of by walking into the room.
func top_speed() -> float:
	return 0.0


## What check_enemies.gd prints, mirroring [method ObstacleDef.describe].
func describe() -> String:
	return "behaviour"
