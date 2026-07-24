# Project structure

This repository is laid out so it stays navigable as the game grows, and the
layout is **enforced** — `tools/check_layout.py` runs first in CI and fails the
pipeline the moment a file lands in the wrong place. Run it locally any time:

```bash
python3 tools/check_layout.py
```

## The tree

```
/                       project.godot, export_presets.cfg, icon.svg, docs — nothing else
├── assets/             engine-imported, game-ready media. Type-grouped.
│   ├── audio/
│   │   ├── music/
│   │   ├── sfx/
│   │   └── voice/
│   ├── fonts/
│   ├── models/         3D: .glb / .gltf and their baked textures
│   ├── shaders/        .gdshader
│   ├── sprites/
│   │   ├── characters/
│   │   ├── environment/
│   │   ├── ui/
│   │   └── vfx/
│   └── themes/         .tres / .theme UI resources
├── src/                the game itself. Feature-grouped: a scene lives with
│   │                   the scripts that drive it.
│   ├── autoload/       singletons registered in project.godot (audio, timer)
│   ├── entities/       player, enemies, pickups — one folder each
│   ├── screens/        full-screen scenes you navigate BETWEEN — main menu,
│   │                   credits, game over. Reached by a scene swap.
│   ├── levels/         playable gameplay spaces
│   ├── components/     reusable behaviors composed ONTO many nodes across many
│   │                   scenes (health, hurtbox, state machine) — one-to-many
│   ├── systems/        shared logic not attached to one node — game-rule
│   │                   coordinators (scoring) AND pure helpers (math, easing).
│   │                   Split a dedicated lib/ out once libraries proliferate.
│   └── ui/             UI components instanced INTO screens/levels (HUD,
│                       pause overlay, widgets) — not whole screens themselves
├── addons/             third-party Godot plugins. Never hand-edited.
├── raw/                source art Godot must NOT import (.aseprite, .blend,
│                       .psd, .avif). A `.gdignore` makes the engine skip it,
│                       so it never bloats .godot/ or an export.
├── tools/              dev-only scripts, including the layout checker
└── docs/
```

## Why two grouping strategies

- **`src/` is grouped by feature.** You edit a scene and its scripts together,
  so they live together — adding an enemy means adding one folder, not touching
  three. Dependencies still point inward (see CONTRIBUTING.md): `systems/` knows
  nothing about `ui/`.
- **`assets/` is grouped by type.** A composer dropping in a track shouldn't
  need to know which feature will use it, and Godot's import settings are
  per-type.

### Screens vs. UI components

A common trap: filing whole screens (the main menu) next to UI components (the
HUD). Use this test — **is the scene instanced *into* another scene, or do you
navigate *to* it?**

- Instanced into a scene (`UI.tscn` is a child of `stage.tscn`) → it's a
  component → `src/ui/`.
- A whole-screen destination reached by a scene swap (the main menu is the
  `main_scene` and `change_scene_to_file`s to the stage) → it's a screen →
  `src/screens/`.

So the HUD lives in `ui/`, the main menu lives in `screens/`, and a gameplay
level lives in `levels/` — three different jobs, three different homes.

### Reusable code that isn't a scene

A script that gives behavior to *many* nodes across *many* scenes has a home
too. Ask **how many exist at once, and what does it attach to?**

| It is… | Home | Example |
| --- | --- | --- |
| **one** instance, global, alive all game | `autoload/` | `AudioManager`, `EventBus` |
| attached to **many** nodes for a per-node behavior | `components/` | `Health`, `Hurtbox`, `StateMachine` |
| a **coordinator** of game rules, or a pure helper (no node) | `systems/` | `score_system`, `math_utils` |

A **component** is the answer to "one script, many nodes, many scenes." Build
it as a small self-contained scene plus a `class_name` script and *instance* it
as a child wherever it's needed — composition, not inheritance:

```
src/components/health/
├── health.tscn      # a node with the script attached; @export vars set in-editor
└── health.gd        # class_name Health; signal died; @export var max_hp: int
```

`player.tscn`, `enemy.tscn`, and `breakable_crate.tscn` each add `health.tscn`
as a child. The component emits `died` and each host decides what that means —
signals up, calls down. A component knows nothing about the screens or levels
that use it (dependencies point inward).

## The rules the checker enforces

1. **Root is a closed allowlist.** Only the files and directories named above
   may sit at the repository root. This is the rule that stops the tree from
   ballooning — a stray file at root fails immediately.
2. **Extension decides the neighbourhood.** `.gd`/`.tscn` only under `src/`
   (or `tools/`, `addons/`); images only under `assets/`; `.mp3`/`.ogg`/`.wav`
   only under `assets/audio/`; models only under `assets/models/`; editable
   source art (`.aseprite`, `.blend`, …) only under `raw/`; and so on. An
   extension with **no rule at all** is an error too — so the ruleset can't
   silently rot as new file types appear. Add the rule (or move the file).
3. **snake_case, no spaces.** Matching the GDScript style guide. `Main_Menu.tscn`
   and `Clockwork Pulse.mp3` are both rejected (the space also breaks shell
   steps in CI).
4. **No junk, no orphaned sidecars.** `.tmp`/`.bak`/`.DS_Store` never commit,
   and every `.import`/`.uid` sidecar must sit beside its parent file — this
   catches a half-finished move before it corrupts the project.

## Warnings (loud, but not blocking)

The checker also flags any asset under `assets/` that **no scene or script
references** — dead art, or content that was added but never wired up. These
print as `WARN` and do **not** fail the build; clean them up or wire them in.

## Adding a new category

All rules are data tables at the top of `tools/check_layout.py`
(`ROOT_FILES`, `ROOT_DIRS`, `EXT_RULES`). Adding a file type or a directory is a
one- or two-line edit there — no logic changes. Update this document to match.
