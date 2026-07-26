class_name ObstacleDef
extends Resource

## One kind of solid prop: what it looks like, how big it is, and what it takes
## to break it.
##
## A Resource rather than a scene per prop, for the same bargain [ItemDef] makes
## over in the loot path: a barrel and a crate differ only in numbers and a
## texture, so adding a third is a .tres edit and not another scene to keep in
## step. [Obstacle] is the single scene all of them are dressed from.
##
## Holds a Texture2D despite living under systems/ — the same shape as
## ItemDef.icon, and for the same reason: the thing that knows which art a prop
## uses is the prop's own definition.

## Names the row for a human reading the resource, and what check_obstacles.gd
## prints when an assertion fails. Not used for lookup — nothing indexes props by
## id yet, and a StringName here is what makes that cheap when something does.
@export var id: StringName = &""

@export_group("Appearance")
@export var texture: Texture2D

## None of the three shipped sprites is centred in its own canvas — barrel's art
## sits 2.5px right of centre, crate's 6px left. Applied to the Sprite2D so the
## collider lands on the art rather than beside it, which is a thing you cannot
## see in the editor until a bullet passes through the visible half of a crate.
@export var offset: Vector2 = Vector2.ZERO

## The art is drawn at source resolution otherwise, and the source frames are
## 50-100px against a 16x24 enemy. See docs/TUNING_PROFILES.md for the sizes.
@export var sprite_scale: float = 1.0

@export_group("Body")
## Radius of the solid core, which is deliberately NOT half the sprite: a
## top-down barrel is tall but not fat, so its footprint is narrower than its art.
##
## Capped by ObstaclePlacement.MAX_BODY_RADIUS, and the cap is load-bearing rather
## than tidiness — the proof that a room can never be walled off is a statement
## about this number. Raising it means redoing the arithmetic in that file.
##
## A circle, not a rectangle: the Minkowski sum of two discs is a disc, which is
## what lets the connectivity check inflate props exactly instead of
## conservatively, and a circle gives a chaser no corner to wedge on.
@export var body_radius: float = 8.0

@export_group("Damage")
## Ignored when indestructible. Calibrated against the player's gun, which deals
## BULLET_DAMAGE_VALUES[POWER_LVL - 1] — 10 at level 1, rising to 35.
@export var max_hp: int = 20

## Rocks. Shots still stop dead on them — bullet.gd frees itself on any body it
## touches — they simply never take the damage. A flag rather than a second scene
## so "how tough is this" and "can this be broken at all" are one inspector.
@export var indestructible: bool = false


## Relative, not a percentage, matching DropEntry.weight: a row at 2.0 comes up
## twice as often as one at 1.0, so adding a prop never means retyping the others.
@export var weight: float = 1.0


func describe() -> String:
	var toughness := "indestructible" if indestructible else "%d hp" % max_hp
	return "%s (r%.0f, %s, weight %.1f)" % [id, body_radius, toughness, weight]
