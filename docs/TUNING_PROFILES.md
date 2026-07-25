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
Say what the profile is for at the top, the way the existing two do.
