extends Node2D

@export var total_time: float = 15 # starting time in seconds
var time_left: float
@onready var label: Label = $Label
@onready var needle: Sprite2D = $Needle
@onready var top_border: ColorRect = $Top_Border
@onready var bottom_border: ColorRect = $Bottom_Border

var setup_done = false
var degrees = 90

var borders_shown = false

var top_border_start_pos: Vector2
var top_border_end_pos: Vector2
var bottom_border_start_pos: Vector2
var bottom_border_end_pos: Vector2

var low_time = Color(1.0, 0.0, 0.055, 1.0)
var med_time = Color(1.0, 0.451, 0.0, 1.0)
var high_time = Color(0.667, 0.947, 1.003, 1.0)

const NEEDLE_MAX_TIME := 180.0  # 3 minutes, in seconds
const FLICK_DEGREES := 15.0  # how far the flick swings past the current position
const FLICK_DURATION := 0.10  # seconds for the flick out, same again for return

func setup():
	if setup_done:
		return
	await get_tree().create_timer(0.3).timeout
	time_left = total_time
	update_label()
	setup_done = true

func _ready() -> void:
		needle.rotation_degrees = degrees
		GlobalTimer.tick.connect(setup)
		GlobalTimer.tick.connect(flick_needle)
		
	
		top_border_end_pos = top_border.position
		top_border_start_pos = top_border_end_pos + Vector2(0, -top_border.size.y)
		top_border.position = top_border_start_pos
		
		bottom_border_end_pos = bottom_border.position
		bottom_border_start_pos = bottom_border_end_pos + Vector2(0, bottom_border.size.y)
		bottom_border.position = bottom_border_start_pos
	
func _process(delta: float) -> void:
	if not setup_done:
		return
	if time_left > 0:
		time_left -= delta
		time_left = max(time_left, 0)
		update_label()
		update_needle()
		
	if time_left <= 11.0 and not borders_shown:
		slide_in_borders()
		borders_shown = true
	
	
func update_label() -> void:
	update_label_color()
	if time_left < 10:
		var seconds: float = time_left
		label.text = "%05.2f" % seconds
	else:
		var minutes := int(time_left) / 60
		var seconds := int(time_left) % 60
		label.text = "%d:%02d" % [minutes, seconds]
		
func update_label_color():
	if time_left < 10:
		label.modulate = low_time
	elif time_left < 31:
		var t: float = (time_left - 10.0) / 20.0
		label.modulate = low_time.lerp(med_time,t)
	else:
		label.modulate = high_time
		
func update_needle() -> void:
	var clamped_time: float = clamp(time_left, 0.0, NEEDLE_MAX_TIME)
	degrees = remap(clamped_time, 0.0, NEEDLE_MAX_TIME, 0.0, 180.0)
	needle.rotation_degrees = degrees
	
func flick_needle() -> void:
	await get_tree().create_timer(0.3).timeout
	var base_degrees := needle.rotation_degrees
	var tween := create_tween()
	tween.tween_property(needle, "rotation_degrees", base_degrees + FLICK_DEGREES, FLICK_DURATION)
	tween.tween_property(needle, "rotation_degrees", base_degrees, FLICK_DURATION).set_ease(Tween.EASE_OUT)

func slide_in_borders() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(top_border, "position", top_border_end_pos, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(bottom_border, "position", bottom_border_end_pos, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
