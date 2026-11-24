class_name ArenaView
extends Node3D
## Base for arena presentation scenes. Builds the environment, lights, recolored KayKit
## props, candle flames, light shafts and ambient particles from an ArenaLook; subclasses
## place their geometry in _build_layout().
##
## Arena scenes only show the arena. Collision, spawns and hazards live in the arena's
## ArenaData (content/arenas/); presentation follows the sim through show_sim() and never
## writes to it.
## Fight floor is y = 0, centred on the origin, x along the arena's long side.

const DUNGEON := "res://assets/kaykit-dungeon-remastered/%s.glb"
const HALLOWEEN := "res://assets/kaykit-halloween-bits/%s.gltf"
const DUNGEON_ATLAS := "res://assets/kaykit-dungeon-remastered/dungeon_texture.png"
const HALLOWEEN_ATLAS := "res://assets/kaykit-halloween-bits/halloweenbits_texture.png"
const GRIM_SHADER := preload("res://presentation/arenas/shaders/grim_prop.gdshader")
const FLAME_SHADER := preload("res://presentation/arenas/shaders/flame.gdshader")
const SHAFT_SHADER := preload("res://presentation/arenas/shaders/light_shaft.gdshader")
const WATER_SHADER := preload("res://presentation/arenas/shaders/water.gdshader")
## Atlas cells (bit row * 8 + column) that glow: the dungeon candle flame cell, and the
## Halloween lantern glass cell.
const DUNGEON_GLOW_CELLS := 1 << (2 * 8 + 7)
const HALLOWEEN_GLOW_CELLS := 1 << (3 * 8 + 2)
## Props smaller than this (largest AABB side, metres) do not cast shadows.
const SHADOW_MIN_SIZE := 1.4

@export var look: ArenaLook

var _props: Node3D
var _dungeon_material: ShaderMaterial
var _halloween_material: ShaderMaterial
var _flames: Array[Transform3D] = []
var _flicker_lights: Array[OmniLight3D] = []
var _flicker_base: Array[float] = []
var _time := 0.0

static var _grime_texture: ImageTexture
static var _ripple_textures: Array[ImageTexture] = []


func _ready() -> void:
	if look == null:
		look = ArenaLook.new()
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_make_materials()
	_build_environment()
	_build_layout()
	_build_flames()


func _process(delta: float) -> void:
	_time += delta
	for i in _flicker_lights.size():
		var phase := float(i) * 1.7
		_flicker_lights[i].light_energy = _flicker_base[i] * (1.0 + 0.12 * sin(_time * 9.0 + phase) + 0.07 * sin(_time * 17.0 + phase * 2.3))


## Follows a running match: show_sim() runs after every sim step.
func attach(runner: MatchRunner) -> void:
	runner.stepped.connect(func(_events: Array[SimEvent]) -> void: show_sim(runner.sim))


## Shows the sim state the arena reacts to (hazard phases). Call after every sim step;
## visuals derive from sim state only, so they stay in step through hitstop and replays.
func show_sim(_sim: Sim) -> void:
	pass


## Subclasses place walls, floor, props, lights and VFX here.
func _build_layout() -> void:
	pass


# --- Props -------------------------------------------------------------------------------

## Instances a Dungeon Remastered model with the arena palette.
func dungeon(model: String, pos: Vector3, yaw_degrees: float = 0.0, scale_by: Vector3 = Vector3.ONE) -> Node3D:
	return _place(DUNGEON % model, _dungeon_material, pos, yaw_degrees, scale_by)


## Instances a Halloween Bits model with the arena palette.
func halloween(model: String, pos: Vector3, yaw_degrees: float = 0.0, scale_by: Vector3 = Vector3.ONE) -> Node3D:
	return _place(HALLOWEEN % model, _halloween_material, pos, yaw_degrees, scale_by)


func _place(path: String, material: ShaderMaterial, pos: Vector3, yaw_degrees: float, scale_by: Vector3) -> Node3D:
	var scene: PackedScene = load(path)
	var node: Node3D = scene.instantiate()
	node.position = pos
	node.rotation_degrees.y = yaw_degrees
	node.scale = scale_by
	_props.add_child(node)
	_apply_material(node, material)
	return node


func _apply_material(node: Node, material: ShaderMaterial) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		mesh_instance.material_override = material
		var size := mesh_instance.get_aabb().size
		var biggest := maxf(size.x, maxf(size.y, size.z))
		if biggest < SHADOW_MIN_SIZE:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_material(child, material)


## Plain mesh with a flat material (charred beams, blocking volumes outside the atlas).
func block(size: Vector3, pos: Vector3, rotation_deg: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation_degrees = rotation_deg
	_props.add_child(instance)
	return instance


# --- Fire, light, shafts -----------------------------------------------------------------

## Adds a flickering flame sprite whose base sits at `pos`.
func flame(pos: Vector3, height: float = 0.16) -> void:
	var t := Transform3D(Basis.from_scale(Vector3(height * 0.55, height, height * 0.55)), pos + Vector3(0.0, height * 0.45, 0.0))
	_flames.append(t)


## Adds a flickering warm point light (no shadows; the Compatibility renderer draws one
## extra pass per lit object per light, so arenas keep these few and short-ranged).
func fire_light(pos: Vector3, energy_scale: float = 1.0, light_range: float = 6.0, color: Color = Color(0, 0, 0, 0)) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = look.fire_color if color.a == 0.0 else color
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	add_child(light)
	_flicker_lights.append(light)
	_flicker_base.append(look.fire_light_energy * energy_scale)
	light.light_energy = look.fire_light_energy * energy_scale
	return light


## Steady point light (soul-light, lanterns).
func steady_light(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	add_child(light)
	return light


## A slanted moonlight shaft from `top` to `bottom`.
func light_shaft(top: Vector3, bottom: Vector3, radius_top: float, radius_bottom: float, intensity_scale: float = 1.0) -> void:
	var length := top.distance_to(bottom)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_top
	mesh.bottom_radius = radius_bottom
	mesh.height = length
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.radial_segments = 16
	var material := ShaderMaterial.new()
	material.shader = SHAFT_SHADER
	material.set_shader_parameter("color", look.shaft_color)
	material.set_shader_parameter("intensity", look.shaft_intensity * intensity_scale)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := (top - bottom).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	instance.transform = Transform3D(Basis(side, up, side.cross(up)), (top + bottom) * 0.5)
	add_child(instance)


func _build_flames() -> void:
	if _flames.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var material := ShaderMaterial.new()
	material.shader = FLAME_SHADER
	material.set_shader_parameter("edge_color", look.fire_color)
	material.set_shader_parameter("energy", look.flame_energy)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = _flames.size()
	for i in _flames.size():
		multimesh.set_instance_transform(i, _flames[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Flames"
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Water surface at look.water_level covering a rectangle (centre x/z, size x/z).
func water(center: Vector2, size: Vector2) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = size
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("water_color", look.water_color)
	material.set_shader_parameter("sheen_color", look.water_sheen)
	material.set_shader_parameter("ripple_a", _ripples(0))
	material.set_shader_parameter("ripple_b", _ripples(1))
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = plane
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3(center.x, look.water_level, center.y)
	add_child(instance)
	return instance


# --- Particles ---------------------------------------------------------------------------

## Soul motes drifting up out of a box.
func soul_motes(center: Vector3, extents: Vector3, amount: int) -> CPUParticles3D:
	var particles := _particles(amount, 6.0, look.soul_color, Vector2(0.05, 0.05), true)
	particles.position = center
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.direction = Vector3.UP
	particles.spread = 15.0
	particles.gravity = Vector3(0.0, 0.08, 0.0)
	particles.initial_velocity_min = 0.1
	particles.initial_velocity_max = 0.35
	particles.preprocess = 6.0
	return particles


## Ash flakes drifting down through a box (centre, half extents).
func ash(center: Vector3, extents: Vector3, amount: int) -> CPUParticles3D:
	var particles := _particles(amount, 9.0, look.ash_color, Vector2(0.035, 0.035), false)
	particles.position = center
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.direction = Vector3(0.3, -1.0, 0.1)
	particles.spread = 30.0
	particles.gravity = Vector3(0.05, -0.18, 0.0)
	particles.initial_velocity_min = 0.2
	particles.initial_velocity_max = 0.5
	particles.angular_velocity_min = -90.0
	particles.angular_velocity_max = 90.0
	particles.preprocess = 9.0
	return particles


## Embers rising from a source.
func embers(center: Vector3, extents: Vector3, amount: int, color: Color, size: float = 0.03) -> CPUParticles3D:
	var particles := _particles(amount, 3.2, color, Vector2(size, size), true)
	particles.position = center
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.direction = Vector3.UP
	particles.spread = 20.0
	particles.gravity = Vector3(0.12, 0.45, 0.05)
	particles.initial_velocity_min = 0.3
	particles.initial_velocity_max = 1.1
	particles.preprocess = 3.0
	return particles


func _particles(amount: int, lifetime: float, color: Color, size: Vector2, additive: bool) -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material
	var fade := Gradient.new()
	var bright := Color(color.r * (2.0 if additive else 1.0), color.g * (2.0 if additive else 1.0), color.b * (2.0 if additive else 1.0), color.a)
	fade.set_color(0, Color(bright, 0.0))
	fade.add_point(0.15, bright)
	fade.set_color(fade.get_point_count() - 1, Color(color, 0.0))
	var particles := CPUParticles3D.new()
	particles.amount = maxi(1, amount)
	particles.lifetime = lifetime
	particles.mesh = quad
	particles.color_ramp = fade
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = amount > 0
	particles.visible = amount > 0
	add_child(particles)
	return particles


# --- Environment and materials -----------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = look.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = look.ambient_color
	env.ambient_light_energy = look.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = look.exposure
	env.fog_enabled = true
	env.fog_light_color = look.fog_color
	env.fog_density = look.fog_density
	env.fog_sky_affect = 1.0
	env.fog_height = look.fog_height
	env.fog_height_density = look.fog_height_density
	env.glow_enabled = true
	env.glow_intensity = look.glow_intensity
	env.glow_bloom = look.glow_bloom
	env.glow_hdr_threshold = 0.9
	env.adjustment_enabled = true
	env.adjustment_saturation = look.saturation
	env.adjustment_contrast = 1.08
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = look.key_color
	key.light_energy = look.key_energy
	key.rotation_degrees = look.key_rotation
	key.shadow_enabled = look.key_shadows
	key.directional_shadow_max_distance = 45.0
	key.shadow_blur = 1.5
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_color = look.rim_color
	rim.light_energy = look.rim_energy
	rim.rotation_degrees = look.rim_rotation
	rim.shadow_enabled = false
	rim.light_specular = 1.0
	add_child(rim)


func _make_materials() -> void:
	_dungeon_material = _grim_material(load(DUNGEON_ATLAS), DUNGEON_GLOW_CELLS, look.fire_color)
	_halloween_material = _grim_material(load(HALLOWEEN_ATLAS), HALLOWEEN_GLOW_CELLS, _lantern_color())


## Lantern glass glows with the arena's soul colour where there are souls, else with fire.
func _lantern_color() -> Color:
	return look.soul_color if look.mote_amount > 0 else look.fire_color


func _grim_material(atlas: Texture2D, glow_cells: int, glow_color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GRIM_SHADER
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("tint", look.prop_tint)
	material.set_shader_parameter("desaturate", look.prop_desaturate)
	material.set_shader_parameter("brightness", look.prop_brightness)
	material.set_shader_parameter("contrast", look.prop_contrast)
	material.set_shader_parameter("grime_color", look.grime_color)
	material.set_shader_parameter("grime_amount", look.grime_amount)
	material.set_shader_parameter("grime_noise", _grime())
	material.set_shader_parameter("rim_strength", look.prop_rim)
	material.set_shader_parameter("glow_cells", glow_cells)
	material.set_shader_parameter("glow_color", glow_color)
	return material


## Tileable ripple normal maps, generated synchronously (the web build has no threads).
static func _ripples(index: int) -> ImageTexture:
	if _ripple_textures.is_empty():
		for i in 2:
			var noise := FastNoiseLite.new()
			noise.seed = 77 + i * 31
			noise.frequency = 0.05 + 0.03 * float(i)
			noise.fractal_octaves = 3
			var image := noise.get_seamless_image(128, 128)
			image.bump_map_to_normal_map(6.0)
			image.generate_mipmaps()
			_ripple_textures.append(ImageTexture.create_from_image(image))
	return _ripple_textures[index]


## Greyscale tileable noise (grime, fire tongues).
static func noise_texture() -> ImageTexture:
	return _grime()


static func _grime() -> ImageTexture:
	if _grime_texture == null:
		var noise := FastNoiseLite.new()
		noise.seed = 1213
		noise.frequency = 0.03
		noise.fractal_octaves = 4
		var image := noise.get_seamless_image(128, 128)
		image.generate_mipmaps()
		_grime_texture = ImageTexture.create_from_image(image)
	return _grime_texture
