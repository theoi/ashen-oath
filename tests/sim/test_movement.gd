extends TestCase
## Movement frame data: run/stop, jump, dodge, air dodge, guard, walls, lock-on, buffer.

const F := preload("res://tests/sim/sim_fixtures.gd")
const Action := FighterState.Action

var sim: Sim
var me: FighterState


func before_each() -> void:
	sim = F.fighting_sim(F.config(2))
	me = sim.fighter(0)


func test_run_reaches_full_speed_in_5_frames_and_stops_in_4() -> void:
	var full := Fx.mps(6.5)
	var right := SimInput.make(0, 127, 0)
	for i in 4:
		F.step(sim, right)
		assert_true(me.vel.x < full, "not full speed on frame %d" % (i + 1))
	F.step(sim, right)
	assert_eq(me.vel.x, full, "full speed on frame 5")
	for i in 3:
		F.step(sim)
		assert_true(me.vel.x > 0, "still sliding on stop frame %d" % (i + 1))
	F.step(sim)
	assert_eq(me.vel.x, 0, "stopped on frame 4")


func test_analog_stick_scales_speed() -> void:
	F.hold(sim, 10, SimInput.make(0, 64, 0))
	assert_almost_eq(float(me.vel.x), float(Fx.mps(6.5)) * 64.0 / 127.0, 2.0)


func test_running_turns_30_degrees_per_frame() -> void:
	var start := me.facing
	F.step(sim, SimInput.toward_angle(0, start + Fx.HALF_TURN))
	assert_eq(absi(Fx.angle_diff(start, me.facing)), Fx.deg(30.0))


func test_jump_has_3_frame_squat_42_frame_airtime_and_1_6_m_apex() -> void:
	F.step(sim, F.J)
	assert_eq(me.action, Action.JUMP_SQUAT)
	F.step(sim)
	F.step(sim)
	assert_true(me.grounded, "still on the ground after 3 squat frames")
	var airtime := 0
	var apex := 0
	for _i in 80:
		F.step(sim)
		if not me.grounded:
			airtime += 1
			apex = maxi(apex, me.pos.y)
		elif airtime > 0:
			break
	assert_true(absi(airtime - 42) <= 1, "airtime %d" % airtime)
	assert_almost_eq(Fx.to_m(apex), 1.6, 0.05)
	assert_eq(me.action, Action.LAND)
	F.hold(sim, 3)
	assert_eq(me.action, Action.IDLE, "3 landing frames")


func test_dodge_roll_frames_invincibility_and_distance() -> void:
	var start := me.pos
	var facing := me.facing
	F.step(sim, F.D)
	assert_eq(me.action, Action.DODGE)
	var invulnerable_frames: Array[int] = []
	if sim.is_invulnerable(me):
		invulnerable_frames.append(1)
	for frame in range(2, 25):
		F.step(sim)
		assert_eq(me.action, Action.DODGE, "still rolling on frame %d" % frame)
		if sim.is_invulnerable(me):
			invulnerable_frames.append(frame)
	assert_eq(invulnerable_frames, [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])
	F.step(sim)
	assert_eq(me.action, Action.IDLE, "roll is 24 frames")
	var travel := me.pos - start
	assert_almost_eq(Fx.to_m(Fx.length_xz(travel)), 3.5, 0.02)
	var back := Fx.wrap_angle(facing + Fx.HALF_TURN)
	assert_true(absi(Fx.angle_diff(back, Fx.angle_of(travel.x, travel.z))) <= 2, "neutral stick rolls backward")


func test_dodge_has_6_frame_lockout() -> void:
	F.step(sim, F.D)
	F.hold(sim, 24)
	F.step(sim, F.D)
	assert_eq(me.action, Action.IDLE, "no new roll right after one")
	F.hold(sim, 4)
	F.step(sim, F.D)
	assert_eq(me.action, Action.DODGE, "buffered roll starts after the lockout")


func test_air_dodge_once_per_airtime() -> void:
	F.step(sim, F.J)
	F.hold(sim, 6)
	F.step(sim, F.D)
	assert_eq(me.action, Action.AIR_DODGE)
	F.hold(sim, 3)
	assert_true(sim.is_invulnerable(me), "air dodge frame 4 is invincible")
	F.hold(sim, 16)
	assert_eq(me.action, Action.AIR)
	F.step(sim, F.D)
	assert_eq(me.action, Action.AIR, "second air dodge refused")


func test_guard_comes_up_after_2_frames_and_slows_movement() -> void:
	F.step(sim, F.G)
	assert_eq(me.action, Action.GUARD)
	assert_false(sim.guard_up(me), "frame 1")
	F.step(sim, F.G)
	assert_false(sim.guard_up(me), "frame 2")
	F.step(sim, F.G)
	assert_true(sim.guard_up(me), "frame 3: up 2 frames after the press")
	F.hold(sim, 20, SimInput.make(F.G, 127, 0))
	assert_eq(me.vel.x, Fx.mps(6.5) * 40 / 100)


func test_parry_window_then_lockout() -> void:
	F.step(sim, F.G)
	assert_eq(me.parry_timer, 5, "window of 6 frames including the press frame")
	F.hold(sim, 5, F.G)
	assert_eq(me.parry_timer, 0)
	assert_eq(me.parry_lockout, 20)
	F.step(sim)
	F.step(sim, F.G)
	assert_eq(me.parry_timer, 0, "locked out: no new window")


func test_walls_and_pillars_stop_fighters() -> void:
	var arena := F.arena()
	var pillar := ArenaObstacle.new()
	pillar.a = Vector2(3.0, -1.5)
	pillar.b = pillar.a
	pillar.radius = 0.5
	arena.obstacles.append(pillar)
	sim = F.fighting_sim(F.config(2, null, arena))
	me = sim.fighter(0)
	F.hold(sim, 60, SimInput.make(0, 127, 0))
	assert_almost_eq(Fx.to_m(me.pos.x), 3.0 - 0.95, 0.01)
	F.hold(sim, 30, SimInput.make(0, 0, -127))
	F.hold(sim, 120, SimInput.make(0, 127, 0))
	assert_almost_eq(Fx.to_m(me.pos.x), 12.0 - 0.45, 0.001)
	F.hold(sim, 200, SimInput.make(0, 127, -127))
	assert_almost_eq(Fx.to_m(me.pos.z), -10.0 + 0.45, 0.001)


func test_fighters_do_not_overlap() -> void:
	F.hold(sim, 60, SimInput.make(0, 0, 127), SimInput.make(0, 0, -127))
	var gap := Fx.dist_xz(me.pos, sim.fighter(1).pos)
	assert_true(gap >= Fx.m(0.9) - Fx.m(0.1), "gap %d" % gap)


func test_lock_on_cycles_targets_then_unlocks() -> void:
	sim = F.fighting_sim(F.config(3))
	me = sim.fighter(0)
	F.step(sim, SimInput.LOCK)
	assert_true(me.hard_lock)
	var first := me.target
	F.step(sim)
	F.step(sim, SimInput.LOCK)
	assert_true(me.hard_lock)
	assert_ne(me.target, first, "switched target")
	F.step(sim)
	F.step(sim, SimInput.LOCK)
	assert_false(me.hard_lock, "unlocked after the last target")


func test_hard_lock_strafes_facing_the_target() -> void:
	F.step(sim, SimInput.LOCK)
	F.hold(sim, 30, SimInput.make(0, 127, 0))
	var to_target := sim.fighter(1).pos - me.pos
	# Facing turns before this tick's movement, so it trails by about one tick of strafing.
	assert_true(absi(Fx.angle_diff(me.facing, Fx.angle_of(to_target.x, to_target.z))) <= Fx.deg(3.0))


func test_input_buffer_lasts_buffer_frames() -> void:
	var n := CombatRules.new().buffer_frames
	assert_eq(n, 12)
	F.step(sim, F.D)
	F.hold(sim, 23 - n)
	F.step(sim, F.J)
	F.hold(sim, n)
	assert_eq(me.action, Action.JUMP_SQUAT, "jump pressed %d frames before the roll ended is kept" % (n + 1))
	sim = F.fighting_sim(F.config(2))
	me = sim.fighter(0)
	F.step(sim, F.D)
	F.hold(sim, 22 - n)
	F.step(sim, F.J)
	F.hold(sim, n + 1)
	assert_eq(me.action, Action.IDLE, "a press older than %d frames is dropped" % n)
