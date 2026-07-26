class_name ItemPickup
extends Area2D

## Any dropped item, lying on the floor waiting to be walked into.
##
## One scene for the whole catalogue. What it looks like, what noise it makes and
## what it does all come off the [ItemDef] it is handed, so adding an item is
## authoring a .tres rather than duplicating this scene — which is what the
## oxygen and bomb pickups this replaces each were.
##
## Duck-types whoever walks into it, the same way bullet.gd duck-types
## take_damage: this has no dependency on Player beyond the effects' methods
## existing, and the PICKUP layer only masks PLAYER so nothing else can trip it.

## Set before this enters the tree, the way [method Enemy.configure] and
## Health.max_hp are. _ready is what draws it, so an item assigned later would be
## invisible.
@export var item: ItemDef

@export_group("Hover")
@export var hover_amplitude := 3.0
@export var hover_speed := 3.0
## How much the shadow shrinks at the peak of the hover, relative to its resting
## size — 0 leaves it fixed, 1 would pinch it to nothing. Ties the shadow to the
## bob instead of leaving it a static decal under a sprite that is visibly
## moving.
@export_range(0.0, 1.0) var shadow_shrink := 0.3

## The backdrop and the icon move as one unit, so they never drift apart during
## the bob. The shadow stays put on the ground; only its size answers the bob.
@onready var _visual: Node2D = $Visual
@onready var _backdrop: Sprite2D = $Visual/Backdrop
@onready var _icon: Sprite2D = $Visual/Icon
@onready var _icon_anim: AnimatedSprite2D = $Visual/IconAnim
@onready var _shadow: Sprite2D = $Shadow

var _visual_base_y := 0.0
var _shadow_base_scale := Vector2.ONE
var _time := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual_base_y = _visual.position.y
	_shadow_base_scale = _shadow.scale
	_apply_appearance()


func _process(delta: float) -> void:
	_time += delta
	var lift := sin(_time * hover_speed) * hover_amplitude
	_visual.position.y = _visual_base_y + lift
	if hover_amplitude > 0.0:
		# 1 at the bottom of the bob (lift at +hover_amplitude, closest to the
		# ground) down to 1 - shadow_shrink at the top — the same 0..1 phase the
		# visual's own offset already runs on, just read the other way round.
		var grounded := (lift + hover_amplitude) / (2.0 * hover_amplitude)
		_shadow.scale = _shadow_base_scale * lerpf(1.0 - shadow_shrink, 1.0, grounded)


## Dress this pickup as whatever it is carrying.
##
## An item with no backdrop hides the node rather than leaving it drawing an
## empty texture, so the two-layer bomb and the single-layer canister are the
## same scene with one node switched off.
func _apply_appearance() -> void:
	if item == null:
		# Loud, because a pickup carrying nothing is invisible and un-collectable:
		# it would read as "drops are broken" rather than as one missing slot.
		push_error("ItemPickup: no item assigned — nothing to show or grant.")
		return

	# Animated and static icons are mutually exclusive views of the same slot —
	# whichever the item carries is shown, the other stays hidden rather than
	# drawing over it.
	var animated: bool = item.icon_frames != null
	_icon.visible = not animated
	_icon.texture = item.icon
	_icon.scale = Vector2.ONE * item.icon_scale
	_icon_anim.visible = animated
	if animated:
		_icon_anim.sprite_frames = item.icon_frames
		_icon_anim.scale = Vector2.ONE * item.icon_scale
		_icon_anim.play(item.icon_animation)
	_backdrop.visible = item.backdrop != null
	_backdrop.texture = item.backdrop
	_backdrop.scale = Vector2.ONE * item.backdrop_scale


func _on_body_entered(body: Node2D) -> void:
	if item == null:
		return
	# Before the effects, not after: an effect can end the run — a bomb wipe or a
	# heal that outlives the body — and a sound queued after that never plays.
	if not item.pickup_sound.is_empty():
		AudioManager.play_sfx(item.pickup_sound)
	_spawn_oxygen_text()
	item.grant_to(body)
	queue_free()


## "+15s" drifting up off an oxygen canister. Reads the RestoreOxygen effect's
## own seconds rather than item.describe() — "+15s air" is fine in a tooltip but
## busier than the sprite it is hovering over needs.
##
## Parented to the current scene rather than to this: this frees itself the
## instant grant_to returns, and a popup made a child of it would go with it.
func _spawn_oxygen_text() -> void:
	for effect in item.effects:
		if effect is RestoreOxygen:
			FloatingText.spawn(get_tree().current_scene, global_position, "+%ds" % int(effect.seconds))
