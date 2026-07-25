class_name CollisionLayers
extends RefCounted

## The physics layers, mirroring the [layer_names] block in project.godot.
##
## Kept as code as well as project settings because masks are built by OR-ing
## them together, and `CollisionLayers.WORLD | CollisionLayers.ENEMY` says what
## it means where `5` does not. If you edit one, edit the other.
##
## WORLD is deliberately bit 1 — the engine default — so anything that was
## written against the old everything-is-layer-1 world keeps working.

const WORLD := 1 << 0
const PLAYER := 1 << 1
const ENEMY := 1 << 2
const PLAYER_BULLET := 1 << 3
const ENEMY_BULLET := 1 << 4
const DOOR := 1 << 5
