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
	assert_true(FightFx.WEIGHT_SHAKE[5] > FightFx.WEIGHT_SHAKE[3])
	assert_true(FightFx.WEIGHT_SHAKE[3] > FightFx.WEIGHT_SHAKE[1])
	var e := SimEvent.new()
	e.hitstop = 14
	assert_eq(FightFx.weight_of(e), 5)
	e.hitstop = 3
	assert_eq(FightFx.weight_of(e), 1)


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
