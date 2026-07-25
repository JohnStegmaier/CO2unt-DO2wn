class_name PauseMenu
extends CanvasLayer

## Stop the world, including the clock.
##
## The O2 countdown is glued to AudioManager's music by a set of hand-tuned
## offsets counted from GlobalTimer's one-second beat (see Game._start_music).
## Pausing the tree is what keeps that intact: GlobalTimer's Timer stops, so the
## beat grid stops, and every stream freezes at its playhead and resumes there.
## Nothing is stopped and restarted, so nothing has to be re-synchronised.
##
## The corollary is that every await feeding that scheme must be pause-aware —
## hence the `false` process_always argument on the create_timer calls in
## game.gd, o_2_timer.gd and player.gd. A wait that ran on through a pause would
## land its downbeat at the wrong offset for the rest of the run.

signal paused
signal resumed

## Placeholder art: the two bars ARE the pause glyph. Godot's default font has
## no U+23F8 (nor U+275A, U+25AE or U+2016 — all checked), so a Label holding one
## draws an empty box. Two ColorRects always draw, and swapping them for a sprite
## later is a one-node change.
@onready var _contents: Control = $Contents

var _pause_allowed := true


func _ready() -> void:
	_contents.visible = false


## Once the run is over, pausing it is meaningless — and a paused death sequence
## is a soft lock, since the tree pause would freeze the very tweens that are
## supposed to carry us to the game over screen.
func set_pause_allowed(allowed: bool) -> void:
	_pause_allowed = allowed


func is_paused() -> bool:
	return get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if get_tree().paused:
		_resume()
	elif _pause_allowed:
		_pause()


func _pause() -> void:
	# Tree first, then audio. The engine pauses our streams for us the moment
	# AudioManager stops processing; saying it out loud costs nothing and means
	# the beat grid and the playhead provably stop on the same frame.
	get_tree().paused = true
	AudioManager.set_all_paused(true)
	_contents.visible = true
	paused.emit()


func _resume() -> void:
	_contents.visible = false
	get_tree().paused = false
	AudioManager.set_all_paused(false)
	resumed.emit()
