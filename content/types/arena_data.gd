class_name ArenaData
extends Resource
## Arena collision and rules data. The floor is flat at y = 0. Coordinates are meters in
## the x-z plane (Godot world x and z).

@export var id: StringName = &""
@export var display_name: String = ""
## Walkable floor as a convex polygon (x, z), any winding. Each edge is a wall.
@export var floor_polygon: PackedVector2Array = PackedVector2Array([
		Vector2(-12.0, -10.0), Vector2(12.0, -10.0), Vector2(12.0, 10.0), Vector2(-12.0, 10.0)])
## Walls block projectiles and splat up to this height.
@export var wall_height: float = 6.0
@export var obstacles: Array[ArenaObstacle] = []
@export var hazards: Array[HazardData] = []
## Spawn positions (x, z). Slot i uses spawn_points[i]. Fighters face the centroid of the
## other spawns at round start.
@export var spawn_points: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -3.0), Vector2(0.0, 3.0), Vector2(-3.0, 3.0), Vector2(3.0, 3.0)])
## Presentation scene path (models, lights); the sim ignores it.
@export var scene: String = ""
## Camera hints for presentation (x-z rectangle the camera may move in).
@export var camera_bounds: Rect2 = Rect2(-11.0, -9.0, 22.0, 18.0)
## Fixed yaw of the gameplay camera, in degrees, as the direction it looks: the view
## direction on the floor is (sin(yaw), cos(yaw)) in (x, z), so 0 looks along +z and 180
## looks along -z from the +z side (the FightCamera yaw convention). Movement is relative
## to it. FightCamera reads it; ArenaView cuts the walls on the camera side. Presentation only.
@export var camera_yaw: float = 0.0
