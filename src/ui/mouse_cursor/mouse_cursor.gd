class_name MouseCursor
extends CanvasLayer

## Reticle sprite standing in for the OS pointer, so the mouse reads as an aim
## target instead of an arrow during a run.
##
## Sits on canvas layer 25 — above the pause menu at 20, so the reticle keeps
## tracking the mouse over a paused screen rather than vanishing behind it.

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	# Always, not the default Pausable: the mouse keeps moving while the game
	# is paused, and a reticle that stops updating would drift from the pointer
	# the moment the pause menu opens.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_sprite.position = get_viewport().get_mouse_position()
