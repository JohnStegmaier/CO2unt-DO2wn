# Enemies

Every bad guy in the game comes out of one scene, `src/entities/enemy/enemy.tscn`,
dressed at spawn from an `EnemyDef` resource. **Adding a new kind of enemy is a
`.tres` file and no GDScript at all** — unless it needs a way of fighting that
none of the four existing archetypes covers.

```
EnemySet ────── src/config/enemies/default.tres     which enemies exist, how often
   │
   ├─ EnemyDef  src/config/enemies/defs/guard.tres  one enemy: art, body, gun, loot
   │     │
   │     ├─ EnemyBehaviour   (inline)               how it fights
   │     └─ SpriteFrames     frames/guard_frames.tres
   │
   └─ … one file per enemy
```

Three levels, one file each, and exactly one inline sub-resource — the behaviour,
which is one-to-one with its def, so opening `guard.tres` gives you the whole
guard on one inspector page. Compare `docs/DROPS.md`, which is six levels of
anonymous sub-resources in a single file; that is the shape this deliberately is
not.

## The four archetypes

| | Behaviour | What it does | Art |
| --- | --- | --- | --- |
| **booger** | `ChaseBehaviour` | Walks at you and does not stop. Leans around props rather than grinding into them, and dissolves the one it corners you against. No gun. | 4 frames, no facing |
| **guard** | `SkirmishBehaviour` | Holds a firing ring, strafes, dodges bullets, and puts a barrel between you and it. Holds fire while it is behind cover, which is what makes it pop out. | 4-way walk, 8/8/4/4 |
| **licker** | `ChargeBehaviour` | Stalks → telegraphs → lunges → recovers. The lunge is committed and blind: duck behind a crate and it hits the crate. | left/right, 6 each |
| **turret** | `TurretBehaviour` | Bolted to a wall. Fires along a bearing, turns, fires along the next one. Never aims at you. 120 hp. | 16 frames = 16 bearings |

A turret alone is a puzzle you walk around. The point of it is layering: put one
behind a room of boogers and the fight stops being about killing things and
starts being about where you are standing while you do it.

## Adding an enemy with no new code

1. Put the frames in `assets/sprites/characters/bad_guy/<name>/`.
2. Build a `SpriteFrames` in the editor and save it to
   `src/config/enemies/frames/<name>_frames.tres`. The animation names are not
   free — see [Facing](#facing) below.
3. Copy an existing def in `src/config/enemies/defs/`, point it at the frames,
   pick a behaviour in the **Behaviour** slot, and set the numbers.
4. Add the def to `defs` in `src/config/enemies/default.tres`.
5. Add a `DropRule` for its `loot_source` in `src/config/drops/default.tres`, or
   it drops nothing. (Dropping nothing is a valid choice, not an error.)
6. `godot --headless --script tools/check_enemies.gd`

Adding an entirely new *way of fighting* is a new script extending
`EnemyBehaviour` in `src/systems/enemies/`, overriding whichever of `steer`,
`aim`, `facing` and `dodge` it needs. Nothing else changes — `enemy.gd` does not
contain the name of a single archetype, and is not supposed to start.

## Facing

Four modes, one formula. A heading is an angle; an angle cut into N even sectors
is an index; the index is either an animation name or a frame number.

```
                    up  (-PI/2)
                     │
   left (PI) ────────┼──────── right (0)      sectors run CLOCKWISE from
                     │                        due right, because that is
                   down (+PI/2)               what Vector2.angle() counts
                                              in a Y-down world
```

| `facing` | Animations the SpriteFrames must contain |
| --- | --- |
| `omni` | `move` |
| `two_way` | `move_right`, `move_left` |
| `four_way` | `move_right`, `move_down`, `move_left`, `move_up` |
| `rotation` | `move` — its **frames** are the bearings, and it is paused and indexed rather than played |

The names are checked by `tools/check_enemies.gd`, because a misnamed animation
is silent at runtime and shows up as an enemy stuck on its first frame forever,
which reads as a physics bug rather than a typo.

If art was drawn pointing somewhere other than due right, set
`facing_offset_degrees` rather than re-exporting it.

**Gait periods, not frame rates.** The guard's side-on walk is 4 frames and its
front-on is 8, so `guard_frames.tres` authors the side-on at half the speed and
both cycles take the same time. That is why `frame_rate` on the def is a
`speed_scale` multiplier and not an absolute FPS — an absolute one would undo it.

## The body-radius budget

`EnemyDef.body_radius` is capped, and the cap is load-bearing rather than
tidiness. `ObstaclePlacement` proves a generated room can never be walled off,
and that proof is a statement about the widest body in the game:

```
EnemyPlacement.MAX_AGENT_RADIUS = 6.8

  a boss-eligible def spends   body_radius × game.gd's boss_size_scale
  anything else spends         body_radius
```

So the turret carries a radius of 6 (it is 32×32 art and can never be promoted),
while the guard carries 4 (×1.7 = 6.8 if it becomes a boss). Exceed the budget
and `tools/check_obstacles.gd` is flood-filling for a body that no longer exists —
a room it calls crossable may not be. `check_enemies.gd` fails the build first.

A wall fixture must never be `boss_eligible`: a boss that cannot move is a
target, not a fight, and on floor 1 the boss gate is the only way down.

## How the AI sees the room

There is no pathfinding and no nav mesh. Enemies steer, and everything they know
about the room comes through `ObstacleField`:

| Question | Method |
| --- | --- |
| Can I see him? | `has_line_of_sight(from, to, padding)` |
| What is in the way? | `first_blocker(from, to, padding)` → index, or -1 |
| Which way do I lean to miss it? | `avoidance(at, heading, radius, look_ahead)` |
| Where do I hide? | `cover_point(at, threat, radius, max_travel, bounds)` |

Rooms hold at most six circular props, so every one of those is a handful of
distance tests. What it buys is leaning around a barrel and hiding behind one.
What it does **not** buy is routing: a look-ahead cannot solve an L of two
crates, and is not meant to. `Enemy`'s stuck-guard covers the rest, and covers
walls, which are not in the field at all.

**Everything in `ObstacleField` is room-local.** Enemies live in global space and
a room sits at `coord * STRIDE`, so the two are thousands of pixels apart on any
floor bigger than one room. `Enemy.set_room()` takes the room's origin and the
conversion happens once a frame in `_physics_process`. No behaviour ever learns
that rooms have positions.

Breaking a prop calls `ObstacleField.remove_id()`, and because the field is
shared by reference with every enemy in the room, the whole room agrees on the
next frame. Shooting away cover means something to the things using it.

## Behaviours hold no state

An `EnemyBehaviour` is a `.tres` shared by every enemy of its type — one object,
a roomful of bodies. A strafe sign or a charge phase stored on it would be stored
once for all of them, and the bug does not look like a missing call: it looks
like twelve lickers lunging on the same frame forever.

So the knobs live on the behaviour and the state lives in the caller's
`SteeringContext`, one per enemy. That also leaves every behaviour a pure
function of its arguments, which is what lets `check_enemies.gd` step one for six
hundred ticks in a terminal with no scene, no physics server and no autoloads.

Phase timers count down from `delta` rather than comparing against
`Time.get_ticks_msec()`. Wall-clock keeps running while the game is paused, so a
licker paused mid-telegraph would resume already committed to a lunge it never
wound up for.

## Tuning profiles

```
godot -- --profile=enemy_zoo    9-12 enemies, every archetype, cluttered rooms
godot -- --profile=swarm        8-12, for placement and frame time
godot -- --profile=peaceful     none at all; rooms must still never lock
godot -- --profile=cluttered    maximum props, for the steering
```

A profile can swap the whole bestiary:

```ini
[enemies]
min = 9
max = 12
set = "zoo"     ; names src/config/enemies/<name>.tres
```

Note that a second `EnemySet` pointing at the *same* def files would be a
byte-for-byte copy of the shipped one, because `weight` lives on the def. A
genuinely different mix needs defs of its own.

## Checking your work

```bash
godot --headless --script tools/check_enemies.gd
```

Catalogue validity, pick rates against declared weights, the radius budget, the
required animation names, all four field queries, six hundred ticks of every
behaviour, and 8100 spawn spots across 60 seeds × 15 door masks.

The one it exists for above all others: **a fixture spawned inside a prop is
unkillable, so the room never unlocks, and on floor 1 that makes the run
unfinishable.** A mobile enemy survives a bad spawn by walking out. A turret does
not.
