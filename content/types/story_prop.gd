class_name StoryProp
extends Resource
## Extra set dressing for a scene: a KayKit model placed in the arena with its palette.

enum Kit { HALLOWEEN, DUNGEON }

@export var kit: Kit = Kit.HALLOWEEN
## Model file name without extension, e.g. "coffin" or "bone_A".
@export var model: String = ""
@export var position: Vector3 = Vector3.ZERO
@export var yaw_degrees: float = 0.0
@export var scale: Vector3 = Vector3.ONE
@export var rotation_degrees: Vector3 = Vector3.ZERO
