class_name AmmoCounter
extends Node2D

## The magazine, what is holding it, and how long that will last.
##
## A dumb sink, like every other HUD element here: it knows nothing about a
## player and never polls one. It exposes setters, and game.gd connects the
## player's signals to them and primes each with the current value. See
## docs/STRUCTURE.md.

@onready var label: Label = $Label
@onready var _weapon_icon: Sprite2D = $WeaponIcon

const RELOAD_COLOR := Color(1.0, 0.451, 0.0, 1.0)
## "RELOADING" is far wider than any ammo count, so it gets its own smaller
## size to keep it from overflowing the label's box off the edge of the screen.
const AMMO_FONT_SIZE := 22
const RELOAD_FONT_SIZE := 14

## The countdown bar under the ammo, shown only while a timed weapon is held.
## Drawn rather than built from nodes for the same reason the reload indicator
## is: it is two rectangles and a colour ramp, and a scene for that is a scene to
## keep in step.
const TIMER_BAR_RECT := Rect2(-91.0, 24.0, 80.0, 3.0)
const TIMER_BAR_BACKING := Color(1.0, 1.0, 1.0, 0.15)
const TIMER_BAR_COLOR := Color(0.4, 0.9, 1.0, 0.9)
## Below this fraction the bar turns the same orange the reload uses, so "about
## to lose the gun" reads as the same kind of warning as "about to be unable to
## shoot" rather than as a new colour to learn.
const TIMER_BAR_WARN_BELOW := 0.25

var _current := 0
var _magazine_size := 0
## Tracked separately from _current: a manual reload can start with rounds
## still in the mag, so "empty" alone is not enough to know a reload is on.
var _reloading := false

## Seconds left on the held weapon and what it started at. A total of zero is a
## permanent weapon, and the bar is hidden entirely rather than drawn full.
var _equip_remaining := 0.0
var _equip_total := 0.0


## Called off Player.weapon_changed, and once up front to sync whatever the
## player is already holding — see game.gd.
##
## Takes the weapon rather than a flag so that adding a weapon never touches this
## file: the icon and its scale come off the resource, and this stays the same
## size whether the game ships two guns or twelve.
func set_weapon(weapon: WeaponDef) -> void:
	if weapon == null:
		return
	# hud_icon is the override for art that is unreadable at this size; most
	# weapons leave it empty and are shown exactly as they are held.
	_weapon_icon.texture = weapon.hud_icon if weapon.hud_icon != null else weapon.held_texture
	_weapon_icon.scale = Vector2.ONE * weapon.hud_icon_scale


## Called off Player.equip_time_changed. Zeroes mean a permanent weapon.
func set_equip_time(remaining: float, total: float) -> void:
	_equip_remaining = remaining
	_equip_total = total
	queue_redraw()


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


func _draw() -> void:
	if _equip_total <= 0.0:
		return
	draw_rect(TIMER_BAR_RECT, TIMER_BAR_BACKING)
	var fraction := clampf(_equip_remaining / _equip_total, 0.0, 1.0)
	var filled := TIMER_BAR_RECT
	filled.size.x *= fraction
	var color := RELOAD_COLOR if fraction < TIMER_BAR_WARN_BELOW else TIMER_BAR_COLOR
	draw_rect(filled, color)
