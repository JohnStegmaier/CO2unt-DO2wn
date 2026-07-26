class_name FloorConfig
extends Resource

## Tuning for a generated floor.
##
## A Resource rather than constants in [FloorGenerator] so a run's shape is an
## inspector slot you can swap and tune while the game runs. Pure data — it
## holds no RNG and makes no decisions, so reading it cannot change a floor.

@export_group("Size")
## Rooms to aim for on the first floor. Spawn plus its four arms are placed
## unconditionally, so five is the effective floor of this range whatever you
## set, and a value below the number of special rooms will starve them.
@export var rooms_min: int = 14
@export var rooms_max: int = 18
## Added to both ends of the range per floor descended — the only difficulty
## curve the generator itself provides.
@export var rooms_per_floor: int = 2

@export_group("Shape")
## Hard ceiling on rooms travelled from spawn. This is the design brief made
## mechanical: the exit sits at the deepest dead end, so capping depth is what
## guarantees it is never more than this many rooms away.
@export var max_depth: int = 6
## How strongly growth favours deep rooms over shallow ones. 0 spreads evenly
## and gives a blob around spawn; higher values pull the floor out into
## corridors and dead ends, which is what makes it read as a maze.
@export_range(0.0, 4.0) var depth_bias: float = 1.5

@export_group("Special rooms")
## The exit never lands closer than this, so a floor is never a short walk.
@export var exit_min_depth: int = 3
## No special room is ever adjacent to spawn — a boss you can see from the
## starting room is not much of a climax.
@export var special_min_depth: int = 2


## Fold in whatever the active tuning profile's [code][floor][/code] section says.
##
## Called by the run rather than from the constructor, so a config built by a
## tool or a test is exactly what its caller asked for and nothing else. Every
## default stays in the exports above — a profile that names none of these keys
## changes nothing. See docs/TUNING_PROFILES.md.
func apply_overrides() -> void:
	rooms_min = GameConfig.get_value("floor", "rooms_min", rooms_min)
	rooms_max = GameConfig.get_value("floor", "rooms_max", rooms_max)
	rooms_per_floor = GameConfig.get_value("floor", "rooms_per_floor", rooms_per_floor)
	max_depth = GameConfig.get_value("floor", "max_depth", max_depth)
	depth_bias = GameConfig.get_value("floor", "depth_bias", depth_bias)
	exit_min_depth = GameConfig.get_value("floor", "exit_min_depth", exit_min_depth)
	special_min_depth = GameConfig.get_value("floor", "special_min_depth", special_min_depth)


## Rooms to aim for on the given floor, as a (min, max) pair for the caller to
## roll. Returning the range rather than a rolled value keeps this side-effect
## free, so the same config cannot produce two different floors from one seed.
func room_range(floor_number: int) -> Vector2i:
	var growth: int = rooms_per_floor * floor_number
	return Vector2i(rooms_min + growth, rooms_max + growth)
