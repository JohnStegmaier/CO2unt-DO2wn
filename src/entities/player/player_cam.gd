extends Camera2D
@onready var background = get_node("/root/Stage/background")
@onready var player = get_parent()
var camera_shift = 200
@export var slow_distance := 100.0
@export var movement_offset := 50.0
@export var follow_speed := 0.05
@export var min_speed_factor := 0.05
@export var walk_edge_inset := 10.0
@export var mouse_lead_weight := 0.6
@export var movement_lead_weight := 0.2
@export var lead_smoothing := 0.1  # how quickly the lead vector catches up (lower = smoother, laggier)

var current_lead := Vector2.ZERO

func _ready():
	zoom = Vector2(1.4,1.4)
	var texture_size = background.texture.get_size()
	limit_left = 0
	limit_top = 0
	limit_right = texture_size.x
	limit_bottom = texture_size.y

func _process(_delta):
	# movement-leading camera (based on player velocity)
	var move_lead = Vector2.ZERO
	if player.velocity.length() > 0:
		move_lead = player.velocity.normalized() * movement_offset

	# mouse-leading camera
	var mouse_distance = player.global_position.distance_to(player.get_global_mouse_position())
	var mouse_direction = player.global_position.direction_to(player.get_global_mouse_position())
	var mouse_offset = mouse_direction * min(mouse_distance, camera_shift) * 0.25

	# smooth the combined lead instead of snapping to it directly —
	# this prevents opposing move/mouse leads from causing frame-to-frame jitter
	var target_lead = (mouse_offset * mouse_lead_weight)
	current_lead = current_lead.lerp(target_lead, lead_smoothing)

	var walk_position = player.global_position + (move_lead * movement_lead_weight)
	var walk_target = clamp_to_inset(walk_position, walk_edge_inset)

	var target_position = walk_target + current_lead

	var move_dir = target_position - global_position
	var factor = get_wall_slowdown_factor(target_position, move_dir)

	global_position.x = lerp(global_position.x, target_position.x, follow_speed * factor.x)
	global_position.y = lerp(global_position.y, target_position.y, follow_speed * factor.y)

func clamp_to_inset(pos: Vector2, inset: float) -> Vector2:
	var half_size = get_viewport_rect().size / zoom / 2.0
	var min_x = limit_left + half_size.x + inset
	var max_x = limit_right - half_size.x - inset
	var min_y = limit_top + half_size.y + inset
	var max_y = limit_bottom - half_size.y - inset
	if min_x > max_x:
		var mid_x = (limit_left + limit_right) / 2.0
		min_x = mid_x
		max_x = mid_x
	if min_y > max_y:
		var mid_y = (limit_top + limit_bottom) / 2.0
		min_y = mid_y
		max_y = mid_y
	return Vector2(clamp(pos.x, min_x, max_x), clamp(pos.y, min_y, max_y))

func get_wall_slowdown_factor(target_pos: Vector2, move_dir: Vector2) -> Vector2:
	var half_size = get_viewport_rect().size / zoom / 2.0
	var dist_left = (target_pos.x - half_size.x) - limit_left
	var dist_right = limit_right - (target_pos.x + half_size.x)
	var dist_top = (target_pos.y - half_size.y) - limit_top
	var dist_bottom = limit_bottom - (target_pos.y + half_size.y)
	var factor_x = 1.0
	var factor_y = 1.0
	if move_dir.x > 0:
		factor_x = compute_axis_factor(dist_right)
	elif move_dir.x < 0:
		factor_x = compute_axis_factor(dist_left)
	if move_dir.y > 0:
		factor_y = compute_axis_factor(dist_bottom)
	elif move_dir.y < 0:
		factor_y = compute_axis_factor(dist_top)
	return Vector2(factor_x, factor_y)

func compute_axis_factor(dist: float) -> float:
	dist = max(dist, 0.0)
	if dist >= slow_distance:
		return 1.0
	var t = dist / slow_distance
	var smoothed = smoothstep(0.0, 1.0, t)
	return lerp(min_speed_factor, 1.0, smoothed)
