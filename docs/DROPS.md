# Drops

What enemies leave behind, and how to change it without touching code.

Three candidate drop economies were designed for this game. Reading them side by
side, the *items* barely differ — what differs is **which source offers each
item**. The crossbow is a chest drop in one, an enemy drop in another, and a shop
item in the third. So this is not three drop systems. It is:

- **an item catalogue** — stable: what a thing *does*
- **a routing table** — volatile: which source offers it, how often, on which floor

Picking an economy is swapping one `.tres`. Tuning one is editing rows in it.

| Where | What |
|---|---|
| `src/systems/loot/` | the types — pure data plus one static roller |
| `src/config/items/*.tres` | the catalogue: one file per item |
| `src/config/drops/*.tres` | the routing tables: one file per economy |
| `tools/check_drops.gd` | validates every config and prints the real drop rates |

## The pieces

```
ItemDef ─── effects: [ItemEffect, …]      what a thing is and does
   ▲
DropEntry ── item + weight + count        one row of a pool
   ▲
DropTable ── rolls + [DropEntry, …]       a pool, drawn from `rolls` times
   ▲
DropRule ─── source + floors + [DropTable, …]
   ▲
DropConfig ─ [DropRule, …]                one whole economy
```

`DropConfig` is a `Resource` rather than constants in a script for the same
reason `FloorConfig` is: a run's economy becomes an inspector slot you can swap
and tune while the game is running. It holds no RNG and makes no decisions —
`LootRoller` does the rolling — so reading a config can never change what drops.

### Sources

A `DropRule` is keyed on a **source**, not on "enemy": `&"booger"`, `&"guard"`,
`&"licker"`, `&"turret"`, `&"boss"`, `&"shop"`, `&"crate"`, `&"barrel"`, and
later `&"chest"`. An enemy carries only its `loot_source`, and its `EnemyDef`
says what that is — see docs/ENEMIES.md. `game.gd` overrides it in exactly one
case, `&"boss"` for the one it just promoted, which is what lets a single boss
row serve every archetype instead of needing one per enemy. A prop carries its
own the same way — `Obstacle` reuses its `ObstacleDef.id`, since that was
already a unique name for the row and nothing else indexed by it.

The rows were `&"grunt"` and `&"skirmisher"` when an enemy's drop row was named
after the behaviour `game.gd` had just handed it. With four archetypes carrying
their own defs, they are named after the enemy.

That is what lets the treasure room and the shop use this same table when they
land, instead of needing a loot system each. A source with no rule drops nothing,
which is what makes an unnamed source quiet rather than an error.

#### Storefronts

The shop is the first source that does not roll. `DropEntry.price` is what a
source charges for a row — zero everywhere else — and a source whose rows are
**all** priced is a storefront: everything on it is offered at once rather than
sampled, so `weight` means nothing there. `check_drops.gd` recognises one by that
same all-priced test, prints it as a price list instead of a drop rate, and
asserts it is actually sellable. See [SHOP.md](SHOP.md).

### Floors

`DropRule.floors` is a list of **descent indices** — `0` is the top floor, `5` is
the Basement. See [`FloorLadder`](../src/systems/floor_ladder.gd): the index
counts up while the sign on the wall counts down, so index 3 is "FLOOR 2".

Empty means every floor. A rule that names floors **beats** one that names none,
so the baseline for a source is one rule and a deeper-floor override is a second.
Resolution is most-specific-wins, not a merge — "floor 3 grunts drop everything
grunts drop, plus this" reads well right up until you want floor 3 to drop
*less*, and a rule you cannot subtract from is worse than one you write out.

### Weights, and the "nothing" row

Weights are relative, not percentages: a row at `2.0` comes up twice as often as
one at `1.0`, whatever else is in the table. A `DropEntry` with **no item** is the
"nothing drops" row.

That is why there is no `drop_chance` anywhere in this system. The old code had
two of them on the enemy plus a comment warning you to keep their sum under 1.0;
a table cannot express that bug.

A **guaranteed** drop is a table with no empty row — that is how "coins SMALL,
always some per room" is written.

## Adding an item

1. If it needs a new kind of effect, write one — a script in
   `src/systems/loot/effects/` extending `ItemEffect` with an `apply(target)` and
   a `describe()`. Ten lines is typical; see `grant_bomb.gd`.
2. In the editor, right-click in `src/config/items/` → **New Resource** →
   `ItemDef`. Fill in `id`, `display_name`, `icon`, and add your effect to
   `effects`.
3. Add a `DropEntry` for it to whichever `DropTable` should offer it.
4. `godot --headless --script tools/check_drops.gd`.

No existing file has to be edited to make room, which is the point of `effects`
being an array of resources rather than a kind-and-amount pair.

### Worked example: the bomb

The bomb is the useful case to copy, because its *mechanic* lives somewhere else
entirely. `player.gd` already owns `use_bomb()`, `_spawn_pulse()` and
`gain_bomb()`. Making it a drop took:

- `grant_bomb.gd` — six lines, calling `target.gain_bomb()`
- `src/config/items/bomb.tres` — the orb backdrop, the bomb icon, that one effect
- one row in `default.tres`

and nothing in `player.gd` changed. An item whose behaviour already exists
somewhere is a `.tres` and an adapter, not a feature.

## Appearance

One scene, `src/entities/pickup/item_pickup.tscn`, draws every item. `ItemDef`
carries `icon` + `icon_scale` and an optional `backdrop` + `backdrop_scale`:

- **oxygen** is a single picture — `Drop_orb_o2.png`, no backdrop
- **the bomb** is `bomb.png` layered on the `Drop_orb.png` glow

Both hover as one unit, so the layers cannot drift apart. Sprites here are
authored much larger than they are drawn, so the scale is part of how an item
looks rather than a fudge factor — the orb sits at `0.265`, the coin at `0.15`.

## Sound

Two fields, because a drop makes noise at two different moments:

| Field | Fires | Played by |
|---|---|---|
| `drop_sound` | the item hits the floor | `game.gd._spawn_loot` |
| `pickup_sound` | the player collects it | `item_pickup.gd` |

The coin uses both — `money_drop_2` landing, `money_jingle_1` on collection.
Leave either empty for silence.

A `drop_sound` plays **once per distinct sound per spawn**, so a table that drops
three coins at once makes one noise rather than three stacked copies of it.

Both are `StringName`s naming a bare file under `assets/audio/sfx/`, the way
`AudioManager.play_sfx` wants them. They live on the item rather than in code so
that "what noise does a coin make" is tuned in the same Inspector as everything
else about the coin.

## Switching economies

The inspector slot on `game.tscn` is what ships. A tuning profile can redirect
it for a playtest without editing anything tracked:

```ini
[drops]
config = "economy"
```

`drops_economy` is already in the toolbar dropdown — pick it, press play. See
[TUNING_PROFILES.md](TUNING_PROFILES.md). A mistyped name is a loud error, not a
silent fall back to the shipped tables.

## Checking your work

```bash
godot --headless --script tools/check_drops.gd
```

Validates every config — unique ids, no empty slots, no negative weights, every
source resolving on every floor — then rolls each table 100,000 times and prints
what actually comes out:

```
res://src/config/drops/economy.tres
  grunt        index 0 (FLOOR 5)
      coin_small     200.08 per 100 kills
      oxygen_small    14.93 per 100 kills
```

That table is the useful part when tuning. A config that passes every check can
still be miserly, and playing until something drops is a slow way to find out.

It also asserts that `default.tres` still pays what the hard-coded roll it
replaced did. Retuning the shipped economy fails that check once, on purpose:
updating `DEFAULT_RATES` in the checker is how you say you meant it.

## What ships

- **`default.tres`** — the shipped economy:

  | Row | Weight | Rate |
  |---|---|---|
  | `coin_small` | 0.40 | 40% |
  | `oxygen_small` | 0.20 | 20% |
  | `bomb` | 0.20 | 20% |
  | `power_up` | 0.03 | 3% |
  | `firerate_up` | 0.03 | 3% |
  | *(nothing)* | 0.14 | 14% |

  **This is the one deliberate balance change in the branch.** PR #51's roll was
  coin 0.6 / oxygen 0.2 / bomb 0.2, summing to 1.0 — every kill dropped
  something. Coins are thinned to 0.4 and the freed 0.2 becomes a chance of
  nothing; **oxygen and bomb are untouched at 0.2 each**. Guaranteed loot from
  every enemy devalues it, and oxygen is effectively the health bar here, so it
  should not get rarer just because coins got commoner.

  The two stat upgrades were later paid for out of that same *nothing* row —
  0.06 of it — for the reason below. The three asserted rates did not move,
  which is the point: the row that shrank is the one nobody feels.

  `tools/check_drops.gd` asserts these rates, so nothing else can drift into the
  shipped economy unnoticed.

### Where the upgrades are offered

`power_up` and `firerate_up` reached the shop the long way round. They existed,
worked, and had art from the day the catalogue did — and were routed **only** to
`&"chest"`, so a run that found no treasure room never saw a single one and the
game read as having three drops. The catalogue was never the problem; the routing
table was, which is the distinction this whole file is built on.

They now appear on four sources, deliberately at four different pressures:

| Source | Offer | Why |
|---|---|---|
| `&"shop"` | 30 coins each | The guaranteed one. Coins finally buy power, not just a salad. |
| `&"chest"` | in the upgrades pool | Unchanged. |
| `&"crate"` / `&"barrel"` | 0.05 each | Out of the prop table's *nothing*, 0.78 → 0.68. Rewards smashing scenery. |
| enemies | 0.03 each | Rare on purpose — see below. |

Enemy rate is the one worth arguing about. A level is **permanent** and the cap is
7, so at 3% a hundred-kill run hands out roughly three of each and a long run
still cannot max a stat off trash alone. Raise it and the shop rows stop being
worth 30 coins.
- **`economy.tres`** — the coin-heavy candidate, as far as the current item set
  reaches. Also the worked example of the three things a rule can do that the
  default does not: a guaranteed table beside a chance table, a source that
  differs from the others, and a floor-specific override.

## Weapons

A weapon is an item like any other here — `WeaponDef` extends `ItemDef` and
equips itself on pickup — so it is a row in a `DropTable` and needs nothing else
from this system. Crates, barrels, chests and the shop all offer them today; the
enemy tables deliberately do not, because they are rate-locked by
`check_drops.gd`. See **docs/WEAPONS.md**.

A picked-up weapon keeps its own damage and fire interval, but both are now
scaled by the player's POWER and FIRERATE levels — otherwise a Damage Upgrade
bought from the shop does nothing for the twenty seconds a borrowed gun is held,
which reads as a broken purchase. See `scales_with_player_stats` in
**docs/WEAPONS.md**.

## The three candidate economies

Kept here as the roadmap. All three assume chests and a shop. Four of the six
weapons now exist — pistol, shotgun, timmy gun and chakram, under
`src/config/weapons/` — and the rest become a `.tres` each when their art does.

Common to all three:

- **Boss** — max ammo / weapon timer up, and/or max oxygen up, plus a big coin.
- **Minor enemies** — duct tape, small oxygen (common), small coins (always some
  per room).

**1 — Ammo.** Weapons come from chests and carry ammo counts. Chest: oxygen
small/big, move speed up, crossbow, freeze gun, chakrams, shotgun, flamethrower,
coins medium/big. Buyable: bomb, more bullets per shot, adrenaline, chill pill,
weapon damage up, helmet upgrade, suit sealant, minigun, charge shot.

**2 — Timeouts.** Weapons are timed pickups from enemies rather than ammo from
chests, gun-game style. Chest keeps the consumables plus the minigun; the five
weapons move to the minor-enemy table.

**3 — Economy.** Coins are the point — it leans hardest into the capitalist
hellscape. Chest gains the minigun, charge shot, helmet and sealant; the weapons
move into **shop pools**, three of them: weapons + bomb, then damage/speed
upgrades, then oxygen/chill pill/shield.

`DropTable` is already the "pool" those three pools mean, so config 3 needs no
new types — just a `DropRule` for `&"shop"` holding three tables.
