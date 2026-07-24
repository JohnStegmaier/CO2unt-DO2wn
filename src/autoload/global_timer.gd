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
