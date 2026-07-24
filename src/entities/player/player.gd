extends CharacterBody2D
@onready var sprite = $AnimatedSprite2D
const WALK_SPEED = 150
const DODGE_SPEED = 200
const DODGE_DURATION = 0.6  # total time the dodge burst lasts, in seconds
var input_vector := Vector2.ZERO
var last_direction = "down" 
var can_move = true
var is_dodging = false
var dodge_direction := Vector2.ZERO
var dodge_timer := 0.0

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

func dodge_down() -> void:
	can_move = false
	is_dodging = true
	dodge_direction = Vector2.DOWN
	dodge_timer = 0.0
	sprite.play("dodge_down")
	await sprite.animation_finished
	is_dodging = false
	can_move = true

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
