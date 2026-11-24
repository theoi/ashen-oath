class_name WeaponTrail
extends MeshInstance3D
## A fading ribbon behind a weapon: samples of the blade segment (base, tip) in world
## space, drawn as a triangle strip whose alpha falls off with age.

const LIFETIME := 0.14
const MAX_SAMPLES := 24

var color: Color = Color(1.0, 0.55, 0.2, 0.8)

var _bases: PackedVector3Array = PackedVector3Array()
var _tips: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = false
	material_override = _material


## Adds the current blade segment (when `emitting`) and ages old samples by `delta`.
func feed(segment: PackedVector3Array, emitting: bool, delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	var i := 0
	while i < _ages.size():
		_ages[i] += delta
		if _ages[i] > LIFETIME:
			_ages.remove_at(i)
			_bases.remove_at(i)
			_tips.remove_at(i)
		else:
			i += 1
	if emitting and segment.size() == 2:
		_bases.append(segment[0])
		_tips.append(segment[1])
		_ages.append(0.0)
		if _ages.size() > MAX_SAMPLES:
			_ages.remove_at(0)
			_bases.remove_at(0)
			_tips.remove_at(0)
	_draw()


func clear() -> void:
	_bases.clear()
	_tips.clear()
	_ages.clear()
	_mesh.clear_surfaces()


func _draw() -> void:
	_mesh.clear_surfaces()
	if _ages.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for i in _ages.size():
		var fade := 1.0 - _ages[i] / LIFETIME
		var tip_color := Color(color, color.a * fade * fade)
		var base_color := Color(color, color.a * fade * 0.15)
		_mesh.surface_set_color(base_color)
		_mesh.surface_add_vertex(_bases[i])
		_mesh.surface_set_color(tip_color)
		_mesh.surface_add_vertex(_tips[i])
	_mesh.surface_end()
