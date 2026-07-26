class_name GrantCoins
extends ItemEffect

## Money.
##
## Amount is a property of the effect rather than of the coin sprite, so
## "coins SMALL" and "coins BIG" are two .tres files sharing one icon and one
## script instead of two of everything.

@export var amount: int = 1


func apply(target: Node) -> void:
	if not target.has_method("add_coins"):
		return
	target.add_coins(amount)


func describe() -> String:
	return "+%d coins" % amount
