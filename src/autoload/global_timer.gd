extends Node

signal tick

#true = tick, false = tock
var tickflip = false

@onready var _timer: Timer = $Timer

func _ready() -> void:
	_timer.timeout.connect(_on_timeout)

func _on_timeout() -> void:
	tickflip = !tickflip
	tick.emit()


## Stop the beat grid where it stands, or start it again.
##
## Paused rather than stopped, and that distinction is the whole point: Timer
## keeps its time_left across a pause, so a tick that was 0.4s away is still 0.4s
## away when the grid resumes. Stop and start would restart the second from zero
## and shift every downbeat after it, which is exactly what the hand-tuned
## offsets in Game._start_music and O2Timer cannot survive. See [ClockHold],
## which is what freezes the music on the same frame.
##
## Independent of the tree pause the pause menu uses. Both can be true at once
## and neither clears the other.
func set_suspended(suspended: bool) -> void:
	_timer.paused = suspended


func is_suspended() -> bool:
	return _timer.paused
