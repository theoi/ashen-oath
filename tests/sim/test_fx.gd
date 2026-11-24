extends TestCase
## Fixed-point math and input frame packing.


func test_angles_follow_godot_rotation() -> void:
	assert_eq(Fx.angle_of(0, 100), 0, "+Z is angle 0")
	assert_eq(Fx.angle_of(100, 0), Fx.QUARTER_TURN, "+X is a quarter turn")
	assert_eq(Fx.angle_of(0, -100), Fx.HALF_TURN)
	assert_eq(Fx.angle_of(-100, 0), Fx.HALF_TURN + Fx.QUARTER_TURN)
	for angle: int in [0, 100, 777, 1500, 2048, 3000, 4000]:
		var v := Fx.dir(angle, 100000)
		assert_true(absi(Fx.angle_diff(angle, Fx.angle_of(v.x, v.z))) <= 1, "angle_of inverts dir at %d" % angle)
		# Same direction as Godot's rotation of +Z by the angle.
		var godot := Basis(Vector3.UP, Fx.angle_to_rad(angle)) * Vector3(0, 0, 1)
		assert_almost_eq(Fx.to_m(v.x), godot.x * 10.0, 0.002)
		assert_almost_eq(Fx.to_m(v.z), godot.z * 10.0, 0.002)


func test_rotate_matches_godot_local_space() -> void:
	var local := Vector3(0.5, 1.0, 2.0)
	var angle := Fx.deg(70.0)
	var rotated := Fx.to_vec3(Fx.rotate(Fx.v3(local), angle))
	var expected := Basis(Vector3.UP, Fx.angle_to_rad(angle)) * local
	assert_true(rotated.distance_to(expected) < 0.002, "%s vs %s" % [rotated, expected])


func test_angle_diff_wraps() -> void:
	assert_eq(Fx.angle_diff(4000, 100), 196)
	assert_eq(Fx.angle_diff(100, 4000), -196)
	assert_eq(Fx.turn_toward(0, 2000, 341), 341)
	assert_eq(Fx.turn_toward(0, 3000, 341), Fx.wrap_angle(-341))


func test_isqrt_is_exact_floor() -> void:
	for n: int in [0, 1, 2, 3, 4, 15, 16, 17, 99999999, 1 << 40, (1 << 52) + 12345]:
		var r := Fx.isqrt(n)
		assert_true(r * r <= n and (r + 1) * (r + 1) > n, "isqrt(%d) = %d" % [n, r])


func test_trig_table_is_stable() -> void:
	# Guards cross-platform drift of the generated tables (they feed every checksum).
	var sum := 0
	for a in Fx.TURN:
		sum = (sum * 31 + Fx.sin_q(a)) & 0xFFFFFFFF
	for x in range(0, 2000, 7):
		sum = (sum * 31 + Fx.angle_of(x, 1000)) & 0xFFFFFFFF
	assert_eq(sum, _expected_table_hash())


func test_input_frames_round_trip() -> void:
	for x: int in [-127, -1, 0, 1, 127]:
		for z: int in [-127, -64, 0, 99, 127]:
			var frame := SimInput.make(SimInput.LIGHT | SimInput.SUPER, x, z)
			assert_eq(SimInput.stick_x(frame), x)
			assert_eq(SimInput.stick_z(frame), z)
			assert_eq(SimInput.buttons_of(frame), SimInput.LIGHT | SimInput.SUPER)
	assert_eq(SimInput.make(0), 0, "neutral frame is 0")
	var packed := PackedInt32Array([SimInput.make(SimInput.GUARD, -127, -127)])
	assert_eq(SimInput.stick_z(packed[0]), -127, "survives int32 storage")


func _expected_table_hash() -> int:
	return 763421323
