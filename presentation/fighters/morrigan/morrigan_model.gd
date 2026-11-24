extends FighterModel
## Morrigan: a drowned grave-witch. A soul-lantern swings from her hip and burns sickly
## green brighter with every stored soul (Lantern of Souls, FighterState.vars[0]), flaring
## when Soul Lance looses them; wisps trail her; she levitates for Requiem.

const SOULS := 0
const MAX_SOULS := 3
## Where the lantern hangs: offset from the hips in the model's space (meters, +Z forward).
const HIP_HOOK := Vector3(0.24, -0.02, 0.1)

@export var lantern_scene: PackedScene
@export var soul_color: Color = Color(0.6, 1.0, 0.3)

var _lantern_pivot: Node3D
var _flame: MeshInstance3D
var _flame_material: StandardMaterial3D
var _light: OmniLight3D
var _wisps: CPUParticles3D
var _hips := -1
var _swing := Vector2.ZERO
var _swing_vel := Vector2.ZERO
var _last_hook := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _flare := 0.0
var _glow := 0.0


func _build_extras() -> void:
	_hips = skeleton.find_bone(&"hips")
	_lantern_pivot = Node3D.new()
	_lantern_pivot.name = "Lantern"
	_lantern_pivot.top_level = true
	add_child(_lantern_pivot)
	if lantern_scene != null:
		var lantern := lantern_scene.instantiate() as Node3D
		# The model hangs 1.3 m below its origin (ring, rod, cage).
		lantern.scale = Vector3.ONE * 0.3
		_lantern_pivot.add_child(lantern)
		_darken(lantern)
	_flame_material = StandardMaterial3D.new()
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.albedo_color = soul_color
	_flame_material.emission_enabled = true
	_flame_material.emission = soul_color
	var orb := SphereMesh.new()
	orb.radius = 0.035
	orb.height = 0.07
	orb.radial_segments = 10
	orb.rings = 5
	_flame = MeshInstance3D.new()
	_flame.mesh = orb
	_flame.material_override = _flame_material
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.position = Vector3(0.0, -0.29, 0.0)
	_lantern_pivot.add_child(_flame)
	_light = OmniLight3D.new()
	_light.light_color = soul_color
	_light.omni_range = 2.6
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, -0.29, 0.0)
	_lantern_pivot.add_child(_light)
	_wisps = _wisp_emitter()
	_flame.add_child(_wisps)
	_last_hook = _hook_point()
	_lantern_pivot.global_position = _last_hook


func update_extras(sim: Sim, f: FighterState, delta: float) -> void:
	var souls := clampi(f.vars[SOULS], 0, MAX_SOULS)
	var move := sim.current_move(f)
	if move != null and move.id == &"soul_lance" and f.move_frame >= move.startup - 2 and f.move_frame <= move.startup + 2:
		_flare = 1.0
	if move != null and move.id == &"requiem_of_the_drowned":
		_flare = maxf(_flare, 0.8)
	_flare = move_toward(_flare, 0.0, delta * 2.5)
	var target := 0.35 + 0.22 * float(souls)
	_glow = move_toward(_glow, target, delta * 2.0)
	var flicker := 0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.011) * sin(Time.get_ticks_msec() * 0.0037)
	var power := (_glow + _flare * 1.2) * flicker
	_flame_material.emission_energy_multiplier = 0.25 + 0.6 * power
	_flame.scale = Vector3.ONE * (0.7 + 0.4 * power)
	_light.light_energy = 0.3 + 0.8 * power
	_wisps.scale_amount_max = 0.8 + 0.4 * float(souls) + _flare
	_swing_lantern(delta)


func adjust_pose(sim: Sim, f: FighterState, pose: FighterPose, sub: float) -> void:
	var move := sim.current_move(f)
	if move == null or f.action != FighterState.Action.ATTACK:
		return
	var frame := float(f.move_frame - 1) + sub
	match move.id:
		&"wraithstep":
			var blink := clampf(frame / 3.0, 0.0, 1.0) * clampf((14.0 - frame) / 4.0, 0.0, 1.0)
			pose.pitch += deg_to_rad(18.0) * blink
		&"requiem_of_the_drowned":
			var rise := clampf(frame / 20.0, 0.0, 1.0) * clampf((float(move.total_frames()) - frame) / 12.0, 0.0, 1.0)
			pose.lift += 0.55 * rise
			pose.pitch -= deg_to_rad(6.0) * rise


func _hook_point() -> Vector3:
	if _hips < 0:
		return global_position + Vector3.UP
	var hips := skeleton.global_transform * skeleton.get_bone_global_pose(_hips).origin
	return hips + global_transform.basis.orthonormalized() * HIP_HOOK


## A damped pendulum: the lantern lags behind the hip's acceleration.
func _swing_lantern(delta: float) -> void:
	var hook := _hook_point()
	_lantern_pivot.global_position = hook
	if delta <= 0.0:
		return
	var vel := (hook - _last_hook) / delta
	var accel := (vel - _last_vel) / delta
	_last_hook = hook
	_last_vel = vel
	var push := Vector2(accel.z, -accel.x) * 0.012
	_swing_vel += (push - _swing * 40.0 - _swing_vel * 5.0) * delta
	_swing = (_swing + _swing_vel * delta).clamp(Vector2(-0.9, -0.9), Vector2(0.9, 0.9))
	_lantern_pivot.rotation = Vector3(_swing.x, global_rotation.y, _swing.y)


func _darken(node: Node) -> void:
	if node is MeshInstance3D:
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.07, 0.07, 0.065)
		iron.roughness = 0.9
		iron.metallic = 0.5
		iron.rim_enabled = true
		iron.rim = 0.5
		(node as MeshInstance3D).material_override = iron
	for child in node.get_children():
		_darken(child)


func _wisp_emitter() -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = FightFx._glow()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = material
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = 18
	p.lifetime = 1.2
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.direction = Vector3.UP
	p.spread = 35.0
	p.gravity = Vector3(0.0, 0.5, 0.0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.45
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(soul_color.r * 2.0, soul_color.g * 2.0, soul_color.b * 2.0, 0.9))
	ramp.set_color(1, Color(soul_color.r * 0.3, soul_color.g * 0.6, soul_color.b * 0.3, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
