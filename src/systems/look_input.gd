class_name LookInput
extends RefCounted

## "Which way is the player looking?", as a number from -1 to 1.
##
## Split out of the caller because each device needs its own strength curve and
## getting that wrong is invisible until someone plays on the other one. A
## cursor's strength is how far it sits from the centre of the screen; a stick's
## is how hard it is pushed. Read the cursor on a gamepad and the lead pegs to
## wherever the pointer was abandoned and never moves again — the same trap
## [PlayerCamera] documents at _update_aim_lead.
##
## Static and node-free so it can be exercised without a scene tree.

## Below this fraction of a half-screen the mouse is treated as centred. Without
## it the view drifts whenever the pointer is anywhere but dead centre, which on
## a 640x360 viewport is always.
const DEFAULT_DEADZONE := 0.12


## Horizontal look, -1 (left) to 1 (right).
##
## The gamepad reads the right stick, which in a room with the gun hidden is
## doing nothing else. Its own deadzone is already applied by the input map, so
## the axis is used as-is rather than deadzoned twice.
static func horizontal(viewport: Viewport, use_gamepad: bool,
		deadzone: float = DEFAULT_DEADZONE) -> float:
	if use_gamepad:
		return Input.get_axis("aim_left", "aim_right")
	return mouse_horizontal(viewport, deadzone)


## Where the pointer sits across the window, -1 to 1, with a dead middle.
##
## Remapped past the deadzone rather than clipped to it, so crossing the
## threshold eases away from zero instead of snapping to it.
static func mouse_horizontal(viewport: Viewport, deadzone: float = DEFAULT_DEADZONE) -> float:
	if viewport == null:
		return 0.0
	var half_width: float = viewport.get_visible_rect().size.x * 0.5
	if half_width <= 0.0:
		return 0.0

	var offset: float = viewport.get_mouse_position().x - half_width
	var strength: float = clampf(offset / half_width, -1.0, 1.0)
	return remap_deadzone(strength, deadzone)


## Rescale [-1, 1] so everything inside the deadzone reads as zero and everything
## outside it still reaches full strength at the edges.
static func remap_deadzone(value: float, deadzone: float) -> float:
	var dead: float = clampf(deadzone, 0.0, 0.99)
	var magnitude: float = absf(value)
	if magnitude <= dead:
		return 0.0
	return signf(value) * (magnitude - dead) / (1.0 - dead)
