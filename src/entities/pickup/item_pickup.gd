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

## Set before this enters the tree, the way Enemy.behaviour and Health.max_hp
## are. _ready is what draws it, so an item assigned later would be invisible.
@export var item: ItemDef

@export_group("Hover")
@export var hover_amplitude := 3.0
@export var hover_speed := 3.0

## The backdrop and the icon move as one unit, so they never drift apart during
## the bob. The shadow stays put on the ground.
@onready var _visual: Node2D = $Visual
@onready var _backdrop: Sprite2D = $Visual/Backdrop
@onready var _icon: Sprite2D = $Visual/Icon

var _visual_base_y := 0.0
var _time := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual_base_y = _visual.position.y
	_apply_appearance()


func _process(delta: float) -> void:
	_time += delta
	_visual.position.y = _visual_base_y + sin(_time * hover_speed) * hover_amplitude


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

	_icon.texture = item.icon
	_icon.scale = Vector2.ONE * item.icon_scale
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
	item.grant_to(body)
	queue_free()
