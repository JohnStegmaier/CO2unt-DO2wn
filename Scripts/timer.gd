extends Node

signal tick

@onready var _timer: Timer = $Timer

func _ready() -> void:
	_timer.timeout.connect(_on_timeout)

func _on_timeout() -> void:
	tick.emit()
