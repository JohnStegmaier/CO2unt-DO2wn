extends Camera2D

## Attach this to a Camera2D that is a CHILD of the player node.
## It reads the player's velocity for movement-lead and the mouse
## position for mouse-lead, then smoothly blends both into an offset.

@export_group("Target")
@export var player: CharacterBody2D  ## Assign in inspector, or it auto-finds get_parent()

@export_group("Movement Lead")
@export var movement_lead_amount: float = 20.0      ## Max pixels the camera shifts toward movement direction
@export var movement_lead_smoothing: float = 4.0    ## Higher = snappier response to velocity changes

@export_group("Mouse Lead")
@export var mouse_lead_amount: float = 90.0          ## Max pixels the camera shifts toward the mouse
@export var mouse_lead_deadzone: float = 40.0        ## Pixels from screen center before mouse-lead starts
@export var mouse_lead_smoothing: float = 8.0        ## Higher = snappier response to mouse movement

@export_group("Level Bounds")
## Set these to match your level (e.g. TileMap.get_used_rect() * cell size).
## We clamp manually because Camera2D's built-in limit_* properties are
## applied BEFORE offset is added, so movement/mouse lead can push the
## view past them — this clamps the final result instead.
@export var clamp_to_bounds: bool = true
@export var bounds_left: float = 0.0
@export var bounds_top: float = 0.0
@export var bounds_right: float = 2000.0
@export var bounds_bottom: float = 2000.0

var _movement_offset: Vector2 = Vector2.ZERO
var _mouse_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	if player == null:
		player = get_parent() as CharacterBody2D

	# We do our own exponential smoothing on the lead offsets below, so the
	# built-in smoothing is turned OFF. Leaving it on adds a second, separate
	# lag on top of ours — and since it's applied after our clamp, it was
	# letting the rendered view drift past the walls during fast movement.
	position_smoothing_enabled = false


func _process(delta: float) -> void:
	# Deliberately NOT _physics_process: the camera should update every
	# rendered frame, not every fixed physics tick. Reading player.velocity
	# and player.global_position here is fine since those values persist
	# between physics steps — this just smooths how often we react to them.
	if player == null:
		return

	_update_movement_lead(delta)
	_update_mouse_lead(delta)

	# Combine both leads. Mouse lead dominates because it has a larger
	# amount and higher smoothing responsiveness by default.
	var combined_offset: Vector2 = _movement_offset + _mouse_offset

	if clamp_to_bounds:
		combined_offset = _clamp_offset_to_bounds(combined_offset)

	# Setting local `position` directly (instead of the `offset` property)
	# means the camera's rendered position is EXACTLY player.global_position
	# + combined_offset, with nothing else applied afterward that could
	# push it back past the clamp.
	position = combined_offset


func _clamp_offset_to_bounds(desired_offset: Vector2) -> Vector2:
	# The camera's actual world-space view center is player position + offset.
	# We clamp THAT to stay within bounds_left/top/right/bottom, accounting
	# for half the viewport so the edge of the screen doesn't cross the wall.
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / zoom
	var world_center: Vector2 = player.global_position + desired_offset

	var clamped_center := Vector2(
		clamp(world_center.x, bounds_left + half_view.x, bounds_right - half_view.x),
		clamp(world_center.y, bounds_top + half_view.y, bounds_bottom - half_view.y)
	)

	return clamped_center - player.global_position


func _update_movement_lead(delta: float) -> void:
	var vel: Vector2 = player.velocity
	var target_offset := Vector2.ZERO

	if vel.length() > 1.0:
		target_offset = vel.normalized() * movement_lead_amount

	_movement_offset = _movement_offset.lerp(
		target_offset,
		1.0 - exp(-movement_lead_smoothing * delta)
	)


func _update_mouse_lead(delta: float) -> void:
	var viewport := get_viewport()
	var screen_center: Vector2 = viewport.get_visible_rect().size * 0.5
	var mouse_pos: Vector2 = viewport.get_mouse_position()

	var mouse_delta: Vector2 = mouse_pos - screen_center
	var dist: float = mouse_delta.length()

	var target_offset := Vector2.ZERO
	if dist > mouse_lead_deadzone:
		# Remap so the deadzone doesn't cause a sudden jump at the threshold.
		var strength: float = clamp((dist - mouse_lead_deadzone) / (screen_center.length() - mouse_lead_deadzone), 0.0, 1.0)
		target_offset = mouse_delta.normalized() * strength * mouse_lead_amount

	_mouse_offset = _mouse_offset.lerp(
		target_offset,
		1.0 - exp(-mouse_lead_smoothing * delta)
	)
