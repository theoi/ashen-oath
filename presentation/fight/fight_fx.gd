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
const SLOW_MOTION_TICKS := 24
const DESATURATE_SHADER := preload("res://presentation/fight/shaders/screen_desaturate.gdshader")

## Floating damage numbers and floor decals (telegraphs, counter rings, target circles).
var numbers: DamageNumbers
var decals: GroundDecals

var _overlay: ColorRect
var _overlay_flash := 0.0
var _overlay_color := Color.WHITE
var _grey: ColorRect
var _bars: Array[ColorRect] = []
var _letterbox_left := 0.0
var _letterbox := 0.0

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
	_grey = ColorRect.new()
	_grey.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grey_material := ShaderMaterial.new()
	grey_material.shader = DESATURATE_SHADER
	_grey.material = grey_material
	_grey.visible = false
	layer.add_child(_grey)
	layer.move_child(_grey, 0)
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.0, 0.0, 0.0, 1.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		layer.add_child(bar)
		_bars.append(bar)
	numbers = DamageNumbers.new()
	numbers.name = "DamageNumbers"
	add_child(numbers)
	decals = GroundDecals.new()
	decals.name = "GroundDecals"
	add_child(decals)
	var local := camera.focus_slot if camera != null else 0
	numbers.local_slot = local
	decals.setup(runner, local)
	runner.event_emitted.connect(_on_event)


func _process(delta: float) -> void:
	if runner == null or runner.sim == null:
		return
	_update_sprites(delta)
	_update_effects()
	_update_overlay(delta)
	_update_letterbox(delta)


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
			_shake(0.02, 6)
			_play(e.cue, &"block")
		SimEvent.Type.PARRY:
			var at := _contact_point(e)
			flash_at(at, Color(1.0, 0.85, 0.45), 1.1, 0.14)
			ring_at(at, Color(1.0, 0.8, 0.4), 2.2)
			burst(at, Color(1.0, 0.85, 0.5), 22, 5.0, Vector3.ZERO)
			_shake(0.05, 10)
			_overlay_pulse(Color(1.0, 0.9, 0.7), 0.12)
			Sound.play(&"parry")
		SimEvent.Type.GUARD_BREAK:
			var at := _body_point(e.target)
			burst(at, Color(0.7, 0.85, 1.0), 30, 6.0, Vector3.ZERO)
			ring_at(at, Color(0.6, 0.8, 1.0), 2.0)
			_shake(0.08, 14)
			Sound.play(&"guard_break")
		SimEvent.Type.ARMOR:
			# Armored hits: grey sparks instead of the flash, and a softer shake.
			var at := _contact_point(e)
			var w := weight_of(e)
			burst(at, Color(0.62, 0.64, 0.68), 12, 3.0, _away(e))
			_shake(WEIGHT_SHAKE[w].x * 0.5, WEIGHT_SHAKE[w].y)
			numbers.show_hit(at, e.amount, w, false, _local(e.target), true, "")
			Sound.play(&"armor")
		SimEvent.Type.STANCE_TRIGGER:
			# A stance catching a hit (Bulwark): a shatter flare with the Heavy flash.
			var at := _contact_point(e)
			impact_flash(at, HEAVY)
			ring_at(at, _accent(e.source), 2.4, true)
			burst(at, _accent(e.source), 34, 6.0, Vector3.ZERO)
			_shake(WEIGHT_SHAKE[HEAVY].x, WEIGHT_SHAKE[HEAVY].y)
			if _local(e.source):
				_rumble(HEAVY)
			Sound.play(&"parry")
		SimEvent.Type.LAUNCH:
			Sound.play(&"launch")
		SimEvent.Type.WALL_SPLAT:
			var at := _body_point(e.target)
			burst(at, Color(0.55, 0.52, 0.5), 24, 3.0, Vector3.ZERO)
			ring_at(at, Color(0.8, 0.7, 0.6), 1.6, true)
			_shake(0.08, 14)
			Sound.play(&"wall_splat")
		SimEvent.Type.KNOCKDOWN:
			var at := _ground_point(e.target)
			ring_at(at, Color(0.5, 0.48, 0.45), 1.8)
			burst(at + Vector3.UP * 0.1, Color(0.45, 0.43, 0.42), 14, 1.8, Vector3.UP)
			_shake(0.03, 8)
			Sound.play(&"body_fall")
		SimEvent.Type.MOVE_START:
			_on_move_start(e)
		SimEvent.Type.SUPER_FLASH:
			_on_super_flash(e)
		SimEvent.Type.BURST:
			var at := _body_point(e.source)
			ring_at(at, Color(0.75, 0.95, 1.0), 4.5)
			flash_at(at, Color(0.8, 0.95, 1.0), 1.5, 0.2)
			_shake(0.06, 12)
			Sound.play(&"soul_burst")
		SimEvent.Type.DODGE:
			Sound.play(&"dodge", -4.0)
		SimEvent.Type.PERFECT_DODGE:
			_overlay_pulse(Color(0.55, 0.7, 1.0), 0.2)
			runner.slow_motion(0.5, 12)
			Sound.play(&"perfect_dodge")
		SimEvent.Type.AIR_TECH, SimEvent.Type.TECH_ROLL:
			Sound.play(&"dodge")
		SimEvent.Type.JUMP:
			Sound.play(&"jump", -6.0)
		SimEvent.Type.LAND:
			Sound.play(&"land", -6.0)
		SimEvent.Type.GRAB:
			Sound.play(&"grab")
			_shake(0.02, 6)
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
			var dead := _view(e.target)
			if dead != null and dead.model.ash_on_death:
				dead.dissolve_to_ash()
			flash_at(at, Color(1.0, 0.9, 0.8), 1.8, 0.3)
			_shake(0.12, 20)
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
			_shake(0.03, 8)
			_play(e.cue, &"")
		SimEvent.Type.ROUND_START:
			for id: int in _effects.keys():
				_effects[id].queue_free()
			_effects.clear()


func _on_hit(e: SimEvent) -> void:
	var at := _contact_point(e)
	var weight := weight_of(e)
	var strength := maxf(0.0, float(weight - 1) / 4.0)
	var counter := (e.flags & SimEvent.FLAG_COUNTER) != 0
	var super_hit := (e.flags & SimEvent.FLAG_SUPER) != 0
	var color := _spark_color(e.source)
	if weight == TICK:
		burst(at, color, 8, 2.5, _away(e))
	else:
		burst(at, color, 12 + int(30.0 * strength), 3.0 + 6.0 * strength, _away(e))
		impact_flash(at, weight)
	if counter:
		ring_at(at, Color(1.0, 0.3, 0.2), 1.6)
		_overlay_pulse(Color(1.0, 0.35, 0.25), 0.1)
		Sound.play(&"hit_counter")
	var shake := WEIGHT_SHAKE[maxi(weight, LIGHT) if counter else weight]
	_shake(shake.x, shake.y)
	if weight >= MASSIVE:
		_punch(0.3)
		ring_at(_ground_point(e.target), color, 3.0)
		if super_hit:
			runner.slow_motion(Feel.slow_motion(), SLOW_MOTION_TICKS)
	if _local(e.source) or _local(e.target):
		_rumble(weight)
	numbers.show_hit(at, e.amount, weight, counter, _local(e.target), false, "%d>%d:%s" % [e.source, e.target, e.id])
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


## Awakening camera moment (design-lost-ark §1.6): the world dims and desaturates, letterbox
## bars slide in, the camera swoops low and close on the caster for the freeze, then hands
## back to gameplay framing over ~20 f.
func _on_super_flash(e: SimEvent) -> void:
	var seconds := float(e.amount) / 60.0
	_overlay_color = Color(0.0, 0.0, 0.02)
	_overlay_flash = 0.55
	_letterbox_left = seconds + 0.35
	Sound.play(&"super_flash")
	var at := _body_point(e.source)
	flash_at(at, _accent(e.source), 1.4, seconds)
	ring_at(_ground_point(e.source), _accent(e.source), 3.5)
	if _local(e.source):
		_rumble(MASSIVE, 0.6)
	if camera != null and e.source >= 0:
		var f := runner.sim.fighter(e.source)
		var face := Fx.angle_to_rad(f.facing)
		var ahead := Vector3(sin(face), 0.0, cos(face))
		var side := Vector3(ahead.z, 0.0, -ahead.x)
		var base := runner.fighter_position(e.source)
		camera.cinematic(base + ahead * 2.4 + side * 1.0 + Vector3.UP * 0.7, base + Vector3.UP * 1.1, seconds + 0.33)


# --- Impact by weight (design-lost-ark §1.12) -----------------------------------------------

## Per weight class, indexed 0 TICK, 1 BASIC .. 5 MASSIVE:
## shake (amplitude m, decay frames), impact flash (share of the screen, life frames) and
## rumble (weak, strong, seconds). Ticks and basic hits do not shake; ticks do not flash.
const WEIGHT_SHAKE: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2(0.02, 4), Vector2(0.04, 8),
		Vector2(0.08, 14), Vector2(0.15, 20)]
const WEIGHT_FLASH: Array[Vector2] = [Vector2.ZERO, Vector2(0.01, 5), Vector2(0.02, 6), Vector2(0.03, 7),
		Vector2(0.06, 9), Vector2(0.25, 16)]
const WEIGHT_RUMBLE: Array[Vector3] = [Vector3(0.25, 0.0, 0.03), Vector3(0.3, 0.0, 0.04), Vector3(0.45, 0.0, 0.07),
		Vector3(0.45, 0.45, 0.12), Vector3(0.3, 0.8, 0.18), Vector3(0.5, 1.0, 0.3)]
const TICK := 0
const LIGHT := 2
const HEAVY := 4
const MASSIVE := 5


## Weight class 0..5 (TICK, BASIC .. MASSIVE) of a HIT/ARMOR event: SimEvent.weight
## (HitData.Weight) when the hit has one, else derived from the hitstop it applied (old kits).
static func weight_of(e: SimEvent) -> int:
	if e.weight == HitData.Weight.TICK:
		return TICK
	if e.weight > 0:
		return clampi(e.weight, 1, 5)
	if e.hitstop <= 3:
		return 1
	if e.hitstop <= 5:
		return 2
	if e.hitstop <= 7:
		return 3
	if e.hitstop <= 10:
		return 4
	return 5


## Additive white flash at the contact covering the weight class's share of the screen
## (design-lost-ark §1.12), scaled by Feel.flash_intensity.
func impact_flash(at: Vector3, weight: int) -> void:
	var tier := WEIGHT_FLASH[clampi(weight, 0, 5)]
	var share := tier.x * Feel.flash_intensity()
	if share <= 0.0:
		return
	flash_at(at, Color(1.0, 0.97, 0.9), flash_size(at, share), tier.y / 60.0)


## Quad side (m) at `at` whose soft glow covers `share` of the screen.
func flash_size(at: Vector3, share: float) -> float:
	var view_h := 2.0
	var aspect := 16.0 / 9.0
	if camera != null and camera.is_inside_tree():
		var d := maxf(1.0, camera.global_position.distance_to(at))
		view_h = 2.0 * d * tan(deg_to_rad(camera.fov) * 0.5)
		aspect = get_viewport().get_visible_rect().size.aspect()
	# The radial glow lights roughly 40% of its quad's area.
	return sqrt(share * view_h * view_h * aspect / 0.4)


func _rumble(weight: int, scale: float = 1.0) -> void:
	var r := WEIGHT_RUMBLE[clampi(weight, 0, 5)] * Vector3(scale, scale, 1.0)
	var k := Feel.rumble_scale()
	if k <= 0.0:
		return
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, clampf(r.x * k, 0.0, 1.0), clampf(r.y * k, 0.0, 1.0), r.z)


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


func _shake(amplitude: float, decay_frames: float) -> void:
	if camera != null:
		camera.shake(amplitude, decay_frames)


func _punch(amount: float) -> void:
	if camera != null:
		camera.punch(amount)


## True for the fighter the local player controls (the camera's focus).
func _local(slot: int) -> bool:
	return slot >= 0 and camera != null and slot == camera.focus_slot


func _update_letterbox(delta: float) -> void:
	_letterbox_left = maxf(0.0, _letterbox_left - delta)
	_letterbox = move_toward(_letterbox, 1.0 if _letterbox_left > 0.0 else 0.0, delta * 4.0)
	var height := get_viewport().get_visible_rect().size.y * 0.11 * _letterbox
	for i in _bars.size():
		_bars[i].custom_minimum_size.y = height
		_bars[i].size.y = height
		_bars[i].position.y = 0.0 if i == 0 else get_viewport().get_visible_rect().size.y - height
		_bars[i].visible = _letterbox > 0.001
	_grey.visible = _letterbox > 0.001
	if _grey.visible:
		(_grey.material as ShaderMaterial).set_shader_parameter(&"amount", 0.75 * _letterbox)


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
	return TreeCache.get_or_make(&"fight_fx_glow", _make_glow)


static func _ring() -> GradientTexture2D:
	return TreeCache.get_or_make(&"fight_fx_ring", _make_ring)


static func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.25, Color(1, 1, 1, 0.55))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	return _radial(g, 64)


static func _make_ring() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.72, Color(1, 1, 1, 0.0))
	g.add_point(0.86, Color(1, 1, 1, 1.0))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	return _radial(g, 128)


static func _radial(g: Gradient, size: int) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = size
	t.height = size
	return t
