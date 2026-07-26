class_name AmmoCounter
extends Node2D

## The magazine, what is holding it, and how long that will last.
##
## A dumb sink, like every other HUD element here: it knows nothing about a
## player and never polls one. It exposes setters, and game.gd connects the
## player's signals to them and primes each with the current value. See
## docs/STRUCTURE.md.

@onready var label: Label = $Label
@onready var _timer_label: Label = $TimerLabel
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
##
## The rect is in AmmoCounter-local space and the counter sits at (598, 336), so
## this lands at 532..587 x 352..356 — inside the 640x360 viewport with four
## pixels to spare at the bottom. Both this and the counter's own position are
## whole numbers on purpose: under the canvas_items stretch a fractional origin
## puts the edges of these rects on half pixels and smears them. See the same
## warning in minimap_style.gd.
const TIMER_BAR_RECT := Rect2(-66.0, 16.0, 55.0, 4.0)
const TIMER_BAR_BACKING := Color(1.0, 1.0, 1.0, 0.15)
const TIMER_BAR_COLOR := Color(0.4, 0.9, 1.0, 0.9)
## Below this fraction the bar turns the same orange the reload uses, so "about
## to lose the gun" reads as the same kind of warning as "about to be unable to
## shoot" rather than as a new colour to learn.
const TIMER_BAR_WARN_BELOW := 0.25
## Below this many seconds the bar and the readout pulse together at 2 Hz. An
## alpha dip rather than a hard blink, because a number that is absent half the
## time is a number the player has to wait for.
const TIMER_PULSE_BELOW := 3.0
const TIMER_PULSE_ALPHA := 0.35

var _current := 0
var _magazine_size := 0
## Tracked separately from _current: a manual reload can start with rounds
## still in the mag, so "empty" alone is not enough to know a reload is on.
var _reloading := false

## Seconds left on the held weapon and what it started at. A total of zero is a
## permanent weapon, and the bar is hidden entirely rather than drawn full.
var _equip_remaining := 0.0
var _equip_total := 0.0
## The whole second currently on the readout, so the text is only rewritten when
## it would actually change. -1 is "nothing shown", which no real count can be.
var _timer_seconds_shown := -1


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
	_refresh_equip_label()
	queue_redraw()


## The bar alone is a nameless sliver next to an ammo count, near enough to the
## reload's own orange to be read as one. The seconds spell out which of the two
## clocks it is.
##
## Split out of _draw because a Label is a node and not a draw call: its text can
## only be set from here. Loadout emits every physics frame while the string only
## changes once a second, hence the gate.
func _refresh_equip_label() -> void:
	if _equip_total <= 0.0:
		_timer_label.text = ""
		_timer_seconds_shown = -1
		return
	# ceil, not round: the last fraction of a second is still a second the player
	# has, and it keeps the readout off "0s" while the gun is still firing.
	var seconds := ceili(_equip_remaining)
	if seconds != _timer_seconds_shown:
		_timer_seconds_shown = seconds
		_timer_label.text = "%ds" % seconds
	# Reassigned every frame rather than with the text, because the pulse lives in
	# the alpha and moves faster than the digits do.
	_timer_label.modulate = _equip_color()


## Shared by the bar and the readout so the two always agree and read as one
## object rather than two things that happen to be next to each other.
##
## The pulse is derived from the countdown itself instead of from a Timer or a
## GlobalTimer tick: it needs no _process, and because Loadout stops emitting
## while suspended it stops dead in a shop rather than pulsing at a frozen
## number.
func _equip_color() -> Color:
	var fraction := clampf(_equip_remaining / maxf(_equip_total, 0.001), 0.0, 1.0)
	var color := RELOAD_COLOR if fraction < TIMER_BAR_WARN_BELOW else TIMER_BAR_COLOR
	if _equip_remaining < TIMER_PULSE_BELOW and fmod(_equip_remaining, 0.5) < 0.25:
		color.a *= TIMER_PULSE_ALPHA
	return color


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
	draw_rect(filled, _equip_color())
