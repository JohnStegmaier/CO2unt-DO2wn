class_name MinimapView
extends Control

## One window onto the floor. Draws what the model allows and nothing else.
##
## Two of these are on screen: a five-cell porthole in the corner that travels
## with the player, and a thirteen-cell panel in the middle of the screen that
## appears while the map button is held. They differ only in the style they are
## handed and which coordinate they centre on — every rule about what may be
## drawn lives in minimap_model.gd, and this file never sees a FloorPlan at all.
##
## The panel's size comes from the style and never from the floor in play. That
## is the property that keeps the map quiet about how much is left to find, and
## it is why nothing here may ever call FloorPlan.bounds(): a panel that grew to
## fit would announce the floor's shape before the player had walked a step of it.
##
## This is the project's first _draw() widget. Nodes were the obvious first
## instinct and are wrong here: 169 cells of fill, outline and glyph is several
## hundred nodes to rebuild every time the player walks through a door, a dotted
## outline as ColorRects is a dozen rects per edge, and re-skinning the map from
## a swapped MinimapStyle would mean walking that whole tree instead of calling
## queue_redraw(). ColorRect-as-placeholder is still the house style for
## placeholder art; this is not placeholder art.

## Where the panel sits. Placement is data rather than anchors baked into the
## scene, so moving a view is one value here and nothing else has to know.
@export_enum("top_left", "top_right", "bottom_left", "bottom_right", "centre") var placement: int = 1:
	set(value):
		placement = value
		_apply_placement()
@export var margin: Vector2 = Vector2(8, 8):
	set(value):
		margin = value
		_apply_placement()

## Every colour and dimension. Swap the whole resource to re-skin this view.
##
## One per view, never shared: the corner porthole and the full panel are two
## skins of the same map, and a shared resource would mean tuning one retunes
## the other.
@export var style: MinimapStyle:
	set(value):
		style = value
		_apply_placement()
		queue_redraw()

## Which coordinate the grid is centred on.
##
## Spawn for the full panel, so its contents are nailed in place and a room keeps
## the same cell for a whole floor. The player's room for the corner porthole,
## which is only five cells wide and has to travel to be any use.
##
## Plain int rather than a typed enum, like Kind and Side — see the note in
## grid_direction.gd.
@export_enum("spawn", "player") var focus: int = 1

const PLACEMENT_ANCHORS: Array[Vector2] = [
	Vector2(0, 0),
	Vector2(1, 0),
	Vector2(0, 1),
	Vector2(1, 1),
	Vector2(0.5, 0.5),
]

const FOCUS_SPAWN := 0
const FOCUS_PLAYER := 1

## Handed down by the coordinator. Both views read the same one, so the fog can
## never disagree between them.
var _model: MinimapModel

## Pushed in by the coordinator rather than accumulated here, so the two views
## pulse together. A hidden CanvasItem stops processing, so a per-view timer
## would freeze while hidden and come back out of step every time you peeked.
var _blink_phase: float = 0.0

var _dim_tween: Tween


func _ready() -> void:
	# Belt and braces: the scene supplies a style, but a view dropped into
	# another scene without one should still draw rather than crash. Same
	# argument as the FloorConfig fallback in game.gd.
	if style == null:
		style = MinimapStyle.new()
	# Left-click is the fire button. A Control at MOUSE_FILTER_STOP would eat
	# every shot aimed through the patch of screen it covers — which for the
	# full panel is the middle of the room, while the game is still running.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The porthole shows five cells of a floor up to twelve across. Clipping is
	# not a safety net here, it is the design.
	clip_contents = true
	# The exported setters ran before this node was ready, so their placement
	# calls bailed out.
	_apply_placement()


func set_model(model: MinimapModel) -> void:
	_model = model
	queue_redraw()


func set_blink_phase(phase: float) -> void:
	if is_equal_approx(phase, _blink_phase):
		return
	_blink_phase = phase
	queue_redraw()


## Fade this view down while the O2 letterbox slides over the corner it occupies.
## Only the corner view is wired to it — see Minimap.set_dimmed.
func set_dimmed(dim: bool) -> void:
	if _dim_tween != null and _dim_tween.is_valid():
		_dim_tween.kill()
	var target: float = style.critical_alpha if dim else 1.0
	_dim_tween = create_tween()
	_dim_tween.tween_property(self, "modulate:a", target, style.critical_fade_time) \
			.set_trans(Tween.TRANS_SINE)


## The grid this view draws, so the coordinator can size-check a floor against
## the biggest window on offer without reaching into the style resource itself.
func window_cells() -> Vector2i:
	return style.window_cells if style != null else Vector2i.ZERO


func _draw() -> void:
	if _model == null:
		return

	var panel := Rect2(Vector2.ZERO, style.panel_size())
	if style.panel_color.a > 0.0:
		draw_rect(panel, style.panel_color, true)
	if style.panel_border_color.a > 0.0:
		draw_rect(panel, style.panel_border_color, false, style.outline_width)

	# Doors first, so a cell's fill and outline sit on top of the stub rather
	# than the stub cutting across the room it leads out of.
	_draw_doors()

	# One buffer for every dotted outline on the panel, emitted in a single call
	# below. They can all share it because dots are never recoloured by room kind
	# — an unexplored room reports NO_MARKER by definition, so there is no kind
	# to colour them with.
	var dots := PackedVector2Array()
	for coord in _model.visible_coords():
		_draw_cell(coord, dots)
	if not dots.is_empty():
		draw_multiline(dots, style.discovered_outline_color, style.outline_width)


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


func _draw_cell(coord: Vector2i, dots: PackedVector2Array) -> void:
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
			# Dotted, which is the whole tell: this one has not been walked into.
			_append_dots(dots, rect)

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


## Perimeter dots for one unexplored cell, appended to the panel's shared buffer.
## draw_multiline reads it in pairs, so every dot is two points.
##
## Dots rather than dashes. A gap in a dashed outline falls exactly where a door
## stub would and reads as an opening — the one characteristic an unexplored room
## must not appear to have, since the whole point is that nothing about it is
## known yet. Dots are plainly a texture and cannot be mistaken for a feature.
##
## Inset by half the stroke: Godot draws an unfilled draw_rect INSIDE the rect
## while draw_line centres the stroke on it, so without this the dotted outline
## would sit half a pixel outside where the explored rooms' solid outlines sit and
## the two states would look like slightly different sizes.
func _append_dots(into: PackedVector2Array, rect: Rect2) -> void:
	var inner: Rect2 = rect.grow(-style.outline_width * 0.5)
	var period: float = maxf(style.dot_length + style.dot_gap, 0.5)

	var x: float = inner.position.x
	while x < inner.end.x:
		var run: float = minf(style.dot_length, inner.end.x - x)
		into.append(Vector2(x, inner.position.y))
		into.append(Vector2(x + run, inner.position.y))
		into.append(Vector2(x, inner.end.y))
		into.append(Vector2(x + run, inner.end.y))
		x += period

	# Starts one period down and stops one dot short, so the corners the two
	# horizontal edges have already laid down are not drawn over a second time.
	# A doubled dot at one pixel is visibly darker than its neighbours.
	var y: float = inner.position.y + period
	while y < inner.end.y - style.dot_length:
		var run: float = minf(style.dot_length, inner.end.y - y)
		into.append(Vector2(inner.position.x, y))
		into.append(Vector2(inner.position.x, y + run))
		into.append(Vector2(inner.end.x, y))
		into.append(Vector2(inner.end.x, y + run))
		y += period


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
	return lerpf(style.current_alpha_min, style.current_alpha_max, \
			0.5 - 0.5 * cos(TAU * _blink_phase))


## What the grid is centred on. Resolved here on every draw rather than cached:
## origin_coord() falls back to zero with no floor and current_coord() keeps the
## last floor's value after the map is blanked, neither of which matters only
## because nothing is drawn in that state — and that stays true only if it is
## asked fresh each time.
func _focus_coord() -> Vector2i:
	if focus == FOCUS_SPAWN:
		return _model.origin_coord()
	return _model.current_coord()


## Where a room's cell lands, measured out from the focus room at the centre of
## the grid. Cells outside the window fall outside the panel and are clipped,
## which is how a five-cell porthole shows a twelve-cell floor.
func _cell_rect(coord: Vector2i) -> Rect2:
	var pitch: Vector2 = style.pitch()
	var centre: Vector2 = Vector2(style.padding, style.padding) \
			+ Vector2(style.window_cells - Vector2i.ONE) * 0.5 * pitch
	return Rect2(centre + Vector2(coord - _focus_coord()) * pitch, style.cell_size)


func _apply_placement() -> void:
	# Exported setters fire before the node is ready; _ready calls this again.
	if not is_node_ready() or style == null:
		return
	var panel: Vector2 = style.panel_size()
	var anchor: Vector2 = PLACEMENT_ANCHORS[placement]
	anchor_left = anchor.x
	anchor_right = anchor.x
	anchor_top = anchor.y
	anchor_bottom = anchor.y

	var top_left := Vector2(
		_edge_offset(anchor.x, margin.x, panel.x),
		_edge_offset(anchor.y, margin.y, panel.y),
	)
	# Rounded because the centred branch halves the panel, and an odd panel would
	# otherwise put every rect on a half pixel and smear the whole map.
	top_left = top_left.round()
	offset_left = top_left.x
	offset_top = top_left.y
	offset_right = top_left.x + panel.x
	offset_bottom = top_left.y + panel.y


## Distance from the anchor to the panel's near edge on one axis. Margin pushes
## away from the edge the view is pinned to, and for a centred view it is a plain
## nudge — which is what lets the full panel sit slightly low to clear the O2
## gauge without giving up being centred.
func _edge_offset(anchor: float, edge_margin: float, extent: float) -> float:
	if anchor == 0.0:
		return edge_margin
	if anchor == 1.0:
		return -(edge_margin + extent)
	return -extent * 0.5 + edge_margin
