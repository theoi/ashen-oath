extends TestCase
## The arena set-up for the fixed high gameplay camera: camera-side walls are the ones cut,
## overhead pieces and camera-side wall props hide, and the rim light ends up behind the
## fighters as seen from the camera.

const ARENAS: PackedStringArray = [
	"res://content/arenas/ashen_chapel.tres",
	"res://content/arenas/ashen_chapel_night.tres",
	"res://content/arenas/drowned_crypt.tres",
	"res://content/arenas/drowned_crypt_depths.tres",
]


func test_camera_side_edges_face_the_camera() -> void:
	var square := PackedVector2Array([Vector2(-12, -10), Vector2(12, -10), Vector2(12, 10), Vector2(-12, 10)])
	# Camera looking along -z sits on the +z side: only the +z wall is cut.
	var edges := ArenaView._camera_side_edges(square, Vector2(0.0, 1.0))
	assert_eq(edges.size(), 1)
	assert_almost_eq(edges[0].w, 1.0, 0.001, "outward normal points at the camera")
	assert_almost_eq(edges[0].y, 10.0, 0.001, "the +z wall")
	# Looking along +x from the -x side cuts the -x wall.
	edges = ArenaView._camera_side_edges(square, Vector2(-1.0, 0.0))
	assert_eq(edges.size(), 1)
	assert_almost_eq(edges[0].z, -1.0, 0.001)


func test_gameplay_setup_hides_camera_side_and_overhead() -> void:
	for path in ARENAS:
		var data: ArenaData = load(path)
		var arena: ArenaView = (load(data.scene) as PackedScene).instantiate()
		add_child_autofree(arena)
		arena.apply_gameplay_camera(data)
		var yaw := deg_to_rad(data.camera_yaw)
		var toward_camera := -Vector2(sin(yaw), cos(yaw))
		assert_true(arena._cut_edges.size() >= 1, "%s cuts at least one wall" % path)
		for edge in arena._cut_edges:
			assert_true(Vector2(edge.z, edge.w).dot(toward_camera) > 0.25, "%s cuts only camera-side walls" % path)
		for node in arena._overhead:
			assert_false(node.visible, "%s hides overhead pieces" % path)
		var hidden := 0
		var far_side_hidden := 0
		for child in arena.get_node("Props").get_children():
			var node := child as Node3D
			if not node.visible:
				hidden += 1
				if Vector2(node.position.x, node.position.z).dot(toward_camera) < -6.0 and not node in arena._overhead:
					far_side_hidden += 1
		assert_true(hidden > 0, "%s hides camera-side wall pieces" % path)
		assert_eq(far_side_hidden, 0, "%s keeps the far walls" % path)
		# Rim light shines toward the camera (from behind the fighters as seen on screen).
		var rim: DirectionalLight3D = arena.get_node("RimLight")
		var shine := -rim.global_transform.basis.z
		assert_true(Vector2(shine.x, shine.z).normalized().dot(toward_camera) > 0.5, "%s rim light backlights fighters" % path)
