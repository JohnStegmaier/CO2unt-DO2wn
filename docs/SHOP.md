# The shop

A belt-scroll room, seen from the side. You walk a shallow strip in front of a
counter, the scenery slides against itself as you look around, and the run's
clock stops while you are inside.

It is a [`Room`](../src/levels/shop_room/shop_room.gd) like any other, so `Game`
instances it into `RoomContainer` and it reports the side you left through. It
knows nothing about the clock, the music or the item catalogue.

---

## How a shop gets its stock

Stock routes through the same drop configuration everything else does. A
`DropRule` is keyed on a **source**, and the shop's source is `&"shop"` — which
is exactly what [DROPS.md](DROPS.md) says the source keying is for.

```
default.tres
  DropRule(source = &"shop")
    DropTable
      DropEntry{ item: vinaigrette.tres, price: 10 }
      DropEntry{ item: speed_up.tres,    price: 25 }
             │
             ▼
  DropTableShopStockProvider   (the adapter)
             │  Array[ShopOffer]
             ▼
  ShopRegistry  ──►  ShopStock  ──►  ShopRoom
```

**`price` lives on `DropEntry`, not on `ItemDef`.** A price is not a property of
a thing — the same oxygen canister is a free drop on floor 5 and costs coins in a
shop. Putting it on the row means the rule that routes an item to a source also
says what that source charges. Rows that are never sold leave it at zero.

**One reinterpretation to know about.** A `DropTable` is normally a pool you
*roll*. A shelf is not a roll — it is everything on offer, laid out. So
`DropTableShopStockProvider` takes every row rather than sampling, and
`DropEntry.weight` is ignored for a storefront source. `check_drops.gd` detects
storefronts by their rows all being priced, reports them as a price list rather
than a drop rate, and asserts they are actually sellable.

Stock is owned by `ShopRegistry` for the length of a run, keyed by floor and
coord. Rooms are freed when you walk out, so stock held on the room node would
restock itself on every visit and the same item could be bought forever.

`ShopStockProvider` is a port. `DropTableShopStockProvider` is what ships;
`StaticShopStockProvider` is a hand-authored list, kept because it is the
simplest possible implementation to test against.

## Resizing the shelf

`ShopGrid` on the `ShopRoom` node. Change `rows` or `columns` and the planks, the
cubbies, the items and the price tags all regenerate — nothing is hand-placed.
`tools/check_shop.gd` covers the indexing and the wrap.

## Drawing an item

The shop draws `backdrop` then `icon`, each at the scale the `ItemDef` authored,
and shrinks the pair only if it would overflow its cubby. An item on the shelf
has to be recognisably the item you find on the floor, so the shop honours
`icon_scale` and `backdrop_scale` rather than fitting the bare texture to the
cell.

## The clock

Entering a shop stops the countdown, the once-a-second tick and the run's music,
and leaving resumes all three **in phase**. That is
[`ClockHold`](../src/systems/clock_hold.gd), and the reasoning is in its
docstring — the short version is *freeze, never stop and restart*.

This means a shop is a safe room you can stand in indefinitely. That is
deliberate. If it ever needs a budget, `ClockHold.set_held()` is the one place
that would change.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Talk to the shopkeeper, confirm a purchase | `E`, `Enter` | X (button 2) |
| Move the selection | arrows / WASD | D-pad / left stick |
| Step out of browsing | `Backspace` | Y (button 3) |
| Leave | walk into the bottom of the frame | — |

`back` is on Y rather than the conventional B because B is `bomb`. Engaging
freezes the player with `is_warping` rather than `can_move`, because `bomb`,
`shoot` and `reload` are all polled outside `player.gd`'s `can_move` block —
without it, Space would detonate a bomb while you read price tags.

## Testing it

`src/screens/debug/shop_debug.tscn` (F6) runs the whole shop with no `Game` and
no clock, stocked from the real `DropConfig`. Point its `floor_number` at a
different descent index to see that floor's shelf without playing to it.

---

## Appendix: the vinaigrette

`vinaigrette.tres` currently does something boring — it raises your speed by one
level, same as `speed_up`. It is on the shelf under false pretences, and this is
the note explaining why, so that nobody later "fixes" it by deleting it.

**It is a typo that became canon.** It comes from mispronouncing *vignette* while
describing the death sequence — the dark closing in as you suffocate, which is
`O2Timer`'s letterbox and `DeathOverlay`'s closing dark.

**What it is eventually meant to do:** buying the vinaigrette should slow the
*vignette* part of dying substantially, giving you a window to recover from a
death that would otherwise be final. Mechanically that means an effect that
raises `O2Timer.suffocation_time` — the seconds you survive on an empty tank,
which the player keeps full control for — or slows `suffocation_changed`'s climb.

That is out of scope for the change that added the shop. When someone picks it
up, it is a new `ItemEffect` beside the others in `src/systems/loot/effects/`
and a one-line edit to `vinaigrette.tres`. Nothing else has to move, which is
the entire point of the catalogue being data.
