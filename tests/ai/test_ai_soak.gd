extends TestCase
## Short soak: CPU matches on the slice arenas (hazards included) and in 1v2 finish without
## stuck states, and the CPU actually fights (hits, guards, uses abilities). Engine errors
## fail the test through the runner. Long soaks: tools/ai_soak.sh.

const A := preload("res://tests/ai/ai_fixtures.gd")
const E := AiDifficulty.Level.EASY
const N := AiDifficulty.Level.NORMAL
const H := AiDifficulty.Level.HARD
const X := AiDifficulty.Level.NIGHTMARE


func _check(bout: AiBout, label: String) -> void:
	assert_true(bout.finished, "%s: match ended (%d ticks)" % [label, bout.ticks])
	assert_eq(bout.stuck, PackedStringArray(), "%s: no stuck states" % label)


func test_one_vs_one_on_slice_arenas() -> void:
	var arenas: PackedStringArray = ["ashen_chapel", "drowned_crypt", "drowned_crypt_depths"]
	var pairs: Array[Array] = [[X, H], [N, E], [H, N]]
	var defended := 0
	for i in arenas.size():
		var cfg := A.config([0, 1], 40 + i, 60, 1, "res://content/arenas/%s.tres" % arenas[i])
		var levels: Array[int] = []
		levels.assign(pairs[i])
		var bout := A.bout(cfg, levels)
		_check(bout, arenas[i])
		for slot in 2:
			assert_true(int(bout.stats[slot]["hits"]) > 0, "%s: slot %d lands hits" % [arenas[i], slot])
		for key: String in ["blocks", "parries", "dodges"]:
			defended += bout.team_stat(0, key) + bout.team_stat(1, key)
		assert_true(bout.team_stat(0, "abilities") > 0 and bout.team_stat(1, "abilities") > 0,
				"%s: both use abilities" % arenas[i])
	assert_true(defended > 10, "the CPUs block, parry and dodge (%d)" % defended)


func test_one_vs_two() -> void:
	var bout := A.bout(A.config([0, 1, 1], 21, 60, 1, "res://content/arenas/ashen_chapel.tres"), [H, N, N])
	_check(bout, "1v2")
	assert_true(int(bout.stats[1]["hits"]) > 0 and int(bout.stats[2]["hits"]) > 0, "both enemies get turns")


func test_one_attacker_at_a_time_in_one_vs_two() -> void:
	var cfg := A.config([0, 1, 1], 8, 40)
	var sources := A.sources(cfg, [-1, N, N])
	var sim := Sim.new(cfg)
	var both := 0
	var attacking := PackedInt32Array([0, 0, 0])
	var inputs := PackedInt64Array([0, 0, 0])
	while not sim.is_over() and sim.state.tick < 4000:
		for slot in range(1, 3):
			inputs[slot] = sources[slot].next_frame(sim, slot)
		sim.step(inputs)
		var count := 0
		for slot in range(1, 3):
			if sim.fighter(slot).action == FighterState.Action.ATTACK:
				count += 1
				attacking[slot] += 1
		if count == 2:
			both += 1
	assert_true(sim.fighter(0).ko, "the pair beats a standing dummy")
	assert_eq(both, 0, "never two attackers at once with one token")
	assert_true(attacking[1] > 0 and attacking[2] > 0, "the token rotates: %s" % attacking)


func test_match_setup_cpu_drives_any_slot() -> void:
	# Story playthroughs drive the player's slot 0 with the CPU too.
	var config := MatchConfig.versus(&"aldric", &"hollowed", &"ashen_chapel", MatchConfig.Difficulty.NIGHTMARE)
	config.rounds_to_win = 1
	config.round_seconds = 60
	var cfg := MatchSetup.sim_config(config)
	var cpu := MatchSetup.cpu_source(config, 0) as AiInputSource
	assert_not_null(cpu)
	assert_eq(cpu.difficulty.level, X)
	var sources: Array[InputSource] = [cpu, null]
	var bout := AiBout.new(cfg, sources).run()
	assert_eq(bout.winner_team, 0, "the CPU in slot 0 beats a standing opponent")
	config.ai_cap = E
	assert_eq((MatchSetup.cpu_source(config, 1) as AiInputSource).difficulty.level, E, "ai_cap applies")


func test_nightmare_crowd_gets_two_tokens() -> void:
	var sources := AiInputSource.for_match(A.config([0, 1, 1], 1), PackedInt32Array([1, 2]), X)
	assert_null(sources[0])
	var a := sources[1] as AiInputSource
	var b := sources[2] as AiInputSource
	assert_true(a.tokens != null and a.tokens == b.tokens, "teammates share tokens")
	assert_eq(a.tokens.capacity, 2)
	var capped := AiInputSource.for_match(A.config([0, 1], 1), PackedInt32Array([1]), X, E)
	assert_eq((capped[1] as AiInputSource).difficulty.level, E, "story cap keeps fight 1 at Easy")
	assert_null((capped[1] as AiInputSource).tokens, "a lone CPU is not throttled by tokens")
