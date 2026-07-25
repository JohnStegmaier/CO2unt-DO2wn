class_name DeathOverlay
extends CanvasLayer

## The last thing the player sees.
##
## Two stages, both awaitable so the run can sequence them against sound and the
## death animation: the vignette closes to a tight iris around the body while it
## is still visible, then a plain black wipe takes the rest of the screen.
##
## Knows nothing about why the player died or what comes next. Game drives it.

## Seconds for the darkness to close in from the edges. This is the pace of the
## whole death beat — long enough to feel like suffocating, short enough that a
## player who wants to retry is not held hostage.
@export var vignette_duration: float = 2.5

## How far the iris shuts, 0 clear to 1 fully black. Deliberately short of 1 so
## the body stays visible in the last pinhole and the wipe below has something
## left to do.
@export_range(0.0, 1.0) var vignette_closed_amount: float = 0.85

## Seconds for the final wipe to black, once the iris has stopped.
@export var fade_out_duration: float = 1.0

@onready var _vignette: ColorRect = $Vignette
@onready var _blackout: ColorRect = $Blackout


func _ready() -> void:
	_set_progress(0.0)
	_blackout.color.a = 0.0
	# The hole has to be round on whatever the viewport actually is, not on the
	# 16:9 the shader assumes by default.
	var size := get_viewport().get_visible_rect().size
	if size.y > 0.0:
		_vignette.material.set_shader_parameter("aspect", size.x / size.y)


## Close the iris. Await this to hold until the darkness has stopped moving.
func close_vignette() -> void:
	var tween := create_tween()
	# EASE_IN_OUT, not EASE_IN: eased in from a standstill the darkness spends
	# most of the first second doing nothing visible, and the beat reads as a
	# hang rather than as suffocation.
	tween.tween_method(_set_progress, 0.0, vignette_closed_amount, vignette_duration) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished


## Wipe whatever is left to black. Await this before swapping scenes, or the new
## screen appears under a fade that never finished.
func fade_to_black() -> void:
	var tween := create_tween()
	tween.tween_property(_blackout, "color:a", 1.0, fade_out_duration)
	await tween.finished


func _set_progress(progress: float) -> void:
	_vignette.material.set_shader_parameter("progress", progress)
