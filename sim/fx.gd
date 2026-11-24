class_name Fx
extends RefCounted
## Fixed-point math for the simulation.
##
## Sim state holds only integers so a fight is bit-identical on every platform (desktop,
## web) without relying on float behavior or libm. Content is authored in floats (meters,
## m/s, degrees) and converted with these helpers when the sim reads it; the conversion of a
## given authored value is itself deterministic.
##
## - Distance: ONE units per meter (0.1 mm). Velocities are units per tick.
## - Angle: TURN steps per full turn. Facing `a` points along (sin a, 0, cos a), so angle 0
##   faces +Z and a Godot node with `rotation.y = Fx.angle_to_rad(a)` faces the same way.
## - Trig results are Q14 (TRIG_ONE = 1.0).

const ONE := 10000
const TICKS_PER_SECOND := 60
const TURN := 4096
const HALF_TURN := 2048
const QUARTER_TURN := 1024
const TRIG_ONE := 16384
const _ATAN_STEPS := 1024

static var _sin_table := PackedInt32Array()
static var _atan_table := PackedInt32Array()


static func _static_init() -> void:
	_sin_table.resize(QUARTER_TURN + 1)
	for i in QUARTER_TURN + 1:
		_sin_table[i] = roundi(sin(float(i) * TAU / TURN) * TRIG_ONE)
	_atan_table.resize(_ATAN_STEPS + 1)
	for i in _ATAN_STEPS + 1:
		_atan_table[i] = roundi(atan(float(i) / _ATAN_STEPS) * TURN / TAU)


## Meters to units.
static func m(meters: float) -> int:
	return roundi(meters * ONE)


## Meters per second to units per tick.
static func mps(meters_per_second: float) -> int:
	return roundi(meters_per_second * ONE / TICKS_PER_SECOND)


## Meters per second squared to units per tick squared.
static func mps2(meters_per_second_sq: float) -> int:
	return roundi(meters_per_second_sq * ONE / (TICKS_PER_SECOND * TICKS_PER_SECOND))


## Degrees to angle steps.
static func deg(degrees: float) -> int:
	return roundi(degrees * TURN / 360.0)


## Authored local-space point (meters) to units.
static func v3(meters: Vector3) -> Vector3i:
	return Vector3i(m(meters.x), m(meters.y), m(meters.z))


static func to_m(units: int) -> float:
	return float(units) / ONE


static func to_vec3(units: Vector3i) -> Vector3:
	return Vector3(units) / ONE


static func angle_to_rad(angle: int) -> float:
	return float(angle) * TAU / TURN


static func wrap_angle(angle: int) -> int:
	return angle & (TURN - 1)


## Signed shortest difference to - from, in (-HALF_TURN, HALF_TURN].
static func angle_diff(from: int, to: int) -> int:
	var d := (to - from) & (TURN - 1)
	return d - TURN if d > HALF_TURN else d


## Rotates `current` toward `target` by at most `max_step`.
static func turn_toward(current: int, target: int, max_step: int) -> int:
	var d := angle_diff(current, target)
	if d > max_step:
		d = max_step
	elif d < -max_step:
		d = -max_step
	return wrap_angle(current + d)


static func sin_q(angle: int) -> int:
	var a := angle & (TURN - 1)
	if a < QUARTER_TURN:
		return _sin_table[a]
	if a < HALF_TURN:
		return _sin_table[HALF_TURN - a]
	if a < HALF_TURN + QUARTER_TURN:
		return -_sin_table[a - HALF_TURN]
	return -_sin_table[TURN - a]


static func cos_q(angle: int) -> int:
	return sin_q(angle + QUARTER_TURN)


## Facing angle of the x-z direction (x, z). Returns 0 for a zero vector.
static func angle_of(x: int, z: int) -> int:
	if x == 0 and z == 0:
		return 0
	var ax := absi(x)
	var az := absi(z)
	var base: int
	if ax <= az:
		base = _atan_table[ax * _ATAN_STEPS / az]
	else:
		base = QUARTER_TURN - _atan_table[az * _ATAN_STEPS / ax]
	var a: int
	if z >= 0:
		a = base if x >= 0 else -base
	else:
		a = HALF_TURN - base if x >= 0 else HALF_TURN + base
	return a & (TURN - 1)


## Horizontal vector of `length` units along `angle`.
static func dir(angle: int, length: int) -> Vector3i:
	return Vector3i(sin_q(angle) * length / TRIG_ONE, 0, cos_q(angle) * length / TRIG_ONE)


## Rotates a fighter-local offset into world space for facing `angle`. Local axes are Godot
## node-local axes of a model facing +Z: +Z forward, +Y up, +X the model's left side.
static func rotate(local: Vector3i, angle: int) -> Vector3i:
	var s := sin_q(angle)
	var c := cos_q(angle)
	return Vector3i((local.x * c + local.z * s) / TRIG_ONE, local.y, (local.z * c - local.x * s) / TRIG_ONE)


## Floor of the square root for n >= 0.
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var r := int(sqrt(float(n)))
	while r * r > n:
		r -= 1
	while (r + 1) * (r + 1) <= n:
		r += 1
	return r


## Horizontal (x-z) length.
static func length_xz(v: Vector3i) -> int:
	return isqrt(v.x * v.x + v.z * v.z)


static func dist_xz(a: Vector3i, b: Vector3i) -> int:
	var dx := b.x - a.x
	var dz := b.z - a.z
	return isqrt(dx * dx + dz * dz)


static func dist2_xz(a: Vector3i, b: Vector3i) -> int:
	var dx := b.x - a.x
	var dz := b.z - a.z
	return dx * dx + dz * dz


## Scales the x-z part of `v` to `length` (keeps y). Zero vectors stay zero.
static func with_length_xz(v: Vector3i, length: int) -> Vector3i:
	var l := length_xz(v)
	if l == 0:
		return Vector3i(0, v.y, 0)
	return Vector3i(v.x * length / l, v.y, v.z * length / l)
