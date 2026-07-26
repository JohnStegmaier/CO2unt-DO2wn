class_name ShopOffer
extends Resource

## One thing on a shelf, and what this shop wants for it.
##
## Price lives here rather than on the item because it is not a property of the
## item: the same vinaigrette is free when an enemy drops it and costs ten in a
## shop, and a second shop is free to charge something else. Pairing the two at
## the shelf is what keeps the item catalogue from having to know shops exist.


## The catalogue entry being sold. The shop reads what it looks like off this and
## hands the whole thing to [method ItemDef.grant_to] on purchase, so buying and
## picking up run the same code — which is what that method exists for.
@export var item: ItemDef

## What this shop charges. Coins.
@export var price: int = 10


## What to call this on a price tag. Falls back to the resource name so a
## half-authored item is still identifiable on the shelf rather than blank.
func display_name() -> String:
	if item == null:
		return "?"
	if not item.display_name.is_empty():
		return item.display_name
	return item.resource_name
