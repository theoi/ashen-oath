extends TestCase
## Arena collision data sanity: the floor is a convex ~24 x 20 m polygon, spawns are clear
## of walls, pillars, vents and each other, and the presentation scene lines up with the
## collision (pillars and grave vents where the data puts them).

const ARENAS: PackedStringArray = [
	"res://content/arenas/ashen_chapel.tres",
	"res://content/arenas/ashen_chapel_night.tres",
	"res://content/arenas/drowned_crypt.tres",
	"res://content/arenas/drowned_crypt_depths.tres",
]
## Largest fighter radius we plan for, plus breathing room at round start.
const FIGHTER_CLEARANCE := 0.45 + 0.5
const MIN_SPAWN_GAP := 3.0


func test_floor_is_convex_and_about_24_by_20() -> void:
	for path in ARENAS:
		var data: ArenaData = load(path)
		var poly := data.floor_polygon
		assert_true(poly.size() >= 4, path)
		var sign := 0.0
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var c := poly[(i + 2) % poly.size()]
			var cross := (b - a).cross(c - b)
			assert_true(absf(cross) > 0.001, "%s: collinear corner at %s" % [path, b])
			if sign == 0.0:
				sign = signf(cross)
			assert_eq(signf(cross), sign, "%s: concave corner at %s" % [path, b])
		var box := _bounds(poly)
		assert_almost_eq(box.size.x, 24.0, 1.0, "%s width" % path)
		assert_almost_eq(box.size.y, 20.0, 1.0, "%s depth" % path)
		assert_true(box.encloses(data.camera_bounds), "%s camera bounds inside the floor" % path)


func test_spawns_are_clear() -> void:
	for path in ARENAS:
		var data: ArenaData = load(path)
		assert_true(data.spawn_points.size() >= 4, "%s has 4 spawns" % path)
		for i in data.spawn_points.size():
			var p := data.spawn_points[i]
			var label := "%s spawn %d" % [path, i]
			assert_true(_wall_distance(data.floor_polygon, p) > FIGHTER_CLEARANCE, "%s is clear of walls" % label)
			for obstacle in data.obstacles:
				var gap := _segment_distance(obstacle.a, obstacle.b, p) - obstacle.radius
				assert_true(gap > FIGHTER_CLEARANCE, "%s is clear of the obstacle at %s" % [label, obstacle.a])
			for hazard in data.hazards:
				assert_true(p.distance_to(hazard.center) - hazard.radius > FIGHTER_CLEARANCE, "%s is clear of %s" % [label, hazard.id])
			for j in i:
				assert_true(p.distance_to(data.spawn_points[j]) >= MIN_SPAWN_GAP, "%s is apart from spawn %d" % [label, j])


func test_obstacles_and_hazards_are_on_the_floor() -> void:
	for path in ARENAS:
		var data: ArenaData = load(path)
		for obstacle in data.obstacles:
			assert_true(_wall_distance(data.floor_polygon, obstacle.a) > obstacle.radius + FIGHTER_CLEARANCE * 2.0,
					"%s: fighters can pass behind the obstacle at %s" % [path, obstacle.a])
		for hazard in data.hazards:
			assert_true(_wall_distance(data.floor_polygon, hazard.center) > hazard.radius, "%s: %s on the floor" % [path, hazard.id])
			for obstacle in data.obstacles:
				assert_true(_segment_distance(obstacle.a, obstacle.b, hazard.center) > obstacle.radius + hazard.radius,
						"%s: %s clear of pillars" % [path, hazard.id])


func test_scene_matches_collision() -> void:
	for path in ARENAS:
		var data: ArenaData = load(path)
		var scene: PackedScene = load(data.scene)
		assert_not_null(scene, "%s scene" % path)
		var script: Script = scene.get_state().get_node_property_value(0, 0)
		var constants := script.get_script_constant_map()
		var pillars: Array[Vector2] = constants["PILLARS"]
		assert_eq(pillars.size(), data.obstacles.size(), "%s pillar count" % path)
		for obstacle in data.obstacles:
			assert_true(obstacle.a.is_equal_approx(obstacle.b), "%s: obstacles are pillars" % path)
			assert_has(pillars, obstacle.a, "%s: a pillar model stands at %s" % [path, obstacle.a])
		var vents: Array[Vector2] = constants.get("VENTS", [] as Array[Vector2])
		assert_eq(vents.size(), data.hazards.size(), "%s vent count" % path)
		for hazard in data.hazards:
			assert_has(vents, hazard.center, "%s: a grate lies under %s" % [path, hazard.id])
			assert_almost_eq(constants["VENT_FIRE_RADIUS"], hazard.radius, 0.001, "%s: fire matches the hit radius" % path)


func _bounds(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	return box


## Distance from `p` to the nearest edge of the (convex) floor polygon; negative outside.
func _wall_distance(poly: PackedVector2Array, p: Vector2) -> float:
	var inside := Geometry2D.is_point_in_polygon(p, poly)
	var nearest := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		nearest = minf(nearest, p.distance_to(q))
	return nearest if inside else -nearest


func _segment_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
