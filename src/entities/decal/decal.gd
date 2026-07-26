class_name RoomDecal
extends Node2D

## One piece of cosmetic floor dressing, dressed from a [DecalDef] the same way
## [Obstacle] is dressed from an [ObstacleDef] — except this is a Node2D, not a
## StaticBody2D: no collider, no Health, no signal. Nothing in the game ever
## needs to know a decal is there, which is the whole difference.
##
## Named RoomDecal rather than Decal — Godot's own Decal is a native 3D node,
## and a class_name that shadows an engine type fails to load.

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _sprite_anim: AnimatedSprite2D = $AnimatedSprite2D

var def: DecalDef


## Call it BEFORE this enters the tree, the same window Obstacle.configure and
## Enemy.make_boss are set in.
func configure(p_def: DecalDef) -> void:
	def = p_def


func _ready() -> void:
	assert(def != null, "Decal needs configure() before it enters the tree")

	# Mutually exclusive, the same split ItemPickup draws between its Icon and
	# IconAnim: whichever def carries is shown, the other stays hidden rather
	# than drawing an empty texture over it.
	var animated: bool = def.sprite_frames != null
	_sprite.visible = not animated
	_sprite.texture = def.texture
	_sprite.offset = def.offset
	_sprite.scale = Vector2.ONE * def.sprite_scale
	_sprite.modulate.a = def.opacity

	_sprite_anim.visible = animated
	if animated:
		_sprite_anim.sprite_frames = def.sprite_frames
		_sprite_anim.offset = def.offset
		_sprite_anim.scale = Vector2.ONE * def.sprite_scale
		_sprite_anim.modulate.a = def.opacity
		_sprite_anim.play(def.animation)
