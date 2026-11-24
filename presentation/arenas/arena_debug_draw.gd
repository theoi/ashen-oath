class_name ArenaDebugDraw
extends RefCounted
## Draws an ArenaData's collision over its scene: floor walls (red), obstacle capsules
## (yellow), hazard cylinders (green), spawn points (numbered) and camera bounds (blue).


static func build(data: ArenaData) -> Node3D:
	var root := Node3D.new()
	root.name = "ArenaDebug"
	var lines := ImmediateMesh.new()
	var poly := data.floor_polygon
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for y: float in [0.05, data.wall_height]:
			_line(lines, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Color.RED)
		_line(lines, Vector3(a.x, 0.05, a.y), Vector3(a.x, data.wall_height, a.y), Color.RED)
	for obstacle in data.obstacles:
		for y: float in [0.05, obstacle.height]:
			_capsule(lines, obstacle.a, obstacle.b, obstacle.radius, y, Color.YELLOW)
	for hazard in data.hazards:
		for y: float in [0.05, hazard.height]:
			_circle(lines, hazard.center, hazard.radius, y, Color.GREEN)
	var r := data.camera_bounds
	var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		_line(lines, Vector3(a.x, 0.08, a.y), Vector3(b.x, 0.08, b.y), Color.CORNFLOWER_BLUE)
	lines.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	# Transparent so it draws after the opaque scene instead of under it.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 10
	var instance := MeshInstance3D.new()
	instance.mesh = lines
	instance.material_override = material
	root.add_child(instance)
	for i in data.spawn_points.size():
		var label := Label3D.new()
		label.text = str(i)
		label.font_size = 96
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color.CYAN
		label.position = Vector3(data.spawn_points[i].x, 2.3, data.spawn_points[i].y)
		root.add_child(label)
	return root


static func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b)


static func _circle(mesh: ImmediateMesh, center: Vector2, radius: float, y: float, color: Color) -> void:
	_arc(mesh, center, radius, y, 0.0, TAU, color)


static func _arc(mesh: ImmediateMesh, center: Vector2, radius: float, y: float, from: float, to: float, color: Color) -> void:
	const SEGMENTS := 24
	for i in SEGMENTS:
		var t0 := lerpf(from, to, float(i) / SEGMENTS)
		var t1 := lerpf(from, to, float(i + 1) / SEGMENTS)
		_line(mesh, Vector3(center.x + cos(t0) * radius, y, center.y + sin(t0) * radius),
				Vector3(center.x + cos(t1) * radius, y, center.y + sin(t1) * radius), color)


static func _capsule(mesh: ImmediateMesh, a: Vector2, b: Vector2, radius: float, y: float, color: Color) -> void:
	if a.is_equal_approx(b):
		_circle(mesh, a, radius, y, color)
		return
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x) * radius
	_line(mesh, Vector3(a.x + side.x, y, a.y + side.y), Vector3(b.x + side.x, y, b.y + side.y), color)
	_line(mesh, Vector3(a.x - side.x, y, a.y - side.y), Vector3(b.x - side.x, y, b.y - side.y), color)
	var angle := side.angle()
	_arc(mesh, b, radius, y, angle - PI, angle, color)
	_arc(mesh, a, radius, y, angle, angle + PI, color)
