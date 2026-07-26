class_name Minimap
extends Control

## The floor, as much of it as the player has earned.
##
## Fills in as rooms are entered: the room you are in pulses, rooms you have
## walked get a solid outline, and rooms you have only seen the door of sit
## dotted and nearly blank until you go in.
##
## Two views of one map. A five-cell porthole rides the top-right corner and
## travels with the player, which is enough to know which way you came from
## without eating the screen. Holding the map button swaps it for a much larger
## panel in the middle showing everything found so far — and does NOT pause the
## game, so a long look costs air and invites getting shot.
##
## This node owns the single MinimapModel and hands it to both views, so the two
## can never disagree about what has been found. It owns the pulse for the same
## reason. Everything about how a map is drawn lives in minimap_view.gd, and
## everything about what may be drawn lives in minimap_model.gd; this file is the
## seam Game talks to and nothing else.

## Dev cheat: lift the fog and show the whole floor, kinds and all.
##
## Deliberately left unbound to any key. GameConfig is the natural driver now
## that it has landed — a [minimap] reveal_all key in a debug profile — but that
## is a wiring decision for whoever owns launch-time dev settings.
@export var reveal_all: bool = false:
	set(value):
		reveal_all = value
		_model.set_reveal_all(value)
		_redraw_views()

@export_group("Pulse")
## The current room's heartbeat. Lives here rather than on MinimapStyle because a
## pulse rate is a property of the map, not of a skin — two styles with two
## periods would be the two views drifting apart, written down as data.
@export var blink_period: float = 1.4
## Steps in one pulse. Doubles as the redraw throttle: the views only redraw when
## the step changes, so 12 is about nine redraws a second rather than sixty. A
## stepped pulse also reads as deliberate at this resolution, where a smooth fade
## has too few pixels to be smooth in.
@export var blink_steps: int = 12

## The peek. Held, not toggled: a map you have to hold open is a map you cannot
## forget you left open while the air runs out.
##
## Polled rather than handled as an event, which is not the usual instinct. A
## hold is a STATE and events only report edges — hold the button, open the pause
## menu, release it while the tree is frozen, and the release is never delivered
## (this node's process_mode inherits, so it stops with the game), leaving the map
## stuck open on resume. Polling has no such hole, and the project already polls
## for held input in player.gd, game_over.gd and main_menu.gd. What is given up is
## set_input_as_handled(), and nothing else in project.godot binds Tab or LB.
##
## Godot's built-in ui_focus_next is also on Tab. Nothing in this project has a
## focusable Control today so both firing costs nothing, but a real Button in a
## menu would take focus behind the map.
const PEEK_ACTION := "show_map"

## Built here rather than in _ready because an exported setter fires while the
## scene is still being instantiated — reveal_all would otherwise write to a
## model that does not exist yet.
var _model := MinimapModel.new()

var _blink_time: float = 0.0
var _blink_step: int = -1
var _peeking: bool = false
## push_warning once per floor at most, not once per frame.
var _warned_oversized: bool = false

@onready var _scrim: ColorRect = $Scrim
@onready var _corner_view: MinimapView = $CornerView
@onready var _full_view: MinimapView = $FullView


func _ready() -> void:
	# This node is the full screen so the scrim can be, so it must not swallow
	# clicks — left click is the fire button. Note the scrim needs its own: a
	# Control's children are hit-tested independently of their parent's filter.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_on_visibility_changed)

	_corner_view.set_model(_model)
	_full_view.set_model(_model)
	# The exported setter ran before this node was ready, so let the model catch
	# up on a reveal flag the scene may have set.
	_model.set_reveal_all(reveal_all)
	_apply_peek()


## Point the map at a floor. Pass null when the floor is thrown away, so the
## model does not sit holding the dead plan alive.
func show_floor(plan: FloorPlan) -> void:
	_model.set_floor(plan)
	_warned_oversized = false
	if plan != null:
		_warn_if_oversized(plan)
	_redraw_views()


## The player is now in this room. Reveals its unexplored neighbours, drops the
## room they left back to a plain explored cell, and starts this one pulsing.
func set_current_room(coord: Vector2i) -> void:
	_model.set_current(coord)
	_redraw_views()


func set_reveal_all(reveal: bool) -> void:
	reveal_all = reveal


## Fade the corner map down while the O2 letterbox slides over the corner it
## occupies. Wired to O2Timer.air_critical_changed in Game._ready.
##
## The corner only. The full panel is centred, clear of both bars, and is the one
## thing the player deliberately reached for — taking it away under the same
## signal would remove the map at the exact moment they asked for it. The side
## effect is a good one: with the air critical the corner map has faded out, so
## peeking becomes the only way to read the floor in the last few seconds.
func set_dimmed(dim: bool) -> void:
	_corner_view.set_dimmed(dim)


## Poll the peek, then advance the pulse. Quantised so the views redraw about
## nine times a second instead of sixty.
func _process(delta: float) -> void:
	_set_peeking(Input.is_action_pressed(PEEK_ACTION))

	var period: float = maxf(blink_period, 0.001)
	var steps: int = maxi(blink_steps, 1)
	_blink_time = fmod(_blink_time + delta, period)
	var step: int = int(_blink_time / period * steps)
	if step == _blink_step:
		return
	_blink_step = step
	var phase: float = float(step) / float(steps)
	_corner_view.set_blink_phase(phase)
	_full_view.set_blink_phase(phase)


func _set_peeking(peeking: bool) -> void:
	if peeking == _peeking:
		return
	_peeking = peeking
	_apply_peek()


## The corner map goes away rather than sitting alongside the full one: the same
## rooms twice at two scales is two things to read, and the panel it would sit on
## top of is the one the player asked for.
func _apply_peek() -> void:
	_corner_view.visible = not _peeking
	_full_view.visible = _peeking
	_scrim.visible = _peeking


## Godot sends this when the tree pauses under this node. _process stops with it,
## so a peek held into a pause would otherwise sit frozen on screen behind the
## pause menu until the game resumed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_set_peeking(false)


## A floor too big for the grid would be drawn with its far rooms clipped off.
## The generator's depth cap makes that impossible today — check_minimap.gd
## asserts it over a thousand floors — so this is here to complain loudly if
## max_depth is ever raised without widening window_cells.
##
## Checked against the full panel alone. The corner porthole is five cells wide
## and clips by design; warning about that would fire on every floor.
##
## bounds() is safe to read HERE and nowhere else in the minimap: it decides
## whether to print a warning, never what to draw or how big to be. The views
## never see a FloorPlan at all.
func _warn_if_oversized(plan: FloorPlan) -> void:
	if _warned_oversized:
		return
	var window: Vector2i = _full_view.window_cells()
	var size: Vector2i = plan.bounds().size
	if size.x <= window.x and size.y <= window.y:
		return
	_warned_oversized = true
	push_warning("Minimap: floor is %v cells but the full map draws %v — rooms will be clipped" \
			% [size, window])


## Both views, always — a redraw on the hidden one is nearly free, and skipping it
## would mean the map you peek at was built from whatever was true last time it
## happened to be visible.
##
## Guarded because the reveal_all setter fires while the scene is still being
## instantiated, before the child references resolve. _ready redraws once the
## model is handed down.
func _redraw_views() -> void:
	if not is_node_ready():
		return
	_corner_view.queue_redraw()
	_full_view.queue_redraw()


## Godot skips _draw for a hidden CanvasItem but keeps calling _process, and the
## death sequence hides the whole HUD.
func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())
