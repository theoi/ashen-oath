extends Node3D
## Menu backdrop: a fog-lit ring of broken pillars around an ember brazier, slowly orbited.
## Presentation only. The brazier sits right of center so menus on the left stay readable.

const ORBIT_RADIUS := 5.5
const ORBIT_HEIGHT := 2.6
const ORBIT_SPEED := 0.12
const LOOK_TARGET := Vector3(0.0, 1.8, 0.0)
## Shifts the view so the brazier appears right of center.
const VIEW_OFFSET := -1.9
const PILLAR_RING_RADIUS := 9.0
## Heights of the ring pillars; short ones are drawn as broken stumps.
const PILLAR_HEIGHTS: Array[float] = [6.0, 2.1, 6.0, 6.0, 3.4, 6.0, 1.4, 6.0, 6.0, 2.7]

var _camera: Camera3D
var _ember_light: OmniLight3D
var _time := 0.0


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_pillars()
	_build_brazier()
	_build_camera()


func _process(delta: float) -> void:
	_time += delta
	var angle := _time * ORBIT_SPEED
	_camera.position = Vector3(sin(angle) * ORBIT_RADIUS, ORBIT_HEIGHT, cos(angle) * ORBIT_RADIUS)
	_camera.look_at(LOOK_TARGET)
	_ember_light.light_energy = 3.0 + 0.4 * sin(_time * 11.0) + 0.25 * sin(_time * 4.3)

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.018, 0.026)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.45)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.055, 0.075)
	env.fog_density = 0.03
	env.glow_enabled = true
	env.glow_intensity = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 0.85)
	moon.light_energy = 0.45
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	add_child(moon)


func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	_add_mesh(plane, _stone(Color(0.11, 0.1, 0.11)), Vector3.ZERO)


func _build_pillars() -> void:
	var material := _stone(Color(0.2, 0.19, 0.2))
	for i in PILLAR_HEIGHTS.size():
		var height := PILLAR_HEIGHTS[i]
		var angle := TAU * float(i) / float(PILLAR_HEIGHTS.size())
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.42
		pillar.bottom_radius = 0.5
		pillar.height = height
		var pos := Vector3(sin(angle) * PILLAR_RING_RADIUS, height * 0.5, cos(angle) * PILLAR_RING_RADIUS)
		_add_mesh(pillar, material, pos)
		var base := BoxMesh.new()
		base.size = Vector3(1.3, 0.35, 1.3)
		_add_mesh(base, material, Vector3(pos.x, 0.175, pos.z))


func _build_brazier() -> void:
	var iron := _stone(Color(0.08, 0.075, 0.08), 0.6)
	var stand := CylinderMesh.new()
	stand.top_radius = 0.18
	stand.bottom_radius = 0.35
	stand.height = 1.0
	_add_mesh(stand, iron, Vector3(0.0, 0.5, 0.0))
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.75
	bowl.bottom_radius = 0.3
	bowl.height = 0.35
	_add_mesh(bowl, iron, Vector3(0.0, 1.15, 0.0))

	var coals := StandardMaterial3D.new()
	coals.albedo_color = Color(0.2, 0.05, 0.0)
	coals.emission_enabled = true
	coals.emission = Color(1.0, 0.38, 0.08)
	coals.emission_energy_multiplier = 4.0
	var coal_mesh := SphereMesh.new()
	coal_mesh.radius = 0.55
	coal_mesh.height = 0.5
	_add_mesh(coal_mesh, coals, Vector3(0.0, 1.3, 0.0))

	_ember_light = OmniLight3D.new()
	_ember_light.light_color = Color(1.0, 0.5, 0.2)
	_ember_light.omni_range = 11.0
	_ember_light.position = Vector3(0.0, 2.0, 0.0)
	add_child(_ember_light)

	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = Color(1.0, 0.55, 0.2)
	spark_material.vertex_color_use_as_albedo = true
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.025
	spark_mesh.height = 0.05
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	spark_mesh.material = spark_material
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.75, 0.35, 1.0))
	fade.set_color(1, Color(1.0, 0.25, 0.05, 0.0))

	var embers := CPUParticles3D.new()
	embers.mesh = spark_mesh
	embers.amount = 70
	embers.lifetime = 3.5
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.45
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.gravity = Vector3(0.15, 0.5, 0.0)
	embers.initial_velocity_min = 0.4
	embers.initial_velocity_max = 1.3
	embers.color_ramp = fade
	embers.position = Vector3(0.0, 1.4, 0.0)
	add_child(embers)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.position = Vector3(0.0, ORBIT_HEIGHT, ORBIT_RADIUS)
	add_child(_camera)
	_camera.look_at(LOOK_TARGET)
	_camera.h_offset = VIEW_OFFSET
	_camera.make_current()


func _stone(color: Color, roughness: float = 0.95) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _add_mesh(mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance
