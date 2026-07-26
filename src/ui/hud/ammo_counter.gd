class_name AmmoCounter
extends Node2D

@onready var label: Label = $Label
@onready var _weapon_icon: Sprite2D = $WeaponIcon

## Swapped onto the icon for the whole of a shotgun window; see
## set_shotgun_equipped. Whatever the icon shows the rest of the time is read
## back off the node itself in _ready() rather than duplicated here, so this
## HUD can never disagree with the scene about what the starter gun looks like.
@export var shotgun_texture: Texture2D = preload("res://assets/sprites/weapons/shotgun.png")
var _default_texture: Texture2D

const RELOAD_COLOR := Color(1.0, 0.451, 0.0, 1.0)
## "RELOADING" is far wider than any ammo count, so it gets its own smaller
## size to keep it from overflowing the label's box off the edge of the screen.
const AMMO_FONT_SIZE := 22
const RELOAD_FONT_SIZE := 14

var _current := 0
var _magazine_size := 0
## Tracked separately from _current: a manual reload can start with rounds
## still in the mag, so "empty" alone is not enough to know a reload is on.
var _reloading := false


func _ready() -> void:
	_default_texture = _weapon_icon.texture


## Called off Player.weapon_changed, and once up front to sync whatever state
## the player already carried in — see game.gd.
func set_shotgun_equipped(equipped: bool) -> void:
	_weapon_icon.texture = shotgun_texture if equipped else _default_texture


func set_ammo(current: int, magazine_size: int) -> void:
	_current = current
	_magazine_size = magazine_size
	_refresh()


func set_reloading(reloading: bool) -> void:
	_reloading = reloading
	_refresh()


func _refresh() -> void:
	if _reloading or _current <= 0:
		label.text = "RELOADING"
		label.modulate = RELOAD_COLOR
		label.add_theme_font_size_override("font_size", RELOAD_FONT_SIZE)
	else:
		label.text = "%d / %d" % [_current, _magazine_size]
		label.modulate = Color.WHITE
		label.add_theme_font_size_override("font_size", AMMO_FONT_SIZE)
