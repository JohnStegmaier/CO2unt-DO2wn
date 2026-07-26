class_name O2Timer
extends Node2D

## The countdown, and the player's health bar — they are the same thing. Damage
## does not come off a hit point pool, it comes off the clock, so this script
## owns the conversion from a hit to a cost in air.

## The tank read zero. The suit powers down — but the player is still alive and
## still playing, on whatever is left in their lungs. Fires once.
signal depleted

@onready var heartbeat = $UIMain/heartbeat
## Air came back after the tank had read zero. The counterpart to depleted, so a
## run that gets a second wind can undo whatever depleted set in motion.
signal air_restored

## The air is nearly gone and the walls are closing in. Carries the direction, so
## the heartbeat and the letterbox are driven by one event and cannot drift apart
## — including on the way back out.
signal air_critical_changed(critical: bool)

## How far through suffocating the player is, 0 to 1. Rises while the tank reads
## zero and falls again if air comes back; whatever draws the closing dark just
## follows this number rather than running a timer of its own.
signal suffocation_changed(progress: float)

## The last breath is gone. THIS is death — not depleted.
signal suffocated

@export var total_time: float = 90 # starting time in seconds
var time_left

## How fast air is spent, as a multiplier on real time. Piercing damage tears the
## suit and raises it; it eases back toward normal so a tear is a crisis rather
## than a death sentence.
var drain_rate: float = 1.0

## Whether the tank empties at all. Only a tuning profile ever turns this off —
## see the god_mode and peaceful profiles.
##
## A flag rather than an enormous total_time, because damage comes off the clock
## as well as time: a big number still lets a roomful of enemies whittle a run
## down, and "unlimited health" has to mean the hits themselves cost nothing.
## infinite_oxygen keeps using the big number on purpose — it wants a run that
## cannot time out but can still be fought.
var drain_enabled := true

@export_group("Damage")
## Seconds of air a point of blunt damage costs. This single number sets the
## lethality of every fight in the game.
@export var seconds_per_blunt_point := 0.5
## How much a point of piercing damage raises the drain rate. 0.05 means a
## 10-damage hit spends air 50% faster.
@export var drain_per_piercing_point := 0.05
## However torn the suit gets, air never leaves faster than this.
@export var max_drain_rate := 3.0
## How quickly a tear seals itself again.
@export var drain_recovery_per_second := 0.1

@export_group("Endgame")
## Seconds left when the letterbox closes in and the heartbeat comes up. This is
## the whole "you are running out" beat — raise it to give the player longer to
## panic, lower it to make the end arrive without warning.
@export var border_slide_time: float = 8.0

## How the letterbox tracks the air.
##
## "continuous" ties the bars directly to the gauge across the last
## border_slide_time seconds, so they creep in as the air goes and creep back out
## the instant any is recovered. "snap" is the original feel — one cubic slide at
## the threshold — made reversible, so crossing back out slides them away again.
## Both are wired; flip this to change which one the run uses.
@export_enum("continuous", "snap") var border_style: int = 0

## Seconds the player survives on an empty tank. The whole death cinematic runs
## on this clock: the dark closes in over exactly this long, and the player keeps
## playing for every second of it.
@export var suffocation_time: float = 2.5

## Seconds to undo a full suffocation once air comes back. Deliberately quicker
## than suffocation_time — clawing your way back should read as relief, not as a
## second slow crawl.
@export var suffocation_recovery_time: float = 1.0

var _depleted_emitted := false
var _suffocated_emitted := false
## 0 while there is air, 1 when the player has run out of lungs.
var _suffocation := 0.0
var _air_critical := false
@onready var label: Label = $Label
@onready var needle: Sprite2D = $Needle
@onready var top_border: ColorRect = $Top_Border
@onready var bottom_border: ColorRect = $Bottom_Border
@onready var lights_odd: Array[Sprite2D] = [$UIMain/Light1, $UIMain/Light3, $UIMain/Light5]
@onready var lights_even: Array[Sprite2D] = [$UIMain/Light2, $UIMain/Light4, $UIMain/Light6]
@onready var bomb_containers: Array[Sprite2D] = [
	$UIMain/bomb_container1, $UIMain/bomb_container2, $UIMain/bomb_container3
]

var setup_done = false

var degrees: float = 90.0
## Only used by the "snap" border style — the tween owns the bars there, and it
## must not be restarted every frame the player sits under the threshold.
var _border_tween: Tween

var top_border_start_pos: Vector2
var top_border_end_pos: Vector2
var bottom_border_start_pos: Vector2
var bottom_border_end_pos: Vector2

const LOW_TIME := Color(1.0, 0.0, 0.055, 1.0)
const MED_TIME := Color(1.0, 0.451, 0.0, 1.0)
const HIGH_TIME := Color(0.588, 1.003, 0.676, 1.0)

const LIGHT_ON_COLOR := Color(1, 0.5254902, 0.3647059, 1)
const LIGHT_OFF_COLOR := Color(1, 0.5254902, 0.3647059, 0.25)

## Matches the self_modulate already authored onto bomb_container2/3 in the scene.
const BOMB_FULL_ALPHA := 1.0
const BOMB_EMPTY_ALPHA := 80.0 / 255.0

var _lights_alternate := false

## Values for border_style. Plain ints rather than an enum, because GDScript will
## not carry an enum type across a script boundary and this is an exported knob.
const BORDER_STYLE_CONTINUOUS := 0
const BORDER_STYLE_SNAP := 1

const NEEDLE_MAX_TIME := 180.0  # 3 minutes, in seconds
const FLICK_DEGREES := 15.0  # how far the flick swings past the current position
const FLICK_DURATION := 0.10  # seconds for the flick out, same again for return

func _ready() -> void:
	print("ready!")
	
	# Before anything reads it: _setup() and refill() both copy total_time into
	# time_left, and they are the only things that start the clock. Overriding
	# here rather than editing the number above is the whole point of issue #26 —
	# a test value in a profile cannot be committed into the game by accident.
	total_time = GameConfig.get_value("oxygen", "total_time", total_time)
	time_left = total_time
	# GlobalTimer's Timer has no wait_time override, so it defaults to Godot's
	# 1.0 — this is what makes the digital readout tick over once a second
	# instead of drifting with delta and drain_rate like the needle does.
	GlobalTimer.tick.connect(update_label)
	GlobalTimer.tick.connect(play_heartbeat)
	drain_enabled = GameConfig.get_value("oxygen", "drain", drain_enabled)
	GlobalTimer.tick.connect(_setup)
	needle.rotation_degrees = degrees

	top_border_end_pos = top_border.position
	top_border_start_pos = top_border_end_pos + Vector2(0, -top_border.size.y)
	top_border.position = top_border_start_pos

	bottom_border_end_pos = bottom_border.position
	bottom_border_start_pos = bottom_border_end_pos + Vector2(0, bottom_border.size.y)
	bottom_border.position = bottom_border_start_pos

#anything called in here will run begin on the first tick sound of the level
		
## Reset the countdown for a new level. This is the ONE place O2 policy lives —
## if levels should get progressively less time, or time should carry over
## instead of resetting, change it here and nowhere else.
func refill() -> void:
	time_left = total_time
	drain_rate = 1.0
	# Announced, not just cleared. Reaching the exit while already out of air is
	# reachable — the player keeps full control while suffocating — and everything
	# _on_air_depleted switched off is switched back on by the listener to this,
	# not by the flag. Clearing it silently would leave the clock tick and the
	# music disconnected, and the player drawn over the walls, for the whole rest
	# of the run.
	if _depleted_emitted:
		air_restored.emit()
	_depleted_emitted = false
	_suffocated_emitted = false
	_set_suffocation(0.0)
	_set_air_critical(false)
	if _border_tween != null and _border_tween.is_valid():
		_border_tween.kill()
	top_border.position = top_border_start_pos
	bottom_border.position = bottom_border_start_pos
	update_label()
	update_needle()


## The one place a hit becomes a cost in air.
##
## Ignored until the countdown has actually started: _setup() waits for the first
## GlobalTimer tick plus 0.3s before assigning time_left, and anything spent
## before that would be silently overwritten.
func apply_damage(amount: int, type: int) -> void:
	_flash_heartbeat()
	# The single gate on damage, because this is the single place a hit becomes a
	# cost in air. A profile that stops the clock stops hits costing anything too.
	if not drain_enabled:
		return
	if type == Damage.Type.PIERCING:
		add_drain(amount * drain_per_piercing_point)
	else:
		spend_seconds(amount * seconds_per_blunt_point)


## A hit reads on the readout too, not just as lost time — a couple of quick red
## flickers rather than one smooth flash, to read as distinct from the needle
## and label's own easing.
func _flash_heartbeat() -> void:
	var flash := create_tween()
	for i in 3:
		flash.tween_property(heartbeat, "modulate", Color(10.178, 0.0, 0.0, 1.0), 0.05)
		flash.tween_property(heartbeat, "modulate", Color.WHITE, 0.05)


func spend_seconds(seconds: float) -> void:
	time_left = maxf(time_left - seconds, 0.0)
	update_label()
	update_needle()


func add_drain(amount: float) -> void:
	drain_rate = minf(drain_rate + amount, max_drain_rate)


func _process(delta: float) -> void:
	if time_left > 0:
	if not setup_done:
		return
	if drain_enabled and time_left > 0:
		time_left -= delta * drain_rate
		time_left = max(time_left, 0)
		update_needle()

	# Below 10 seconds the readout switches to a hundredths-place countdown —
	# smooth enough to need every frame, not just the once-a-second tick the
	# lights and heartbeat are locked to.
	if time_left < 10:
		_update_label_text()

	# A torn suit seals itself slowly, so piercing hits stack into a spike that
	# then subsides rather than a permanent sentence.
	drain_rate = maxf(1.0, drain_rate - drain_recovery_per_second * delta)

	_update_borders(delta)
	_update_suffocation(delta)


## The letterbox. Both styles read the same threshold and both run in both
## directions, so recovering air always opens the frame back up again.
func _update_borders(_delta: float) -> void:
	var critical: bool = time_left <= border_slide_time
	if critical != _air_critical:
		_set_air_critical(critical)
		if border_style == BORDER_STYLE_SNAP:
			_slide_borders(critical)

	if border_style == BORDER_STYLE_CONTINUOUS:
		_track_borders_to_air()


## Bars pinned straight to the gauge. Squared so the frame barely moves for the
## first few seconds and then bites hard at the end — a linear crawl across the
## whole window reads as a slow letterbox rather than as the walls closing in.
func _track_borders_to_air() -> void:
	var closeness: float = 1.0 - clampf(time_left / maxf(border_slide_time, 0.001), 0.0, 1.0)
	var eased: float = closeness * closeness
	top_border.position = top_border_start_pos.lerp(top_border_end_pos, eased)
	bottom_border.position = bottom_border_start_pos.lerp(bottom_border_end_pos, eased)


## The original one-second cubic slide, made to run both ways.
func _slide_borders(closing: bool) -> void:
	if _border_tween != null and _border_tween.is_valid():
		_border_tween.kill()
	_border_tween = create_tween()
	_border_tween.set_parallel(true)
	var top_target: Vector2 = top_border_end_pos if closing else top_border_start_pos
	var bottom_target: Vector2 = bottom_border_end_pos if closing else bottom_border_start_pos
	_border_tween.tween_property(top_border, "position", top_target, 1) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_border_tween.tween_property(bottom_border, "position", bottom_target, 1) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Running out of air does not kill you — running out of lungs does.
##
## The tank reading zero starts this clock, and the player keeps playing for the
## whole of it. Get any air back and it unwinds, which is why this is a value that
## rises and falls rather than a tween that has been fired off and forgotten.
func _update_suffocation(delta: float) -> void:
	if _suffocated_emitted:
		return

	if time_left <= 0.0:
		if not _depleted_emitted:
			_depleted_emitted = true
			depleted.emit()
		_set_suffocation(_suffocation + delta / maxf(suffocation_time, 0.001))
		if _suffocation >= 1.0:
			_suffocated_emitted = true
			suffocated.emit()
		return

	# Air is back, so the last breath is no longer the last one.
	if _depleted_emitted:
		_depleted_emitted = false
		air_restored.emit()
	if _suffocation > 0.0:
		_set_suffocation(_suffocation - delta / maxf(suffocation_recovery_time, 0.001))


func _set_suffocation(progress: float) -> void:
	var clamped: float = clampf(progress, 0.0, 1.0)
	if is_equal_approx(clamped, _suffocation):
		return
	_suffocation = clamped
	suffocation_changed.emit(_suffocation)


func _set_air_critical(critical: bool) -> void:
	_air_critical = critical
	air_critical_changed.emit(critical)
	
	
## Lights up one bomb_container per bomb carried, left to right; the rest sit
## dimmed at the alpha already authored onto them in the scene.
func set_bombs(current: int, _max_bombs: int = 0) -> void:
	for i in bomb_containers.size():
		bomb_containers[i].self_modulate.a = BOMB_FULL_ALPHA if i < current else BOMB_EMPTY_ALPHA


func update_label() -> void:
	await get_tree().create_timer(0.2).timeout
	_alternate_lights()
	update_label_color()
	_update_label_text()


## Split out of update_label() so _process() can refresh just the text every
## frame under 10 seconds, without also re-triggering the lights and heartbeat
## that are meant to stay locked to the once-a-second GlobalTimer tick.
func _update_label_text() -> void:
	var new_text: String
	if time_left < 10:
		var seconds: float = time_left
		new_text = "%05.2f" % seconds
	else:
		var minutes := int(time_left) / 60
		var seconds := int(time_left) % 60
		new_text = "%d:%02d" % [minutes, seconds]
	label.text = new_text

func play_heartbeat():
	if time_left > 0:
		await get_tree().create_timer(0.1).timeout
		heartbeat.play("beat")
	else:
		heartbeat.play("flatline")

## Flips which trio of warning lights is lit, in step with the label ticking
## over. Keeps the two groups (1/3/5 and 2/4/6) in lockstep opposition rather
## than tracking three independent blink states.
func _alternate_lights() -> void:
	_lights_alternate = not _lights_alternate
	var odd_color := LIGHT_ON_COLOR if _lights_alternate else LIGHT_OFF_COLOR
	var even_color := LIGHT_OFF_COLOR if _lights_alternate else LIGHT_ON_COLOR
	for light in lights_odd:
		light.self_modulate = odd_color
	for light in lights_even:
		light.self_modulate = even_color

func update_label_color():
	if time_left < 10:
		label.modulate = LOW_TIME
	elif time_left < 31:
		var t: float = (time_left - 10.0) / 20.0
		label.modulate = LOW_TIME.lerp(MED_TIME,t)
	else:
		label.modulate = HIGH_TIME
		
func update_needle() -> void:
	var clamped_time: float = clamp(time_left, 0.0, NEEDLE_MAX_TIME)
	degrees = remap(clamped_time, 0.0, NEEDLE_MAX_TIME, 0.0, 180.0)
	needle.rotation_degrees = degrees
	
## The needle stops twitching while the tank reads empty — a dead gauge should
## read as dead. It starts again on its own if air comes back, because
## _depleted_emitted goes false again with it.
func flick_needle() -> void:
	if _depleted_emitted:
		return
	await get_tree().create_timer(0.3, false).timeout
	if _depleted_emitted:
		return
	var base_degrees := needle.rotation_degrees
	var tween := create_tween()
	tween.tween_property(needle, "rotation_degrees", base_degrees + FLICK_DEGREES, FLICK_DURATION)
	tween.tween_property(needle, "rotation_degrees", base_degrees, FLICK_DURATION).set_ease(Tween.EASE_OUT)
