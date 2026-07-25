class_name Damage
extends RefCounted

## What a hit does, as opposed to how much.
##
## Blunt spends oxygen outright — a dent in the tank. Piercing tears the suit, so
## the air you have left drains faster. Only two places ever learn what a type
## means: Health, for anything with hit points, and O2Timer, for the player.
##
## Values travel as plain int, for the same reason sides do — see the note in
## grid_direction.gd on enums across script boundaries.

enum Type { BLUNT, PIERCING }

const NAMES: Array[String] = ["blunt", "piercing"]


static func type_name(type: int) -> String:
	return NAMES[type]
