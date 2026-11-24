extends TestCase
## The fight presentation on a real match: Aldric vs a Hollowed in the Ashen Chapel driven by
## sparring CPUs for 40 seconds of sim time, so every pose branch and event handler runs
## (hits, blocks, launches, knockdowns, supers, effects, KOs, round resets). Any logged error
## fails the test.

const ALDRIC := "res://content/fighters/aldric/aldric.tres"
const HOLLOWED := "res://content/fighters/hollowed/hollowed.tres"
const MORRIGAN := "res://content/fighters/morrigan/morrigan.tres"
const GORRATH := "res://content/fighters/gorrath/gorrath.tres"
const OATH_SHADE := "res://content/fighters/oath_shade/oath_shade.tres"
const ALL: Array[String] = [ALDRIC, MORRIGAN, GORRATH, HOLLOWED, OATH_SHADE]


func _config(p1: String, p2: String) -> SimConfig:
	var config := SimConfig.new()
	config.rules = load("res://content/rules/default_rules.tres")
	config.arena = load("res://content/arenas/ashen_chapel.tres")
	config.seed = 3
	for path: String in [p1, p2]:
		var slot := SlotConfig.new()
		slot.fighter = load(path)
		slot.team = config.slots.size()
		slot.start_soul = 100
		config.slots.append(slot)
	return config


func test_fight_view_runs_a_match_without_errors() -> void:
	var fight := FightView.new()
	add_child_autofree(fight)
	var sources: Array[InputSource] = [SparringInputSource.new(11), SparringInputSource.new(29)]
	fight.start(_config(ALDRIC, HOLLOWED), sources)
	fight.runner.paused = true
	var seen := {}
	for t in 2400:
		for e in fight.runner.sim.events():
			seen[e.type] = true
		fight.runner.step_once()
		if t % 6 == 0:
			await wait_frames(1)
		if fight.runner.sim.is_over():
			break
	for type: SimEvent.Type in [SimEvent.Type.HIT, SimEvent.Type.SUPER_FLASH, SimEvent.Type.EFFECT_SPAWN]:
		assert_true(seen.has(type), "match produced %s" % SimEvent.Type.keys()[type])
	assert_eq(fight.views.size(), 2)
	assert_not_null(fight.views[0].model.skeleton, "Aldric's model loaded")


func test_morrigan_and_gorrath_fight_without_errors() -> void:
	var fight := FightView.new()
	add_child_autofree(fight)
	var sources: Array[InputSource] = [SparringInputSource.new(5), SparringInputSource.new(17)]
	fight.start(_config(MORRIGAN, GORRATH), sources)
	fight.runner.paused = true
	var seen := {}
	for t in 1500:
		for e in fight.runner.sim.events():
			seen[e.type] = true
		fight.runner.step_once()
		if t % 6 == 0:
			await wait_frames(1)
		if fight.runner.sim.is_over():
			break
	assert_true(seen.has(SimEvent.Type.HIT), "the match produced hits")
	assert_true(seen.has(SimEvent.Type.EFFECT_SPAWN), "the match produced effects")
	for i in 2:
		assert_not_null(fight.views[i].model.skeleton, "fighter %d's model loaded" % i)
	assert_eq(fight.views[0].model.name, &"Morrigan")
	assert_eq(fight.views[1].model.name, &"Gorrath")


func _still_fight() -> FightView:
	var fight := FightView.new()
	add_child_autofree(fight)
	var sources: Array[InputSource] = [ScriptedInputSource.new(), ScriptedInputSource.new()]
	fight.start(_config(ALDRIC, HOLLOWED), sources)
	fight.runner.paused = true
	SimFixtures.skip_intro(fight.runner.sim)
	return fight


func _settle(fight: FightView, frames: int = 240) -> void:
	fight.runner.step_once()
	for _i in frames:
		fight.camera._process(1.0 / 60.0)


func test_camera_is_high_with_a_fixed_yaw() -> void:
	var fight := _still_fight()
	SimFixtures.place(fight.runner.sim, 0, -3.0, 0.0, Fx.deg(90.0))
	SimFixtures.place(fight.runner.sim, 1, 3.0, 0.0, Fx.deg(-90.0))
	_settle(fight)
	var forward := -fight.camera.global_basis.z
	var pitch := rad_to_deg(asin(-forward.y))
	assert_almost_eq(pitch, rad_to_deg(Feel.camera_pitch()), 1.0, "pitch")
	var yaw_before := atan2(forward.x, forward.z)
	# The fighters swap sides: the camera does not orbit after them.
	SimFixtures.place(fight.runner.sim, 0, 3.0, 2.0, Fx.deg(-90.0))
	SimFixtures.place(fight.runner.sim, 1, -3.0, -2.0, Fx.deg(90.0))
	_settle(fight)
	forward = -fight.camera.global_basis.z
	assert_almost_eq(atan2(forward.x, forward.z), yaw_before, 0.001, "yaw stays fixed")
	assert_almost_eq(fight.camera.fov, Feel.camera_fov(), 0.5, "fov")


func test_camera_keeps_both_fighters_in_frame_and_settles_back() -> void:
	var fight := _still_fight()
	# The headless test viewport is square, so the split is narrower than on a 16:9 screen.
	SimFixtures.place(fight.runner.sim, 0, -4.0, -3.0, 0)
	SimFixtures.place(fight.runner.sim, 1, 4.0, 4.0, Fx.HALF_TURN)
	_settle(fight, 360)
	var rect := fight.camera.get_viewport().get_visible_rect()
	for slot in 2:
		var p := fight.runner.fighter_position(slot) + Vector3.UP
		assert_true(fight.camera.is_position_in_frustum(p), "fighter %d on screen" % slot)
		var s := fight.camera.unproject_position(p) / rect.size
		assert_true(s.x > 0.08 and s.x < 0.92 and s.y > 0.08 and s.y < 0.92, "fighter %d inside the frame (%s)" % [slot, s])
	var far := fight.camera._distance
	assert_true(far > Feel.camera_distance(), "pulled back for a wide split (%.1f m)" % far)
	SimFixtures.place(fight.runner.sim, 0, 0.0, 0.0, 0)
	SimFixtures.place(fight.runner.sim, 1, 0.0, 2.0, Fx.HALF_TURN)
	_settle(fight, 360)
	assert_almost_eq(fight.camera._distance, Feel.camera_distance(), 0.3, "back to the resting distance")


func test_every_fighter_move_names_an_existing_clip() -> void:
	for path in ALL:
		var data: FighterData = load(path)
		for move in data.moves:
			assert_true(move.animation == &"" or FighterClips.has(move.animation), "%s: clip %s" % [move.id, move.animation])


func test_attack_clip_reaches_its_impact_on_the_first_active_frame() -> void:
	for path in ALL:
		var data: FighterData = load(path)
		for move in data.moves:
			var clip := FighterPoser.attack_clip(move)
			var at_impact := FighterPoser.attack_time(move, clip, float(move.startup - 1))
			assert_almost_eq(at_impact, minf(FighterClips.impact(clip), FighterClips.length(clip)), 0.001, String(move.id))
			var last := FighterPoser.attack_time(move, clip, float(move.total_frames()))
			assert_true(last <= FighterClips.length(clip) + 0.0001, "%s stays inside its clip" % move.id)
