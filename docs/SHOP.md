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
    DropTable  { DropEntry{ item: oxygen_small.tres, price: 15 } }
    DropTable  { DropEntry{ item: oxygen_big.tres,    price: 25 } }
    DropTable  { DropEntry{ item: bomb.tres,          price: 20 } }
    DropTable  { DropEntry{ item: shotgun.tres,   price: 40 }
                 DropEntry{ item: timmy_gun.tres, price: 40 }
                 DropEntry{ item: chakram.tres,   price: 40 } }  ← rolls: 1
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

**A shelf rolls too, table by table** — the same `DropTable.rolls` /
`DropEntry.weight` every other source reads, not a special case. A table with
one row and no empty slot is guaranteed, so "oxygen small, always" is a
one-row table same as it would be on an enemy. A table with more rows than
`rolls`, like the weapon row above, is a genuine pick — `default.tres` sells
one random weapon rather than a fixed one, at the same price whichever it is.
`DropTableShopStockProvider` rolls each table exactly once, the moment
`ShopRegistry` first asks for this shop's stock, and the result is what
`ShopRegistry` then holds for the rest of the run — see below. `check_drops.gd`
still finds a storefront by its rows all being priced and reports it as a price
list, listing every row a table *could* pay out rather than simulating which
one a given shop rolled.

Stock is owned by `ShopRegistry` for the length of a run, keyed by floor and
coord. Rooms are freed when you walk out, so stock held on the room node would
restock itself on every visit and the same item could be bought forever.

`ShopStockProvider` is a port. `DropTableShopStockProvider` is what ships;
`StaticShopStockProvider` is a hand-authored list, kept because it is the
simplest possible implementation to test against.

## Resizing the shelf

`ShopGrid` on the `ShopRoom` node. Change `rows` or `columns` and the planks, the
cubbies, the items and the price tags all regenerate — nothing is hand-placed.
`tools/check_shop.gd` covers the indexing and the wrap, and
`tools/check_prompts.gd` checks that the prompts still clear the shelves after a
resize as well as that they name real buttons.

`center_gap` splits every row into two banks with a space between them, which is
where the shopkeeper stands — product either side of him, so the shelf reads as a
stall rather than a wall he happens to be in front of. It is purely about where
cubbies are *drawn*: the index space is unbroken, so stepping right off the last
cubby of the left bank lands on the first of the right with no special case.
Planks are drawn one per bank so neither runs behind him.

The shipped shape is 3 × 8 with a 96px gap — four cubbies each side. Two things
constrain it: the HUD covers roughly the top 31 room units (`HUD_BOTTOM` in
`tools/check_prompts.gd`), so `origin.y` has to clear that or the top row is
clipped; and the shelf has to end above the counter
at y 165.

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

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Talk to the shopkeeper, confirm a purchase | `E`, `Enter` | X (button 2) |
| Move the selection | arrows / WASD, **or hover an item** | D-pad / left stick |
| Buy | `E` / `Enter`, **or left-click an item** | X (button 2) |
| Step out of browsing | `Esc` | Y (button 3) |
| Leave | walk into the bottom of the frame | — |

Two of these are on screen while they apply: `TalkPrompt` at the counter, and
`BrowsePrompt` on the back wall for as long as you are browsing. Neither spells
its key out — both are written at runtime from [`InputPrompt`](../src/systems/input_prompt.gd),
which reads the real binding out of the input map and the last device the player
touched, so a pad reads `[PAD X] BUY    [PAD Y] LEAVE`. Prompts that name the
wrong button are worse than none, and `tools/check_prompts.gd` is what keeps
them honest.

Mouse and pad are both first-class: hovering moves the selection frame and
left-click buys, but only once the cursor has actually **moved**. A pointer left
resting over a cubby would otherwise re-select it every frame and quietly undo
every D-pad press, so it stays out of the way until you pick it up. Left-click is
`shoot`, which is dead while you are talking to the shopkeeper.

`back` is on Y rather than the conventional B because B is `bomb`, and on Escape
rather than Backspace, which is a text-editing key nobody reaches for in a game.

Escape leaves **browsing**, not the shop: one press hands the player back her
legs at the counter, a second one pauses, and leaving the room stays a deliberate
walk into the bottom of the frame. Escape is therefore bound to two actions at
once — `back` and `pause` — and `ShopRoom._input` is what keeps them apart. It is
the only input in this room that is *not* polled, because leaving has to
**consume** the press or the same Escape would also open the pause menu on top of
the player. Godot runs every `_input` in the tree before any `_unhandled_input`,
so it reliably beats `PauseMenu`.

Nothing global is suppressed to make that work — no `set_pause_allowed(false)`,
so there is no flag to leak if the room is freed mid-conversation. The `_engaged`
guard is read before `_disengage()` clears it, so the second press always reaches
the pause menu; a shop that never engaged never eats a press at all. `P` and pad
START still pause while browsing, which is better than taking them away.

Engaging freezes the player with `is_warping` rather than `can_move`, because
`bomb`, `shoot` and `reload` are all polled outside `player.gd`'s `can_move`
block — without it, Space would detonate a bomb while you read price tags. On a
pad, `interact` and `reload` share button X for the same reason it does not
matter: the freeze returns `player.gd` out of `_physics_process` before `reload`
is ever read, so the press only ever buys.

## Testing it

`src/screens/debug/shop_debug.tscn` (F6) runs the whole shop with no `Game` and
no clock, stocked from the real `DropConfig`. Point its `floor_number` at a
different descent index to see that floor's shelf without playing to it.

---

## Appendix: the vinaigrette

`vinaigrette.tres` currently does something boring — it raises your speed by one
level, and since `speed_up` stopped dropping (reload took its slots when the HUD
swapped rows) it is the only thing that does. The shelf rework moved it into
the chest pool, with one exception: the Floor 3 shelf still stocks it at 10
coins — a floor-specific `&"shop"` rule, so every run walks past it exactly
once. It is in the game under false pretences either way, and this is the note
explaining why, so that nobody later "fixes" it by deleting it.

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
