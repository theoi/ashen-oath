extends TestCase
## The fight presentation on a real match: Aldric vs a Hollowed in the Ashen Chapel driven by
## sparring CPUs for 40 seconds of sim time, so every pose branch and event handler runs
## (hits, blocks, launches, knockdowns, supers, effects, KOs, round resets). Any logged error
## fails the test.

const ALDRIC := "res://content/fighters/aldric/aldric.tres"
const HOLLOWED := "res://content/fighters/hollowed/hollowed.tres"


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


func test_every_fighter_move_names_an_existing_clip() -> void:
	for path: String in [ALDRIC, HOLLOWED]:
		var data: FighterData = load(path)
		for move in data.moves:
			assert_true(move.animation == &"" or FighterClips.has(move.animation), "%s: clip %s" % [move.id, move.animation])


func test_attack_clip_reaches_its_impact_on_the_first_active_frame() -> void:
	var data: FighterData = load(ALDRIC)
	for move in data.moves:
		var clip := FighterPoser.attack_clip(move)
		var at_impact := FighterPoser.attack_time(move, clip, float(move.startup - 1))
		assert_almost_eq(at_impact, minf(FighterClips.impact(clip), FighterClips.length(clip)), 0.001, String(move.id))
		var last := FighterPoser.attack_time(move, clip, float(move.total_frames()))
		assert_true(last <= FighterClips.length(clip) + 0.0001, "%s stays inside its clip" % move.id)
