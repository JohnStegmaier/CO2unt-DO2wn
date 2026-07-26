# Tuning profiles

Named sets of tuning overrides you can run the game with, so a test value never
has to be typed into a script that then gets committed. This exists because
`total_time` in `o_2_timer.gd` flip-flopped between 15 and 90 three separate
times in git history — see issue #26.

Godot has no profile system of its own, so this is ours. Three pieces:

| Where | What |
|---|---|
| `src/config/profiles/*.cfg` | the profiles themselves |
| `src/autoload/game_config.gd` | reads the selected one at startup |
| `addons/profile_switcher/` | the editor toolbar dropdown |

## Switching

**In the editor:** pick one from the dropdown in the top toolbar, then press
play as normal. That is the whole workflow.

The dropdown writes your choice to `src/config/local.cfg`, which `.gitignore`
covers, so what you select is yours alone and cannot follow you into a pull
request. This is deliberately *not* Project Settings → Editor → Run → Main Run
Args: that field lives in `project.godot`, which is tracked, so committing it
would hand your debug profile to everyone who presses F5 — a milder replay of
the exact accident this feature exists to stop.

**From a terminal:**

```bash
godot -- --profile=die_quickly
```

The bare `--` is load-bearing: it is what tells Godot that the rest is for the
game rather than the engine. A `--profile=` argument beats whatever the dropdown
has selected, so scripted and CI runs get what they asked for.

Whenever a profile is active it prints an orange banner listing every value it
changed, and the toolbar dropdown tints orange. A forgotten profile that looks
like normal play is the one failure mode that would make this worse than
nothing.

Profiles are refused outside a debug build, so none of this can reach players.

## What there is

Listed the way the dropdown lists them: get out of my way, then shape the floor,
then make it hard.

| Profile | What it does |
|---|---|
| `god_mode` | Unlimited air, health and ammo. Enemies still spawn and still shoot. |
| `peaceful` | No enemies anywhere, no drain, no damage. An empty station to walk around. |
| `infinite_oxygen` | 24 hours of air. Damage still costs seconds, so a fight can still kill you. |
| `tiny_floor` | Six-room floors with the exit two rooms out — for the elevator and the descent. |
| `fixed_seed` | Pins the run seed, so every launch generates the identical floors. |
| `swarm` | 8–12 enemies a room. Placement, door locking and frame time under load. |
| `combat_lab` | Small floor, packed rooms, air that will not run out. For tuning fights. |
| `die_quickly` | 15 seconds of air — the letterbox, the heartbeat, suffocation, game over. |

The order is not alphabetical and not the order they were written. Each file
declares where it sits:

```ini
[meta]
order = 40
summary = "Six-room floors, exit two rooms away — for testing the descent."
```

`order` sorts the dropdown, in tens so a new profile can be slotted between two
others without renumbering; ties fall back to alphabetical. `summary` is the
tooltip on the dropdown item and the line printed under the banner at launch. No
game code reads `[meta]`, and `GameConfig` leaves it out of the banner's list of
overrides — a section is only listed there if it actually changed something.

## Keys a profile can set

| Section | Key | Read by |
|---|---|---|
| `oxygen` | `total_time` | `o_2_timer.gd` — seconds in a full tank |
| `oxygen` | `drain` | `o_2_timer.gd` — `false` stops the clock *and* makes damage free |
| `player` | `invulnerable` | `player.gd` — hits are ignored outright, no flash |
| `player` | `infinite_ammo` | `player.gd` — the magazine never empties, so it never reloads |
| `enemies` | `min`, `max` | `game.gd` — per-room count. `max = 0` empties the floor |
| `enemies` | `boss_min`, `boss_max` | `game.gd` — how many the boss room holds. Forced to zero when `max = 0`, so an emptied station has no boss barring the way down |
| `floor` | `run_seed` | `game.gd` — non-zero pins the whole run |
| `floor` | `rooms_min`, `rooms_max`, `rooms_per_floor` | `floor_config.gd` — size, and growth per floor |
| `floor` | `max_depth`, `depth_bias` | `floor_config.gd` — shape |
| `floor` | `exit_min_depth`, `special_min_depth` | `floor_config.gd` — how far out the specials sit |

Shrinking a floor means lowering the depth rules with it: the generator rerolls
40 times and then warns before it will ship an exit shallower than
`exit_min_depth`, so a small `max_depth` and the shipped depth rules together
print a warning on every floor. `tiny_floor` shows the pairing.

## Adding a value

Two steps. Put the key in a profile:

```ini
[oxygen]
total_time = 15.0
```

and read it where the default already lives, passing the current value as the
fallback:

```gdscript
total_time = GameConfig.get_value("oxygen", "total_time", total_time)
```

Defaults stay at the call site on purpose: the numbers that ship are the ones
written in the scripts, so a missing or misspelt profile can never change the
game — it just fails to override anything, loudly.

## Adding a profile

Drop a new `.cfg` in `src/config/profiles/`; the filename is the profile name,
and the dropdown picks it up on the next editor start. Names must be
`snake_case` — `tools/check_layout.py` enforces that everywhere under `src/`.
Say what the profile is for at the top, the way the existing ones do, and give
it a `[meta]` block so it lands somewhere deliberate in the list rather than
wherever its spelling puts it.

Prefer combining existing keys over adding a switch. `combat_lab` is three
sections of values that already existed, and it needed no code at all.
