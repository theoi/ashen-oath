class_name ArenaCollision
extends RefCounted
## Integer collision geometry compiled from ArenaData: a convex floor polygon whose edges are
## walls, plus capsule obstacles (pillars, sarcophagi). Fighters are circles in x-z.

var data: ArenaData
var wall_height: int = 0
## Wall edges: start point and inward unit normal (Q14), both in x-z (y unused).
var edge_points: Array[Vector3i] = []
var edge_normals: Array[Vector3i] = []
var obstacle_a: Array[Vector3i] = []
var obstacle_b: Array[Vector3i] = []
var obstacle_radius: PackedInt32Array = PackedInt32Array()
var obstacle_height: PackedInt32Array = PackedInt32Array()
var hazards: Array[HazardData] = []
var hazard_centers: Array[Vector3i] = []

## Set by push_circle: whether the circle touched a wall/obstacle, the push-out normal
## (Q14, x-z) and whether that surface can wall-splat. Transient, not state.
var contact: bool = false
var contact_normal: Vector3i = Vector3i.ZERO
var contact_splat: bool = false


func _init(arena: ArenaData) -> void:
	data = arena
	wall_height = Fx.m(arena.wall_height)
	var poly := arena.floor_polygon
	var area2 := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		area2 += p.x * q.y - q.x * p.y
	var flip := area2 < 0.0
	for i in poly.size():
		var a := Vector3i(Fx.m(poly[i].x), 0, Fx.m(poly[i].y))
		var b_2d := poly[(i + 1) % poly.size()]
		var b := Vector3i(Fx.m(b_2d.x), 0, Fx.m(b_2d.y))
		var dx := b.x - a.x
		var dz := b.z - a.z
		var length := Fx.isqrt(dx * dx + dz * dz)
		if length == 0:
			continue
		# Left normal of a->b in (x, z) is (-dz, dx); it points inside for a CCW polygon.
		var nx := -dz * Fx.TRIG_ONE / length
		var nz := dx * Fx.TRIG_ONE / length
		if flip:
			nx = -nx
			nz = -nz
		edge_points.append(a)
		edge_normals.append(Vector3i(nx, 0, nz))
	for obstacle in arena.obstacles:
		obstacle_a.append(Vector3i(Fx.m(obstacle.a.x), 0, Fx.m(obstacle.a.y)))
		obstacle_b.append(Vector3i(Fx.m(obstacle.b.x), 0, Fx.m(obstacle.b.y)))
		obstacle_radius.append(Fx.m(obstacle.radius))
		obstacle_height.append(Fx.m(obstacle.height))
	hazards = arena.hazards
	for hazard in hazards:
		hazard_centers.append(Vector3i(Fx.m(hazard.center.x), 0, Fx.m(hazard.center.y)))


## Signed distance from `pos` to wall edge `i`, positive inside.
func edge_distance(i: int, pos: Vector3i) -> int:
	var a := edge_points[i]
	var n := edge_normals[i]
	return ((pos.x - a.x) * n.x + (pos.z - a.z) * n.z) / Fx.TRIG_ONE


## Pushes a circle of `radius` at `pos` out of walls and obstacles. Sets contact fields.
func push_circle(pos: Vector3i, radius: int) -> Vector3i:
	contact = false
	contact_splat = false
	contact_normal = Vector3i.ZERO
	var p := pos
	for i in edge_points.size():
		var d := edge_distance(i, p)
		if d < radius:
			var n := edge_normals[i]
			p.x += n.x * (radius - d) / Fx.TRIG_ONE
			p.z += n.z * (radius - d) / Fx.TRIG_ONE
			_touch(n, true)
	for i in obstacle_a.size():
		if p.y >= obstacle_height[i]:
			continue
		var closest := closest_on_segment(obstacle_a[i], obstacle_b[i], p)
		var dx := p.x - closest.x
		var dz := p.z - closest.z
		var reach := obstacle_radius[i] + radius
		var dist2 := dx * dx + dz * dz
		if dist2 >= reach * reach:
			continue
		var dist := Fx.isqrt(dist2)
		var n := Vector3i(Fx.TRIG_ONE, 0, 0)
		if dist > 0:
			n = Vector3i(dx * Fx.TRIG_ONE / dist, 0, dz * Fx.TRIG_ONE / dist)
		p.x = closest.x + n.x * reach / Fx.TRIG_ONE
		p.z = closest.z + n.z * reach / Fx.TRIG_ONE
		_touch(n, data.obstacles[i].wall_splat)
	return p


## True if a sphere at `pos` touches a wall or a projectile-blocking obstacle.
func blocks_projectile(pos: Vector3i, radius: int) -> bool:
	if pos.y < wall_height:
		for i in edge_points.size():
			if edge_distance(i, pos) < radius:
				return true
	for i in obstacle_a.size():
		if not data.obstacles[i].blocks_projectiles or pos.y >= obstacle_height[i]:
			continue
		var closest := closest_on_segment(obstacle_a[i], obstacle_b[i], pos)
		var reach := obstacle_radius[i] + radius
		if Fx.dist2_xz(closest, pos) < reach * reach:
			return true
	return false


## True if `pos` is on the floor polygon (ignores obstacles).
func inside_floor(pos: Vector3i) -> bool:
	for i in edge_points.size():
		if edge_distance(i, pos) < 0:
			return false
	return true


static func closest_on_segment(a: Vector3i, b: Vector3i, p: Vector3i) -> Vector3i:
	var abx := b.x - a.x
	var abz := b.z - a.z
	var len2 := abx * abx + abz * abz
	if len2 == 0:
		return Vector3i(a.x, p.y, a.z)
	var t := (p.x - a.x) * abx + (p.z - a.z) * abz
	if t <= 0:
		return Vector3i(a.x, p.y, a.z)
	if t >= len2:
		return Vector3i(b.x, p.y, b.z)
	return Vector3i(a.x + abx * t / len2, p.y, a.z + abz * t / len2)


func _touch(normal: Vector3i, splat: bool) -> void:
	contact = true
	contact_normal = normal
	contact_splat = contact_splat or splat
