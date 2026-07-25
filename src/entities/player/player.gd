extends CharacterBody2D

class_name Player

@export var bullet_scene: PackedScene
@export var muzzle_offset := 25.0
@export var muzzle_y_offset := 6.0
@export var fire_rate := 0.05

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

var can_shoot := true
var gun_direction := Vector2.RIGHT


func _ready() -> void:
	gun_default_position = gun.position
	gun_default_scale = gun.scale


func _process(_delta: float) -> void:
	if is_dodging:
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	var direction: Vector2 = mouse_pos - gun.global_position
	gun.rotation = direction.angle()
	gun.flip_v = direction.x < 0
	gun_direction = direction.normalized()


func _physics_process(delta: float) -> void:
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


func shoot() -> void:
	can_shoot = false

	var bullet = bullet_scene.instantiate()

	var perpendicular := gun_direction.orthogonal()
	var flip_sign := -1.0 if gun_direction.x < 0 else 1.0
	var spawn_offset := gun_direction * muzzle_offset + perpendicular * muzzle_y_offset * flip_sign

	bullet.direction = gun_direction
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
