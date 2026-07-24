extends CharacterBody2D

@export var bullet_scene: PackedScene
@export var muzzle_offset := 40.0  # distance from gun's pivot to barrel tip, tune to your sprite
@export var fire_rate := 0.15

@onready var sprite = $AnimatedSprite2D
@onready var gun: Sprite2D = $BigGunBTransparent
const WALK_SPEED = 150
const DODGE_SPEED = 200
const DODGE_DURATION = 0.6  # total time the dodge burst lasts, in seconds
var input_vector := Vector2.ZERO
var last_direction = "down" 
var can_move = true
var is_dodging = false
var dodge_direction := Vector2.ZERO
var dodge_timer := 0.0
var gun_default_position: Vector2
var gun_default_scale: Vector2

var can_shoot := true
var gun_direction := Vector2.RIGHT  # cached each frame from _process

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
	
	if can_move == true:
		velocity = Vector2(100, 0)
		input_vector.x = Input.get_axis("ui_left", "ui_right")
		input_vector.y = Input.get_axis("ui_up", "ui_down")
		input_vector = input_vector.normalized()
		
		velocity = input_vector * WALK_SPEED
		update_animation(input_vector)
		move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if can_move and velocity != Vector2.ZERO and last_direction == "down":
			dodge_down()
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if can_shoot and not is_dodging:
			shoot()

func shoot() -> void:
	can_shoot = false
	
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = gun.global_position + gun_direction * muzzle_offset
	bullet.direction = gun_direction
	
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
	sprite.play ("walk_" + last_direction)
