class_name FightCamera
extends Camera3D
## The fight camera (design-lost-ark §3): high, wide and stable. A fixed yaw per arena
## (ArenaData.camera_yaw when the arena has it), ~52° pitch, 15–20 m out, 40° FOV, a
## critically damped follow of the player with a small lead toward the aim, and a distance
## that pulls back only when framing needs it (with hysteresis so it does not breathe).
## Values come from Feel (FeelTuning when present) every frame.
##
## Hooks: add_trauma() for shake, punch() for a zoom punch, cinematic() for awakening and
## other authored shots. Presentation only: DeviceInputSource reads this camera's basis to
## make movement camera-relative.

const MAX_DISTANCE := 20.0
const FAR_ENEMY := 16.0
const WAVE_RADIUS := 12.0
## Framing hysteresis: pull back when the frame is this full, return below the second.
const PULL_BACK_AT := 0.85
const RETURN_AT := 0.65

var runner: MatchRunner
var focus_slot: int = 0
var bounds: Rect2 = Rect2(-11.0, -9.0, 22.0, 18.0)
## World yaw the camera looks along (radians; 0 looks along +Z). Fixed per arena.
var yaw: float = 0.0
## Kept for callers (attract mode, clips); the camera never takes orbit input.
var player_control: bool = true
var spectator: bool = false

var _trauma := 0.0
var _punch := 0.0
var _time := 0.0
var _focus := Vector3.ZERO
var _focus_vel := Vector3.ZERO
var _distance := 15.0
var _distance_vel := 0.0
var _want_distance := 15.0
var _shot_left := 0.0
var _shot_total := 0.0
var _shot_position := Vector3.ZERO
var _shot_look := Vector3.ZERO
var _initialized := false


func setup(match_runner: MatchRunner, slot: int, camera_bounds: Rect2) -> void:
	runner = match_runner
	focus_slot = slot
	bounds = camera_bounds
	var arena := runner.sim.config.arena
	yaw = deg_to_rad(float(arena.get(&"camera_yaw"))) if arena != null and &"camera_yaw" in arena else 0.0
	near = 0.3
	far = 200.0
	_initialized = false


## Adds screen shake (0..1, accumulates, decays over ~0.6 s). Scaled by Feel.shake_scale.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## A quick zoom toward the focus (metres of the FOV-equivalent push, decays in ~0.2 s).
func punch(amount: float) -> void:
	_punch = maxf(_punch, amount)


## Short authored shot: moves to `at` looking at `look` for `seconds`, blending in and out.
func cinematic(at: Vector3, look: Vector3, seconds: float) -> void:
	_shot_left = seconds
	_shot_total = seconds
	_shot_position = at
	_shot_look = look


func is_cinematic() -> bool:
	return _shot_left > 0.0


## The world point the camera is centred on (after smoothing).
func focus_point() -> Vector3:
	return _focus


func _process(delta: float) -> void:
	if runner == null or runner.sim == null:
		return
	_time += delta
	var pitch := Feel.camera_pitch()
	fov = Feel.camera_fov() - 6.0 * _punch
	var target := _target_focus()
	var want := _framing_distance(target, pitch)
	if not _initialized:
		_focus = target
		_distance = want
		_want_distance = want
		_initialized = true
	_focus = _smooth_v(_focus, target, delta, Feel.camera_smoothing())
	_distance = _smooth_f(_distance, _want_distance, delta, 0.6)
	var forward := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	var eye := _focus - forward * _distance
	var xf := Transform3D(Basis.looking_at(forward, Vector3.UP), eye)
	if _shot_left > 0.0:
		_shot_left -= delta
		var shot := Transform3D(Basis.IDENTITY, _shot_position).looking_at(_shot_look, Vector3.UP)
		# Swoop in over the first 0.25 s, hold, and hand back over the last ~0.33 s (20 f).
		var into := clampf((_shot_total - _shot_left) / 0.25, 0.0, 1.0)
		var out := clampf(_shot_left / 0.33, 0.0, 1.0)
		var w := minf(into, out)
		w = w * w * (3.0 - 2.0 * w)
		xf = xf.interpolate_with(shot, w)
	global_transform = xf
	_apply_shake(delta)
	_punch = move_toward(_punch, 0.0, delta * 5.0)


## Player × 0.6 + enemies × 0.4 (enemies within reach), plus a lead toward the aim or the
## move direction, clamped to the camera bounds.
func _target_focus() -> Vector3:
	var sim := runner.sim
	var me := runner.fighter_position(focus_slot)
	var f := sim.fighter(focus_slot)
	var enemies := Vector3.ZERO
	var count := 0
	var reach := FAR_ENEMY if sim.slot_count() <= 2 else WAVE_RADIUS
	for slot in sim.slot_count():
		var other := sim.fighter(slot)
		if slot == focus_slot or other.team == f.team or other.ko:
			continue
		var p := runner.fighter_position(slot)
		if Vector2(p.x - me.x, p.z - me.z).length() > reach:
			continue
		enemies += p
		count += 1
	var focus := me
	if count > 0:
		focus = me * 0.6 + (enemies / float(count)) * 0.4
	focus += _lead(f) * Feel.camera_lead()
	focus.y = 0.9
	focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
	focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	return focus


## Unit lead direction: toward the cursor aim point, else the stick, else none.
func _lead(f: FighterState) -> Vector3:
	var aim := Vector3(float(f.get(&"aim_x")) if &"aim_x" in f else 0.0, 0.0, float(f.get(&"aim_z")) if &"aim_z" in f else 0.0)
	if aim.length_squared() > 0.0:
		return aim.normalized()
	var stick := Vector3(f.stick_x, 0.0, f.stick_z)
	return stick.normalized() if stick.length_squared() > 0.0 else Vector3.ZERO


## Distance that keeps the player and enemies (within reach) inside the middle of the
## frame, with hysteresis; returns the current wanted distance.
func _framing_distance(focus: Vector3, pitch: float) -> float:
	var sim := runner.sim
	var base := Feel.camera_distance()
	var half_v := tan(deg_to_rad(Feel.camera_fov()) * 0.5)
	var aspect := get_viewport().get_visible_rect().size.aspect() if is_inside_tree() else 16.0 / 9.0
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var ahead := Vector3(sin(yaw), 0.0, cos(yaw))
	var me := runner.fighter_position(focus_slot)
	var f := sim.fighter(focus_slot)
	var need := 0.0
	var reach := FAR_ENEMY if sim.slot_count() <= 2 else WAVE_RADIUS
	for slot in sim.slot_count():
		var other := sim.fighter(slot)
		if other.ko or (slot != focus_slot and other.team == f.team):
			continue
		var p := runner.fighter_position(slot)
		if slot != focus_slot and Vector2(p.x - me.x, p.z - me.z).length() > reach:
			continue
		var d := p - focus
		var sx := absf(d.dot(right))
		var sz := absf(d.dot(ahead))
		# Relative to the safe frame: the middle 80% of the screen.
		need = maxf(need, maxf(sx / (0.8 * aspect * half_v), sz * sin(pitch) / (0.8 * half_v)))
	var fill := need / maxf(1.0, _want_distance)
	if fill > PULL_BACK_AT:
		_want_distance = clampf(need / (PULL_BACK_AT - 0.05), base, MAX_DISTANCE)
	elif fill < RETURN_AT:
		_want_distance = clampf(maxf(base, need / RETURN_AT), base, MAX_DISTANCE)
	_want_distance = clampf(_want_distance, base, maxf(base, MAX_DISTANCE))
	return _want_distance


func _apply_shake(delta: float) -> void:
	if _trauma <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
		return
	var s := _trauma * _trauma * Feel.shake_scale()
	var t := _time * 38.0
	h_offset = s * 0.35 * (sin(t * 1.3) + sin(t * 2.9) * 0.5)
	v_offset = s * 0.3 * (cos(t * 1.7) + sin(t * 3.3) * 0.5)
	rotate_object_local(Vector3.FORWARD, s * 0.02 * sin(t * 2.1))
	_trauma = maxf(0.0, _trauma - delta * 1.8)


## Critically damped smoothing toward `target` with time constant `smoothing` seconds.
func _smooth_v(current: Vector3, target: Vector3, delta: float, smoothing: float) -> Vector3:
	var omega := 2.0 / maxf(0.01, smoothing)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (_focus_vel + omega * change) * delta
	_focus_vel = (_focus_vel - omega * temp) * e
	return target + (change + temp) * e


func _smooth_f(current: float, target: float, delta: float, smoothing: float) -> float:
	var omega := 2.0 / maxf(0.01, smoothing)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (_distance_vel + omega * change) * delta
	_distance_vel = (_distance_vel - omega * temp) * e
	return target + (change + temp) * e
