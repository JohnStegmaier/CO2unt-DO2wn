class_name CoinCounter
extends Node2D

@onready var label: Label = $Label


func set_coins(current: int) -> void:
	label.text = "%d" % current
