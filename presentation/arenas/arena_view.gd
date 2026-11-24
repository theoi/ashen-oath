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
const VIGNETTE_SHADER := preload("res://presentation/arenas/shaders/vignette.gdshader")
## Render layers: fighters stay on layer 1 (the default); arena geometry moves to layer 2 so
## the fighter-only fill and rim lights skip it.
const FIGHTER_LAYER := 1
const ARENA_LAYER := 2
## Camera-side walls are cut down to about this height (m) for the gameplay camera.
const CUT_HEIGHT := 1.1
## Props whose origin is above CUT_HEIGHT and within this distance inside a cut floor edge
## (or beyond it) are hidden: torches, shelves and lanterns on camera-side walls.
const CUT_REACH := 0.6
## Screen-space size (m at the fighter) of the dither hole around each fighter.
const OCCLUDER_RADIUS := 1.5
## Time constant (s) of the light pool easing after the fighters.
const POOL_FOLLOW_SECONDS := 0.6
## Atlas cells (bit row * 8 + column) that glow: the dungeon candle flame cell, and the
## Halloween lantern glass cell.
const DUNGEON_GLOW_CELLS := 1 << (2 * 8 + 7)
const HALLOWEEN_GLOW_CELLS := 1 << (3 * 8 + 2)
## Dungeon banner cloth cell, recoloured to the look's blood-dark stain tone.
const DUNGEON_STAIN_CELLS := 1 << (2 * 8 + 3)
## Props smaller than this (largest AABB side, metres) do not cast shadows.
const SHADOW_MIN_SIZE := 1.4

@export var look: ArenaLook

var _props: Node3D
var _dungeon_material: ShaderMaterial
var _halloween_material: ShaderMaterial
var _flames: Array[Transform3D] = []
var _flame_multimesh: MultiMesh
var _overhead: Array[Node3D] = []
var _cut_edges: Array[Vector4] = []
var _runner: MatchRunner
var _rim: DirectionalLight3D
var _pool_light: SpotLight3D
## Where the fight light pool is centred now (x, z); follows the fighters in a match.
var _pool_center := Vector2.ZERO
var _pool_follow := false
var _fill: DirectionalLight3D
var _flicker_lights: Array[OmniLight3D] = []
var _flicker_base: Array[float] = []
var _time := 0.0



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
	if _runner != null and _runner.sim != null:
		var points: Array[Vector3] = []
		for slot in mini(4, _runner.sim.slot_count()):
			points.append(_runner.fighter_position(slot))
		follow_fighters(points, delta)
	for i in _flicker_lights.size():
		var phase := float(i) * 1.7
		_flicker_lights[i].light_energy = _flicker_base[i] * (1.0 + 0.12 * sin(_time * 9.0 + phase) + 0.07 * sin(_time * 17.0 + phase * 2.3))


## Follows a running match: show_sim() runs after every sim step, the arena is set up for
## the fixed gameplay camera of the match's ArenaData, and props between the camera and the
## fighters dither out.
func attach(runner: MatchRunner) -> void:
	_runner = runner
	runner.stepped.connect(func(_events: Array[SimEvent]) -> void: show_sim(runner.sim))
	if runner.sim.config.arena != null:
		apply_gameplay_camera(runner.sim.config.arena)


## Sets the arena up for the high fixed-yaw gameplay camera (ArenaData.camera_yaw): walls
## and props on the camera side are cut down to low broken stubs, roofs and ceilings are
## hidden, and the rim light moves behind the fighters as seen from the camera with the
## fighter fill in front. Story shots skip this and keep the full set.
func apply_gameplay_camera(data: ArenaData) -> void:
	var yaw := deg_to_rad(data.camera_yaw)
	var view := Vector2(sin(yaw), cos(yaw))
	_cut_edges = _camera_side_edges(data.floor_polygon, -view)
	var packed: Array[Vector4] = []
	for edge in _cut_edges:
		packed.append(edge)
	for material: ShaderMaterial in [_dungeon_material, _halloween_material]:
		material.set_shader_parameter("cut_edges", packed)
		material.set_shader_parameter("cut_edge_count", _cut_edges.size())
		material.set_shader_parameter("cut_height", CUT_HEIGHT)
	for node in _overhead:
		node.visible = false
	for child in _props.get_children():
		var node := child as Node3D
		if node != null and node.position.y > CUT_HEIGHT and _is_cut(Vector2(node.position.x, node.position.z), CUT_REACH):
			node.visible = false
	if _flame_multimesh != null:
		for i in _flames.size():
			var origin := _flames[i].origin
			if origin.y > CUT_HEIGHT and _is_cut(Vector2(origin.x, origin.z), CUT_REACH):
				_flame_multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), origin))
	# Lights rotate with the camera: rim from behind the fighters, fill from the camera side.
	var camera_light_yaw := data.camera_yaw + 180.0
	_rim.rotation_degrees = Vector3(look.rim_camera_pitch, camera_light_yaw + 180.0 + look.rim_camera_offset, 0.0)
	if _fill != null:
		_fill.rotation_degrees = Vector3(look.fill_camera_pitch, camera_light_yaw + look.fill_camera_offset, 0.0)


## Floor edges whose outward normal faces `toward_camera`, as (point x, point z, normal x,
## normal z). Up to 8.
static func _camera_side_edges(polygon: PackedVector2Array, toward_camera: Vector2) -> Array[Vector4]:
	var edges: Array[Vector4] = []
	var centroid := Vector2.ZERO
	for p in polygon:
		centroid += p
	centroid /= float(maxi(1, polygon.size()))
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var n := Vector2(b.y - a.y, a.x - b.x).normalized()
		if n.dot(a - centroid) < 0.0:
			n = -n
		if n.dot(toward_camera) > 0.25 and edges.size() < 8:
			edges.append(Vector4(a.x, a.y, n.x, n.y))
	return edges


## True if `p` (x, z) lies beyond a cut floor edge, or within `reach` metres inside it.
func _is_cut(p: Vector2, reach: float) -> bool:
	for edge in _cut_edges:
		if (p - Vector2(edge.x, edge.y)).dot(Vector2(edge.z, edge.w)) > -reach:
			return true
	return false


## Marks a roof, beam or ceiling piece that the high gameplay camera would look through.
func overhead(node: Node3D) -> Node3D:
	_overhead.append(node)
	return node


## Keeps the fight readable where the fighters actually are: the light pool (spot and prop
## darkening) eases toward the fighters' centroid, and props between them and the camera
## dither away. attach() feeds this every frame; tools without a runner call it directly.
func follow_fighters(fighters: Array[Vector3], delta: float) -> void:
	if fighters.is_empty():
		return
	var centroid := Vector2.ZERO
	for p in fighters:
		centroid += Vector2(p.x, p.z)
	centroid /= float(fighters.size())
	var blend := 1.0 if not _pool_follow else 1.0 - exp(-delta / POOL_FOLLOW_SECONDS)
	_pool_follow = true
	_set_pool_center(_pool_center.lerp(centroid, blend))
	_set_occluders(fighters)


func _set_pool_center(center: Vector2) -> void:
	_pool_center = center
	var pool := Vector4(center.x, center.y, look.pool_inner, look.pool_outer)
	_dungeon_material.set_shader_parameter("pool", pool)
	_halloween_material.set_shader_parameter("pool", pool)
	if _pool_light != null:
		_pool_light.position = Vector3(center.x, look.pool_light_height, center.y)


func _set_occluders(fighters: Array[Vector3]) -> void:
	var targets: Array[Vector4] = []
	for i in 4:
		if i < fighters.size():
			var p := fighters[i]
			targets.append(Vector4(p.x, p.y + 1.0, p.z, OCCLUDER_RADIUS))
		else:
			targets.append(Vector4.ZERO)
	_dungeon_material.set_shader_parameter("occluder_targets", targets)
	_halloween_material.set_shader_parameter("occluder_targets", targets)

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
		mesh_instance.layers = ARENA_LAYER
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
	instance.layers = ARENA_LAYER
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
	_flame_multimesh = multimesh
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
	material.set_shader_parameter("opacity", look.water_opacity)
	material.set_shader_parameter("murk_color", look.water_murk_color)
	material.set_shader_parameter("murk", look.water_murk)
	material.set_shader_parameter("murk_noise", noise_texture())
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = plane
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3(center.x, look.water_level, center.y)
	instance.layers = ARENA_LAYER
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


## Fine dust hanging in a light shaft, drifting slowly (catches the shaft colour).
func dust(center: Vector3, extents: Vector3, amount: int) -> CPUParticles3D:
	var color := Color(look.shaft_color, 0.5)
	var particles := _particles(amount, 12.0, color, Vector2(0.02, 0.02), true)
	particles.position = center
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.direction = Vector3(0.2, -0.3, 0.1)
	particles.spread = 180.0
	particles.gravity = Vector3(0.0, -0.01, 0.0)
	particles.initial_velocity_min = 0.02
	particles.initial_velocity_max = 0.08
	particles.preprocess = 12.0
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
	_rim = rim
	rim.name = "RimLight"
	rim.light_color = look.rim_color
	rim.light_energy = look.rim_energy
	rim.rotation_degrees = look.rim_rotation
	rim.shadow_enabled = false
	rim.light_specular = 1.0
	if not look.rim_lights_props:
		rim.light_cull_mask = FIGHTER_LAYER
	add_child(rim)

	if look.fighter_fill_energy > 0.0:
		var fill := DirectionalLight3D.new()
		_fill = fill
		fill.name = "FighterFill"
		fill.light_color = look.fighter_fill_color
		fill.light_energy = look.fighter_fill_energy
		fill.rotation_degrees = look.fighter_fill_rotation
		fill.shadow_enabled = false
		fill.light_specular = 0.3
		fill.light_cull_mask = FIGHTER_LAYER
		add_child(fill)

	if look.pool_light_energy > 0.0:
		var spot := SpotLight3D.new()
		_pool_light = spot
		spot.name = "PoolLight"
		spot.light_color = look.pool_light_color
		spot.light_energy = look.pool_light_energy
		spot.spot_range = look.pool_light_height + 4.0
		# Wide cone with a steep angular falloff: bright centre fading to nothing well before
		# the cone edge, so the pool has no visible rim on the floor.
		spot.spot_angle = minf(look.pool_light_angle * 1.6, 80.0)
		spot.spot_angle_attenuation = 3.0
		spot.spot_attenuation = 0.4
		spot.shadow_enabled = false
		# Mostly diffuse: a full-strength specular glares off the crypt water toward the camera.
		spot.light_specular = 0.15
		spot.position = Vector3(look.pool_center.x, look.pool_light_height, look.pool_center.y)
		spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		add_child(spot)

	if look.vignette > 0.0:
		var layer := CanvasLayer.new()
		layer.name = "Vignette"
		layer.layer = -10
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = VIGNETTE_SHADER
		material.set_shader_parameter("strength", look.vignette)
		rect.material = material
		layer.add_child(rect)
		add_child(layer)


func _make_materials() -> void:
	_dungeon_material = _grim_material(load(DUNGEON_ATLAS), DUNGEON_GLOW_CELLS, look.fire_color)
	_dungeon_material.set_shader_parameter("stain_cells", DUNGEON_STAIN_CELLS)
	_halloween_material = _grim_material(load(HALLOWEEN_ATLAS), HALLOWEEN_GLOW_CELLS, _lantern_color())


## Lantern glass glows with the arena's soul colour where there are souls, else with fire.
func _lantern_color() -> Color:
	return look.soul_color if look.mote_amount > 0 else look.fire_color


func _grim_material(atlas: Texture2D, glow_cells: int, glow_color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GRIM_SHADER
	var params := {
		"atlas": atlas,
		"tint": look.prop_tint,
		"desaturate": look.prop_desaturate,
		"brightness": look.prop_brightness,
		"contrast": look.prop_contrast,
		"grime_color": look.grime_color,
		"grime_amount": look.grime_amount,
		"grime_noise": noise_texture(),
		"breakup": look.breakup,
		"damp_color": look.damp_color,
		"damp_amount": look.damp_amount,
		"damp_height": look.damp_height,
		"soot_color": look.soot_color,
		"soot_amount": look.soot_amount,
		"soot_start": look.soot_start,
		"streak_amount": look.streak_amount,
		"stain_color": look.stain_color,
		"stain_amount": look.stain_amount,
		"pool": Vector4(look.pool_center.x, look.pool_center.y, look.pool_inner, look.pool_outer),
		"pool_darken": look.pool_darken,
		"rim_strength": look.prop_rim,
		"glow_cells": glow_cells,
		"glow_color": glow_color,
	}
	for key: String in params:
		material.set_shader_parameter(key, params[key])
	return material


## Tileable ripple normal map `index` (0 or 1), generated synchronously (the web build has
## no threads).
static func _ripples(index: int) -> ImageTexture:
	return TreeCache.get_or_make(&"arena_ripples_%d" % index, func() -> ImageTexture:
		var noise := FastNoiseLite.new()
		noise.seed = 77 + index * 31
		noise.frequency = 0.05 + 0.03 * float(index)
		noise.fractal_octaves = 3
		var image := noise.get_seamless_image(128, 128)
		image.bump_map_to_normal_map(6.0)
		image.generate_mipmaps()
		return ImageTexture.create_from_image(image))


## Greyscale tileable noise (grime, fire tongues, water murk).
static func noise_texture() -> ImageTexture:
	return TreeCache.get_or_make(&"arena_noise", func() -> ImageTexture:
		var noise := FastNoiseLite.new()
		noise.seed = 1213
		noise.frequency = 0.03
		noise.fractal_octaves = 4
		var image := noise.get_seamless_image(128, 128)
		image.generate_mipmaps()
		return ImageTexture.create_from_image(image))
