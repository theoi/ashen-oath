extends TestCase
## The CPU in story-style fights (sim waves, design-lost-ark 5.4 and 5.8): every wave slot gets
## a CPU source, wave enemies share the wave attack tokens across the whole field, slots that
## respawn as other fighters are read afresh, and Hard breaks a channel-break gauge.

const F := preload("res://tests/sim/sim_fixtures.gd")
const T := SimEvent.Type
const ALDRIC := "res://content/fighters/aldric/aldric.tres"
const HOLLOWED := "res://content/fighters/hollowed/hollowed.tres"


func _wave_config(waves: int, size: int, seed_value: int, fighters: Array[String] = [HOLLOWED]) -> SimConfig:
	var cfg := SimConfig.new()
	cfg.rules = load("res://content/rules/default_rules.tres")
	cfg.arena = load("res://content/arenas/ashen_chapel.tres")
	cfg.seed = seed_value
	cfg.rounds_to_win = 1
	var player := SlotConfig.new()
	player.fighter = load(ALDRIC)
	player.team = 0
	# A sturdy player, so every wave gets to spawn.
	player.hp_override = 9000
	cfg.slots.append(player)
	for w in waves:
		var entry := WaveEntry.new()
		entry.fighter = load(fighters[w % fighters.size()])
		entry.count = size
		entry.hp_percent = 30
		entry.interval = 30
		var wave := WaveData.new()
		wave.entries.append(entry)
		cfg.waves.append(wave)
	return cfg


func test_for_match_gives_every_wave_slot_a_cpu_with_wave_tokens() -> void:
	var cfg := _wave_config(2, 3, 1)
	var sources := AiInputSource.for_match(cfg, PackedInt32Array(), AiDifficulty.Level.HARD)
	assert_eq(sources.size(), cfg.total_slots(), "one entry per combatant slot")
	assert_null(sources[0], "the player's slot stays human")
	var pools: Array[AiAttackTokens] = []
	for slot in range(1, sources.size()):
		var ai := sources[slot] as AiInputSource
		assert_not_null(ai, "wave slot %d has a CPU" % slot)
		if ai != null and not pools.has(ai.team_tokens.get(1)):
			pools.append(ai.team_tokens.get(1))
	assert_eq(pools.size(), 1, "one shared pool for the wave team")
	assert_eq(pools[0].capacity, AiDifficulty.preset(AiDifficulty.Level.HARD).wave_attack_tokens)


func test_waves_play_out_with_shared_tokens() -> void:
	# Waves alternate fighters, so slots respawn as another fighter.
	var cfg := _wave_config(3, 3, 2, [HOLLOWED, ALDRIC])
	var sources := AiInputSource.for_match(cfg, PackedInt32Array([0]), AiDifficulty.Level.HARD)
	var pool: AiAttackTokens = (sources[1] as AiInputSource).team_tokens.get(1)
	var sim := Sim.new(cfg)
	var inputs := PackedInt64Array()
	inputs.resize(sim.slot_count())
	var spawns := 0
	var most_holders := 0
	while not sim.is_over() and sim.state.tick < 15000:
		for slot in sim.slot_count():
			inputs[slot] = sources[slot].next_frame(sim, slot)
		for e in sim.step(inputs):
			if e.type == T.SPAWN:
				spawns += 1
		most_holders = maxi(most_holders, pool.holder_count())
	assert_true(sim.is_over(), "the fight ends (tick %d)" % sim.state.tick)
	assert_eq(spawns, 9, "every wave member spawned")
	assert_true(most_holders >= 2 and most_holders <= pool.capacity,
			"wave enemies share %d tokens (most held at once: %d)" % [pool.capacity, most_holders])


func test_hard_breaks_a_channel_gauge() -> void:
	var boss := (load(HOLLOWED) as FighterData).duplicate() as FighterData
	boss.moves = boss.moves.duplicate()
	var index := boss.find_move(boss.heavy)
	var special := boss.moves[index].duplicate() as MoveData
	special.startup = 80
	special.channel_gauge = 40
	special.channel_start = 1
	special.channel_end = 76
	# Boss specials are push immune, so only the gauge stops them.
	special.push_immune_start = 1
	special.push_immune_end = 80
	boss.moves[index] = special
	var cfg := F.config(2, load(ALDRIC))
	cfg.slots[1].fighter = boss
	var sim := F.fighting_sim(cfg)
	F.place(sim, 0, 0.0, 0.0, 0)
	F.place(sim, 1, 0.0, 3.0, Fx.HALF_TURN)
	sim.start_move(sim.fighter(1), index)
	var ai := AiInputSource.new(AiDifficulty.preset(AiDifficulty.Level.HARD))
	var broke := false
	for _t in 80:
		for e in F.step(sim, ai.next_frame(sim, 0)):
			if e.type == T.CHANNEL_BREAK and e.source == 0:
				broke = true
		if broke:
			break
	assert_true(broke, "Hard Aldric empties the gauge before the special fires")
	assert_true(int(ai.counters.get("channel_breaks", 0)) > 0)
