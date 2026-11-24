class_name StoryShot
extends Resource
## A fixed camera for scene stills, in arena world space (meters, floor at y = 0).

@export var position: Vector3 = Vector3(0.0, 1.8, 5.0)
@export var target: Vector3 = Vector3(0.0, 1.1, 0.0)
@export var fov: float = 50.0
