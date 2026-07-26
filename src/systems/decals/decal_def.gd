class_name DecalDef
extends Resource

## One piece of cosmetic floor dressing: a blood splat, a torch.
##
## Not an ObstacleDef with body_radius set to zero. check_obstacles.gd asserts
## every obstacle's radius is positive, because the room's connectivity proof
## is stated in terms of it — a decal makes no such promise, blocks nothing,
## and needs no radius to make none. Same bargain ItemDef and ObstacleDef make
## over their own scenes: a splat and a torch differ in art and a number, so
## adding a third is a .tres and not a new scene to keep in step.

@export var id: StringName = &""

@export_group("Appearance")
## A still image. Ignored while [member sprite_frames] is set — see there.
@export var texture: Texture2D
## Plays instead of the static texture when set — a flickering torch rather
## than one frame of it. Nullable the same way ItemDef.icon_frames is: most
## decals are still a plain texture, and animating one is opting into a second
## way of being drawn rather than something every row must carry.
@export var sprite_frames: SpriteFrames
## Which animation on sprite_frames to play. Unused while sprite_frames is null.
@export var animation: StringName = &"default"
@export var sprite_scale: float = 1.0
@export var offset: Vector2 = Vector2.ZERO
## Flat alpha, not a fade-in — a blood splat reads as old stains rather than
## fresh paint at less than full opacity. 1.0 leaves the art alone.
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0

## How much room this wants around it, so two decals do not render on top of
## each other.
##
## NOT a collision radius. Only [DecalPlacement] ever reads this — nothing
## steers on it the way EnemyBehaviour steers on ObstacleField, and it carries
## no promise about whether a room can be crossed the way
## [member ObstacleDef.body_radius] does.
@export var clearance_radius: float = 12.0

## Relative, matching every other weight in the game — see
## [member ObstacleDef.weight].
@export var weight: float = 1.0


func describe() -> String:
	var kind := "animated" if sprite_frames != null else "static"
	return "%s (%s, weight %.1f)" % [id, kind, weight]
