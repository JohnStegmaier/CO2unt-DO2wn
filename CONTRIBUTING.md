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

## Workflow

- Work on a feature branch; open a pull request into `master`.

### Branch rules for `master`

These are enforced by the repository — not just convention:

- Direct pushes to `master` are blocked — all changes must go through a pull
  request, with no exceptions for admins.
- Every pull request needs **1 approving review** before it can merge.
- Pushing new commits to a PR dismisses existing approvals — it must be
  re-approved.
- All four build checks must pass before merging: **Export Linux**,
  **Export Windows**, **Export macOS**, and **Export Web**.
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
- [ ] The diff contains only what the PR description says it does.
