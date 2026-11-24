class_name FightFx
extends Node3D
## Turns the sim event stream into feel: hit sparks and flashes, parry/burst rings, dust,
## camera shake, sounds, a super-flash dim, and visuals for sim effects (projectiles,
## eruptions, pillars). Presentation only: it reads events and state, never writes them.

const SPARK_POOL := 16
const FLASH_POOL := 10
const RING_POOL := 6
const EffectVisualScript := preload("res://presentation/fight/effect_visual.gd")

var runner: MatchRunner
var camera: FightCamera
var views: Array[FighterView] = []

var _sparks: Array[CPUParticles3D] = []
var _spark_next := 0
var _flashes: Array[MeshInstance3D] = []
var _flash_ages: PackedFloat32Array = PackedFloat32Array()
var _flash_lives: PackedFloat32Array = PackedFloat32Array()
var _flash_sizes: PackedFloat32Array = PackedFloat32Array()
var _flash_next := 0
var _rings: Array[MeshInstance3D] = []
var _ring_ages: PackedFloat32Array = PackedFloat32Array()
var _ring_sizes: PackedFloat32Array = PackedFloat32Array()
var _ring_next := 0
var _effects: Dictionary[int, Node3D] = {}
var _overlay: ColorRect
var _overlay_flash := 0.0
var _overlay_color := Color.WHITE

static var _glow_texture: GradientTexture2D
static var _ring_texture: GradientTexture2D


func setup(match_runner: MatchRunner, fighter_views: Array[FighterView], fight_camera: FightCamera) -> void:
	runner = match_runner
	views = fighter_views
	camera = fight_camera
	for i in SPARK_POOL:
		_sparks.append(_make_sparks())
	for i in FLASH_POOL:
		_flashes.append(_make_sprite(_glow(), true))
	_flash_ages.resize(FLASH_POOL)
	_flash_lives.resize(FLASH_POOL)
	_flash_sizes.resize(FLASH_POOL)
	_flash_ages.fill(99.0)
	_flash_lives.fill(0.1)
	for i in RING_POOL:
		_rings.append(_make_sprite(_ring(), false))
	_ring_ages.resize(RING_POOL)
	_ring_sizes.resize(RING_POOL)
	_ring_ages.fill(99.0)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(0, 0, 0, 0)
	layer.add_child(_overlay)
	runner.event_emitted.connect(_on_event)


func _process(delta: float) -> void:
	if runner == null or runner.sim == null:
		return
	_update_sprites(delta)
	_update_effects()
	_update_overlay(delta)


# --- Events ------------------------------------------------------------------------------

func _on_event(e: SimEvent) -> void:
	for view in views:
		view.on_event(e)
	match e.type:
		SimEvent.Type.HIT:
			_on_hit(e)
		SimEvent.Type.BLOCK:
			var at := _contact_point(e)
			burst(at, Color(0.6, 0.8, 1.0), 10, 3.5, _away(e))
			flash_at(at, Color(0.55, 0.75, 1.0), 0.6, 0.08)
			_shake(0.12)
			_play(e.cue, &"block")
		SimEvent.Type.PARRY:
			var at := _contact_point(e)
			flash_at(at, Color(1.0, 0.85, 0.45), 1.1, 0.14)
			ring_at(at, Color(1.0, 0.8, 0.4), 2.2)
			burst(at, Color(1.0, 0.85, 0.5), 22, 5.0, Vector3.ZERO)
			_shake(0.3)
			_overlay_pulse(Color(1.0, 0.9, 0.7), 0.12)
			Sound.play(&"parry")
		SimEvent.Type.GUARD_BREAK:
			var at := _body_point(e.target)
			burst(at, Color(0.7, 0.85, 1.0), 30, 6.0, Vector3.ZERO)
			ring_at(at, Color(0.6, 0.8, 1.0), 2.0)
			_shake(0.5)
			Sound.play(&"guard_break")
		SimEvent.Type.ARMOR:
			var at := _contact_point(e)
			flash_at(at, Color(1.0, 0.55, 0.2), 1.0, 0.1)
			burst(at, Color(1.0, 0.6, 0.25), 12, 3.0, _away(e))
			_shake(0.15)
			Sound.play(&"armor")
		SimEvent.Type.LAUNCH:
			Sound.play(&"launch")
		SimEvent.Type.WALL_SPLAT:
			var at := _body_point(e.target)
			burst(at, Color(0.55, 0.52, 0.5), 24, 3.0, Vector3.ZERO)
			ring_at(at, Color(0.8, 0.7, 0.6), 1.6, true)
			_shake(0.55)
			Sound.play(&"wall_splat")
		SimEvent.Type.KNOCKDOWN:
			var at := _ground_point(e.target)
			ring_at(at, Color(0.5, 0.48, 0.45), 1.8)
			burst(at + Vector3.UP * 0.1, Color(0.45, 0.43, 0.42), 14, 1.8, Vector3.UP)
			_shake(0.2)
			Sound.play(&"body_fall")
		SimEvent.Type.MOVE_START:
			_on_move_start(e)
		SimEvent.Type.SUPER_FLASH:
			_on_super_flash(e)
		SimEvent.Type.BURST:
			var at := _body_point(e.source)
			ring_at(at, Color(0.75, 0.95, 1.0), 4.5)
			flash_at(at, Color(0.8, 0.95, 1.0), 1.5, 0.2)
			_shake(0.4)
			Sound.play(&"soul_burst")
		SimEvent.Type.DODGE:
			Sound.play(&"dodge", -4.0)
		SimEvent.Type.PERFECT_DODGE:
			_overlay_pulse(Color(0.55, 0.7, 1.0), 0.2)
			Sound.play(&"perfect_dodge")
		SimEvent.Type.AIR_TECH, SimEvent.Type.TECH_ROLL:
			Sound.play(&"dodge")
		SimEvent.Type.JUMP:
			Sound.play(&"jump", -6.0)
		SimEvent.Type.LAND:
			Sound.play(&"land", -6.0)
		SimEvent.Type.GRAB:
			Sound.play(&"grab")
			_shake(0.15)
		SimEvent.Type.GRAB_TECH:
			flash_at(_contact_point(e), Color(1, 1, 1), 1.0, 0.1)
			Sound.play(&"block")
		SimEvent.Type.THROW_RELEASE:
			Sound.play(&"swing_heavy")
		SimEvent.Type.BUFF:
			var at := _body_point(e.source)
			flash_at(at, _accent(e.source), 0.9, 0.2)
			burst(at, _accent(e.source), 26, 3.0, Vector3.UP)
			_play(e.cue, &"")
		SimEvent.Type.KO:
			var at := _body_point(e.target)
			flash_at(at, Color(1.0, 0.9, 0.8), 1.8, 0.3)
			_shake(0.9)
			_overlay_pulse(Color(1.0, 1.0, 1.0), 0.3)
			Sound.play(&"ko")
		SimEvent.Type.EFFECT_SPAWN:
			_spawn_effect(e)
			_play(e.cue, &"")
		SimEvent.Type.EFFECT_ACTIVE:
			var node: Node3D = _effects.get(e.amount)
			if node != null:
				node.call(&"activate")
				_play(StringName(String(e.cue) + "_active") if e.cue != &"" else &"", &"")
		SimEvent.Type.EFFECT_END, SimEvent.Type.EFFECT_DESTROYED:
			var node: Node3D = _effects.get(e.amount)
			if node != null:
				_effects.erase(e.amount)
				node.call(&"finish", e.type == SimEvent.Type.EFFECT_DESTROYED)
				if e.type == SimEvent.Type.EFFECT_DESTROYED:
					burst(Fx.to_vec3(e.position), _accent(e.source), 12, 2.5, Vector3.ZERO)
		SimEvent.Type.HAZARD_ACTIVE:
			_shake(0.2)
			_play(e.cue, &"")
		SimEvent.Type.ROUND_START:
			for id: int in _effects.keys():
				_effects[id].queue_free()
			_effects.clear()


func _on_hit(e: SimEvent) -> void:
	var at := _contact_point(e)
	var strength := clampf(float(e.hitstop - 3) / 11.0, 0.0, 1.0)
	var counter := (e.flags & SimEvent.FLAG_COUNTER) != 0
	var super_hit := (e.flags & SimEvent.FLAG_SUPER) != 0
	var color := _spark_color(e.source)
	burst(at, color, 12 + int(30.0 * strength), 3.0 + 6.0 * strength, _away(e))
	flash_at(at, color.lerp(Color.WHITE, 0.4), 0.5 + 0.8 * strength, 0.07 + 0.06 * strength)
	if counter:
		ring_at(at, Color(1.0, 0.3, 0.2), 1.6)
		_overlay_pulse(Color(1.0, 0.35, 0.25), 0.1)
		Sound.play(&"hit_counter")
	_shake(0.12 + 0.4 * strength + (0.2 if counter else 0.0) + (0.25 if super_hit else 0.0))
	if not _play(e.cue, &""):
		Sound.play(&"hit_heavy" if strength > 0.35 else &"hit_light")
	if strength > 0.35:
		Sound.play(&"hit_flesh", -3.0)


func _on_move_start(e: SimEvent) -> void:
	if e.source < 0:
		return
	var data := runner.sim.fighter_data[e.source]
	if e.amount < 0 or e.amount >= data.moves.size():
		return
	var move := data.moves[e.amount]
	if _play(move.cue, &""):
		return
	match move.kind:
		MoveData.Kind.LIGHT, MoveData.Kind.AIR_LIGHT, MoveData.Kind.GETUP_ATTACK:
			Sound.play(&"swing_light", -2.0)
		MoveData.Kind.HEAVY, MoveData.Kind.AIR_HEAVY:
			Sound.play(&"swing_heavy")
		MoveData.Kind.GRAB:
			Sound.play(&"swing_light", -6.0)


func _on_super_flash(e: SimEvent) -> void:
	_overlay_color = Color(0.0, 0.0, 0.02)
	_overlay_flash = 0.55
	Sound.play(&"super_flash")
	var at := _body_point(e.source)
	flash_at(at, _accent(e.source), 1.4, float(e.amount) / 60.0)
	if camera != null and e.source >= 0:
		var f := runner.sim.fighter(e.source)
		var face := Fx.angle_to_rad(f.facing)
		var ahead := Vector3(sin(face), 0.0, cos(face))
		var side := Vector3(ahead.z, 0.0, -ahead.x)
		var base := runner.fighter_position(e.source)
		camera.cinematic(base + ahead * 2.6 + side * 1.2 + Vector3.UP * 1.3, base + Vector3.UP * 1.2, 0.9)


# --- Helpers -----------------------------------------------------------------------------

## Plays cue `id` if it exists, else `fallback` (if not empty). True when something played.
func _play(id: StringName, fallback: StringName) -> bool:
	if id != &"" and Sound.has_cue(id):
		Sound.play(id)
		return true
	if fallback != &"" and Sound.has_cue(fallback):
		Sound.play(fallback)
		return true
	return false


func _shake(amount: float) -> void:
	if camera != null:
		camera.add_trauma(amount)


func _overlay_pulse(color: Color, amount: float) -> void:
	_overlay_color = color
	_overlay_flash = maxf(_overlay_flash, amount)


func _update_overlay(delta: float) -> void:
	var freeze := runner.sim.state.freeze > 0
	if freeze:
		_overlay.color = Color(0.0, 0.0, 0.02, 0.5)
		return
	_overlay_flash = move_toward(_overlay_flash, 0.0, delta * 2.5)
	_overlay.color = Color(_overlay_color, _overlay_flash)


func _view(slot: int) -> FighterView:
	for view in views:
		if view.slot == slot:
			return view
	return null


func _spark_color(slot: int) -> Color:
	var view := _view(slot)
	return view.model.spark_color if view != null else Color(1.0, 0.7, 0.4)


func _accent(slot: int) -> Color:
	var view := _view(slot)
	return view.model.accent_color if view != null else Color(1.0, 0.5, 0.2)


func _body_point(slot: int) -> Vector3:
	if slot < 0 or slot >= runner.sim.slot_count():
		return Vector3.UP
	var view := _view(slot)
	if view != null:
		return view.model.bone_position(&"chest")
	return runner.fighter_position(slot) + Vector3.UP * 1.1


func _ground_point(slot: int) -> Vector3:
	if slot < 0 or slot >= runner.sim.slot_count():
		return Vector3.ZERO
	var p := runner.fighter_position(slot)
	return Vector3(p.x, 0.05, p.z)


## Where a hit or block lands: the event position when it carries a height, else on the
## victim's body toward the attacker.
func _contact_point(e: SimEvent) -> Vector3:
	var pos := Fx.to_vec3(e.position)
	if pos.y > 0.2:
		return pos
	var body := _body_point(e.target)
	return body - _away(e) * 0.3


## Direction from attacker to victim (horizontal), or zero.
func _away(e: SimEvent) -> Vector3:
	if e.source < 0 or e.target < 0:
		return Vector3.ZERO
	var a := runner.fighter_position(e.source)
	var b := runner.fighter_position(e.target)
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.ZERO


## Burst of `amount` glowing sparks flying out at `speed` m/s (biased along `direction`).
func burst(at: Vector3, color: Color, amount: int, speed: float, direction: Vector3) -> void:
	var p := _sparks[_spark_next]
	_spark_next = (_spark_next + 1) % _sparks.size()
	p.global_position = at
	p.amount = clampi(amount, 1, 64)
	p.direction = (direction + Vector3.UP * 0.35).normalized() if direction != Vector3.ZERO else Vector3.UP
	p.spread = 70.0 if direction != Vector3.ZERO else 180.0
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	var ramp := Gradient.new()
	var hot := Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 1.0)
	ramp.set_color(0, hot)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	p.restart()
	p.emitting = true


## A bright billboard flash that pops and fades over `life` seconds.
func flash_at(at: Vector3, color: Color, size: float, life: float) -> void:
	var i := _flash_next
	_flash_next = (_flash_next + 1) % _flashes.size()
	var sprite := _flashes[i]
	sprite.global_position = at
	sprite.visible = true
	(sprite.material_override as StandardMaterial3D).albedo_color = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 1.0)
	_flash_ages[i] = 0.0
	_flash_lives[i] = maxf(0.03, life)
	_flash_sizes[i] = size


## An expanding ring; flat on the ground unless `upright` (wall splats).
func ring_at(at: Vector3, color: Color, size: float, upright: bool = false) -> void:
	var i := _ring_next
	_ring_next = (_ring_next + 1) % _rings.size()
	var ring := _rings[i]
	ring.global_position = at
	ring.rotation = Vector3(0.0 if upright else -PI / 2.0, 0.0, 0.0)
	if upright and camera != null:
		ring.look_at(camera.global_position, Vector3.UP)
	ring.visible = true
	(ring.material_override as StandardMaterial3D).albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 1.0)
	_ring_ages[i] = 0.0
	_ring_sizes[i] = size


func _update_sprites(delta: float) -> void:
	for i in _flashes.size():
		if _flash_ages[i] > _flash_lives[i]:
			_flashes[i].visible = false
			continue
		_flash_ages[i] += delta
		var t := clampf(_flash_ages[i] / _flash_lives[i], 0.0, 1.0)
		var s := _flash_sizes[i] * (0.35 + 0.65 * sqrt(t))
		_flashes[i].scale = Vector3.ONE * s
		var m := _flashes[i].material_override as StandardMaterial3D
		m.albedo_color.a = (1.0 - t) * (1.0 - t)
	for i in _rings.size():
		if _ring_ages[i] > 0.35:
			_rings[i].visible = false
			continue
		_ring_ages[i] += delta
		var t := clampf(_ring_ages[i] / 0.35, 0.0, 1.0)
		_rings[i].scale = Vector3.ONE * _ring_sizes[i] * (0.2 + t)
		var m := _rings[i].material_override as StandardMaterial3D
		m.albedo_color.a = (1.0 - t) * (1.0 - t)


func _spawn_effect(e: SimEvent) -> void:
	var sim := runner.sim
	var state: EffectState = null
	for candidate in sim.state.effects:
		if candidate.id == e.amount:
			state = candidate
			break
	if state == null:
		return
	var data := sim.effect_data(state)
	var node: Node3D
	if data.scene != "" and ResourceLoader.exists(data.scene):
		node = (load(data.scene) as PackedScene).instantiate()
	else:
		node = EffectVisualScript.new()
	add_child(node)
	if node.has_method(&"setup"):
		node.call(&"setup", data, _accent(state.owner))
	node.global_position = Fx.to_vec3(state.pos)
	_effects[state.id] = node


func _update_effects() -> void:
	if _effects.is_empty():
		return
	var alpha := 0.0 if runner.sim.state.freeze > 0 or runner.paused else runner.alpha()
	for state in runner.sim.state.effects:
		var node: Node3D = _effects.get(state.id)
		if node == null:
			continue
		var data := runner.sim.effect_data(state)
		var moving := state.age > data.delay
		var pos := Fx.to_vec3(state.pos) + (Fx.to_vec3(state.vel) * alpha if moving else Vector3.ZERO)
		node.global_position = pos
		node.rotation.y = Fx.angle_to_rad(state.facing)
		if node.has_method(&"set_radius"):
			node.call(&"set_radius", Fx.to_m(state.radius))


func _make_sparks() -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = _glow()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = material
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.lifetime = 0.45
	p.amount = 24
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.damping_min = 2.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.1))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _make_sprite(texture: Texture2D, billboard: bool) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.no_depth_test = billboard
	if billboard:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var sprite := MeshInstance3D.new()
	sprite.mesh = quad
	sprite.material_override = material
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.visible = false
	sprite.top_level = true
	add_child(sprite)
	return sprite


static func _glow() -> GradientTexture2D:
	if _glow_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.25, Color(1, 1, 1, 0.55))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = g
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(0.5, 0.0)
		_glow_texture.width = 64
		_glow_texture.height = 64
	return _glow_texture


static func _ring() -> GradientTexture2D:
	if _ring_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.add_point(0.72, Color(1, 1, 1, 0.0))
		g.add_point(0.86, Color(1, 1, 1, 1.0))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		_ring_texture = GradientTexture2D.new()
		_ring_texture.gradient = g
		_ring_texture.fill = GradientTexture2D.FILL_RADIAL
		_ring_texture.fill_from = Vector2(0.5, 0.5)
		_ring_texture.fill_to = Vector2(0.5, 0.0)
		_ring_texture.width = 128
		_ring_texture.height = 128
	return _ring_texture
