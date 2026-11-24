extends TestCase
## Aim in the input frame: encoding, aim types on moves, aim assist, aim travel, replays.

const F := preload("res://tests/sim/sim_fixtures.gd")
const S1 := SimInput.SKILL_1
const S2 := SimInput.SKILL_2
const S3 := SimInput.SKILL_3
const S4 := SimInput.SKILL_4
const S5 := SimInput.SKILL_5
const S6 := SimInput.SKILL_6
const EAST := 1024


static func _move(id: StringName, aim: MoveData.Aim, startup: int = 10) -> MoveData:
	var move := MoveData.new()
	move.id = id
	move.kind = MoveData.Kind.ABILITY
	move.aim = aim
	move.startup = startup
	move.active = 2
	move.recovery = 10
	move.tracking = 0.0
	return move


## Skills: 1 direction, 2 ground target (5 m) with a TARGET effect, 3 dash-to (6 m),
## 4 leap to the point (7 m), 5 teleport to the point, 6 legacy AUTO.
static func _fighter() -> FighterData:
	var data := F.fighter()
	var direction := _move(&"direction", MoveData.Aim.DIRECTION)
	var ground := _move(&"ground", MoveData.Aim.GROUND_TARGET)
	ground.max_range = 5.0
	var effect := EffectData.new()
	effect.id = &"rune"
	effect.anchor = EffectData.Anchor.TARGET
	effect.offset = Vector3.ZERO
	effect.max_range = 12.0
	effect.lifetime = 5
	ground.effects = [effect]
	var dash_to := _move(&"dash_to", MoveData.Aim.DASH_TO, 30)
	dash_to.max_range = 6.0
	var run := MotionData.new()
	run.start_frame = 1
	run.end_frame = 30
	run.forward_speed = 15.0
	run.aim_travel = MotionData.AimTravel.STOP_AT
	dash_to.motions = [run]
	var leap := _move(&"leap", MoveData.Aim.GROUND_TARGET, 20)
	leap.max_range = 7.0
	var arc := MotionData.new()
	arc.start_frame = 2
	arc.end_frame = 17
	arc.up_speed = 4.0
	arc.aim_travel = MotionData.AimTravel.ARRIVE
	leap.motions = [arc]
	var blink := _move(&"blink", MoveData.Aim.GROUND_TARGET)
	blink.max_range = 8.0
	blink.teleport = TeleportData.new()
	blink.teleport.frame = 2
	blink.teleport.mode = TeleportData.Mode.AIM_POINT
	blink.teleport.max_range = 8.0
	var legacy := _move(&"legacy", MoveData.Aim.AUTO)
	data.moves = [direction, ground, dash_to, leap, blink, legacy]
	data.abilities = [&"direction", &"ground", &"dash_to", &"leap", &"blink", &"legacy"]
	return data


## Slot 0 at the origin facing +Z, slot 1 three meters ahead (+Z).
static func _sim() -> Sim:
	var sim := F.fighting_sim(F.config(2, _fighter()))
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, 3.0, Fx.HALF_TURN)
	return sim


static func _point(buttons: int, x: float, z: float) -> int:
	return SimInput.with_aim_point(SimInput.make(buttons), Vector2(x, z))


static func _dir(buttons: int, x: float, z: float) -> int:
	return SimInput.with_aim_direction(SimInput.make(buttons), Vector2(x, z))


func test_frame_round_trips_aim_and_keeps_buttons_and_stick() -> void:
	var frame := SimInput.with_aim_point(SimInput.make(S6 | SimInput.LIGHT, -127, 90), Vector2(-20.47, 3.21))
	assert_true(frame > 0, "64-bit frames are never negative")
	assert_eq(SimInput.buttons_of(frame), S6 | SimInput.LIGHT)
	assert_eq(SimInput.stick_x(frame), -127)
	assert_eq(SimInput.stick_z(frame), 90)
	assert_eq(SimInput.aim_x(frame), -2047)
	assert_eq(SimInput.aim_z(frame), 321)
	assert_true(SimInput.aim_is_point(frame))
	var dir := SimInput.with_aim_direction(SimInput.make(0), Vector2(0.0, -0.5))
	assert_false(SimInput.aim_is_point(dir))
	assert_eq(SimInput.aim_z(dir), -1024)
	assert_true(SimInput.has_aim(dir))
	assert_false(SimInput.has_aim(SimInput.make(S1, 50, 50)))
	var far := SimInput.with_aim_point(0, Vector2(40.0, 10.0))
	assert_eq(SimInput.aim_x(far), 2047, "far points are scaled into range, keeping direction")
	assert_eq(SimInput.aim_z(far), 512)


func test_int32_frames_still_step() -> void:
	var sim := _sim()
	var frame := SimInput.make(0, -127, -127)
	sim.step(PackedInt32Array([frame, 0]))
	assert_eq(sim.fighter(0).stick_x, -127)
	assert_eq(sim.fighter(0).stick_z, -127)
	assert_eq(sim.fighter(0).aim_x, 0, "sign extension does not leak into aim")
	assert_false(sim.fighter(0).aim_point)


func test_direction_skill_snaps_to_cursor_on_frame_one() -> void:
	var sim := _sim()
	F.step(sim, _point(S1, 4.0, 0.0))
	var f := sim.fighter(0)
	assert_eq(f.action, FighterState.Action.ATTACK)
	assert_eq(f.move_frame, 1)
	assert_eq(f.facing, EAST, "faces the cursor, not the enemy ahead")


func test_direction_skill_tracks_current_aim_during_startup() -> void:
	var sim := _fighter_sim_with_tracking(10.0)
	F.step(sim, _point(S1, 4.0, 0.0))
	for _i in 3:
		F.step(sim, _point(S1, 0.0, 4.0))
	assert_eq(sim.fighter(0).facing, EAST - 3 * Fx.deg(10.0))
	for _i in 20:
		F.step(sim, _point(S1, 0.0, 4.0))
	assert_eq(sim.fighter(0).facing, 0)


func _fighter_sim_with_tracking(degrees: float) -> Sim:
	var data := _fighter()
	data.moves[0].tracking = degrees
	data.moves[0].startup = 30
	var sim := F.fighting_sim(F.config(2, data))
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, 3.0, Fx.HALF_TURN)
	return sim


func test_stick_aim_assist_snaps_within_cone_only() -> void:
	var sim := _sim()
	F.place(sim, 1, 1.0, 5.0, Fx.HALF_TURN)
	F.step(sim, _dir(S1, 0.0, 1.0))
	assert_eq(sim.fighter(0).facing, Fx.angle_of(10000, 50000), "enemy 11° off the stick: snapped")
	var far := _sim()
	F.place(far, 1, 5.0, 5.0, Fx.HALF_TURN)
	F.step(far, _dir(S1, 0.0, 1.0))
	assert_eq(far.fighter(0).facing, 0, "enemy 45° off the stick: aim stays on the stick")


func test_ground_target_clamps_to_range_and_anchors_effects() -> void:
	var sim := _sim()
	var events := F.step(sim, _point(S2, 10.0, 0.0))
	var f := sim.fighter(0)
	assert_eq(f.move_point, Vector3i(50000, 0, 0))
	assert_eq(f.facing, EAST)
	var spawn: SimEvent = null
	for e in events:
		if e.type == SimEvent.Type.EFFECT_SPAWN:
			spawn = e
	assert_not_null(spawn)
	assert_eq(spawn.position, Vector3i(50000, 0, 0), "TARGET effects land on the aim point")


func test_stick_ground_target_uses_deflection_with_minimum() -> void:
	var sim := _sim()
	F.step(sim, _dir(S2, 0.5, 0.0))
	assert_eq(sim.fighter(0).move_point, Vector3i(30000, 0, 0), "5 m × 0.5 = 2.5 m, raised to 3 m")
	var full := _sim()
	F.step(full, _dir(S2, 1.0, 0.0))
	assert_eq(full.fighter(0).move_point, Vector3i(50000, 0, 0))


func test_no_aim_ground_target_falls_back_to_soft_lock_target() -> void:
	var sim := _sim()
	F.step(sim, S2)
	assert_eq(sim.fighter(0).move_point, Vector3i(0, 0, 30000))


func test_dash_to_stops_on_the_point() -> void:
	var sim := _sim()
	F.step(sim, _point(S3, -3.0, 0.0))
	F.hold(sim, 20)
	var f := sim.fighter(0)
	assert_eq(f.pos, Vector3i(-30000, 0, 0))
	assert_eq(f.action, FighterState.Action.ATTACK, "still in the move, holding position")


func test_dash_to_stops_at_an_enemy_in_front() -> void:
	var data := _fighter()
	(data.moves[2] as MoveData).motions[0].stop_at_distance = 1.5
	var sim := F.fighting_sim(F.config(2, data))
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, 3.0, Fx.HALF_TURN)
	F.step(sim, _point(S3, 0.0, 6.0))
	F.hold(sim, 20)
	var z := sim.fighter(0).pos.z
	assert_true(z >= 15000 and z < 20000, "stopped within 1.5 m of the enemy: z=%d" % z)


func test_leap_arrives_on_the_point_at_the_end_of_its_motion() -> void:
	var sim := _sim()
	F.step(sim, _point(S4, 0.0, -5.0))
	F.hold(sim, 16)
	var f := sim.fighter(0)
	assert_eq(f.move_frame, 17)
	assert_eq(Vector2i(f.pos.x, f.pos.z), Vector2i(0, -50000))
	F.hold(sim, 3)
	assert_eq(Vector2i(f.pos.x, f.pos.z), Vector2i(0, -50000), "no drift after the motion ends")


func test_teleport_to_aim_point() -> void:
	var sim := _sim()
	F.step(sim, _point(S5, 2.0, -2.0))
	F.step(sim)
	assert_eq(sim.fighter(0).pos, Vector3i(20000, 0, -20000))


func test_hard_lock_overrides_aim() -> void:
	var sim := _sim()
	F.step(sim, SimInput.LOCK)
	F.step(sim)
	F.step(sim, _point(S1, 4.0, 0.0))
	assert_eq(sim.fighter(0).facing, 0, "locked: faces the target, not the cursor")


func test_auto_moves_ignore_aim() -> void:
	var sim := _sim()
	F.step(sim, _point(S6, 4.0, 0.0))
	assert_eq(sim.fighter(0).facing, 0, "legacy AUTO moves face the soft-lock target")


func test_replay_keeps_aim_frames_through_save_and_load() -> void:
	var config := F.config(2, _fighter())
	var sim := Sim.new(config)
	var replay := Replay.create(config)
	for t in 240:
		var inputs := PackedInt64Array([0, 0])
		if t >= 100 and t % 40 == 0:
			inputs[0] = _point(SimInput.SKILLS[(t / 40) % 6], 3.0 - t * 0.01, -2.0)
		sim.step(inputs)
		replay.record(inputs, sim.checksum(), true)
	var path := "user://test_aim_replay.res"
	assert_eq(ResourceSaver.save(replay, path), OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Replay
	assert_eq(loaded.frames, replay.frames)
	assert_eq(loaded.format_version, Replay.FORMAT_VERSION)
	assert_eq(loaded.verify(), -1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
