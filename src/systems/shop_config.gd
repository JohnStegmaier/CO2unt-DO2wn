class_name ShopConfig
extends Resource

## Everything the run needs to know about shops, in one inspector slot.
##
## Bundled rather than spread across four exports on [Game] because game.tscn is
## edited by more than one branch at a time and .tscn files do not merge — one
## property is one conflict instead of four. Same shape as [FloorConfig], which
## is already authored as a sub-resource in that scene.
##
## An empty [member room_scene] turns the whole feature off: shops fall back to
## ordinary rooms with their placeholder tint, exactly as if this had never been
## added.

@export_group("Room")
## Stand-in scene for any cell the floor plan marked as a shop. Injected rather
## than preloaded so [Game] names no shop class and clearing the slot removes the
## feature with no code change — the same reasoning as exit_room_scene.
@export var room_scene: PackedScene

@export_group("Stock")
## Where a shop's shelves come from. See [ShopStockProvider].
@export var stock_provider: ShopStockProvider

@export_group("Economy")
## What the player starts a run with. Overridable from a tuning profile via the
## [code][shop][/code] section — see docs/TUNING_PROFILES.md.
##
## A shop concern rather than a player one: the coins themselves belong to the
## player, but how many a run opens with is an economy knob and this is where the
## economy is tuned.
@export var starting_coins: int = 60

@export_group("Audio")
## Named track from AudioManager, played while the player is in a shop. Empty
## plays nothing, so a build without the music file is quiet rather than broken.
@export var music: String = "shop_calm"


## Fold in whatever the active tuning profile's [code][shop][/code] section says.
##
## Called by the run rather than from the constructor, so a config built by a
## tool or a test is exactly what its caller asked for. Mirrors
## [method FloorConfig.apply_overrides].
func apply_overrides() -> void:
	starting_coins = GameConfig.get_value("shop", "starting_coins", starting_coins)
