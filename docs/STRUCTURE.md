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
│   ├── levels/         playable scenes
│   ├── systems/        engine-light game logic (scoring, state machines) —
│   │                   the code we can unit-test without the scene tree
│   └── ui/             menus and HUD
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
