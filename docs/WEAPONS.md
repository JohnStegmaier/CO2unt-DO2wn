# Weapons

## The bet

A weapon is a `.tres`, not code.

There is one branch in the game that asks what you are holding — `should_fire`,
which asks whether the trigger is held or was just pulled — and there will only
ever be one, however many guns ship. Everything else that differs between a
pistol and a shotgun is a number on a resource: how fast, how many, how wide,
how hard, how long you keep it.

That is the same bet `docs/DROPS.md` made for items, and it is made here for the
same reason: the previous shotgun was five exports on `Player`, a `_shotgun_active`
bool, a branch inside `shoot()`, a bespoke effect script and a
`set_shotgun_equipped(bool)` on the HUD. A fourth weapon written that way is a
file nobody can read at 5am.

## The shape

```
WeaponDef ──── extends ItemDef, so it is already a droppable thing
   │              equip time, firing, projectile, audio
   │
   ├─ Loadout ── what is held right now: ammo, reload, cooldown, countdown
   │                (a component node, src/components/loadout/)
   │
   └─ DropEntry ─ one row of a DropTable — the ONLY thing that says where a
                  weapon comes from. No weapon-specific routing exists.
```

| File | What it is |
|---|---|
| `src/systems/weapons/weapon_def.gd` | The form. Pure data and pure maths — no node, no autoload. |
| `src/components/loadout/loadout.gd` | The runtime. One weapon at a time, and every clock attached to it. |
| `src/entities/gun_stuff/projectile.gd` | What `arm()` means. `bullet.gd` and `chakram.gd` extend it. |
| `src/config/weapons/*.tres` | The weapons themselves. One file each. |
| `tools/check_weapons.gd` | The invariants, the spread maths, and the routing report. |

## Adding a weapon

Three steps. None of them is a script edit.

1. In the editor, right-click in `src/config/weapons/` → **New Resource** →
   `WeaponDef`. Fill in the form. The groups are in the order you need them:
   Appearance (the pickup), Equip (how long, how it is held), Firing, Projectile,
   Audio.
2. Add a `DropEntry` for it to whichever `DropTable` should offer it, in
   `src/config/drops/default.tres`. Or don't — a weapon in no table is simply
   never offered, which is a legitimate place for one to sit while it is tuned.
3. `godot --headless --script tools/check_weapons.gd`

Nothing else. It gets a pickup, a shop shelf, a HUD icon, a countdown bar with a
seconds readout beside it, and a drop table for free, because it is an `ItemDef`
and everything downstream of one already works.

### If it needs a new sound

Add the key to the `sounds` dictionary in `src/autoload/audio_manager.gd`, then
name it in `fire_sound`. An unknown key is silence rather than a crash, which is
the deliberate escape hatch for audio that has not landed yet.

### If it needs to fly differently

Only then is there a script. A new scene under `src/entities/gun_stuff/`
extending `Projectile`, overriding `_on_body_entered`. `chakram.gd` is eleven
lines: it remembers what it has already cut and does not free itself on contact.
Then name the scene in `projectile_scene`. Nothing that fires weapons changes.

## The two fields that carry design weight

**`equip_seconds`.** Zero means permanent. That is the *only* thing separating
the starting pistol from everything else — there is no "is the starter" flag.
When a window runs out the player falls back to `Loadout.starting_weapon`,
never to the previous pickup, so three weapons in a row leave no stack to unwind.
Picking the same weapon up mid-window does not stack either: it tops the magazine
up and restarts the clock, the same bargain `gain_bomb` makes at the cap.

The countdown is **suspended** whenever the player is frozen — a shop, a lift —
via `Player.is_warping`. A twenty-second weapon should not be spent reading price
tags.

**`scales_with_player_stats`.** On for the pistol, off for everything picked up.
On, the weapon draws damage and fire interval from `Player.BULLET_DAMAGE_VALUES`
and `FIRE_RATE_VALUES`, so power-ups are felt through the gun you own.

Off, it keeps **its own** numbers — a shotgun is a different weapon, not your gun
renamed — but multiplied by how far `POWER_LVL` and `FIRERATE_LVL` have come from
level 1. So a shotgun found on floor 5 does hit harder than one found on floor 1,
in proportion, while the gap between a shotgun and a timmy gun stays as tuned. At
`POWER_LVL` 7 that factor is 35/10 = ×3.5, the same curve the pistol rides.

The flag was an all-or-nothing swap until upgrades reached the shop. A Damage
Upgrade that goes invisible for the twenty seconds a borrowed gun is held reads
as a broken purchase, not as weapon identity — so the scaling lives in
`WeaponDef.damage_against` / `interval_against`, which is the one place to change
it and the only place either number is read.

## Where weapons come from

There is no weapon routing. A weapon is a row in a `DropTable`, so the four
answers are the four things a `DropRule` can be keyed on, and a fifth answer is
"no row at all".

| Route | How | Shipped today |
|---|---|---|
| Prop | a row in the `&"crate"` / `&"barrel"` table | shotgun 8%, timmy gun 8%, chakram 6% |
| Chest | a row in the `&"chest"` table | all three, evenly — treasure rooms are not wired up yet, but the rule is |
| Shop | a row with a `price` on the `&"shop"` shelf | chakram @ 40 coins |
| Enemy | a row in the `&"grunt"` / `&"skirmisher"` / `&"boss"` table | **none — deliberately** |
| Nowhere | no row anywhere | — |

**Enemies drop no weapons today, and turning that on is one row.** Add a
`DropEntry` pointing at the weapon to the grunt table in `default.tres` and
rebalance the "nothing" row against it. The reason it is off is not design: the
enemy tables are locked by `DEFAULT_RATES` in `tools/check_drops.gd`, so adding a
row there moves every other rate and that lock has to be updated in the same
breath. That is the check doing its job, not an obstacle.

## The checker

```bash
godot --headless --script tools/check_weapons.gd
```

Asserts the things that make a weapon usable at all — an icon, a held texture, a
projectile scene, a magazine of at least one, unique ids, and a starting weapon
that is actually permanent.

Then it exercises `shot_directions()`, which is why that maths is pure: it proves
every projectile leaves as a unit vector, that the right number leave, that none
leaves further off-aim than half the spread, and that an even fan is **symmetric
about the aim** rather than hanging off one side of it. That last one is the
off-by-one that turns a shotgun into a gun that shoots slightly to the right, and
it is invisible in play.

Finally it prints where every weapon can be found:

```
default.tres — where weapons come from
  chakram      crate 6.3%, barrel 6.3%, chest 33.5%, shop @ 40 coins
  pistol       carried from the start
  shotgun      crate 8.2%, barrel 8.2%, chest 33.5%
  timmy_gun    crate 8.1%, barrel 8.1%, chest 33.5%
```

Rolled through the same `LootRoller` the game uses rather than derived from the
weights, so a rule that resolves to nothing or a row shadowed by a more specific
rule shows up as a missing route instead of as a weight that looked fine.

`NOWHERE — offered by no source` is a report, not a failure. An unreferenced
config file looks exactly like a referenced one, and this is the only place that
difference is visible.

## What ships

| Weapon | Equip | Trigger | Mag / reload | Per pull | Damage | Feel |
|---|---|---|---|---|---|---|
| Pistol | permanent | semi | 6 / 1.2s | 1 | *scales with POWER* | The gun you own. Unchanged from before this system existed. |
| Shotgun | 20s | semi | 2 / 1.2s | 5 pellets, 18° even fan | 10 each | Devastating at point blank, two shots and you are reloading. |
| Timmy Gun | 20s | **automatic** | 30 / 1.6s | 1, 7° random | 6 | Hold the trigger. Sprays. |
| Chakram | 20s | semi, 0.45s | 4 / 1.4s | 1 piercing | 18 piercing | Slow, heavy, passes through everything in a line. |

The Timmy Gun is the only automatic — it is the reason `fire_mode` exists, and
the reason the trigger is read two ways.

The Chakram is the only weapon that needed a projectile script, and it is the
proof the `Projectile` split works: adding it changed nothing in `Loadout`,
`Player` or `WeaponDef`.

## Things worth knowing before you change something

- **`Projectile.arm()` and `Projectile.direction` belong to more than the
  player.** `enemy.gd` calls `arm()`, and the skirmisher's dodge sensor reads
  `direction` off the node by name. Renaming either fails *silently* into
  "enemies never dodge".
- **The gun sprite is the player's, not the weapon's.** A `WeaponDef` brings its
  own texture, scale, offset, flip, crop and tint, and `Player._apply_weapon_look`
  puts them on `$BigGunBTransparent`. The art in this project is authored at
  wildly different sizes — the pistol is 242×202 drawn at 0.05, the shotgun is
  14×3 drawn at 1.0 — so those fields are how a weapon looks, not fudge factors.
- **Cooldowns are counted down, not awaited.** An awaited `SceneTreeTimer` cannot
  be cancelled, so swapping weapons or freezing for a shop mid-wait would leave a
  coroutine that comes back and re-arms a gun you are no longer holding.
- **The Loadout knows nothing about the player.** The two numbers it needs for
  the pistol are pushed in from above. It could be given to anything that can
  hold a gun; enemies fire their own way today, and giving them one is a job of
  its own.
