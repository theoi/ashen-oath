extends TestCase
## Impact presentation (design-lost-ark §1.12): damage numbers, weight-scaled shake,
## presentation-only slow motion that leaves sim results unchanged, and the Hollowed ash
## dissolve on KO.

const ALDRIC := "res://content/fighters/aldric/aldric.tres"
const HOLLOWED := "res://content/fighters/hollowed/hollowed.tres"


func _config() -> SimConfig:
	var config := SimConfig.new()
	config.rules = load("res://content/rules/default_rules.tres")
	config.arena = load("res://content/arenas/ashen_chapel.tres")
	config.seed = 5
	for path: String in [ALDRIC, HOLLOWED]:
		var slot := SlotConfig.new()
		slot.fighter = load(path)
		slot.team = config.slots.size()
		config.slots.append(slot)
	return config


func _fight() -> FightView:
	var fight := FightView.new()
	add_child_autofree(fight)
	var sources: Array[InputSource] = [ScriptedInputSource.new(), ScriptedInputSource.new()]
	fight.start(_config(), sources)
	fight.runner.paused = true
	SimFixtures.skip_intro(fight.runner.sim)
	SimFixtures.place(fight.runner.sim, 0, 0.0, 0.0, 0)
	SimFixtures.place(fight.runner.sim, 1, 0.0, 1.2, Fx.HALF_TURN)
	return fight


func _hit(fight: FightView) -> SimEvent:
	for t in 30:
		var inputs := PackedInt64Array([SimInput.LIGHT if t == 0 else 0, 0])
		var events := fight.runner.sim.step(inputs)
		for e in events:
			fight.runner.event_emitted.emit(e)
			if e.type == SimEvent.Type.HIT:
				return e
	return null


func test_a_hit_shows_its_damage_number() -> void:
	var fight := _fight()
	var hit := _hit(fight)
	assert_not_null(hit)
	var shown := false
	for label in fight.fx.numbers.find_children("*", "Label3D", false, false):
		if (label as Label3D).visible and (label as Label3D).text == str(hit.amount):
			shown = true
	assert_true(shown, "a label shows %d" % hit.amount)


func test_heavier_hits_shake_harder() -> void:
	assert_true(FightFx.WEIGHT_SHAKE[5].x > FightFx.WEIGHT_SHAKE[3].x)
	assert_true(FightFx.WEIGHT_SHAKE[3].x > FightFx.WEIGHT_SHAKE[2].x)
	assert_eq(FightFx.WEIGHT_SHAKE[1].x, 0.0, "basic hits do not shake")
	assert_eq(FightFx.WEIGHT_SHAKE[0].x, 0.0, "ticks do not shake")
	assert_eq(FightFx.WEIGHT_FLASH[0].x, 0.0, "ticks do not flash")
	assert_true(FightFx.WEIGHT_FLASH[5].x > FightFx.WEIGHT_FLASH[4].x)
	var e := SimEvent.new()
	e.hitstop = 14
	assert_eq(FightFx.weight_of(e), 5)
	e.hitstop = 3
	assert_eq(FightFx.weight_of(e), 1)
	e.weight = HitData.Weight.TICK
	assert_eq(FightFx.weight_of(e), FightFx.TICK)


func test_shake_alternates_every_frame_and_decays() -> void:
	var fight := _fight()
	var camera := fight.camera
	camera.shake(0.08, 14)
	var offsets: Array[float] = []
	for _i in 14:
		camera._apply_shake(1.0 / 60.0)
		offsets.append(camera.h_offset + camera.v_offset)
	for i in range(1, 4):
		assert_true(signf(offsets[i]) != signf(offsets[i - 1]), "frame %d flips direction" % i)
	assert_true(absf(offsets[1]) < absf(offsets[0]), "decays")
	assert_true(camera.shake_amplitude() < 0.08 * 0.1, "about gone after its decay frames (%.4f)" % camera.shake_amplitude())
	camera.shake(0.15, 20)
	camera.shake(0.02, 4)
	assert_almost_eq(camera.shake_amplitude(), 0.15, 0.0001, "a weaker shake does not cut a stronger one")


func test_massive_flash_covers_a_quarter_of_the_screen() -> void:
	var fight := _fight()
	fight.camera._process(1.0 / 60.0)
	var at := fight.camera.focus_point()
	var side := fight.fx.flash_size(at, 0.25)
	var d := fight.camera.global_position.distance_to(at)
	var view_h := 2.0 * d * tan(deg_to_rad(fight.camera.fov) * 0.5)
	var aspect := fight.get_viewport().get_visible_rect().size.aspect()
	var lit := side * side * 0.4 / (view_h * view_h * aspect)
	assert_almost_eq(lit, 0.25, 0.01)


func test_cinder_wheel_ticks_roll_into_one_number() -> void:
	var fight := _fight()
	var numbers := fight.fx.numbers
	numbers.show_hit(Vector3.UP, 15, FightFx.TICK, false, false, false, "0>1:cinder_wheel")
	numbers.show_hit(Vector3.UP, 15, FightFx.TICK, false, false, false, "0>1:cinder_wheel")
	numbers.show_hit(Vector3.UP, 15, FightFx.TICK, false, false, false, "0>1:cinder_wheel")
	var shown := 0
	for label in numbers.find_children("*", "Label3D", false, false):
		if (label as Label3D).visible:
			shown += 1
	assert_eq(shown, 1, "one rolling number")
	assert_eq(numbers.rolling_label().text, "45")


func test_numbers_pop_rise_and_fade() -> void:
	var fight := _fight()
	var numbers := fight.fx.numbers
	numbers.show_hit(Vector3.UP, 70, 3, false, false, false, "a")
	var label: Label3D = null
	for l in numbers.find_children("*", "Label3D", false, false):
		if (l as Label3D).visible:
			label = l
	var start := label.global_position.y
	assert_almost_eq(label.scale.x, 1.4, 0.01, "pops in large")
	for _i in 6:
		numbers._process(1.0 / 60.0)
	assert_almost_eq(label.scale.x, 1.0, 0.01, "settles after 6 f")
	assert_almost_eq(label.modulate.a, 1.0, 0.01, "opaque before the last 0.2 s")
	for _i in 36:
		numbers._process(1.0 / 60.0)
	assert_almost_eq(label.global_position.y - start, 0.6, 0.02, "rose 0.6 m over 0.7 s")
	assert_true(label.modulate.a < 0.1, "faded out")


func test_camera_lead_follows_the_device() -> void:
	var device := host.get_tree().root.get_node_or_null(^"ActiveDevice")
	if device == null:
		return
	var before: int = device.get(&"scheme")
	device.set(&"scheme", 0)
	assert_almost_eq(Feel.camera_lead(), 0.5, 0.001, "0.5 m toward the cursor on keyboard + mouse")
	device.set(&"scheme", 2)
	assert_almost_eq(Feel.camera_lead(), 0.0, 0.001, "none on gamepad")
	device.set(&"scheme", before)


func test_slow_motion_slows_the_clock_for_a_number_of_ticks() -> void:
	var fight := _fight()
	fight.runner.slow_motion(0.4, 24)
	assert_almost_eq(Engine.time_scale, 0.4, 0.001)
	for _i in 23:
		fight.runner.step_once()
	assert_true(fight.runner.is_slowed())
	fight.runner.step_once()
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "back to real time after 24 ticks")


func test_slow_motion_does_not_change_sim_results() -> void:
	var a := Sim.new(_config())
	var b := Sim.new(_config())
	var runner := MatchRunner.new()
	add_child_autofree(runner)
	runner.start(_config(), [SparringInputSource.new(3), SparringInputSource.new(4)] as Array[InputSource])
	runner.paused = true
	runner.paused = false
	runner.slow_motion(0.4, 50)
	for _i in 300:
		runner.step_once()
	var plain := MatchRunner.new()
	add_child_autofree(plain)
	plain.start(_config(), [SparringInputSource.new(3), SparringInputSource.new(4)] as Array[InputSource])
	for _i in 300:
		plain.step_once()
	assert_eq(runner.sim.checksum(), plain.sim.checksum())
	assert_almost_eq(Engine.time_scale, 1.0, 0.001)
	assert_not_null(a)
	assert_not_null(b)


func test_pausing_ends_slow_motion() -> void:
	var fight := _fight()
	fight.runner.slow_motion(0.4, 24)
	fight.runner.paused = true
	assert_almost_eq(Engine.time_scale, 1.0, 0.001)


func test_hollowed_burn_to_ash_on_ko() -> void:
	var fight := _fight()
	var view := fight.views[1]
	assert_true(view.model.ash_on_death)
	view.dissolve_to_ash()
	for _i in 60:
		view._update_ash(1.0 / 60.0)
	assert_false(view.model.visible, "gone after the dissolve")
	var round_start := SimEvent.new()
	round_start.type = SimEvent.Type.ROUND_START
	view.on_event(round_start)
	assert_true(view.model.visible, "back for the next round")

func test_slow_enemy_attacks_get_a_red_telegraph() -> void:
	var config := _config()
	config.slots[1].fighter = load("res://content/fighters/gorrath/gorrath.tres")
	var fight := FightView.new()
	add_child_autofree(fight)
	var sources: Array[InputSource] = [ScriptedInputSource.new(), ScriptedInputSource.new()]
	fight.start(config, sources)
	fight.runner.paused = true
	SimFixtures.skip_intro(fight.runner.sim)
	SimFixtures.place(fight.runner.sim, 0, 0.0, 0.0, 0)
	SimFixtures.place(fight.runner.sim, 1, 0.0, 2.0, Fx.HALF_TURN)
	# Gorrath's charged heavy: 22 f of startup, well over the 12 f decal rule.
	fight.runner.sim.step(PackedInt64Array([0, SimInput.HEAVY]))
	for _i in 4:
		fight.runner.sim.step(PackedInt64Array([0, 0]))
	assert_false(fight.runner.sim.telegraphs().is_empty(), "the sim reports the wind-up")
	fight.fx.decals._process(1.0 / 60.0)
	var shown := 0
	for decal in fight.fx.decals.get_children():
		if (decal as MeshInstance3D).visible:
			shown += 1
	assert_true(shown >= 1, "a red decal is on the floor")
