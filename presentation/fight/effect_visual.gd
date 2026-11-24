extends Node3D
## Default look of a sim effect (EffectData without its own scene): a glowing bolt for
## projectiles, a floor rune that erupts for delayed effects, a ground ring for shockwaves
## and a rising column for pillars. Colour comes from the owner's FighterModel accent.

enum Kind { BOLT, RUNE, RING, PILLAR }

const COLUMN_SHADER := preload("res://presentation/fight/shaders/fire_column.gdshader")

var kind: Kind = Kind.BOLT
var color: Color = Color(1.0, 0.5, 0.2)

var _data: EffectData
var _core: MeshInstance3D
var _particles: CPUParticles3D
var _material: StandardMaterial3D
var _column: ShaderMaterial
var _age := 0.0
var _active := false
var _ending := -1.0
var _radius := 0.3


func setup(data: EffectData, accent: Color) -> void:
	_data = data
	color = accent
	_radius = data.radius
	if data.speed > 0.0:
		kind = Kind.BOLT
	elif data.grow_speed > 0.0:
		kind = Kind.RING
	elif data.delay > 0:
		kind = Kind.RUNE
	else:
		kind = Kind.PILLAR
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_texture = FightFx._glow() if kind == Kind.BOLT else FightFx._ring()
	_material.albedo_color = _hot(1.0)
	_core = MeshInstance3D.new()
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.material_override = _material
	match kind:
		Kind.BOLT:
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE * maxf(0.5, data.radius * 3.0)
			_core.mesh = quad
			_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			_particles = _trail_particles(26, 0.35)
		Kind.RUNE, Kind.RING:
			var plane := QuadMesh.new()
			plane.size = Vector2.ONE * 2.0
			_core.mesh = plane
			_core.rotation.x = -PI / 2.0
			_core.position.y = 0.04
			_core.scale = Vector3.ONE * maxf(0.4, data.radius)
			if kind == Kind.RUNE:
				_material.albedo_color = _hot(0.5)
		Kind.PILLAR:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = data.radius * 0.7
			cylinder.bottom_radius = data.radius
			cylinder.height = maxf(1.0, data.height)
			cylinder.cap_top = false
			cylinder.cap_bottom = false
			_core.mesh = cylinder
			_core.position.y = cylinder.height * 0.5
			_column = ShaderMaterial.new()
			_column.shader = COLUMN_SHADER
			_column.set_shader_parameter(&"color", Color(color, 0.9))
			_core.material_override = _column
			_particles = _trail_particles(40, 0.7)
			_particles.direction = Vector3.UP
			_particles.initial_velocity_min = 3.0
			_particles.initial_velocity_max = 7.0
			_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			_particles.emission_sphere_radius = data.radius
	add_child(_core)
	_active = data.delay <= 0


func activate() -> void:
	_active = true
	if kind == Kind.RUNE:
		_material.albedo_color = _hot(1.0)
		_particles = _trail_particles(36, 0.6)
		_particles.direction = Vector3.UP
		_particles.spread = 25.0
		_particles.initial_velocity_min = 4.0
		_particles.initial_velocity_max = 8.0
		_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_particles.emission_sphere_radius = _radius
		_particles.one_shot = true
		_particles.explosiveness = 0.8
		_particles.restart()


## Fades out and frees itself (top_level particles finish first).
func finish(_destroyed: bool) -> void:
	_ending = 0.0
	if _particles != null:
		_particles.emitting = false


func set_radius(radius: float) -> void:
	_radius = radius
	if kind == Kind.RING:
		_core.scale = Vector3.ONE * maxf(0.2, radius)


func _process(delta: float) -> void:
	_age += delta
	if _ending >= 0.0:
		_ending += delta
		_material.albedo_color.a = maxf(0.0, 1.0 - _ending / 0.25)
		if _column != null:
			_column.set_shader_parameter(&"fade", maxf(0.0, 1.0 - _ending / 0.25))
		if _ending > 0.8:
			queue_free()
		return
	match kind:
		Kind.RUNE:
			if not _active:
				_core.rotation.y += delta * 1.5
				_material.albedo_color = _hot(0.35 + 0.3 * absf(sin(_age * 10.0)))
		Kind.PILLAR:
			var rise := clampf(_age / 0.12, 0.0, 1.0)
			_core.scale = Vector3(1.0 + 0.06 * sin(_age * 30.0), rise, 1.0 + 0.06 * cos(_age * 27.0))
			_core.position.y = (_core.mesh as CylinderMesh).height * 0.5 * rise


func _hot(alpha: float) -> Color:
	return Color(color.r * 2.5, color.g * 2.5, color.b * 2.5, alpha)


func _trail_particles(amount: int, life: float) -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = FightFx._glow()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = material
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.gravity = Vector3(0.0, 0.6, 0.0)
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	var ramp := Gradient.new()
	ramp.set_color(0, _hot(1.0))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p
