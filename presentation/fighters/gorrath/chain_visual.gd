class_name ChainVisual
extends MultiMeshInstance3D
## A chain of rusted iron links laid along a polyline in world space (Gorrath's chains).
## Links alternate 90 degrees so the chain reads as interlocked at fighting distance.

const LINK_LENGTH := 0.085

var color := Color(0.26, 0.13, 0.08)
var glow := Color(0.9, 0.22, 0.05)
## Ember heat of the rust (0..1); raised while the chain is thrown or straining.
var heat := 0.3:
	set(value):
		heat = value
		if _material != null:
			_material.emission_energy_multiplier = 0.25 + 2.4 * heat

var _material: StandardMaterial3D
var _spacing := LINK_LENGTH


func _init(max_links: int = 64, link_scale: float = 1.0) -> void:
	top_level = true
	_spacing = LINK_LENGTH * link_scale
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var link := TorusMesh.new()
	link.inner_radius = 0.02 * link_scale
	link.outer_radius = 0.042 * link_scale
	link.rings = 8
	link.ring_segments = 6
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.roughness = 0.95
	_material.metallic = 0.35
	_material.emission_enabled = true
	_material.emission = glow
	_material.rim_enabled = true
	_material.rim = 0.4
	link.material = _material
	heat = heat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = link
	multimesh.instance_count = max_links
	multimesh.visible_instance_count = 0


## Lays links along `points` (world space); hides the chain for fewer than two points.
func set_points(points: PackedVector3Array) -> void:
	var count := 0
	var max_links := multimesh.instance_count
	var spacing := _spacing
	var carry := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := b - a
		var length := seg.length()
		if length < 0.0001:
			continue
		var dir := seg / length
		var t := carry
		while t < length and count < max_links:
			var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
			var basis := Basis.looking_at(dir, up)
			# The torus ring lies in its XZ plane, which already contains the chain
			# direction (-Z); stretch it into an oval and twist every other link.
			basis = basis * Basis(Vector3.BACK, PI / 2.0 * float(count % 2))
			basis = basis.scaled_local(Vector3(1.0, 1.0, 1.6))
			multimesh.set_instance_transform(count, Transform3D(basis, a + dir * t))
			count += 1
			t += spacing
		carry = t - length
	multimesh.visible_instance_count = count
