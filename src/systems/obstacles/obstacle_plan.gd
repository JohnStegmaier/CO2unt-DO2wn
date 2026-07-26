class_name ObstaclePlan
extends RefCounted

## One prop, decided but not yet built: what it is and where it goes.
##
## The hand-off between [ObstaclePlacement], which owns the rules and no nodes,
## and game.gd, which owns the nodes and none of the rules. Keeping it a type
## rather than a Dictionary is what lets check_obstacles.gd read a layout without
## instancing a single scene.

var def: ObstacleDef
## Room-local, ready for Room.add_obstacle.
var position: Vector2


func _init(p_def: ObstacleDef = null, p_position: Vector2 = Vector2.ZERO) -> void:
	def = p_def
	position = p_position


## The prop's solid extent. What the connectivity flood fill inflates.
func radius() -> float:
	return def.body_radius if def != null else 0.0
