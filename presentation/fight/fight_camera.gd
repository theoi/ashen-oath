class_name FightCamera
extends Camera3D
## Third-person fight camera: sits behind the focus fighter, frames its target, orbits
## with the mouse / right stick and turns to face the target under hard lock. Presentation
## only: DeviceInputSource reads this camera's yaw to make movement camera-relative.
##
## Hooks: add_trauma() for shake, cinematic() for short super shots.

const MOUSE_SENSITIVITY := 0.0035
const STICK_SPEED := 2.6
const MIN_PITCH := -0.75
const MAX_PITCH := 0.05

var runner: MatchRunner
var focus_slot: int = 0
var bounds: Rect2 = Rect2(-11.0, -9.0, 22.0, 18.0)
## Orbit angles (radians). Yaw 0 looks along +Z.
var yaw: float = 0.0
var orbit_pitch: float = -0.3
var base_distance: float = 4.6
## Over-the-shoulder offset (meters to the camera's right) so the focus fighter does not
## hide the target.
var shoulder: float = 1.25
## Spectator framing (attract mode, clips): a three-quarter side view of both fighters
## instead of over the focus fighter's shoulder.
var spectator: bool = false
## Reads mouse/stick orbit input (off for clips and attract mode).
var player_control: bool = true

var _trauma: float = 0.0
var _time: float = 0.0
var _focus := Vector3.ZERO
var _distance: float = 5.6
var _shot_left: float = 0.0
var _shot_from := Transform3D.IDENTITY
var _shot_position := Vector3.ZERO
var _shot_look := Vector3.ZERO
var _initialized := false
var _arena: ArenaData
## Smoothed fraction of the wanted distance left free by walls and pillars.
var _clear := 1.0
## Yaw swung away from straight-behind so a cornered fighter is framed along the wall
## instead of from inside it (radians, relative to the target-facing yaw).
var _wall_bias := 0.0
## Chest points of the focus fighter and its target this frame (line-of-sight checks).
var _me_chest := Vector3.ZERO
var _them_chest := Vector3.ZERO


func setup(match_runner: MatchRunner, slot: int, camera_bounds: Rect2) -> void:
	runner = match_runner
	focus_slot = slot
	bounds = camera_bounds.grow(-0.4)
	_arena = runner.sim.config.arena
	fov = 58.0
	near = 0.1
	var f := runner.sim.fighter(slot)
	yaw = Fx.angle_to_rad(f.facing)
	_initialized = false


## Adds screen shake (0..1, accumulates, decays over ~0.6 s).
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Short cinematic shot: moves to `at` looking at `look` for `seconds` (super cameras).
func cinematic(at: Vector3, look: Vector3, seconds: float) -> void:
	_shot_left = seconds
	_shot_position = at
	_shot_look = look


func is_cinematic() -> bool:
	return _shot_left > 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not player_control:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		yaw -= motion.relative.x * MOUSE_SENSITIVITY
		orbit_pitch = clampf(orbit_pitch - motion.relative.y * MOUSE_SENSITIVITY, MIN_PITCH, MAX_PITCH)


func _process(delta: float) -> void:
	if runner == null or runner.sim == null:
		return
	_time += delta
	var sim := runner.sim
	var f := sim.fighter(focus_slot)
	var me := runner.fighter_position(focus_slot)
	var target_slot := f.target
	var has_target := target_slot >= 0 and not sim.fighter(target_slot).ko
	var them := runner.fighter_position(target_slot) if has_target else me
	if player_control:
		var stick := Input.get_axis(&"camera_left", &"camera_right")
		yaw -= stick * STICK_SPEED * delta
		var vertical := Input.get_axis(&"camera_up", &"camera_down")
		orbit_pitch = clampf(orbit_pitch - vertical * STICK_SPEED * 0.5 * delta, MIN_PITCH, MAX_PITCH)
	var to := Vector3(them.x - me.x, 0.0, them.z - me.z)
	var separation := to.length()
	_me_chest = me + Vector3.UP * 1.0
	_them_chest = them + Vector3.UP * 1.0
	var focus := me + Vector3.UP * 1.15
	if has_target and separation < 14.0:
		focus = focus.lerp(them + Vector3.UP * 1.0, 0.5 if spectator else 0.42)
	var want_distance := clampf(base_distance + separation * (0.55 if spectator else 0.3), base_distance, 9.5)
	var offset := 0.0 if spectator else shoulder
	if not _initialized:
		_focus = focus
		_distance = want_distance
		_initialized = true
	_focus = _focus.lerp(focus, 1.0 - exp(-9.0 * delta))
	_distance = lerpf(_distance, want_distance, 1.0 - exp(-3.0 * delta))
	if has_target and separation > 0.5:
		var desired := atan2(to.x, to.z) + (deg_to_rad(62.0) if spectator else 0.0)
		_update_wall_bias(desired, offset, delta)
		var aim := desired + _wall_bias
		var off := absf(angle_difference(yaw, aim))
		var rate := 6.0 if f.hard_lock else (1.4 if off > deg_to_rad(40.0) else 0.0)
		if spectator:
			rate = 1.2 if off > deg_to_rad(25.0) else 0.4
		if _wall_bias != 0.0:
			rate = maxf(rate, 3.0)
		yaw = lerp_angle(yaw, aim, 1.0 - exp(-rate * delta))
	var forward := _forward(yaw)
	var right := Vector3(-cos(yaw), 0.0, sin(yaw))
	var wanted := _focus - forward * _distance + right * offset
	var clear := _free_fraction(_focus, wanted)
	_clear = clear if clear < _clear else lerpf(_clear, clear, 1.0 - exp(-4.0 * delta))
	# Pull in only part of the way and rise over the obstacle instead, so the camera never
	# ends up inside a fighter.
	var eye := _focus.lerp(wanted, lerpf(0.55, 1.0, _clear))
	eye.y = maxf(eye.y + (1.0 - _clear) * 2.2, 0.6)
	var xf := Transform3D(Basis.IDENTITY, eye).looking_at(_focus + right * offset * 0.5, Vector3.UP)
	if _shot_left > 0.0:
		_shot_left -= delta
		var shot := Transform3D(Basis.IDENTITY, _shot_position).looking_at(_shot_look, Vector3.UP)
		var w := clampf(minf(_shot_left, 0.25) / 0.25, 0.0, 1.0)
		xf = xf.interpolate_with(shot, w)
	global_transform = xf
	_apply_shake(delta)


func _forward(at_yaw: float) -> Vector3:
	return Vector3(sin(at_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(at_yaw) * cos(orbit_pitch))


## How good a camera yaw is: the free fraction toward its spot, capped low when a pillar
## would hide either fighter from there.
func _clear_at(at_yaw: float, offset: float) -> float:
	var right := Vector3(-cos(at_yaw), 0.0, sin(at_yaw))
	var wanted := _focus - _forward(at_yaw) * _distance + right * offset
	var clear := _free_fraction(_focus, wanted)
	var eye := _focus.lerp(wanted, lerpf(0.55, 1.0, clear))
	if _hugs_pillar(eye) or not (_sees(eye, _me_chest) and _sees(eye, _them_chest)):
		return minf(clear, 0.5)
	return clear


## True when `eye` is so close to a pillar that it would fill the screen.
func _hugs_pillar(eye: Vector3) -> bool:
	if _arena == null:
		return false
	var e := Vector2(eye.x, eye.z)
	for o in _arena.obstacles:
		if eye.y < o.height and _segment_distance(e, o.a, o.b) < o.radius + 1.0:
			return true
	return false


## False when a pillar taller than the sight line stands between `eye` and `point`.
func _sees(eye: Vector3, point: Vector3) -> bool:
	if _arena == null:
		return true
	var e := Vector2(eye.x, eye.z)
	var p := Vector2(point.x, point.z)
	var low := minf(eye.y, point.y)
	for o in _arena.obstacles:
		if o.height < low:
			continue
		if _segments_distance(e, p, o.a, o.b) < o.radius + 0.3:
			return false
	return true


static func _segments_distance(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(p1, p2, q1, q2) != null:
		return 0.0
	return minf(minf(_segment_distance(p1, q1, q2), _segment_distance(p2, q1, q2)),
			minf(_segment_distance(q1, p1, p2), _segment_distance(q2, p1, p2)))


## Swings the camera around a fighter backed against a wall or pillar until it has room
## behind it, and eases back to straight-behind once that is clear again.
func _update_wall_bias(desired: float, offset: float, delta: float) -> void:
	const ENOUGH := 0.9
	const MAX_BIAS := 1.75
	const STEP := 0.22
	if _clear_at(desired + _wall_bias, offset) < ENOUGH:
		var best := _wall_bias
		var best_clear := -1.0
		for k in range(1, 9):
			for side: float in [1.0, -1.0]:
				var bias := clampf(_wall_bias + side * STEP * k, -MAX_BIAS, MAX_BIAS)
				var c := _clear_at(desired + bias, offset)
				if c > best_clear + 0.02:
					best = bias
					best_clear = c
			if best_clear >= ENOUGH:
				break
		_wall_bias = best
	elif _wall_bias != 0.0:
		var eased := move_toward(_wall_bias, 0.0, delta * 0.6)
		if _clear_at(desired + eased, offset) >= 0.98:
			_wall_bias = eased


## How far (0..1) the camera can go from `from` toward `to` before it would enter a wall or
## pillar (with a margin), so it pulls in instead of clipping through scenery.
func _free_fraction(from: Vector3, to: Vector3) -> float:
	const STEPS := 24
	const WALL_MARGIN := 0.7
	const PILLAR_MARGIN := 0.9
	# A pillar the focus point is inside (fighters on both sides of it) is left to the
	# line-of-sight check; counting it would block every direction alike.
	var start := Vector2(from.x, from.z)
	var pillars: Array[ArenaObstacle] = []
	if _arena != null:
		for o in _arena.obstacles:
			if _segment_distance(start, o.a, o.b) >= o.radius + 0.1:
				pillars.append(o)
	for i in range(1, STEPS + 1):
		var t := float(i) / STEPS
		var p := from.lerp(to, t)
		var p2 := Vector2(p.x, p.z)
		var blocked := not bounds.has_point(p2)
		if _arena != null and not blocked:
			blocked = _outside_floor(p2, WALL_MARGIN)
			for o in pillars:
				if blocked:
					break
				if p.y < o.height + 0.5 and _segment_distance(p2, o.a, o.b) < o.radius + PILLAR_MARGIN:
					blocked = true
		if blocked:
			return float(i - 1) / STEPS
	return 1.0


func _outside_floor(p: Vector2, margin: float) -> bool:
	var poly := _arena.floor_polygon
	var n := poly.size()
	if n < 3:
		return false
	var area := 0.0
	for i in n:
		area += poly[i].cross(poly[(i + 1) % n])
	var winding := signf(area)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var edge := b - a
		var inside := edge.cross(p - a) * winding
		if inside < margin * edge.length():
			return true
	return false


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 0.0001 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _apply_shake(delta: float) -> void:
	if _trauma <= 0.0:
		return
	var s := _trauma * _trauma
	var t := _time * 38.0
	h_offset = s * 0.12 * (sin(t * 1.3) + sin(t * 2.9) * 0.5)
	v_offset = s * 0.10 * (cos(t * 1.7) + sin(t * 3.3) * 0.5)
	rotate_object_local(Vector3.FORWARD, s * 0.03 * sin(t * 2.1))
	_trauma = maxf(0.0, _trauma - delta * 1.8)
	if _trauma <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
