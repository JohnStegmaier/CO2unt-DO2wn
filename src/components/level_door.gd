class_name LevelDoor
extends Area2D

## A doorway trigger.
##
## It knows which side of the room it sits on and nothing else — where that side
## leads is decided at runtime from the floor plan, so the door has no
## destination to configure. It reports and lets the Game decide.

signal player_entered(side: int)

## A GridDirection.Side. Typed int, and declared with @export_enum rather than
## the enum itself, because GDScript will not carry an enum type across script
## boundaries — see the note in grid_direction.gd.
@export_enum("north", "east", "south", "west") var side: int = 0

## How far inside the room an arriving player lands, measured from the centre
## line of the wall band this door sits in. Tuned so they appear at the base of
## the door: past the wall's inner face and clear of this door's own trigger,
## since landing inside it would re-fire it and bounce them straight back out.
@export var spawn_inset: float = 28.0

@onready var _trigger: CollisionShape2D = $trigger


## Size the trigger to the doorway it is standing in: as deep as the wall band,
## as wide as the hole in it.
##
## Told rather than assumed. The depth used to be a constant copied off the wall
## thickness, and an art pass that thinned the walls left it 11px too deep — a
## trigger spilling onto the floor pulls a player through a door they only walked
## past. [Room] measures its own walls and calls this, so there is one set of
## numbers instead of two that can disagree.
##
## The width must span the FULL opening. A narrower trigger lets a player hugging
## the edge of the doorway walk out of the room without ever entering it.
func fit_opening(depth: float, width: float) -> void:
	# Built here rather than authored in the scene because sub-resources are
	# shared between instances of the same scene — one authored shape could not
	# be oriented per side without all four doors changing together.
	var shape := RectangleShape2D.new()
	if side == GridDirection.Side.EAST or side == GridDirection.Side.WEST:
		shape.size = Vector2(depth, width)
	else:
		shape.size = Vector2(width, depth)
	# Deferred defensively: a door is cheap to spawn in response to a collision,
	# and the physics server rejects shape changes made while it is flushing
	# queries. The door is not monitoring yet, so a frame's delay costs nothing.
	_trigger.set_deferred("shape", shape)


## Where a player arriving through this door should be placed. Inward is always
## the opposite of the side's grid offset, so this cannot be mis-authored.
func spawn_position() -> Vector2:
	return global_position - Vector2(GridDirection.offset(side)) * spawn_inset


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_entered.emit(side)
