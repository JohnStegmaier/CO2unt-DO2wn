class_name ClockHold
extends RefCounted

## Stop the run's clock without stopping the world.
##
## The O2 countdown, the once-a-second tick and the music track are one
## assembly, glued together by hand-tuned offsets counted from GlobalTimer's beat
## (see Game._start_music and the waits in o_2_timer.gd). The pause menu keeps
## that intact by pausing the whole tree, so every part of it stops on the same
## frame and resumes from where it stood. A shop cannot do that — the player has
## to keep walking around — so this freezes exactly the three things that carry
## run time and leaves everything else running.
##
## **Freeze, never stop and restart.** A Timer keeps its time_left across a
## pause and an AudioStreamPlayer keeps its playhead; thaw both on the same frame
## and the quarter-beat offset is exactly where it was. Anything that stopped and
## replayed would come back on the wrong beat for the rest of the run.
##
## [method set_held] is idempotent derived state rather than an event, so the
## caller can re-assert the truth on every room change instead of remembering to
## undo it. A leaked hold — a run whose clock never restarts — is the one failure
## this must not have, and re-deriving it makes that unreachable.

## The countdown, frozen by disabling its processing rather than by a flag inside
## it. Held as a plain Node because that file belongs to another branch right now
## and this must not need a line in it.
var _o2_timer: Node
## Named track to play while held. Empty plays nothing.
var _music: String
## The beat grid's own voice, silenced along with the grid.
##
## Suspending GlobalTimer stops new ticks, but a tick already sounding plays on —
## and this one is over two seconds long against a one-second beat, so there is
## ALWAYS one in flight. Without cutting it, every single entry into a shop was
## followed by one more audible tick after the countdown had visibly stopped.
var _tick_sfx: StringName
## What [method AudioManager.play_music] handed back, so the shop's own track can
## be faded out without touching the frozen one underneath it.
var _shop_player: Node
var _held: bool = false


func _init(o2_timer: Node, music: String = "", tick_sfx: StringName = &"") -> void:
	_o2_timer = o2_timer
	_music = music
	_tick_sfx = tick_sfx


func is_held() -> bool:
	return _held


## Take or release the hold. Safe to call with the value it already has.
func set_held(held: bool) -> void:
	if held == _held:
		return
	_held = held

	# The beat grid first, so the tick and the music stop on the same frame.
	GlobalTimer.set_suspended(held)
	AudioManager.suspend_music(held)
	_set_countdown_frozen(held)

	if held:
		# After suspending the grid, not before: a tick could otherwise be fired
		# by the very last beat in between the two and survive the silencing.
		_silence_tick()
		_start_shop_music()
	else:
		_stop_shop_music()


## Freeze the countdown by taking it out of processing entirely.
##
## PROCESS_MODE_DISABLED rather than a suspended flag inside O2Timer: that file
## is being rewritten on another branch, and driving it from outside gets the
## identical freeze — drain, drain recovery, the letterbox and the suffocation
## clock all live in its _process — with no edit there at all. It is the same
## lever Game already pulls on the room it is leaving.
##
## INHERIT is the correct restore value because O2Timer carries no explicit
## process_mode of its own, so it is what the node had before we touched it.
##
## The catch is that this propagates to children: the heartbeat sprite stops
## animating and any tween bound to those nodes suspends rather than finishing.
## That is intended for the animation and harmless for the tweens — they resume
## where they were — but it is why the hold is taken behind the room-change wipe,
## which puts most of a second between the last tick and the freeze.
func _set_countdown_frozen(frozen: bool) -> void:
	if _o2_timer == null or not is_instance_valid(_o2_timer):
		return
	_o2_timer.process_mode = (
		Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
	)


## Cut off the tick that is still sounding from the last beat before the freeze.
##
## Stopping the grid is not enough on its own — see [member _tick_sfx].
func _silence_tick() -> void:
	if _tick_sfx.is_empty():
		return
	AudioManager.stop_sfx(_tick_sfx)


## The shop track goes on whichever music player the frozen one is not using.
## AudioManager picks that for us: a suspended player still reports playing, so
## its "first non-playing" search skips it.
func _start_shop_music() -> void:
	if _music.is_empty():
		return
	_shop_player = AudioManager.play_music(_music)


func _stop_shop_music() -> void:
	if _shop_player == null:
		return
	if is_instance_valid(_shop_player):
		# stop_player rather than stop_music, which would also fade the run's
		# track — it is thawed by now and playing again.
		AudioManager.stop_player(_shop_player)
	_shop_player = null
