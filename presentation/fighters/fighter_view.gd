class_name FighterView
extends Node3D
## Shows one sim fighter: its FighterModel at the interpolated position and facing, posed
## from sim state each render frame (FighterPoser), with crossfades between poses, hitstop
## shake, hit flashes and a weapon trail. Reads the sim; never writes it.

const FALLBACK_SCENE := "res://presentation/fighters/hollowed/hollowed.tscn"
const GROUND_SHADER := preload("res://presentation/fighters/shaders/fighter_ground.gdshader")
const Action := FighterState.Action

var runner: MatchRunner
var slot: int = 0
var model: FighterModel
var poser := FighterPoser.new()

var _pivot: Node3D
var _body: Node3D
var _trail: WeaponTrail
var _pose := FighterPose.new()
var _clock := 0.0
var _prev_facing := 0
var _cur_facing := 0
## Crossfade: the pose we fade from, frozen at the switch.
var _from_clip: StringName = &"Idle"
var _from_time := 0.0
var _from_root := PackedFloat32Array([0, 0, 0, 0, 0])
var _fade_left := 0.0
var _fade_len := 0.0
var _last_key := ""
var _last_clip: StringName = &"Idle"
var _last_time := 0.0
var _root := PackedFloat32Array([0, 0, 0, 0, 0])
var _flash_color := Color.WHITE
var _flash := 0.0
var _shake := 0.0
var _shake_dir := Vector3.RIGHT
var _hit_variant := 0
var _time := 0.0
## Ash dissolve: seconds since KO (-1 = not dissolving).
var _ash := -1.0
var _ash_embers: CPUParticles3D
## Soft light pool and contact shadow on the floor under the fighter.
var _ground: MeshInstance3D
## Side of the ground quad (m).
const GROUND_SIZE := 2.6

## Ash timing (design-lost-ark §1.12): 6 f freeze, then 40 f of dissolve.
const ASH_HOLD := 0.1
const ASH_TIME := 0.667

const ROOT_SHADER := preload("res://presentation/fighters/shaders/root_chains.gdshader")
const GAUGE_SHADER := preload("res://presentation/fighters/shaders/channel_gauge.gdshader")
const CHILL := Color(0.55, 0.82, 1.0)
const ASH_TINT := Color(0.5, 0.4, 0.62)
## Seconds the channel-break gauge takes to shatter.
const GAUGE_BREAK_TIME := 0.45

## Scene the current model came from (a wave slot can change fighter on SPAWN).
var scene_path := ""
## Chains of ash at the feet while rooted.
var _root_ring: MeshInstance3D
var _root_fade := 0.0
## Orange channel-break gauge over the head (bosses).
var _gauge: MeshInstance3D
var _gauge_break := -1.0
var _gauge_fill := 1.0
var _status := 0.0
var _status_color := CHILL
var _sheen := 0.0


## Builds the view for `slot` of the runner's match.
func setup(match_runner: MatchRunner, fighter_slot: int) -> void:
	runner = match_runner
	slot = fighter_slot
	name = "Fighter%d" % slot
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_body = Node3D.new()
	_body.name = "Body"
	_body.position.y = -FighterModel.HIP_HEIGHT
	_pivot.add_child(_body)
	_trail = WeaponTrail.new()
	_trail.name = "Trail"
	add_child(_trail)
	_ground = _make_ground()
	add_child(_ground)
	_root_ring = _make_flat(&"RootChains", ROOT_SHADER, 1.6)
	add_child(_root_ring)
	_gauge = _make_gauge()
	add_child(_gauge)
	_build_model()
	var f := runner.sim.fighter(slot)
	_prev_facing = f.facing
	_cur_facing = f.facing
	runner.stepped.connect(_on_stepped)
	_update(0.0)


func fighter() -> FighterState:
	return runner.sim.fighter(slot)


## The model for the slot's current fighter (sim.fighter_data[slot]); replaces the old one
## when a wave slot changed fighter.
func _build_model() -> void:
	var data := runner.sim.fighter_data[slot]
	var path := data.scene if data.scene != "" and ResourceLoader.exists(data.scene) else FALLBACK_SCENE
	if model != null:
		if path == scene_path:
			return
		_body.remove_child(model)
		model.queue_free()
	scene_path = path
	model = (load(path) as PackedScene).instantiate() as FighterModel
	_body.add_child(model)
	model.build()
	poser.model = model
	poser.idle_clip = model.idle_clip
	poser.run_clip = model.run_clip
	poser.guard_clip = model.guard_clip
	_trail.color = model.trail_color
	(_ground.material_override as ShaderMaterial).set_shader_parameter(&"glow_color", model.rim_color.lerp(Color.WHITE, 0.35))
	_last_key = ""


## Reacts to an event that involves this fighter (called by FightFx for every event).
func on_event(e: SimEvent) -> void:
	match e.type:
		SimEvent.Type.HIT:
			if e.target == slot:
				_hit_variant += 1
				var counter := (e.flags & SimEvent.FLAG_COUNTER) != 0
				flash(Color(1.0, 0.25, 0.15) if counter else Color(1.0, 0.95, 0.9), 0.85 if counter else 0.7)
				_shake = 1.0
				_shake_dir = _direction_from(e.source)
		SimEvent.Type.BLOCK:
			if e.target == slot:
				_hit_variant += 1
				flash(Color(0.55, 0.75, 1.0), 0.35)
				_shake = 0.5
				_shake_dir = _direction_from(e.source)
		SimEvent.Type.ARMOR:
			if e.target == slot:
				flash(Color(1.0, 0.6, 0.2), 0.6)
				_shake = 0.4
		SimEvent.Type.PARRY:
			if e.source == slot:
				flash(Color(1.0, 0.85, 0.5), 0.8)
		SimEvent.Type.GUARD_BREAK:
			if e.target == slot:
				flash(Color(0.6, 0.8, 1.0), 0.9)
				_shake = 1.0
		SimEvent.Type.ROUND_START:
			_reset_status()
		SimEvent.Type.SPAWN:
			if e.source == slot:
				_build_model()
				_reset_status()
				_prev_facing = fighter().facing
				_cur_facing = _prev_facing
		SimEvent.Type.DESPAWN:
			if e.source == slot:
				_reset_status()
				visible = false
		SimEvent.Type.CHANNEL_BREAK:
			if e.target == slot:
				_gauge_break = 0.0
				flash(Color(1.0, 0.55, 0.15), 1.0)
				_shake = 1.0


func _reset_status() -> void:
	_trail.clear()
	_ash = -1.0
	model.set_dissolve(0.0)
	if _ash_embers != null:
		_ash_embers.emitting = false
	_gauge_break = -1.0
	_root_fade = 0.0
	_status = 0.0
	model.set_status(_status_color, 0.0)
	_sheen = 0.0
	model.set_sheen(0.0)


## Burns the model away into ash with rising embers (Hollowed deaths).
func dissolve_to_ash() -> void:
	_ash = 0.0
	if _ash_embers == null:
		_ash_embers = _make_ash_embers()
		add_child(_ash_embers)
	_ash_embers.emitting = false


func flash(color: Color, amount: float) -> void:
	_flash_color = color
	_flash = maxf(_flash, amount)


func _direction_from(source: int) -> Vector3:
	if source < 0 or source >= runner.sim.slot_count():
		return Vector3.RIGHT
	var from := Fx.to_vec3(runner.sim.fighter(source).pos)
	var to := Fx.to_vec3(fighter().pos)
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.RIGHT


func _on_stepped(_events: Array[SimEvent]) -> void:
	_prev_facing = _cur_facing
	_cur_facing = fighter().facing


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	if runner == null or runner.sim == null:
		return
	_time += delta
	var sim := runner.sim
	var f := fighter()
	visible = f.active
	if not f.active:
		return
	var frozen := f.hitstop > 0 or sim.state.freeze > 0 or runner.paused
	var sub := 0.0 if frozen else clampf(runner.alpha(), 0.0, 1.0)
	if not frozen:
		_clock += delta
	position = runner.fighter_position(slot)
	var a := Fx.angle_to_rad(_prev_facing)
	var b := Fx.angle_to_rad(_cur_facing)
	rotation = Vector3(0.0, lerp_angle(a, b, sub), 0.0)
	poser.evaluate(sim, f, _pose, sub, _clock, _hit_variant)
	_apply_pose(delta, frozen)
	_apply_shake(delta, f)
	if not frozen:
		_flash = move_toward(_flash, 0.0, delta * 6.0)
	# Blue pulse while the fighter's move can be ⚡Countered (design-lost-ark §1.9).
	if sim.in_counter_window(f):
		flash(Color(0.3, 0.6, 1.0), 0.45 + 0.25 * absf(sin(_time * 14.0)))
	model.set_flash(_flash_color, _flash)
	_update_ash(delta)
	_update_ground()
	_update_statuses(f, delta)
	_trail.feed(model.trail_segment(), _pose.trail and not frozen, 0.0 if frozen else delta)
	model.update_extras(sim, f, delta)


func _apply_pose(delta: float, frozen: bool) -> void:
	var target := PackedFloat32Array([_pose.pitch, _pose.roll, _pose.yaw, _pose.lift, _pose.forward])
	if _pose.key != _last_key:
		_from_clip = _last_clip
		_from_time = _last_time
		_from_root = _root.duplicate()
		_fade_len = maxf(0.001, _pose.fade)
		_fade_left = _pose.fade
		_last_key = _pose.key
	if not frozen:
		_fade_left = maxf(0.0, _fade_left - delta)
	var w := _fade_left / _fade_len if _fade_left > 0.0 else 0.0
	w = w * w * (3.0 - 2.0 * w)
	model.pose(_pose.clip, _pose.time, _from_clip, _from_time, w)
	_last_clip = _pose.clip
	_last_time = _pose.time
	for i in 5:
		_root[i] = lerpf(target[i], _from_root[i], w) if i != 2 else lerp_angle(target[i], _from_root[i], w)
	_pivot.position = Vector3(0.0, FighterModel.HIP_HEIGHT + _root[3], _root[4])
	_pivot.rotation = Vector3(_root[0], _root[2], _root[1])


func _apply_shake(delta: float, f: FighterState) -> void:
	var offset := Vector3.ZERO
	if f.hitstop > 0 and _shake > 0.0:
		var local := global_transform.basis.inverse() * _shake_dir
		offset += local * sin(_time * 95.0) * 0.06 * _shake
	elif _shake > 0.0:
		_shake = move_toward(_shake, 0.0, delta * 6.0)
	if _pose.shake > 0.0:
		offset += Vector3(sin(_time * 71.0), 0.0, cos(_time * 83.0)) * 0.015 * _pose.shake
	_body.position = Vector3(offset.x, -FighterModel.HIP_HEIGHT + offset.y, offset.z)

func _update_ash(delta: float) -> void:
	if _ash < 0.0:
		return
	_ash += delta
	var t := clampf((_ash - ASH_HOLD) / ASH_TIME, 0.0, 1.0)
	model.set_dissolve(t)
	if _ash_embers != null:
		_ash_embers.emitting = t > 0.0 and t < 0.95
		_ash_embers.global_position = global_position + Vector3.UP * lerpf(1.4, 0.3, t)


func _update_ground() -> void:
	var p := global_position
	_ground.global_position = Vector3(p.x, 0.03, p.z)
	var lift := clampf(1.0 - p.y / 4.0, 0.35, 1.0)
	var gone := clampf((_ash - ASH_HOLD) / ASH_TIME, 0.0, 1.0) if _ash >= 0.0 else 0.0
	(_ground.material_override as ShaderMaterial).set_shader_parameter(&"fade", lift * (1.0 - gone))


## Root chains, debuff tint and the channel-break gauge, from sim state.
func _update_statuses(f: FighterState, delta: float) -> void:
	var p := global_position
	_root_fade = move_toward(_root_fade, 1.0 if f.rooted > 0 and not f.ko else 0.0, delta * 6.0)
	_root_ring.visible = _root_fade > 0.01
	if _root_ring.visible:
		_root_ring.global_position = Vector3(p.x, 0.04, p.z)
		(_root_ring.material_override as ShaderMaterial).set_shader_parameter(&"fade", _root_fade)
	var want := 0.0
	var armored := false
	for buff in f.buffs:
		if buff.armor != 0 or buff.damage_taken_percent < 0:
			armored = true
		if buff.source == Sim.VICTIM_BUFF:
			_status_color = CHILL if buff.speed_bonus_percent < 0 else ASH_TINT
			want = 0.75 if buff.speed_bonus_percent < 0 else 0.5
	_status = move_toward(_status, want if not f.ko else 0.0, delta * 4.0)
	model.set_status(_status_color, _status * (0.85 + 0.15 * sin(_time * 5.0)))
	_sheen = move_toward(_sheen, 0.8 if armored and not f.ko else 0.0, delta * 4.0)
	model.set_sheen(_sheen)
	var material := _gauge.material_override as ShaderMaterial
	if _gauge_break >= 0.0:
		_gauge_break += delta
		var t := clampf(_gauge_break / GAUGE_BREAK_TIME, 0.0, 1.0)
		material.set_shader_parameter(&"fill", 0.0)
		material.set_shader_parameter(&"broken", maxf(0.001, t))
		_gauge.visible = t < 1.0
		if t >= 1.0:
			_gauge_break = -1.0
	elif f.channel_max > 0 and f.channel > 0:
		_gauge.visible = true
		_gauge_fill = float(f.channel) / float(f.channel_max)
		material.set_shader_parameter(&"fill", _gauge_fill)
		material.set_shader_parameter(&"broken", 0.0)
	else:
		_gauge.visible = false
	if _gauge.visible:
		_gauge.global_position = p + Vector3.UP * (runner.sim.fighter_data[slot].height + 0.75)


## True while the orange channel-break gauge shows (or is shattering).
func gauge_shown() -> bool:
	return _gauge.visible


func gauge_fill() -> float:
	return _gauge_fill


func _make_flat(node_name: StringName, shader: Shader, size: float) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var flat := MeshInstance3D.new()
	flat.name = node_name
	flat.mesh = plane
	flat.material_override = material
	flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flat.top_level = true
	flat.visible = false
	return flat


func _make_gauge() -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = GAUGE_SHADER
	material.render_priority = 20
	var quad := QuadMesh.new()
	quad.size = Vector2(1.7, 0.16)
	var gauge := MeshInstance3D.new()
	gauge.name = "ChannelGauge"
	gauge.mesh = quad
	gauge.material_override = material
	gauge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gauge.top_level = true
	gauge.visible = false
	return gauge


func _make_ground() -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.render_priority = -1
	var quad := PlaneMesh.new()
	quad.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = quad
	ground.material_override = material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.top_level = true
	return ground


func _make_ash_embers() -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = FightFx._glow()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	quad.material = material
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = 60
	p.lifetime = 1.4
	p.local_coords = false
	p.top_level = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.35, 0.3, 0.35)
	p.direction = Vector3.UP
	p.spread = 30.0
	p.gravity = Vector3(0.0, 1.5, 0.0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(3.0, 1.2, 0.3, 1.0))
	ramp.set_color(1, Color(0.3, 0.28, 0.26, 0.0))
	p.color_ramp = ramp
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
