class_name ShopStockProvider
extends Resource

## PORT — what a shop has in stock.
##
## The item catalogue and the rules for which items show up where are authored
## elsewhere. This is the one question the shop asks, and anything that can
## answer it can be dropped into [ShopConfig]'s provider slot from the inspector
## without a line of shop code moving.
##
## Three explicit arguments rather than a context dictionary: whoever implements
## this gets a signature the compiler checks, and a fourth argument later is
## cheaper to add than a bag of string keys is to unpick.
##
## Returning an empty array is a legitimate answer — it means a shop with bare
## shelves, not an error.


func stock_for(_floor_number: int, _coord: Vector2i, _capacity: int) -> Array[ShopOffer]:
	return []
