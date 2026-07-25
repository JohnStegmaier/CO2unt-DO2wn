class_name DeathOverlay
extends Node2D

## The closing dark, and the wipe that follows it.
##
## Owns no timing of its own. The O2 timer decides how fast the player is
## suffocating and this just draws whatever number it is handed — which is what
## lets the dark back off again when air comes back, rather than being a tween
## that has already been fired and cannot be recalled.
##
## Lives as a child of the player's Camera2D, in the world rather than on a
## screen-space CanvasLayer. That is deliberate: it is the only way the player
## can be drawn ON TOP of the dark, by simply out-ranking it on z_index. The
## shader works off SCREEN_UV so being in the world costs it nothing.
##
## The final wipe is the exception — it has to cover the HUD too, so it sits on
## its own CanvasLayer above everything.

## How far past the viewport the vignette quad extends. The quad rides the camera
## and physics interpolation is on project-wide, so it can lag the view by a
## frame; oversizing means its edge never slides into shot.
const QUAD_OVERSCAN := 2.0

## Where the dark sits in the world's draw order. Above every room decoration
## (the highest in room.tscn is 2), below anything that must stay lit inside it.
## Whoever wants to be seen through the dark sets a higher z_index than this.
const VIGNETTE_Z_INDEX := 50

## Seconds for the final wipe to black, once the player is dead.
@export var fade_out_duration: float = 1.0

@onready var _vignette: ColorRect = $Vignette
@onready var _blackout: ColorRect = $Blackout/Rect


func _ready() -> void:
	set_vignette_progress(0.0)
	_blackout.color.a = 0.0

	var view: Vector2 = get_viewport().get_visible_rect().size
	# The hole has to be round on whatever the viewport actually is, not on the
	# 16:9 the shader assumes by default.
	if view.y > 0.0:
		_vignette.material.set_shader_parameter("aspect", view.x / view.y)

	# Sized in the camera's own space, so the camera's zoom does not shrink the
	# quad out from under the screen it is supposed to cover.
	var camera := get_parent() as Camera2D
	var zoom: Vector2 = camera.zoom if camera != null else Vector2.ONE
	_vignette.size = view / zoom * QUAD_OVERSCAN
	_vignette.position = -_vignette.size * 0.5


## 0 clear, 1 shut. Driven straight from O2Timer.suffocation_changed.
func set_vignette_progress(progress: float) -> void:
	_vignette.material.set_shader_parameter("progress", progress)


## The frame the player died on, for the game over screen to keep showing. Taken
## before the wipe, so it is the closed vignette with the body still lit inside
## it — which is the whole point of drawing the player above the dark.
func capture_screen() -> Texture2D:
	await RenderingServer.frame_post_draw
	return ImageTexture.create_from_image(get_viewport().get_texture().get_image())


## Wipe whatever is left to black. Await this before swapping scenes, or the new
## screen appears under a fade that never finished.
func fade_to_black() -> void:
	var tween := create_tween()
	tween.tween_property(_blackout, "color:a", 1.0, fade_out_duration)
	await tween.finished
