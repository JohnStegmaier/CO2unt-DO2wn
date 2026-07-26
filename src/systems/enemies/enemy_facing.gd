class_name EnemyFacing
extends RefCounted

## Which animation, and which frame of it, faces which way — for every kind of
## enemy art in the game.
##
## Four modes and one formula. A heading is an angle; an angle cut into N even
## sectors is an index; and the index is either an animation name or a frame
## number. That is the whole abstraction, and there is deliberately no per-enemy
## branch anywhere in it: the booger has one animation, the licker two, the guard
## four and the turret sixteen frames of one, and all four are [method sector]
## called with a different count.
##
## The alternative — a case per enemy in [Enemy] — is how the behaviour enum this
## change replaces got to be a problem, and art is the axis that grows fastest.
##
## [b]Sectors run clockwise from due right[/b], because that is what
## Vector2.angle() counts in a Y-down world: right 0, down +PI/2, left PI, up
## -PI/2. Get this backwards and every four-way enemy walks with its up and down
## animations swapped, which looks like an art bug and is not one.

## OMNI is art with no facing at all — a blob looks the same from everywhere.
## ROTATION is one animation whose frames ARE the bearings, so it is paused and
## indexed rather than played; the sixteen-frame sentry turret is the only one,
## and sixteen frames is exactly 22.5° a step.
enum Mode { OMNI, TWO_WAY, FOUR_WAY, ROTATION }

## Animation names per mode, in sector order. The prefix is fixed so a
## SpriteFrames resource can be read at a glance, and so tools/check_enemies.gd
## can insist on exactly these — a misnamed animation is silent at runtime and
## shows up as an enemy stuck on its first frame forever, which reads as a
## physics bug rather than a typo.
const NAMES := {
	Mode.OMNI: [&"move"],
	Mode.TWO_WAY: [&"move_right", &"move_left"],
	Mode.FOUR_WAY: [&"move_right", &"move_down", &"move_left", &"move_up"],
	Mode.ROTATION: [&"move"],
}


## The sector a heading falls in, out of `count` of them. The function everything
## else here is a wrapper around.
##
## Rounded rather than floored, so a sector is centred on its bearing instead of
## starting at it: with four of them, due right lands in the middle of "right"
## rather than on the boundary between right and down, where a body walking
## straight would flicker between two animations.
##
## Falls back to sector zero on a zero-length heading — a standing enemy keeps
## whatever it was last drawn as, rather than snapping to due right.
static func sector(heading: Vector2, count: int, offset_degrees: float = 0.0) -> int:
	if count <= 1 or heading.is_zero_approx():
		return 0
	var angle := heading.angle() - deg_to_rad(offset_degrees)
	return wrapi(roundi(angle / TAU * count), 0, count)


## Which animation to play. ROTATION has only one, which is the point: its
## bearings are frames, not animations — see [method frame_for].
static func animation_for(mode: int, heading: Vector2,
		offset_degrees: float = 0.0) -> StringName:
	var names: Array = NAMES.get(mode, NAMES[Mode.OMNI])
	return names[sector(heading, names.size(), offset_degrees)]


## Which frame to hold, or -1 when the mode animates on a clock instead of a
## bearing.
##
## The -1 rather than a second "is this mode rotational" predicate is what lets
## the caller write `if frame >= 0` and never name a mode — [Enemy] does not
## contain the word ROTATION anywhere, which is the test of whether this file
## did its job.
static func frame_for(mode: int, heading: Vector2, frame_count: int,
		offset_degrees: float = 0.0) -> int:
	if mode != Mode.ROTATION or frame_count <= 0:
		return -1
	return sector(heading, frame_count, offset_degrees)


## Every animation a def in this mode must supply, for tools/check_enemies.gd.
static func required_animations(mode: int) -> Array:
	return NAMES.get(mode, NAMES[Mode.OMNI])
