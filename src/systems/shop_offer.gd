class_name ShopOffer
extends Resource

## One thing on a shelf, and what this shop wants for it.
##
## Price lives here rather than on the item because it is not a property of the
## item: the same vinaigrette is free when an enemy drops it and costs ten in a
## shop, and a second shop is free to charge something else. Pairing the two at
## the shelf is what keeps the item catalogue from having to know shops exist.


## The catalogue entry being sold. Typed [Resource] rather than ItemDef on
## purpose — the catalogue is authored on the drops branch and does not exist on
## master yet. Everything here treats it as opaque and hands it to whoever asked,
## so when ItemDef lands this annotation tightens by one word and nothing else
## moves. Declaring a local ItemDef instead would collide with theirs on merge.
@export var item: Resource

## What this shop charges. Coins, whatever they end up being called.
@export var price: int = 10


## The art to draw in the cubby, or null if the item has none yet.
##
## Duck-typed rather than reaching for a property that is not on master yet, so a
## stubbed item without an icon draws nothing instead of faulting.
func icon() -> Texture2D:
	if item == null or not ("icon" in item):
		return null
	return item.icon as Texture2D


## What to call this on a price tag. Falls back to the resource name so a
## half-authored item is still identifiable on the shelf rather than blank.
func display_name() -> String:
	if item == null:
		return "?"
	if "display_name" in item and not String(item.display_name).is_empty():
		return String(item.display_name)
	return item.resource_name
