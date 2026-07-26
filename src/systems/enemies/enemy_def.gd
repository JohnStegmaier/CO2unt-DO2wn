class_name EnemyDef
extends Resource

## One kind of bad guy: what it looks like, how big it is, what it shoots, and
## which [EnemyBehaviour] drives it.
##
## A Resource rather than a scene per enemy, the same bargain [ObstacleDef] makes
## for props and [ItemDef] for loot: a booger and a licker differ in art, numbers
## and one behaviour slot, so adding a fifth is a .tres and not a fifth scene to
## keep in step. [Enemy] is the single scene all of them are dressed from — see
## [method Enemy.configure].
##
## The nesting is deliberately shallow, because the drop tables are the warning.
## The whole graph is [EnemySet] → this → a [SpriteFrames], each of them its own
## file referenced by path, with exactly one inline sub-resource: the behaviour,
## which is one-to-one with its def and so belongs in it. Opening guard.tres
## gives you the whole guard on one inspector page. Compare
## src/config/drops/default.tres, which is six levels of anonymous sub-resources
## in one file and cannot be read at all.

## Names the row for a human reading the resource, and what tools/check_enemies
## .gd prints when an assertion fails. Not used for lookup by the game — but
## [method EnemySet.by_id] exists for the checker, and a StringName here is what
## keeps that cheap.
@export var id: StringName = &""

@export_group("Behaviour")
## The one slot that decides the archetype, and the reason this schema is not a
## wall of knobs: Godot shows the exports of whichever behaviour script is in
## here, so a turret's row offers a sweep step and no strafe distance. Drop a
## [ChaseBehaviour], [SkirmishBehaviour], [TurretBehaviour] or [ChargeBehaviour]
## in and the rest of the inspector follows.
@export var behaviour: EnemyBehaviour

## Relative, not a percentage, matching [member ObstacleDef.weight] and
## [member DropEntry.weight]: a row at 2.0 comes up twice as often as one at 1.0,
## so adding an enemy never means retyping the others. Zero is how you bench one
## without deleting it.
@export_range(0.0, 10.0, 0.1, "or_greater") var weight: float = 1.0

## Which row of the drop table this one's death is looked up under. An enemy says
## what it is and the run's [DropConfig] says what that is worth, so the whole
## economy is tuned in one inspector rather than across every enemy. A source
## with no rule drops nothing, which is what makes a new enemy quiet rather than
## an error. game.gd overrides it with &"boss" for the one it promoted.
@export var loot_source: StringName = &"grunt"

## May this one be promoted to a floor boss? Off for anything bolted down: a boss
## that cannot move is a target, not a fight. It also decides how much body this
## def is allowed — see [member body_radius].
@export var boss_eligible: bool = true

@export_group("Appearance")
## The animation set, with the names [EnemyFacing] requires for the mode below.
## Authored in the editor and saved under src/config/enemies/frames/.
@export var frames: SpriteFrames

## How the art expresses direction: none at all, left and right, four ways round,
## or one animation whose frames are the bearings. See [EnemyFacing] — this is
## the only place a mode is chosen, and no code branches on it.
@export_enum("omni", "two_way", "four_way", "rotation") var facing: int = 0

## Rotates the heading-to-art mapping. The escape hatch for art that was drawn
## pointing somewhere other than due right, and the one knob that fixes "the
## sprite faces the wrong way" without a code edit or a re-export. Stepped by
## 22.5° because that is one frame of the sixteen-frame turret.
@export_range(-180.0, 180.0, 22.5) var facing_offset_degrees: float = 0.0

## Where the art sits relative to the body. Same job as [member ObstacleDef
## .offset]: land the collider on the sprite rather than beside it. The -5 is
## what the enemy scene carried before enemies had defs.
@export var sprite_offset: Vector2 = Vector2(0, -5)

## The source frames run 20x25 to 32x32 against a player drawn at native size,
## so this is usually a shrink rather than a blow-up.
@export_range(0.25, 3.0, 0.05) var sprite_scale: float = 1.0

## Where the ground shadow sits, in the same sibling-of-the-sprite space as
## [member sprite_offset]. Can't be derived from sprite_offset/sprite_scale
## alone — a crawling licker's art fills the top of its frame with a lot of
## dead canvas below it, while a guard's fills the frame edge to edge, so the
## same "half the frame height" math lands the shadow under a guard's feet and
## a full body-length below a licker's. Tuned per def against the actual
## drawn pixels instead.
@export var shadow_offset: Vector2 = Vector2(0, 8)

## Applied as AnimatedSprite2D.speed_scale, so per-animation speeds authored in
## the SpriteFrames stay relative to each other. That matters for the guard,
## whose side-on walk is four frames and whose front-on is eight — the .tres
## halves the side-on speed so both gaits have the same period, and an absolute
## FPS here would undo it.
@export_range(0.1, 10.0, 0.1) var frame_rate: float = 1.0

@export_group("Body")
## Radius of the solid core, which is deliberately NOT half the sprite — a
## top-down body is tall but not fat, the same argument [member ObstacleDef
## .body_radius] makes for a barrel.
##
## Capped by [constant EnemyPlacement.MAX_AGENT_RADIUS], and the cap is
## load-bearing rather than tidiness: the proof that a generated room can never
## be walled off is a statement about the widest body in the game. A
## [member boss_eligible] def spends that budget times game.gd's boss_size_scale,
## because it can be promoted; one that can never be a boss spends it once and
## may therefore be wider. tools/check_enemies.gd is what enforces the
## difference — the range hint below cannot, because it does not know which.
@export_range(2.0, 6.8, 0.1) var body_radius: float = 4.0

## Height of the capsule. Only the radius is in the connectivity budget: the
## rooms are top-down, so this is how tall the footprint is drawn, not how wide
## a gap it needs.
@export_range(4.0, 32.0, 0.5) var body_height: float = 14.0

## Calibrated against the player's gun, which deals 10 a shot at level 1 rising
## to 35. A turret is meant to take a magazine; a booger is meant to take two
## shots.
@export_range(1, 500) var max_hp: int = 30

## Blunt cost of being walked into. Rate-limited by the player's own mercy
## window, so this needs no timer of its own.
@export_range(0, 60) var contact_damage: int = 6

## What it does to a PROP it walks into. Zero — the default — is what keeps a
## shooter inert: it bumps a crate and nothing happens, exactly as every enemy
## did before this. Only the archetypes that break things by running into them
## carry a non-zero one, and [method EnemyBehaviour.breaks_on_contact] decides
## whether this frame counts.
@export_range(0, 60) var break_damage: int = 0

@export_group("Shot")
## Leave this empty and the enemy has no gun. One legible switch rather than a
## has_weapon flag that could disagree with it — [method Enemy._shoot] returns
## early on null, and tools/check_enemies.gd checks it agrees with
## [method EnemyBehaviour.fires], because a shooter with an empty slot is silent
## at runtime and looks like a broken archetype.
@export var bullet_scene: PackedScene
@export_range(1, 60) var bullet_damage: int = 8
@export_enum("blunt", "piercing") var bullet_damage_type: int = 0

## The single biggest lever on whether a shot is dodgeable, and independent of
## the player's — both sides fire the same scene, so it has to live on the
## shooter to be tunable separately.
@export_range(60.0, 600.0, 5.0) var bullet_speed: float = 180.0

## Seconds between shots. The turret's stops are timed in
## [member TurretBehaviour.aim_time], so the two together decide whether a stop
## is one heavy shot or a burst.
@export_range(0.05, 8.0, 0.05) var fire_interval: float = 1.6

## Radians. They are bad guys, not marksmen.
@export_range(0.0, 1.0, 0.01) var aim_spread: float = 0.2

## Where a shot leaves the body. Per-def rather than a constant because bodies
## now differ by a factor of two, and a muzzle inside the collider spawns a
## bullet that kills its owner.
@export_range(0.0, 24.0, 0.5) var muzzle_offset: float = 10.0

@export_group("Spawn")
## No volley on the frame you walk through the door.
@export_range(0.0, 4.0, 0.05) var spawn_grace: float = 0.8

## Where in the room this one belongs. "against_the_wall" is for fixtures — a
## turret in the middle of the floor is a barrel with a gun, and it is the only
## thing that cannot walk out of a bad spot. See
## [method EnemyPlacement.wall_points].
@export_enum("anywhere", "against_the_wall") var placement: int = 0


## True when this def wants a spot on the edge of the room rather than anywhere
## on the floor. Named so call sites read as a question rather than a magic 1.
func is_fixture() -> bool:
	return placement == 1


## The widest this def can ever be in a live room, which for a boss-eligible one
## is after game.gd has scaled it up. What the connectivity budget is spent
## against — see [member body_radius].
func widest_radius(boss_size_scale: float) -> float:
	return body_radius * (boss_size_scale if boss_eligible else 1.0)


func describe() -> String:
	var gun := "unarmed" if bullet_scene == null else "%d dmg @ %.2fs" % [
			bullet_damage, fire_interval]
	var where := ", wall" if is_fixture() else ""
	return "%s (r%.1f, %d hp, %s, %s, weight %.1f%s)" % [
			id, body_radius, max_hp, gun,
			"no behaviour" if behaviour == null else behaviour.describe(), weight, where]
