# Contributing to CO₂unt DO₂wn

Thanks for helping build CO₂unt DO₂wn! This document explains how we work. It is
short on ceremony and long on craft: most of it boils down to leaving the code
a little better than you found it.

## Getting set up

1. Install [Godot 4.7.1 (stable)](https://godotengine.org/download) — the
   version CI builds with (see `GODOT_VERSION` in
   `.github/workflows/build.yml`). Using the same version avoids noisy diffs
   in `.tscn` and `project.godot` files.
2. Clone the repo and open the project folder in Godot. Let the first import
   finish before making changes.
3. Never commit the `.godot/` or `build/` directories (already gitignored).

## Where files go

The repository has an enforced layout — see
[`docs/STRUCTURE.md`](docs/STRUCTURE.md). In short: game code and scenes live
feature-grouped under `src/`, imported media lives type-grouped under
`assets/`, editable source art (`.aseprite`, `.blend`, …) lives under `raw/`,
and the root is a closed allowlist.

`tools/check_layout.py` runs first in CI and **fails the build** if a file is
misplaced, misnamed (everything is `snake_case`, no spaces), or is an orphaned
sidecar. It also prints a loud, non-blocking warning for any asset no scene or
script references. Run it before you push:

```bash
python3 tools/check_layout.py
```

### Crediting assets

Third-party art, audio, fonts, models, and shaders must be credited in
[`docs/CREDITS.md`](docs/CREDITS.md) — creator, source, and licence — in the
same PR that adds them. Assets you made yourself need no entry; the repo
[`LICENSE`](LICENSE) covers them.

When a PR adds any asset file, the **Asset attribution** workflow
(`.github/workflows/asset-attribution.yml`) posts a review thread listing
exactly which files. The pipeline stays green — it never fails on this — but the
thread must be **resolved** before the PR can merge (see the branch rules
below). For each listed file, confirm it is either credited in
`docs/CREDITS.md` or is your own original work, then click **Resolve
conversation**. That click is a deliberate human sign-off: CI never guesses
whether an asset needs attribution.

## Workflow

- Work on a feature branch; open a pull request into `master`.
- Name branches with a git-flow style prefix that says what kind of change
  they carry:
  - `feature/<short-description>` — new gameplay, content, or tooling
    (e.g. `feature/double-jump`)
  - `bugfix/<short-description>` — fixes for bugs found during development
    (e.g. `bugfix/camera-jitter`)
  - `hotfix/<short-description>` — urgent fixes for something already
    released/broken on `master` (e.g. `hotfix/web-export-crash`)
  - `docs/<short-description>` — documentation-only changes
  - `chore/<short-description>` — CI, config, and housekeeping changes
  - Use short, kebab-case descriptions after the prefix.

### Branch rules for `master`

These are enforced by the repository — not just convention:

- Direct pushes to `master` are blocked — all changes must go through a pull
  request, with no exceptions for admins.
- Every pull request needs **1 approving review** before it can merge.
- Pushing new commits to a PR dismisses existing approvals — it must be
  re-approved.
- All four build checks must pass before merging: **Export Linux**,
  **Export Windows**, **Export macOS**, and **Export Web**.
- **Every review conversation must be resolved before merging** — including the
  thread the **Asset attribution** workflow opens when a PR adds art or audio
  (see [Crediting assets](#crediting-assets)).
- Force pushes to `master` are blocked.
- `master` cannot be deleted.
- CI must be green before merging. Every PR exports the game for Linux,
  Windows, macOS, and Web — if your change breaks an export, it isn't done.
- Keep PRs small and focused. A reviewer should be able to hold the whole
  change in their head. If the description needs the word "also", consider
  splitting it.

## Code philosophy

We follow the spirit of Robert C. Martin's *Clean Code* / *Clean
Architecture*, and the advice of Martin Fowler and Kent Beck — applied with
judgment, not dogma. In practice:

### Clean Code (applied to GDScript)

- **Names carry meaning.** `time_until_detonation` beats `t`. If a name needs
  a comment to explain it, the name is wrong.
- **Small functions that do one thing.** If a function scrolls, or its name
  contains "and", split it.
- **Comments are a last resort.** Prefer code that explains itself; comment
  only what the code *cannot* say (why, not what).
- **The Boy Scout Rule.** Leave every file you touch a little cleaner than
  you found it — but keep unrelated cleanup out of feature commits (see
  "Tidy First" below).
- Follow the official
  [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html):
  `snake_case` for functions/variables/files, `PascalCase` for classes and
  nodes, and use static typing (`var speed: float = 300.0`) wherever
  practical.

### Clean Architecture (applied to Godot)

- **Dependencies point inward.** Game rules and state should not know about
  the UI that displays them. A script that decides *whether* the player dies
  must not care *how* the death screen fades in.
- **Signals up, calls down.** A node may call methods on its children; it
  communicates with its ancestors only by emitting signals. No
  `get_parent().get_parent()` reach-arounds.
- **Prefer composition over inheritance.** Build behavior from small scenes
  and nodes rather than deep class hierarchies.
- **Scenes are the delivery mechanism.** Keep logic in scripts that could, in
  principle, be exercised without instancing the full scene tree — that is
  what makes it testable.

### Fowler & Beck

- **Make it work, make it right, make it fast — in that order.** Don't
  optimize what a profiler hasn't complained about.
- **Refactor in small, safe steps,** and separate refactoring commits from
  behavior-changing commits ("Tidy First"): a reviewer should never have to
  ask "did this diff change behavior or just structure?"
- **YAGNI.** Build what the game needs now, not the framework you imagine it
  might need later.
- **Test what you can.** Pure game logic (scoring, timers, state machines)
  should be written so it *could* be unit-tested, even before we wire up a
  test framework. If a bug bites twice, that's the signal to add one.

## Commits

- Write the subject as **one sentence, in the imperative mood, describing
  what the change does** — e.g. `Add coyote time to the player jump so
  ledge jumps feel fair`. No "WIP", no "misc fixes".
- One logical change per commit. Structural (refactor/rename/move) and
  behavioral changes go in separate commits.
- **Every commit is credited to exactly one contributor: its author.** Do not
  add `Co-Authored-By:`, `Signed-off-by:`, or any other attribution trailers
  to commit messages — this applies to trailers inserted automatically by
  editors, IDEs, and development tools, so check your tooling's output before
  pushing. If several people collaborated on a change, credit them in the
  pull request description instead.

## Pull request checklist

- [ ] The project opens in Godot 4.7.1 without new warnings you introduced.
- [ ] You ran the game and exercised the thing you changed.
- [ ] Commit messages follow the rules above (single author, single
      sentence, imperative).
- [ ] Any third-party assets you added are credited in `docs/CREDITS.md`, and
      the attribution thread (if one was posted) is resolved.
- [ ] The diff contains only what the PR description says it does.
