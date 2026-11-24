extends FighterModel
## Aldric: battered knight whose Oathfire leaks through his armour. Ember seams (glowing
## trim cells), embers rising from his joints, a sword with molten cracks that blazes when
## Oathkeeper's parry buff or a fire ability is active, and leans for his abilities.

const EMBER_BONES: Array[StringName] = [&"chest", &"lowerarm.l", &"lowerarm.r", &"lowerleg.l", &"lowerleg.r"]
const FIRE_MOVES: Array[StringName] = [&"oathfire_lunge", &"brand_rise", &"brand_rise_slam", &"flame_rend",
		&"rend_ignition", &"retribution", &"cinder_wheel", &"verdict", &"pyre_of_the_forsworn"]

var _embers: Array[CPUParticles3D] = []
var _blade_fire: CPUParticles3D
var _heat := 0.0


func _build_extras() -> void:
	for bone in EMBER_BONES:
		var p := _ember_emitter(5, 0.9, 0.06)
		attach_to_bone(bone, p)
		_embers.append(p)
	_blade_fire = _ember_emitter(28, 0.45, 0.08)
	_blade_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_blade_fire.emission_box_extents = Vector3(0.05, 0.5, 0.05)
	_blade_fire.position = Vector3(0.0, 0.85, 0.0)
	_blade_fire.initial_velocity_max = 1.6
	_blade_fire.emitting = false
	if trail_node != null:
		trail_node.add_child(_blade_fire)


func update_extras(sim: Sim, f: FighterState, delta: float) -> void:
	var hot := false
	for buff in f.buffs:
		if buff.source == -1:
			hot = true
	var move := sim.current_move(f)
	if move != null and move.id in FIRE_MOVES:
		hot = true
	_heat = move_toward(_heat, 1.0 if hot else 0.0, delta * (6.0 if hot else 2.0))
	if weapon_material != null:
		weapon_material.set_shader_parameter(&"ignite", _heat)
	_blade_fire.emitting = _heat > 0.3
	trail_color = Color(1.0, 0.45 + 0.1 * (1.0 - _heat), 0.15, 0.6 + 0.35 * _heat)


func adjust_pose(sim: Sim, f: FighterState, pose: FighterPose, sub: float) -> void:
	var move := sim.current_move(f)
	if move == null or f.action != FighterState.Action.ATTACK:
		return
	var frame := float(f.move_frame - 1) + sub
	match move.id:
		&"oathfire_lunge":
			var dash := clampf((frame - 1.0) / 2.0, 0.0, 1.0) * clampf((16.0 - frame) / 4.0, 0.0, 1.0)
			pose.pitch += deg_to_rad(24.0) * dash
			pose.lift -= 0.12 * dash
		&"brand_rise":
			var rise := clampf((frame - 3.0) / 3.0, 0.0, 1.0) * clampf((18.0 - frame) / 8.0, 0.0, 1.0)
			pose.lift += 0.35 * rise
			pose.pitch -= deg_to_rad(12.0) * rise
		&"brand_rise_slam":
			# A 2 m leap that comes down on the first active frame.
			var t := clampf(frame / float(move.startup), 0.0, 1.0)
			pose.lift += 2.0 * 4.0 * t * (1.0 - t)
			pose.pitch += deg_to_rad(18.0) * t
		&"verdict":
			if f.charging:
				pose.lift -= 0.1
				pose.pitch -= deg_to_rad(8.0)
			else:
				var leap := clampf((frame - 2.0) / 12.0, 0.0, 1.0)
				pose.lift += 2.6 * 4.0 * leap * (1.0 - leap)
				pose.pitch += deg_to_rad(16.0) * leap
		&"pyre_of_the_forsworn":
			if frame >= float(move.startup - 1):
				var kneel := clampf((float(move.total_frames()) - frame) / 10.0, 0.0, 1.0)
				pose.lift -= 0.28 * kneel
				pose.pitch += deg_to_rad(10.0) * kneel


func _ember_emitter(amount: int, lifetime: float, size: float) -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = FightFx._glow()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0.0, 1.2, 0.0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	var ramp := Gradient.new()
	ramp.set_color(0, Color(3.0, 1.3, 0.35, 1.0))
	ramp.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
