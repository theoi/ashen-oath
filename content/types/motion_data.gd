class_name MotionData
extends Resource
## Self-propulsion during a move frame range (dashes, lunges, hops). Speeds are m/s relative
## to the fighter's facing at the time.

## Travel toward the move's aim point (MoveData.aim GROUND_TARGET / DASH_TO) instead of along
## facing. ARRIVE spreads the remaining distance over the frames left in the range (leaps land
## on the point); STOP_AT moves at forward_speed and stops on the point.
enum AimTravel { NONE, ARRIVE, STOP_AT }

@export var start_frame: int = 1
@export var end_frame: int = 1
@export var forward_speed: float = 0.0
@export var side_speed: float = 0.0
## Upward velocity set on start_frame (m/s); the fighter becomes airborne when > 0.
@export var up_speed: float = 0.0
## Stops forward motion once the target is within this many meters (0 = never). Aimed moves
## stop for any enemy within this distance in front.
@export var stop_at_distance: float = 0.0
## Keep turning toward the target (aimed moves: the current aim) at the move's tracking
## rate during the motion.
@export var homing: bool = false
@export var aim_travel: AimTravel = AimTravel.NONE
