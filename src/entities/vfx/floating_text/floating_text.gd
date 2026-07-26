class_name FloatingText
extends Label

## A short line of text that drifts upward and fades out, then frees itself.
##
## Same one-shot lifetime as [method Player._spawn_pulse] — spawn it, hand it a
## position, walk away. It does not know or care who spawned it.

const SCENE := preload("res://src/entities/vfx/floating_text/floating_text.tscn")

@export var rise_distance := 20.0
@export var duration := 0.9
## Overrides the scene's baked-in font colour. Left as the oxygen green by
## default so a caller that does not care — the common case — gets that look
## for free.
@export var text_color := Color(0.588, 1.003, 0.676, 1.0)


## Spawn one line of drifting text at a world position.
##
## Takes the parent explicitly rather than assuming get_tree().current_scene,
## so a caller already holding the right long-lived node (as game.gd holds
## itself) does not have to re-derive it. Sets every property before add_child,
## not after: add_child runs _ready synchronously, and _ready is what centers
## the label and computes the tween's target position — setting them
## afterwards would leave the drift animating relative to wherever the label
## started (the origin), not the position it was meant for.
static func spawn(parent: Node, at: Vector2, text: String, color := Color(0.588, 1.003, 0.676, 1.0)) -> void:
	var label: Label = SCENE.instantiate()
	label.text = text
	label.text_color = color
	label.global_position = at
	parent.add_child(label)


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_color_override("font_color", text_color)
	# reset_size needs the text already set, which is why the centering happens
	# here rather than in the spawn helper — this is centered on the position it
	# was handed instead of growing right from it.
	reset_size()
	position -= size * 0.5

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - rise_distance, duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
