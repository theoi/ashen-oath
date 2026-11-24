class_name TeleportData
extends Resource
## Instant reposition on one move frame (blinks, shadowsteps).

enum Mode {
	## `distance` meters in the stick direction (facing when neutral).
	STICK,
	## `distance` meters along facing.
	FORWARD,
	## `distance` meters behind the target, facing it. Fails (no move) beyond `max_range`.
	BEHIND_TARGET,
}

@export var frame: int = 1
@export var mode: Mode = Mode.STICK
@export var distance: float = 5.0
@export var max_range: float = 8.0
