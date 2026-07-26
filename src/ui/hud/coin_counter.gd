class_name CoinCounter
extends Node2D

@onready var icon = $Icon
@onready var label: Label = $Label


func set_coins(current: int) -> void:
	label.text = "%d" % current

func _ready():
	GlobalTimer.tick.connect(spin_coin)

func spin_coin():
	await get_tree().create_timer(0.1).timeout
	icon.play("spin")
