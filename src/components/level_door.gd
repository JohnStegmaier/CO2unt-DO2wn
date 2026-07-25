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

## How far inside the room an arriving player lands. Must clear this door's own
## trigger shape, or arriving instantly re-fires it and bounces you back out.
@export var spawn_inset: float = 50.0


## Where a player arriving through this door should be placed. Inward is always
## the opposite of the side's grid offset, so this cannot be mis-authored.
func spawn_position() -> Vector2:
	return global_position - Vector2(GridDirection.offset(side)) * spawn_inset


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_entered.emit(side)
