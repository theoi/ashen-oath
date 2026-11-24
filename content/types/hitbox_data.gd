class_name HitboxData
extends Resource
## A sphere or capsule hitbox in the fighter's local space (meters; +Z is forward, +Y up),
## active on a range of move frames. Frames count from 1 (the tick the move starts).

## First active frame. -1 = the move's first active frame (MoveData.startup).
@export var start_frame: int = -1
## Last active frame. -1 = the move's last active frame.
@export var end_frame: int = -1
@export var offset: Vector3 = Vector3(0.0, 1.1, 0.9)
## Second capsule point. Ignored unless `capsule` is set.
@export var offset_end: Vector3 = Vector3(0.0, 1.1, 1.6)
@export var capsule: bool = false
@export var radius: float = 0.45
@export var hit: HitData
## Hitboxes sharing a group hit each target at most once per move. Different groups can
## each hit (multi-hit moves). Groups 0-7.
@export var group: int = 0
## Destroys destroyable enemy effects (projectiles) that overlap it.
@export var destroys_projectiles: bool = true
