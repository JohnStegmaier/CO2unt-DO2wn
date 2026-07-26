class_name ScreenFade
extends CanvasLayer

## A plain wipe to black and back, for transitions that are a cut rather than a
## move.
##
## The room slide works because two adjacent cells share an edge, so travelling
## between them reads as one continuous space. Some rooms have no such edge —
## walking into a belt-scroll lobby means the view turns ninety degrees, and
## sliding into it drags the player across geometry that does not connect to
## anything. There is nothing to show during that, so this shows nothing.
##
## Deliberately not the death overlay: that wipe is one-way and never comes back,
## because nothing follows it but a scene change. This one has to open again.
##
## Sits on canvas layer 10 — above the HUD, so a transition covers the whole
## frame, and below the elevator ride at 15 and the pause menu at 20, so pausing
## mid-fade still puts the menu on top of the black rather than behind it.

## Seconds for one direction. A cut wants to be quick: long enough that the swap
## is hidden, short enough that it is not a loading screen.
@export var fade_time: float = 0.22

@onready var _rect: ColorRect = $ColorRect

var _tween: Tween


func _ready() -> void:
	_rect.color.a = 0.0
	# Hidden rather than merely transparent, so a fully clear overlay is not
	# submitted for drawing on every frame of a run that never uses it.
	_rect.visible = false


## Black out. Await it before moving anything the player must not see move.
func fade_out() -> void:
	await _fade_to(1.0)


## Open again. Await it so a caller cannot hand control back under a black screen.
func fade_in() -> void:
	await _fade_to(0.0)
	_rect.visible = false


## Fade from wherever we currently are, over a proportional slice of fade_time.
##
## Proportional so an interrupted fade does not crawl: a transition cut short by
## another one starts from the alpha on screen rather than snapping to an end.
func _fade_to(target: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_rect.visible = true
	if is_equal_approx(_rect.color.a, target):
		return

	var duration: float = fade_time * absf(target - _rect.color.a)
	_tween = create_tween()
	# Idle process, not physics: this draws, it does not move colliders. Pausing
	# is handled by the tree, and the fade pauses with it.
	_tween.tween_property(_rect, "color:a", target, duration)
	await _tween.finished
