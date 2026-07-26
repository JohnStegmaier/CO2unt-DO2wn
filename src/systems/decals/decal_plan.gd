class_name DecalPlan
extends RefCounted

## One decal, decided but not yet built: what it is and where it goes.
##
## [ObstaclePlan]'s exact shape. The hand-off between [DecalPlacement], which
## owns the rules and no nodes, and game.gd, which owns the nodes and none of
## the rules.

var def: DecalDef
## Room-local, ready for Room.add_decal.
var position: Vector2


func _init(p_def: DecalDef = null, p_position: Vector2 = Vector2.ZERO) -> void:
	def = p_def
	position = p_position
