class_name DepthLayer
extends Node2D

## One plane of a side-on room, and how far it slides when the player looks around.
##
## Parallax done by moving the LAYERS rather than the camera. A camera offset
## moves everything by the same amount, which is the one thing that cannot
## suggest depth; planes that move by different amounts against a still camera
## are the whole effect. It also sidesteps [PlayerCamera]'s clamp, which in a room
## exactly the height of the viewport has no room to move at all.
##
## Attach to each plane of the scene and set [member depth_factor] by how near the
## camera it is meant to read. Something driving them — see [ShopRoom] — calls
## [method apply_look] every frame with one shared offset.

## How much of the look offset this plane takes, 0 (pinned to the far wall) to 1
## (right up against the viewport). Values above 1 are legal and read as a plane
## nearly touching the lens; negative ones move against the others, which is
## wrong for depth but occasionally right for a reflection.
@export_range(-1.0, 1.5, 0.01) var depth_factor: float = 0.0

## Where this plane was authored to sit. The offset is always applied to THIS
## rather than to wherever the node currently is, so a hundred thousand frames of
## look cannot accumulate into a drift, and a plane whose factor is 0 is provably
## never touched.
@onready var _home: Vector2 = position


## Slide this plane by its share of the shared look offset.
func apply_look(offset: Vector2) -> void:
	position = _home + offset * depth_factor


## Where this plane was authored to sit, for anything that needs to place a child
## against the authored pose rather than the current one.
func home() -> Vector2:
	return _home


## Re-read the authored position. Only needed if something moved the plane for a
## reason unrelated to looking around — otherwise the value read at _ready is
## correct for the life of the room.
func adopt_current_as_home() -> void:
	_home = position
