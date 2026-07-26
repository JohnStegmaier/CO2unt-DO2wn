class_name StaticShopStockProvider
extends ShopStockProvider

## The shipped adapter: every shop sells the same authored list.
##
## Deliberately the dullest possible implementation of [ShopStockProvider]. It
## exists so the shop is playable and configurable from the inspector today, and
## so the port has one working reference to be replaced against — a provider that
## rolls stock per floor, or reads a drop table, swaps into the same slot.

## What every shop stocks, in shelf order. Anything past the shelf's capacity is
## dropped by [ShopStock].
@export var offers: Array[ShopOffer] = []


## Deliberately ignores floor and coord: "static" is the whole contract. A copy
## is returned rather than the array itself, so a shop that sells out cannot
## quietly empty the configuration every other shop is reading from.
func stock_for(_floor_number: int, _coord: Vector2i, capacity: int) -> Array[ShopOffer]:
	var result: Array[ShopOffer] = []
	for offer in offers:
		if result.size() >= capacity:
			break
		if offer != null:
			result.append(offer)
	return result
