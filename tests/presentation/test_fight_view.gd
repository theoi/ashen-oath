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


func test_camera_swings_around_a_fighter_backed_against_a_wall() -> void:
	var fight := FightView.new()
	add_child_autofree(fight)
	var sources: Array[InputSource] = [ScriptedInputSource.new(), ScriptedInputSource.new()]
	fight.start(_config(ALDRIC, HOLLOWED), sources)
	fight.runner.paused = true
	SimFixtures.skip_intro(fight.runner.sim)
	# Aldric with his back to the east wall (x = 12), the Hollowed toward the centre.
	SimFixtures.place(fight.runner.sim, 0, 11.2, 0.0, Fx.deg(-90.0))
	SimFixtures.place(fight.runner.sim, 1, 8.2, 0.0, Fx.deg(90.0))
	fight.runner.step_once()
	for _i in 240:
		fight.camera._process(1.0 / 60.0)
	var eye := fight.camera.global_position
	var aldric := fight.runner.fighter_position(0)
	assert_false(fight.camera._outside_floor(Vector2(eye.x, eye.z), 0.3), "camera is inside the arena (%s)" % eye)
	var flat := Vector2(eye.x - aldric.x, eye.z - aldric.z).length()
	assert_true(flat > 3.0, "camera keeps its distance from Aldric (%.2f m)" % flat)


func test_camera_moves_so_a_pillar_does_not_hide_the_fighters() -> void:
	var fight := FightView.new()
	add_child_autofree(fight)
	var sources: Array[InputSource] = [ScriptedInputSource.new(), ScriptedInputSource.new()]
	fight.start(_config(ALDRIC, HOLLOWED), sources)
	fight.runner.paused = true
	SimFixtures.skip_intro(fight.runner.sim)
	# The tall pillar at (5, 4.5) stands between Aldric and the Hollowed.
	SimFixtures.place(fight.runner.sim, 0, 1.6, 4.5, Fx.deg(90.0))
	SimFixtures.place(fight.runner.sim, 1, 8.4, 4.5, Fx.deg(-90.0))
	fight.runner.step_once()
	for _i in 240:
		fight.camera._process(1.0 / 60.0)
	var eye := fight.camera.global_position
	for slot in 2:
		var chest := fight.runner.fighter_position(slot) + Vector3.UP
		assert_true(fight.camera._sees(eye, chest), "fighter %d is in view from %s" % [slot, eye])


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
