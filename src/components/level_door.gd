class_name LevelDoor
extends Area2D

## A doorway trigger.
##
## It knows which side of the room it sits on and nothing else — where that side
## leads is decided at runtime from the floor plan, so the door has no
## destination to configure. It reports and lets the Game decide.

signal player_entered(side: int)

## Depth of the trigger along the axis you travel through it. Matches the wall
## band, so the trigger fills the doorway without spilling onto the floor.
const TRIGGER_DEPTH := 28.0

## Width of the trigger across the doorway. Must match the full opening — a
## narrower trigger lets a player hugging the edge of the doorway walk out of
## the room without ever entering it.
const TRIGGER_WIDTH := 46.0

## A GridDirection.Side. Typed int, and declared with @export_enum rather than
## the enum itself, because GDScript will not carry an enum type across script
## boundaries — see the note in grid_direction.gd.
@export_enum("north", "east", "south", "west") var side: int = 0

## How far inside the room an arriving player lands, measured from the doorway
## centre. Tuned so they appear at the base of the door: just past the floor
## edge, but still clear of this door's own trigger, since landing inside it
## would re-fire it and bounce them straight back out.
@export var spawn_inset: float = 22.0

@onready var _trigger: CollisionShape2D = $trigger


func _ready() -> void:
	# Built here rather than authored in the scene because sub-resources are
	# shared between instances of the same scene — one authored shape could not
	# be oriented per side without all four doors changing together.
	var shape := RectangleShape2D.new()
	if side == GridDirection.Side.EAST or side == GridDirection.Side.WEST:
		shape.size = Vector2(TRIGGER_DEPTH, TRIGGER_WIDTH)
	else:
		shape.size = Vector2(TRIGGER_WIDTH, TRIGGER_DEPTH)
	_trigger.shape = shape


## Where a player arriving through this door should be placed. Inward is always
## the opposite of the side's grid offset, so this cannot be mis-authored.
func spawn_position() -> Vector2:
	return global_position - Vector2(GridDirection.offset(side)) * spawn_inset


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_entered.emit(side)
