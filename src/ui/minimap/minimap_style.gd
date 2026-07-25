class_name MinimapStyle
extends Resource

## Every colour and dimension the minimap draws with.
##
## A Resource rather than constants in [Minimap] so the look is an inspector slot
## you can swap and tune while the game runs — the same argument floor_config.gd
## makes for the shape of a floor. Pure data: reading it cannot change what the
## player is allowed to see, which is minimap_model.gd's job alone.
##
## Keep the geometry whole. At 640x360 under the canvas_items stretch a
## fractional cell or gap lands a rect on a half pixel and the outline smears.

@export_group("Geometry")
## Room cells are wider than they are tall because rooms are: Room.STRIDE is
## 442x286, a ratio of 1.55, and 11x7 is 1.57.
@export var cell_size: Vector2 = Vector2(11, 7)
## Wide enough for a door stub to be visible in. Rooms that merely sit next to
## each other are NOT necessarily joined — the floor is a tree, so a branch can
## grow back alongside itself without a door — and the gap plus the stub is what
## tells those two cases apart.
@export var cell_gap: float = 2.0
## The grid drawn, in cells. 13 is 2 * FloorConfig.max_depth + 1, so every room
## of every floor fits however the player wanders — check_minimap.gd asserts it
## (the widest floor in 1000 is 12x12). Nothing here is derived from the floor
## actually in play, which is what stops the panel's size from hinting at how
## much is left to find.
@export var window_cells: Vector2i = Vector2i(13, 13)
@export var padding: float = 4.0
@export var outline_width: float = 1.0

@export_group("Panel")
## Drop the alpha to 0 for a frameless map that is nothing but its rooms.
@export var panel_color: Color = Color(0.03, 0.06, 0.05, 0.30)
@export var panel_border_color: Color = Color(0.25, 0.55, 0.35, 0.30)
## Stubs joining rooms the player has walked between. Only ever drawn from a room
## they have stood in — see MinimapModel.door_mask_at.
@export var door_color: Color = Color(0.40, 0.88, 0.52, 0.75)
@export var door_width: float = 1.0
## How far the stub reaches into the rooms on either side of the gap. Enough to
## touch both, not enough to draw a line across them.
@export var door_overhang: float = 1.0

@export_group("Current room")
## The one thing on the panel that is nearly opaque, so the eye finds it first.
@export var current_color: Color = Color(0.30, 0.95, 0.45, 1.0)
@export var current_alpha_min: float = 0.55
@export var current_alpha_max: float = 0.95
@export var blink_period: float = 1.4
## Steps in one pulse. Doubles as the redraw throttle — the map only redraws when
## the step changes, so 12 is about nine redraws a second rather than sixty. A
## stepped pulse also reads as deliberate at this resolution, where a smooth fade
## has too few pixels to be smooth in.
@export var blink_steps: int = 12

@export_group("Explored rooms")
@export var visited_fill_color: Color = Color(0.24, 0.68, 0.36, 0.22)
@export var visited_outline_color: Color = Color(0.34, 0.80, 0.46, 0.65)

@export_group("Unexplored rooms")
## Barely there on purpose: enough to say a room is out there, not enough to read
## as anything else. The dashed outline is what marks it as not yet walked into.
@export var discovered_fill_color: Color = Color(0.12, 0.34, 0.20, 0.10)
@export var discovered_outline_color: Color = Color(0.20, 0.50, 0.30, 0.40)
@export var dash_length: float = 2.0

@export_group("Special rooms")
## Hue per RoomData.Kind, indexed the way KIND_GLYPHS and Room.KIND_TINTS are.
## Alpha 0 means "no override", the same convention KIND_TINTS uses, so a colour
## on the map always means something is there. The hues echo KIND_TINTS so the
## cell matches the wash the player saw while standing in the room.
##
## Only ever applied to a room the player has been inside — an unexplored special
## is drawn as a plain green cell like any other, which is the model's doing, not
## this table's.
@export var kind_colors: Array[Color] = [
	Color(0, 0, 0, 0),                # NORMAL
	Color(0, 0, 0, 0),                # SPAWN
	Color(0.92, 0.26, 0.28, 1.0),     # BOSS
	Color(0.98, 0.80, 0.30, 1.0),     # SHOP
	Color(0.42, 0.68, 0.98, 1.0),     # TREASURE
	Color(0.40, 0.98, 0.62, 1.0),     # EXIT
]
## RoomData.KIND_GLYPHS with the two ordinary kinds blanked. ASCII on purpose:
## Godot's default font has no symbol glyphs and draws an empty box in their
## place — see the note in pause_menu.gd. Give SPAWN back its "S" if the room you
## started in is worth marking.
@export var kind_glyphs: Array[String] = ["", "", "B", "$", "T", "X"]
@export var marker_font_size: int = 7
@export var marker_alpha: float = 0.95

@export_group("Air critical")
## What the map fades to once the O2 letterbox starts closing over it. 0 takes it
## off screen entirely; raise it to about 0.25 to keep a ghost of it.
@export var critical_alpha: float = 0.0
@export var critical_fade_time: float = 0.6


## Centre-to-centre distance between neighbouring cells.
func pitch() -> Vector2:
	return cell_size + Vector2(cell_gap, cell_gap)


## The widget's size. A constant for a given style — it never depends on the
## floor in play, so it cannot give away how big that floor is.
func panel_size() -> Vector2:
	return Vector2(window_cells) * pitch() - Vector2(cell_gap, cell_gap) \
			+ Vector2(padding, padding) * 2.0
