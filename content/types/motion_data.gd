class_name MotionData
extends Resource
## Self-propulsion during a move frame range (dashes, lunges, hops). Speeds are m/s relative
## to the fighter's facing at the time.

@export var start_frame: int = 1
@export var end_frame: int = 1
@export var forward_speed: float = 0.0
@export var side_speed: float = 0.0
## Upward velocity set on start_frame (m/s); the fighter becomes airborne when > 0.
@export var up_speed: float = 0.0
## Stops forward motion once the target is within this many meters (0 = never).
@export var stop_at_distance: float = 0.0
## Keep turning toward the target at the move's tracking rate during the motion.
@export var homing: bool = false
