class_name TreasureRoom
extends Room

## The floor's treasure cell: an ordinary room with a chest standing in the middle
## of it.
##
## Unlike [ShopRoom] and the elevator room, this one INHERITS room.tscn rather than
## declaring a tree of its own. Those two are drawn side-on and share nothing with
## the top-down shell — no four doorways, no plugs, no door slide — so they were
## cheaper to build from scratch. This room is the top-down shell, plus furniture.
## Inheriting is what lets every override below call super and lets the doors, the
## walls, the tint and the elevator keep working with no code here at all.
##
## The chest itself is a [Chest], parented under Obstacles so it draws behind the
## player rather than hiding her — see the note on the two layers in room.gd.
##
## What comes out of it is not decided here. This reports that it was opened and
## where the contents go; game.gd owns the drop tables and the run's memory of
## which chests are already empty.

## The player opened the chest, and where its contents should land. Connected
## duck-typed by game.gd, which never names this class.
signal treasure_opened(at: Vector2)

@onready var _chest: Chest = $Obstacles/Chest


func _ready() -> void:
	# Called, unlike ShopRoom's: this room has the four doorways and the wall-mounted
	# elevator that Room._ready wires up, and wants all of it.
	super._ready()
	_chest.opened.connect(_on_chest_opened)


## Dress the shell as usual, then put the chest back the way the player left it.
##
## The restore has to happen here rather than in the chest's own _ready, and the
## difference is the whole reason RoomData exists: a room is freed when the player
## walks out and rebuilt when they walk back in, so the chest that comes back is a
## brand new one with no memory of having been opened. The cell remembers; the
## chest is told.
func configure(data: RoomData) -> void:
	super.configure(data)
	if data.treasure_opened:
		_chest.show_opened()


## No solid props in here. The middle of this floor is spoken for, and an empty
## rect is how a room says "not this one" — the same answer the elevator room gives
## about its own lift.
##
## Belt and braces rather than load-bearing: the shipped ObstacleSet does not have
## the treasure bit ticked, so nothing would be scattered in here anyway. This is
## what keeps that true if somebody ticks it.
func obstacle_rect() -> Rect2:
	return Rect2()


func _on_chest_opened(at: Vector2) -> void:
	treasure_opened.emit(at)
