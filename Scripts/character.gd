extends CharacterBody2D

@onready var sprite = $AnimatedSprite2D

const WALK_SPEED = 150

var input_vector := Vector2.ZERO
var last_direction = "down" 
var can_move = true


func _physics_process(_delta: float) -> void:
	if can_move == true:
		velocity = Vector2(100, 0)
		input_vector.x = Input.get_axis("ui_left", "ui_right")
		input_vector.y = Input.get_axis("ui_up", "ui_down")

		input_vector = input_vector.normalized()
		
		velocity = input_vector * WALK_SPEED
		print (velocity)
		update_animation(input_vector)
		move_and_slide()


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
