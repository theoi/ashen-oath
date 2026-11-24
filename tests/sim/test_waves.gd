extends TestCase
## Story waves: extra combatant slots, spawning, rising, wave advance, slot reuse,
## checkpoints, HP overrides and the spawn API.

const F := preload("res://tests/sim/sim_fixtures.gd")
const K := preload("res://tests/sim/test_skill_kit.gd")
const Action := FighterState.Action
const T := SimEvent.Type

var grunt: FighterData
var brute: FighterData


func before_each() -> void:
	grunt = F.fighter()
	grunt.id = &"grunt"
	brute = F.fighter()
	brute.id = &"brute"
	brute.radius = 0.6


static func _entry(data: FighterData, count: int) -> WaveEntry:
	var entry := WaveEntry.new()
	entry.fighter = data
	entry.count = count
	return entry


static func _wave(entries: Array[WaveEntry], advance_alive: int = 1, advance_frames: int = 0) -> WaveData:
	var wave := WaveData.new()
	wave.entries = entries
	wave.advance_alive = advance_alive
	wave.advance_frames = advance_frames
	return wave


func _config(waves: Array[WaveData], wave_slots: int = -1) -> SimConfig:
	var cfg := F.config(1, K.kit())
	cfg.waves = waves
	cfg.wave_slots = wave_slots
	return cfg


## Steps until the event happens (or `limit` ticks); returns the ticks' events.
static func _until(sim: Sim, type: SimEvent.Type, limit: int = 400) -> Array[Array]:
	var ticks: Array[Array] = []
	for i in limit:
		var events := F.step(sim)
		ticks.append(events)
		for e in events:
			if e.type == type:
				return ticks
	return ticks


static func _events(ticks: Array[Array], type: SimEvent.Type) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for events in ticks:
		for e: SimEvent in events:
			if e.type == type:
				out.append(e)
	return out


func _two_waves() -> Array[WaveData]:
	var waves: Array[WaveData] = [_wave([_entry(grunt, 3)]), _wave([_entry(brute, 2)])]
	return waves


func test_wave_slots_start_free() -> void:
	var cfg := _config(_two_waves())
	assert_eq(cfg.total_slots(), 8)
	assert_eq(Replay.create(cfg).slot_count, 8)
	var sim := Sim.new(cfg)
	assert_eq(sim.slot_count(), 8)
	for slot in range(1, 8):
		var f := sim.fighter(slot)
		assert_false(f.active)
		assert_true(f.ko)
	assert_eq(F.config(2).total_slots(), 2, "no waves, no extra slots")


func test_first_wave_spawns_rising_and_invincible() -> void:
	var sim := Sim.new(_config(_two_waves()))
	var ticks := _until(sim, T.FIGHT)
	ticks.append_array(F.play(sim, [], [], 1))
	assert_eq(_events(ticks, T.WAVE_START).size(), 1)
	var spawns := _events(ticks, T.SPAWN)
	assert_eq(spawns.size(), 3)
	assert_eq(spawns[0].source, 1)
	assert_eq(spawns[0].id, &"grunt")
	var f := sim.fighter(1)
	assert_true(f.active)
	assert_eq(f.team, 1)
	assert_eq(f.wave, 0)
	assert_eq(f.action, Action.SPAWN)
	assert_true(sim.is_invulnerable(f))
	F.hold(sim, sim.rules.spawn_rise_frames + 1)
	assert_eq(f.action, Action.IDLE)
	assert_false(sim.is_invulnerable(f))


func test_next_wave_when_one_is_left_and_corpses_free_their_slots() -> void:
	var sim := F.fighting_sim(_config(_two_waves()))
	F.step(sim)
	sim._ko(sim.fighter(1))
	sim._ko(sim.fighter(2))
	var ticks := F.play(sim, [], [], 2)
	assert_eq(sim.state.wave_index, 2, "wave 1 (the last) has spawned")
	var spawns := _events(ticks, T.SPAWN)
	assert_eq(spawns.size(), 2)
	assert_eq(spawns[0].source, 4, "slots 1 and 2 still hold corpses")
	assert_eq(sim.fighter_data[4].id, &"brute")
	assert_eq(sim.state.phase, SimState.Phase.FIGHT, "no round end between waves")
	ticks = F.play(sim, [], [], sim.rules.wave_corpse_frames + 2)
	var gone := _events(ticks, T.DESPAWN)
	assert_eq(gone.size(), 2)
	assert_false(sim.fighter(1).active)


func test_freed_slots_are_reused_and_rebound_on_rollback() -> void:
	var waves: Array[WaveData] = [_wave([_entry(grunt, 2)], 0), _wave([_entry(brute, 1)])]
	var sim := F.fighting_sim(_config(waves, 2))
	assert_eq(sim.slot_count(), 3)
	F.step(sim)
	sim._ko(sim.fighter(1))
	sim._ko(sim.fighter(2))
	F.step(sim)
	var before := sim.snapshot()
	var ticks := _until(sim, T.SPAWN)
	assert_eq(_events(ticks, T.SPAWN)[0].source, 1, "waits for a free slot")
	assert_eq(sim.fighter_data[1].id, &"brute")
	assert_eq(sim.fighter(1).wave, 1)
	sim.restore(before)
	assert_eq(sim.fighter_data[1].id, &"grunt", "restore rebinds the slot's data")


func test_last_wave_cleared_wins_the_round() -> void:
	var waves: Array[WaveData] = [_wave([_entry(grunt, 1)], 0)]
	var sim := F.fighting_sim(_config(waves))
	F.step(sim)
	assert_eq(sim.state.wave_index, 1, "the last wave is done once it has spawned")
	sim._ko(sim.fighter(1))
	F.step(sim)
	assert_eq(sim.state.phase, SimState.Phase.ROUND_END)
	assert_eq(sim.state.round_winner, 0)


func test_wave_timer_and_checkpoint() -> void:
	var waves: Array[WaveData] = [_wave([_entry(grunt, 1)], 0, 100), _wave([_entry(brute, 1)])]
	var sim := F.fighting_sim(_config(waves))
	F.hold(sim, 99)
	assert_eq(sim.state.wave_index, 1, "advanced after 100 frames with the grunt alive")
	var cfg := _config(waves)
	cfg.start_wave = 1
	sim = Sim.new(cfg)
	var ticks := _until(sim, T.WAVE_START)
	assert_eq(_events(ticks, T.WAVE_START)[0].amount, 1, "checkpoint: starts at wave 1")


func test_hp_overrides() -> void:
	var boss := _entry(brute, 1)
	boss.hp_override = 2600
	boss.stagger_max = 600
	var waves: Array[WaveData] = [_wave([boss])]
	var cfg := _config(waves)
	cfg.slots[0].hp_override = 1500
	var sim := F.fighting_sim(cfg)
	assert_eq(sim.fighter(0).max_hp, 1500)
	assert_eq(sim.fighter(1).max_hp, 2600)
	assert_eq(sim.fighter(1).hp, 2600)
	assert_eq(sim.fighter(1).stagger, 600)


func test_spawn_fighter_api_fills_free_slots_then_refuses() -> void:
	var cfg := F.config(2, K.kit())
	cfg.wave_slots = 2
	var sim := F.fighting_sim(cfg)
	var add := _entry(grunt, 1)
	assert_eq(sim.spawn_fighter(add).slot, 2)
	assert_eq(sim.spawn_fighter(add).slot, 3)
	assert_null(sim.spawn_fighter(add))
	assert_eq(sim.fighter(3).team, 1)
	F.step(sim)
	assert_eq(sim.state.phase, SimState.Phase.FIGHT)


func test_wave_fights_are_deterministic_through_rollback() -> void:
	var bots: Array[DebugBot] = []
	for slot in 8:
		bots.append(DebugBot.new(5 + slot))
	var cfg := _config(_two_waves())
	cfg.round_seconds = 99
	var a := Sim.new(cfg)
	var b := Sim.new(cfg)
	var inputs := PackedInt32Array()
	inputs.resize(8)
	var saved: SimState = null
	var saved_inputs: Array[PackedInt32Array] = []
	for t in 900:
		for slot in 8:
			inputs[slot] = bots[slot].next_frame(a, slot)
		if t == 300:
			saved = a.snapshot()
		if t >= 300:
			saved_inputs.append(inputs.duplicate())
		a.step(inputs)
	b.restore(saved)
	for frame in saved_inputs:
		b.step(frame)
	assert_eq(b.checksum(), a.checksum())
