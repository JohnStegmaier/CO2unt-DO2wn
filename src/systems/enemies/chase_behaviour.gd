class_name ChaseBehaviour
extends EnemyBehaviour

## Run at the player and keep running. The mob.
##
## The simplest archetype and the one the room is balanced around: everything
## else is interesting because there are chasers in the way while it happens.
## What it gained in this change is that it now leans around a barrel instead of
## grinding into one — see [method ObstacleField.avoidance] — which is steering
## and not pathfinding, so it still cannot solve an L of two crates. [Enemy]'s
## stuck-guard is what covers that, and covers walls, which are not in the field.
##
## No separation steering between chasers. They mask each other, so
## move_and_slide pushes them apart physically, and that is what lets thirty of
## them run this unchanged.

## Deliberately slower than the player's WALK_SPEED of 150, so you can kite them
## but not ignore them.
@export_range(10.0, 200.0, 1.0) var speed: float = 60.0
## Exponential smoothing rate, matching player_camera.gd's idiom so acceleration
## is frame-rate independent. Higher turns harder.
@export_range(1.0, 20.0, 0.5) var acceleration: float = 6.0

@export_group("Obstacles")
## How far ahead to look for something to lean around. Roughly a body-and-a-half
## of travel: shorter and it commits to the collision before it reacts, longer
## and it swerves around props it was never going to reach.
@export_range(0.0, 120.0, 1.0) var look_ahead: float = 40.0
## How hard to lean, against a unit vector pointing at the player. At 1.0 a prop
## dead ahead cancels the approach entirely and it sidles; below that it always
## keeps closing, which is what a mob is for.
@export_range(0.0, 2.0, 0.05) var avoidance: float = 0.8


func steer(ctx: SteeringContext) -> Vector2:
	return ctx.steer_toward(ctx.to_target(), speed, acceleration, look_ahead, avoidance)


func top_speed() -> float:
	return speed


func describe() -> String:
	return "chase (%.0f px/s, avoid %.2f)" % [speed, avoidance]
