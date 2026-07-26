class_name Chest
extends StaticBody2D

## A container the player opens by standing next to it and pressing interact.
##
## A StaticBody2D on the WORLD layer rather than a walk-over Area2D, for the same
## reason obstacle.gd is one: it should read as furniture. You bump into it, and
## opening it is a thing you decide to do rather than a thing that happens because
## you walked past. Bullets are absorbed by it too, which comes free with the layer.
##
## Only ever opened once. Whether it has been is the RUN's business and not this
## node's — a room is freed on exit and rebuilt on the way back in, so a chest that
## remembered its own state would forget it at the doorway. It reports opening
## upward and is told, on the way back, to come up already open; see
## [method show_opened] and RoomData.treasure_opened.

## The lid came up, and where what was inside should land. Whoever is listening
## decides WHAT falls out — this knows nothing about loot tables and should not
## start now, the same split Obstacle.destroyed makes. It does know its own
## footprint, which is the whole reason it carries the position; see LOOT_OFFSET.
signal opened(at: Vector2)

const TEXTURE_CLOSED := preload("res://assets/sprites/environment/Chest_closed.png")
const TEXTURE_OPEN := preload("res://assets/sprites/environment/Chest_open.png")

## Where the art sits inside its 200x200 canvas, as the gap between the canvas
## centre and the alpha bounding box's — the same measurement ObstacleDef.offset
## carries for the props, arrived at the same way.
##
## ONE offset for both frames, deliberately. The closed art spans y 47..83 and the
## open art y 42..83: the lid is the only part that moves, and it grows upward from
## a base that does not. Holding the closed frame's offset therefore pins the chest
## to the floor and lets the lid rise, which is the whole animation. Re-centring on
## the open frame's own bounding box instead would keep the lid still and drop the
## chest 2.5px into the ground.
const ART_OFFSET := Vector2(14.5, 34.5)

## How far the lid pops past its resting size before settling, and over how long.
## Scale rather than position because the sprite is anchored at its base — the top
## is the only end free to move.
const POP_SCALE := 1.12
const POP_TIME := 0.12
const SETTLE_TIME := 0.16

## Where the contents land, relative to this. In FRONT of the chest, and this is
## not decoration: the chest is a solid body on the WORLD layer, so the player
## cannot stand on it. A pickup dropped at the chest's own centre would sit a few
## pixels beyond the reach of a player pressed against the collider — visible,
## on the floor, and impossible to collect. Far enough out that game.gd's drop
## scatter, which jitters a multi-item drop by LOOT_SCATTER in each axis, still
## cannot push one back inside the collider.
const LOOT_OFFSET := Vector2(0, 26)

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _zone: Area2D = $InteractZone
@onready var _prompt: Label = $Prompt

var _opened: bool = false
var _player_near: bool = false
## Which device the prompt is currently written for. See _refresh_prompt.
var _prompt_for_gamepad: bool = false


func _ready() -> void:
	_sprite.texture = TEXTURE_CLOSED
	_sprite.offset = ART_OFFSET
	_prompt.visible = false
	_refresh_prompt()
	_zone.body_entered.connect(_on_body_entered)
	_zone.body_exited.connect(_on_body_exited)
	# One sweep of who is already inside, deferred to the first frame the physics
	# server has actually run. body_entered only fires on a crossing, and the player
	# does not always cross into this room on foot — a floor starts with a warp to
	# the middle of the floor, which is where this stands. Without the sweep that
	# player would be inside the zone with no prompt and no way to open the chest
	# but to step out and back in. Same trap shop_room.gd calls out for its exit
	# test.
	_sweep_for_player.call_deferred()


func _sweep_for_player() -> void:
	for body in _zone.get_overlapping_bodies():
		_on_body_entered(body)


func _process(_delta: float) -> void:
	if _opened or not _player_near:
		return
	# Checked here rather than every frame of the run: past the guard above is
	# exactly the window in which the prompt is on screen to be read.
	if InputPrompt.using_gamepad() != _prompt_for_gamepad:
		_refresh_prompt()
	if Input.is_action_just_pressed("interact"):
		_open()


## Name the button the player is actually holding.
##
## The text used to be authored in the scene as "[E] OPEN", which is a lie to
## anyone on a pad — there, interact is X. A prompt naming the wrong button is
## worse than none: the player presses what she was told, the chest sits there,
## and she concludes it is scenery.
func _refresh_prompt() -> void:
	_prompt_for_gamepad = InputPrompt.using_gamepad()
	var glyph: String = InputPrompt.glyph("interact")
	# Empty means nothing is bound on this device. Better a bare verb than
	# "[] OPEN", which reads as a rendering bug.
	_prompt.text = "OPEN" if glyph.is_empty() else "[%s] OPEN" % glyph


## Open it now, with the noise and the signal. The one path a player can take.
##
## Guarded here rather than only at the call site. _process already refuses to call
## this twice and the zone stops monitoring below, so a second open is not reachable
## today — but "pays out once, ever" is the one thing this whole feature is built to
## guarantee, and an invariant that holds only as long as every caller remembers to
## check is not guaranteed at all.
func _open() -> void:
	if _opened:
		return
	_opened = true
	_show_open_frame()
	_player_near = false
	_prompt.visible = false
	# Hiding the prompt is not enough to stop the zone reporting, and this is the
	# only thing keeping a second open out of the same frame the first went out in.
	# Deferred because the physics server rejects the change mid-flush.
	_zone.set_deferred("monitoring", false)

	AudioManager.play_sfx("chest_open")

	# The Sprite2D, never self: physics interpolation is on project-wide and
	# tweening a body's own transform smears it — see the same note in obstacle.gd.
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_sprite, "scale", _sprite.scale * POP_SCALE, POP_TIME)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_sprite, "scale", _sprite.scale, SETTLE_TIME)

	opened.emit(global_position + LOOT_OFFSET)


## Come up already open: a chest the player emptied on an earlier visit.
##
## The end state of [method _open] with none of its consequences — no sound for an
## event that happened rooms ago, no tween to draw the eye to a chest that has
## nothing in it, and above all no signal, which would pay the player out again
## every time they walked back through.
func show_opened() -> void:
	_opened = true
	_show_open_frame()
	_prompt.visible = false
	_zone.set_deferred("monitoring", false)


func _show_open_frame() -> void:
	_sprite.texture = TEXTURE_OPEN
	_sprite.offset = ART_OFFSET


func _on_body_entered(body: Node2D) -> void:
	if _opened or not body is Player:
		return
	_player_near = true
	_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if not body is Player:
		return
	_player_near = false
	_prompt.visible = false
