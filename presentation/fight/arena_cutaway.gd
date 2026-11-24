class_name ArenaCutaway
extends RefCounted
## Cuts an arena open for the high fight camera (design-lost-ark §3): geometry that would
## sit between the camera and the fighters (everything above wall height, such as roof
## beams and upper walls, and tall pieces past the camera-side edge of the floor) stops
## rendering but keeps casting shadows, so the arena's lighting stays the same.

const ROOF_HEIGHT := 3.5
const NEAR_MIN_HEIGHT := 1.2
const NEAR_MARGIN := 0.3


## Applies the cutaway to every mesh under `root`. `yaw` is the camera yaw (radians;
## 0 looks along +Z); `floor` is the arena's floor polygon. Returns the nodes it changed.
static func apply(root: Node, yaw: float, floor: PackedVector2Array) -> Array[GeometryInstance3D]:
	var back := Vector2(-sin(yaw), -cos(yaw))
	var near_edge := -INF
	for p in floor:
		near_edge = maxf(near_edge, p.dot(back))
	var cut: Array[GeometryInstance3D] = []
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		if node is CPUParticles3D or node is GPUParticles3D or node is Label3D:
			continue
		var geometry := node as GeometryInstance3D
		if not geometry.visible or geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var box := geometry.global_transform * geometry.get_aabb()
		var roof := box.position.y >= ROOF_HEIGHT
		var center := Vector2(box.get_center().x, box.get_center().z)
		var near := floor.size() >= 3 and box.end.y > NEAR_MIN_HEIGHT \
				and center.dot(back) > near_edge - NEAR_MARGIN
		if roof or near:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			cut.append(geometry)
	return cut
