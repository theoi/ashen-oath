class_name ArenaObstacle
extends Resource
## A solid obstacle on the arena floor, seen from above as a capsule: the segment a-b (x, z
## in meters) thickened by `radius`. A pillar is a == b. A sarcophagus or wall chunk is a
## segment with a radius of half its width.

@export var a: Vector2 = Vector2.ZERO
@export var b: Vector2 = Vector2.ZERO
@export var radius: float = 0.5
@export var height: float = 6.0
## Hard knockback into it can wall-splat.
@export var wall_splat: bool = true
@export var blocks_projectiles: bool = true
