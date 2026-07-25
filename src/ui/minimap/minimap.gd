class_name Minimap
extends Control

## The floor, as much of it as the player has earned.
##
## Fills in as rooms are entered: the room you are in pulses, rooms you have
## walked get a solid outline, and rooms you have only seen the door of sit
## dashed and nearly blank until you go in. What is allowed on screen is decided
## entirely by minimap_model.gd — this file draws what it is handed and never
## reaches for the FloorPlan itself.
##
## The grid is 13x13 cells centred on the spawn room, which is wide enough for
## any floor the generator can build (FloorConfig.max_depth is 6, so nothing is
## ever further than six rooms out). Because that size is a constant rather than
## a measurement of the floor in play, a room keeps the same cell for the whole
## floor — the map never scrolls, slides or rescales — and the panel gives away
## nothing about how much is left to find. Never lay this out from
## FloorPlan.bounds(): a panel that grew to fit would announce the floor's shape
## before the player had walked a step of it.
##
## This is the project's first _draw() widget. Nodes were the obvious first
## instinct and are wrong here: 169 cells of fill, outline and glyph is several
## hundred nodes to rebuild every time the player walks through a door, a dashed
## outline as ColorRects is a dozen rects per edge, and re-skinning the map from
## a swapped MinimapStyle would mean walking that whole tree instead of calling
## queue_redraw(). ColorRect-as-placeholder is still the house style for
## placeholder art; this is not placeholder art.

## Which corner the map lives in, and how far off it. Placement is data rather
## than anchors baked into the scene, so moving the map is one value here and
## nothing else has to know.
@export_enum("top_left", "top_right", "bottom_left", "bottom_right") var corner: int = 1:
	set(value):
		corner = value
		_apply_placement()
@export var margin: Vector2 = Vector2(8, 8):
	set(value):
		margin = value
		_apply_placement()

## Every colour and dimension. Swap the whole resource to re-skin the map.
@export var style: MinimapStyle:
	set(value):
		style = value
		_apply_placement()
		queue_redraw()

## Dev cheat: lift the fog and show the whole floor, kinds and all.
##
## Deliberately left unbound — there is no key for it and project.godot is
## untouched. Whatever ends up owning launch-time dev settings should drive
## set_reveal_all(); until then this is a checkbox in the inspector.
@export var reveal_all: bool = false:
	set(value):
		reveal_all = value
		_model.set_reveal_all(value)
		queue_redraw()

const CORNER_ANCHORS: Array[Vector2] = [
	Vector2(0, 0),
	Vector2(1, 0),
	Vector2(0, 1),
	Vector2(1, 1),
]

## Built here rather than in _ready because an exported setter fires while the
## scene is still being instantiated — reveal_all would otherwise write to a
## model that does not exist yet.
var _model := MinimapModel.new()

var _blink_time: float = 0.0
var _blink_step: int = -1
var _dim_tween: Tween
## push_warning once per floor at most, not once per frame.
var _warned_oversized: bool = false


func _ready() -> void:
	# Belt and braces: the scene supplies a style, but a Minimap dropped into
	# another scene without one should still draw rather than crash. Same
	# argument as the FloorConfig fallback in game.gd.
	if style == null:
		style = MinimapStyle.new()
	# Left-click is the fire button. A Control at MOUSE_FILTER_STOP would eat
	# every shot aimed through the corner it sits in.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	visibility_changed.connect(_on_visibility_changed)
	# The exported setters ran before this node was ready, so their placement
	# calls bailed out. Apply it now, and let the model catch up on a reveal
	# flag the scene may have set.
	_apply_placement()
	_model.set_reveal_all(reveal_all)


## Point the map at a floor. Pass null when the floor is thrown away, so the
## model does not sit holding the dead plan alive.
func show_floor(plan: FloorPlan) -> void:
	_model.set_floor(plan)
	_warned_oversized = false
	if plan != null:
		_warn_if_oversized(plan)
	queue_redraw()


## The player is now in this room. Reveals its unexplored neighbours, drops the
## room they left back to a plain explored cell, and starts this one pulsing.
func set_current_room(coord: Vector2i) -> void:
	_model.set_current(coord)
	queue_redraw()


func set_reveal_all(reveal: bool) -> void:
	reveal_all = reveal


## Fade the map down while the O2 letterbox slides over the corner it occupies.
## Wired to O2Timer.air_critical_changed in Game._ready.
func set_dimmed(dim: bool) -> void:
	if _dim_tween != null and _dim_tween.is_valid():
		_dim_tween.kill()
	var target: float = style.critical_alpha if dim else 1.0
	_dim_tween = create_tween()
	_dim_tween.tween_property(self, "modulate:a", target, style.critical_fade_time) \
			.set_trans(Tween.TRANS_SINE)


## The pulse. Quantised so the map redraws about nine times a second instead of
## sixty, which is both the throttle and the look — a stepped pulse holds its
## shape at this resolution where a smooth fade has too few pixels to work with.
func _process(delta: float) -> void:
	var period: float = maxf(style.blink_period, 0.001)
	_blink_time = fmod(_blink_time + delta, period)
	var step: int = int(_blink_time / period * maxi(style.blink_steps, 1))
	if step == _blink_step:
		return
	_blink_step = step
	queue_redraw()


func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, style.panel_size())
	if style.panel_color.a > 0.0:
		draw_rect(panel, style.panel_color, true)
	if style.panel_border_color.a > 0.0:
		draw_rect(panel, style.panel_border_color, false, style.outline_width)

	# Doors first, so a cell's fill and outline sit on top of the stub rather
	# than the stub cutting across the room it leads out of.
	_draw_doors()
	for coord in _model.visible_coords():
		_draw_cell(coord)


func _draw_doors() -> void:
	for coord in _model.visible_coords():
		# Zero for a room the player has only glimpsed, so a stub is only ever
		# drawn out of somewhere they have stood — nothing here is news to them.
		var doors: int = _model.door_mask_at(coord)
		if doors == 0:
			continue
		for side in GridDirection.SIDES:
			if (doors & GridDirection.bit(side)) == 0:
				continue
			var neighbour: Vector2i = coord + GridDirection.offset(side)
			# Only between two cells that are both on the map. A stub reaching
			# off into the dark would mark a room the player has not found.
			if _model.state_at(neighbour) == MinimapModel.State.UNKNOWN:
				continue
			# Drawn once per pair, deferring to the east or south end. Only when
			# that end can actually draw it, mind: a room the player has merely
			# glimpsed reports no doors at all, so deferring to one would lose
			# the stub entirely and leave the cell floating unattached.
			if (side == GridDirection.Side.WEST or side == GridDirection.Side.NORTH) \
					and _model.door_mask_at(neighbour) != 0:
				continue
			# A stub bridging the gap, not a line between the two centres — a
			# centre-to-centre line draws a cross through every room it links.
			var midpoint: Vector2 = (_cell_rect(coord).get_center() \
					+ _cell_rect(neighbour).get_center()) * 0.5
			var axis := Vector2(GridDirection.offset(side))
			var reach: float = style.cell_gap * 0.5 + style.door_overhang
			draw_line(midpoint - axis * reach, midpoint + axis * reach, \
					style.door_color, style.door_width)


func _draw_cell(coord: Vector2i) -> void:
	var state: int = _model.state_at(coord)
	var rect: Rect2 = _cell_rect(coord)
	# NO_MARKER for anything the player has not walked into, so an unexplored
	# boss room is coloured and lettered exactly like an unexplored broom
	# cupboard. The refusal is the model's; all this does is honour it.
	var kind: int = _model.marker_at(coord)

	match state:
		MinimapModel.State.CURRENT:
			var pulse: Color = style.current_color
			pulse.a = _blink_alpha()
			draw_rect(rect, _recolour(pulse, kind), true)
		MinimapModel.State.VISITED:
			draw_rect(rect, _recolour(style.visited_fill_color, kind), true)
			draw_rect(rect, _recolour(style.visited_outline_color, kind), false, style.outline_width)
		MinimapModel.State.DISCOVERED:
			draw_rect(rect, style.discovered_fill_color, true)
			# Dashed, which is the whole tell: this one has not been walked into.
			_draw_dashed_rect(rect, style.discovered_outline_color, style.outline_width, style.dash_length)

	_draw_marker(rect, kind)


## The room's letter, for the kinds worth marking. Reuses RoomData's glyph
## vocabulary via MinimapStyle.kind_glyphs, so the tag on the map is the tag in
## the terminal dump.
func _draw_marker(rect: Rect2, kind: int) -> void:
	if kind == MinimapModel.NO_MARKER or kind >= style.kind_glyphs.size():
		return
	var glyph: String = style.kind_glyphs[kind]
	if glyph.is_empty():
		return

	var font: Font = get_theme_default_font()
	if font == null:
		return
	var size: int = style.marker_font_size
	var width: float = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	# draw_string takes a baseline, not a top-left corner.
	var baseline: float = (font.get_ascent(size) - font.get_descent(size)) * 0.5
	var colour: Color = _recolour(Color.WHITE, kind)
	colour.a = style.marker_alpha
	var origin: Vector2 = (rect.get_center() + Vector2(-width * 0.5, baseline)).round()
	draw_string(font, origin, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, colour)


## Godot draws no dashed rect, so it is four dashed lines. Wound as a closed
## loop rather than four independent edges so the dashes meet at the corners.
func _draw_dashed_rect(rect: Rect2, colour: Color, width: float, dash: float) -> void:
	var top_right := Vector2(rect.end.x, rect.position.y)
	var bottom_left := Vector2(rect.position.x, rect.end.y)
	draw_dashed_line(rect.position, top_right, colour, width, dash)
	draw_dashed_line(top_right, rect.end, colour, width, dash)
	draw_dashed_line(rect.end, bottom_left, colour, width, dash)
	draw_dashed_line(bottom_left, rect.position, colour, width, dash)


## Take a special room's hue but keep the state's alpha, so an explored boss room
## is still the faint wash an explored room should be — only green becomes red.
## Kinds with a zero-alpha entry are left alone, the convention Room.KIND_TINTS
## already uses.
func _recolour(base: Color, kind: int) -> Color:
	if kind == MinimapModel.NO_MARKER or kind >= style.kind_colors.size():
		return base
	var tint: Color = style.kind_colors[kind]
	if tint.a == 0.0:
		return base
	return Color(tint.r, tint.g, tint.b, base.a)


func _blink_alpha() -> float:
	var phase: float = float(maxi(_blink_step, 0)) / float(maxi(style.blink_steps, 1))
	return lerpf(style.current_alpha_min, style.current_alpha_max, 0.5 - 0.5 * cos(TAU * phase))


## Where a room's cell lands, measured out from the spawn room at the centre of
## the grid. The floor in play never enters into it, which is what keeps the map
## still and keeps it quiet about what has not been found.
func _cell_rect(coord: Vector2i) -> Rect2:
	var pitch: Vector2 = style.pitch()
	var centre: Vector2 = Vector2(style.padding, style.padding) \
			+ Vector2(style.window_cells - Vector2i.ONE) * 0.5 * pitch
	return Rect2(centre + Vector2(coord - _model.origin_coord()) * pitch, style.cell_size)


## A floor too big for the grid would be drawn with its far rooms clipped off.
## The generator's depth cap makes that impossible today — check_minimap.gd
## asserts it over a thousand floors — so this is here to complain loudly if
## max_depth is ever raised without widening window_cells.
##
## bounds() is safe to read HERE and nowhere else in this file: it decides
## whether to print a warning, never what to draw or how big to be.
func _warn_if_oversized(plan: FloorPlan) -> void:
	if _warned_oversized:
		return
	var size: Vector2i = plan.bounds().size
	if size.x <= style.window_cells.x and size.y <= style.window_cells.y:
		return
	_warned_oversized = true
	push_warning("Minimap: floor is %v cells but the map draws %v — rooms will be clipped" \
			% [size, style.window_cells])


## Godot skips _draw for a hidden CanvasItem but keeps calling _process, and the
## death sequence hides the whole HUD.
func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())


func _apply_placement() -> void:
	# Exported setters fire before the node is ready; _ready calls this again.
	if not is_node_ready() or style == null:
		return
	var panel: Vector2 = style.panel_size()
	var anchor: Vector2 = CORNER_ANCHORS[corner]
	anchor_left = anchor.x
	anchor_right = anchor.x
	anchor_top = anchor.y
	anchor_bottom = anchor.y
	offset_left = margin.x if anchor.x == 0.0 else -(margin.x + panel.x)
	offset_top = margin.y if anchor.y == 0.0 else -(margin.y + panel.y)
	offset_right = offset_left + panel.x
	offset_bottom = offset_top + panel.y
