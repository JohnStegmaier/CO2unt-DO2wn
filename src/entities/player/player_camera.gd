extends Camera2D

## Attach this to a Camera2D that is a CHILD of the player node.
## It reads the player's velocity for movement-lead and where they are aiming
## for aim-lead, then smoothly blends both into an offset.

@export_group("Target")
@export var player: Player  ## Assign in inspector, or it auto-finds get_parent()

@export_group("Movement Lead")
@export var movement_lead_amount: float = 20.0      ## Max pixels the camera shifts toward movement direction
@export var movement_lead_smoothing: float = 2.0    ## Higher = snappier response to velocity changes

@export_group("Aim Lead")
@export var aim_lead_amount: float = 90.0            ## Max pixels the camera shifts toward where you aim
@export var aim_lead_deadzone: float = 40.0          ## Pixels from screen center before mouse aim-lead starts
@export var aim_lead_smoothing: float = 3.5          ## Higher = snappier response to aim changes

@export_group("Level Bounds")
## Set these to match your level (e.g. TileMap.get_used_rect() * cell size).
## We clamp manually because Camera2D's built-in limit_* properties are
## applied BEFORE offset is added, so movement/mouse lead can push the
## view past them — this clamps the final result instead.
@export var clamp_to_bounds: bool = true
@export var bounds_left: float = 0.0
@export var bounds_top: float = 90.0
@export var bounds_right: float = 2000.0
@export var bounds_bottom: float = 2000.0

var _movement_offset: Vector2 = Vector2.ZERO
var _aim_offset: Vector2 = Vector2.ZERO
var _lead_enabled: bool = true


## Suppress movement and aim lead, so a room transition reads as a clean slide
## rather than a slide with a wandering offset riding on top of it.
func set_lead_enabled(enabled: bool) -> void:
	_lead_enabled = enabled


## Clamp the view to a room. Called on every room change, because the camera
## outlives the room it is looking at.
func set_bounds(rect: Rect2) -> void:
	bounds_left = rect.position.x
	bounds_top = rect.position.y
	bounds_right = rect.end.x
	bounds_bottom = rect.end.y


func _ready() -> void:
	if player == null:
		player = get_parent() as Player

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

	if _lead_enabled:
		_update_movement_lead(delta)
		_update_aim_lead(delta)
	else:
		# Ease the lead out instead of zeroing it. Snapping a 90px offset to
		# zero would be exactly the jolt the transition is meant to avoid.
		_movement_offset = _movement_offset.lerp(Vector2.ZERO, 1.0 - exp(-movement_lead_smoothing * delta))
		_aim_offset = _aim_offset.lerp(Vector2.ZERO, 1.0 - exp(-aim_lead_smoothing * delta))

	# Combine both leads. Mouse lead dominates because it has a larger
	# amount and higher smoothing responsiveness by default.
	var combined_offset: Vector2 = _movement_offset + _aim_offset

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
		_clamp_axis(world_center.x, bounds_left, bounds_right, half_view.x),
		_clamp_axis(world_center.y, bounds_top, bounds_bottom, half_view.y)
	)

	return clamped_center - player.global_position


## Clamp one axis so the screen edge stops at the wall.
##
## When the view is larger than the room there is no valid range — the minimum
## overruns the maximum and clamp() degenerates, pinning the camera to a corner
## and showing the void past the room. Centre on the room instead.
func _clamp_axis(value: float, low: float, high: float, half_view: float) -> float:
	if low + half_view > high - half_view:
		return (low + high) * 0.5
	return clamp(value, low + half_view, high - half_view)


func _update_movement_lead(delta: float) -> void:
	var vel: Vector2 = player.velocity
	var target_offset := Vector2.ZERO

	if vel.length() > 1.0:
		target_offset = vel.normalized() * movement_lead_amount

	_movement_offset = _movement_offset.lerp(
		target_offset,
		1.0 - exp(-movement_lead_smoothing * delta)
	)


func _update_aim_lead(delta: float) -> void:
	# Each device needs its own strength curve. A cursor's strength is how far it
	# sits from the centre of the screen; a stick's is how hard it is pushed.
	# Reading the cursor on a gamepad would peg the lead to wherever the pointer
	# was abandoned and never move it again.
	var target_offset: Vector2 = _gamepad_lead() if player.aiming_with_gamepad else _mouse_lead()

	_aim_offset = _aim_offset.lerp(
		target_offset,
		1.0 - exp(-aim_lead_smoothing * delta)
	)


func _gamepad_lead() -> Vector2:
	return player.gun_direction * player.aim_deflection * aim_lead_amount


func _mouse_lead() -> Vector2:
	var viewport := get_viewport()
	var screen_center: Vector2 = viewport.get_visible_rect().size * 0.5
	var mouse_delta: Vector2 = viewport.get_mouse_position() - screen_center
	var dist: float = mouse_delta.length()

	if dist <= aim_lead_deadzone:
		return Vector2.ZERO

	# Remap so the deadzone doesn't cause a sudden jump at the threshold.
	var strength: float = clamp((dist - aim_lead_deadzone) / (screen_center.length() - aim_lead_deadzone), 0.0, 1.0)
	return mouse_delta.normalized() * strength * aim_lead_amount
