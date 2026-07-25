extends CharacterBody2D

class_name Player

@export var bullet_scene: PackedScene
@export var muzzle_offset := 25.0
@export var muzzle_y_offset := 6.0
@export var fire_rate := 0.05
@export var bullet_damage := 10

@onready var sprite = $AnimatedSprite2D
@onready var gun: Sprite2D = $BigGunBTransparent

const WALK_SPEED = 150
const DODGE_SPEED = 200
const DODGE_DURATION = 0.6

var input_vector := Vector2.ZERO
var last_direction = "down"
var can_move = true
var is_dodging = false
var dodge_direction := Vector2.ZERO
var dodge_timer := 0.0
var gun_default_position: Vector2
var gun_default_scale: Vector2

## Right-stick deflection below this counts as the stick being at rest. Also the
## threshold for believing a joypad event means the player actually picked a pad
## up — sticks emit a constant trickle of noise even untouched.
const AIM_DEADZONE := 0.25

var can_shoot := true
## World-space aim, whichever device supplied it. Bullets and the gun sprite
## both read this, so neither has to know how the player is aiming.
var gun_direction := Vector2.RIGHT
## How hard the right stick is pushed, 0..1. Zero while aiming with a mouse —
## the camera derives its own strength from cursor distance in that case.
var aim_deflection := 0.0
## Which device last supplied aim. Both can be plugged in, so the most recent
## one wins and the player can swap mid-run without touching a settings screen.
var aiming_with_gamepad := false

## True while the Game is moving us between rooms. Physics is handed over to the
## transition for the duration — a dodge finishing mid-slide would otherwise
## re-enable can_move and fight the tween for control of our position.
var is_warping := false

## Something landed a hit. We deliberately hold no health of our own — the O2
## countdown is the health bar — so this reports upward and lets the run decide
## what a hit costs. Signals up, calls down: the player never touches the HUD.
signal damaged(amount: int, type: int)

## Seconds of mercy after a hit. Without it a stream of bullets lands several
## times a second and a roomful of enemies empties the tank in moments.
@export var invulnerable_time := 0.6

var _invulnerable_until_msec: int = 0


func _ready() -> void:
	gun_default_position = gun.position
	gun_default_scale = gun.scale


## Last device to speak wins. Joypad motion is filtered by deadzone because an
## untouched stick still emits events — without the filter a pad sitting on the
## desk would take aim back from the mouse every frame.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		aiming_with_gamepad = false
	elif event is InputEventJoypadButton:
		aiming_with_gamepad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > AIM_DEADZONE:
		aiming_with_gamepad = true


func _process(_delta: float) -> void:
	if is_dodging:
		return

	if aiming_with_gamepad:
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
		aim_deflection = minf(stick.length(), 1.0)
		# Releasing the stick holds the last aim rather than snapping the gun to
		# some default the player never chose.
		if aim_deflection > 0.0:
			gun_direction = stick / stick.length()
	else:
		aim_deflection = 0.0
		var to_cursor: Vector2 = get_global_mouse_position() - gun.global_position
		if not to_cursor.is_zero_approx():
			gun_direction = to_cursor.normalized()

	gun.rotation = gun_direction.angle()
	gun.flip_v = gun_direction.x < 0


func _physics_process(delta: float) -> void:
	if is_warping:
		return

	if is_dodging:
		dodge_timer += delta
		var t: float = clamp(dodge_timer / DODGE_DURATION, 0.0, 1.0)
		var speed_multiplier: float = 1.0 if t < 0.5 else (1.0 - ((t - 0.5) / 0.5))
		velocity = dodge_direction * DODGE_SPEED * speed_multiplier
		move_and_slide()
		return

	if can_move:
		input_vector.x = Input.get_axis("ui_left", "ui_right")
		input_vector.y = Input.get_axis("ui_up", "ui_down")
		input_vector = input_vector.normalized()

		velocity = input_vector * WALK_SPEED
		update_animation(input_vector)
		move_and_slide()

	if Input.is_action_just_pressed("dodge"):
		if can_move and velocity != Vector2.ZERO and last_direction == "down":
			dodge_down()

	if Input.is_action_just_pressed("shoot") and can_shoot and not is_dodging:
		shoot()


## Take a hit. Damage type is passed straight through — what blunt and piercing
## actually cost is the O2 timer's business, not ours.
##
## Invulnerability is measured against the wall clock rather than counted down in
## _physics_process, because _physics_process returns early while is_warping and
## a countdown there would freeze mid-transition.
func take_damage(amount: int, type: int = Damage.Type.BLUNT) -> void:
	if is_warping:
		return
	if Time.get_ticks_msec() < _invulnerable_until_msec:
		return
	_invulnerable_until_msec = Time.get_ticks_msec() + int(invulnerable_time * 1000.0)
	damaged.emit(amount, type)
	_flash_hit()


## Brief red flash, so a hit reads even when the only feedback is a number in the
## corner ticking down faster.
func _flash_hit() -> void:
	var flash := create_tween()
	flash.tween_property(sprite, "modulate", Color(1.0, 0.4, 0.4), 0.05)
	flash.tween_property(sprite, "modulate", Color.WHITE, invulnerable_time - 0.05)


## Move instantly, without the renderer drawing the trip. Physics interpolation
## is on project-wide, so without the reset a warp between rooms smears across
## a frame.
func warp_to(target: Vector2) -> void:
	global_position = target
	reset_physics_interpolation()


func shoot() -> void:
	can_shoot = false

	var bullet = bullet_scene.instantiate()

	var perpendicular := gun_direction.orthogonal()
	var flip_sign := -1.0 if gun_direction.x < 0 else 1.0
	var spawn_offset := gun_direction * muzzle_offset + perpendicular * muzzle_y_offset * flip_sign

	# Armed before it enters the tree, so its layers are settled by the time the
	# physics server sees it.
	bullet.arm(gun_direction, CollisionLayers.PLAYER_BULLET,
			CollisionLayers.WORLD | CollisionLayers.ENEMY, bullet_damage, Damage.Type.BLUNT)
	get_tree().current_scene.add_child(bullet)
	AudioManager.play_sfx("laser_gun_01")
	bullet.global_position = gun.global_position + spawn_offset
	bullet.reset_physics_interpolation()

	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true


func dodge_down() -> void:
	can_move = false
	is_dodging = true
	dodge_direction = Vector2.DOWN
	dodge_timer = 0.0
	sprite.play("dodge_down")

	var pull_tween := create_tween()
	pull_tween.set_parallel(true)
	pull_tween.tween_property(gun, "position", Vector2.ZERO, 0.1).set_ease(Tween.EASE_OUT)
	pull_tween.tween_property(gun, "scale", gun_default_scale * 0.2, 0.1).set_ease(Tween.EASE_OUT)

	return_gun()

	await sprite.animation_finished
	is_dodging = false
	can_move = true


func return_gun() -> void:
	await get_tree().create_timer(0.35).timeout
	var return_tween := create_tween()
	return_tween.set_parallel(true)
	return_tween.tween_property(gun, "position", gun_default_position, 0.15).set_ease(Tween.EASE_OUT)
	return_tween.tween_property(gun, "scale", gun_default_scale, 0.15).set_ease(Tween.EASE_OUT)


func update_animation(_input_vector):
	if velocity == Vector2.ZERO:
		sprite.play("idle_" + last_direction)
		return
	if Input.is_action_pressed('ui_up') and Input.is_action_pressed('ui_right'):
		last_direction = "up_right"
		sprite.flip_h = false
	elif Input.is_action_pressed('ui_up') and Input.is_action_pressed('ui_left'):
		last_direction = "up_right"
		sprite.flip_h = true
	elif Input.is_action_pressed('ui_up'):
		last_direction = "up"
	elif Input.is_action_pressed('ui_down') and Input.is_action_pressed('ui_right'):
		last_direction = "down_right"
		sprite.flip_h = false
	elif Input.is_action_pressed('ui_down') and Input.is_action_pressed('ui_left'):
		last_direction = "down_right"
		sprite.flip_h = true
	elif Input.is_action_pressed('ui_down'):
		last_direction = "down"
	elif Input.is_action_pressed('ui_right'):
		last_direction = "right"
		sprite.flip_h = false
	elif Input.is_action_pressed('ui_left'):
		last_direction = "right"
		sprite.flip_h = true
	sprite.play("walk_" + last_direction)
