class_name O2Timer
extends Node2D

## The countdown, and the player's health bar — they are the same thing. Damage
## does not come off a hit point pool, it comes off the clock, so this script
## owns the conversion from a hit to a cost in air.

## Out of oxygen. Fires once.
signal depleted

@export var total_time: float = 90 # starting time in seconds
var time_left: float

## How fast air is spent, as a multiplier on real time. Piercing damage tears the
## suit and raises it; it eases back toward normal so a tear is a crisis rather
## than a death sentence.
var drain_rate: float = 1.0

const SECONDS_PER_BLUNT_POINT := 0.5
const DRAIN_PER_PIERCING_POINT := 0.05
const MAX_DRAIN_RATE := 3.0
const DRAIN_RECOVERY_PER_SECOND := 0.1

var _depleted_emitted := false
@onready var label: Label = $Label
@onready var needle: Sprite2D = $Needle
@onready var top_border: ColorRect = $Top_Border
@onready var bottom_border: ColorRect = $Bottom_Border

var setup_done = false

var degrees: float = 90.0
var border_slide_time: float = 8.0
var borders_shown = false

var top_border_start_pos: Vector2
var top_border_end_pos: Vector2
var bottom_border_start_pos: Vector2
var bottom_border_end_pos: Vector2

const LOW_TIME := Color(1.0, 0.0, 0.055, 1.0)
const MED_TIME := Color(1.0, 0.451, 0.0, 1.0)
const HIGH_TIME := Color(0.667, 0.947, 1.003, 1.0)

const NEEDLE_MAX_TIME := 180.0  # 3 minutes, in seconds
const FLICK_DEGREES := 15.0  # how far the flick swings past the current position
const FLICK_DURATION := 0.10  # seconds for the flick out, same again for return

func _ready() -> void:
	GlobalTimer.tick.connect(_setup)
	needle.rotation_degrees = degrees
	GlobalTimer.tick.connect(flick_needle)

	top_border_end_pos = top_border.position
	top_border_start_pos = top_border_end_pos + Vector2(0, -top_border.size.y)
	top_border.position = top_border_start_pos

	bottom_border_end_pos = bottom_border.position
	bottom_border_start_pos = bottom_border_end_pos + Vector2(0, bottom_border.size.y)
	bottom_border.position = bottom_border_start_pos


func _setup() -> void:
	if setup_done:
		return
	await get_tree().create_timer(0.3).timeout
	time_left = total_time
	update_label()
	setup_done = true
	
## Reset the countdown for a new level. This is the ONE place O2 policy lives —
## if levels should get progressively less time, or time should carry over
## instead of resetting, change it here and nowhere else.
func refill() -> void:
	time_left = total_time
	drain_rate = 1.0
	_depleted_emitted = false
	borders_shown = false
	top_border.position = top_border_start_pos
	bottom_border.position = bottom_border_start_pos
	update_label()
	update_needle()


## The one place a hit becomes a cost in air.
##
## Ignored until the countdown has actually started: _setup() waits for the first
## GlobalTimer tick plus 0.3s before assigning time_left, and anything spent
## before that would be silently overwritten.
func apply_damage(amount: int, type: int) -> void:
	if not setup_done:
		return
	if type == Damage.Type.PIERCING:
		add_drain(amount * DRAIN_PER_PIERCING_POINT)
	else:
		spend_seconds(amount * SECONDS_PER_BLUNT_POINT)


func spend_seconds(seconds: float) -> void:
	time_left = maxf(time_left - seconds, 0.0)
	update_label()
	update_needle()


func add_drain(amount: float) -> void:
	drain_rate = minf(drain_rate + amount, MAX_DRAIN_RATE)


func _process(delta: float) -> void:
	if not setup_done:
		return
	if time_left > 0:
		time_left -= delta * drain_rate
		time_left = max(time_left, 0)
		update_label()
		update_needle()

	# A torn suit seals itself slowly, so piercing hits stack into a spike that
	# then subsides rather than a permanent sentence.
	drain_rate = maxf(1.0, drain_rate - DRAIN_RECOVERY_PER_SECOND * delta)

	if time_left <= border_slide_time and not borders_shown:
		slide_in_borders()
		borders_shown = true

	if time_left <= 0.0 and not _depleted_emitted:
		_depleted_emitted = true
		depleted.emit()
	
	
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
		label.modulate = LOW_TIME
	elif time_left < 31:
		var t: float = (time_left - 10.0) / 20.0
		label.modulate = LOW_TIME.lerp(MED_TIME,t)
	else:
		label.modulate = HIGH_TIME
		
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
	tween.tween_property(top_border, "position", top_border_end_pos, 1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(bottom_border, "position", bottom_border_end_pos, 1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
