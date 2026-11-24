extends TestCase
## Determinism: identical inputs give identical states; snapshot/restore and replays
## reproduce a fight exactly.

const F := preload("res://tests/sim/sim_fixtures.gd")
const TICKS := 900


func _config() -> SimConfig:
	var cfg := F.config(3)
	cfg.round_seconds = 10
	return cfg


func _run(sim: Sim, frames: Array[PackedInt32Array], from: int, to: int) -> PackedInt64Array:
	var sums := PackedInt64Array()
	for t in range(from, to):
		sim.step(frames[t])
		sums.append(sim.checksum())
	return sums


func test_same_inputs_give_same_checksums() -> void:
	var frames := F.random_frames(TICKS, 3, 42)
	var a := _run(Sim.new(_config()), frames, 0, TICKS)
	var b := _run(Sim.new(_config()), frames, 0, TICKS)
	assert_eq(a, b)
	var changed := frames.duplicate(true)
	changed[TICKS / 2][1] = SimInput.make(SimInput.JUMP, 50, 0)
	var c := _run(Sim.new(_config()), changed, 0, TICKS)
	assert_ne(a, c, "a different input changes the outcome")


func test_snapshot_restore_round_trips() -> void:
	var frames := F.random_frames(TICKS, 3, 9)
	var sim := Sim.new(_config())
	_run(sim, frames, 0, 300)
	var snap := sim.snapshot()
	var snap_sum := sim.checksum()
	var first := _run(sim, frames, 300, TICKS)
	sim.restore(snap)
	assert_eq(sim.checksum(), snap_sum, "restored state hashes like the snapshot")
	var second := _run(sim, frames, 300, TICKS)
	assert_eq(first, second, "re-simulating after restore gives the same ticks")
	assert_eq(Sim.checksum_of(snap), snap_sum, "running on did not mutate the snapshot")


func test_snapshot_is_independent_copy() -> void:
	var sim := Sim.new(_config())
	var snap := sim.snapshot()
	sim.state.fighters[0].cooldowns[0] = 99
	sim.state.fighters[0].pos.x = 12345
	assert_eq(snap.fighters[0].cooldowns[0], 0)
	assert_ne(snap.fighters[0].pos.x, 12345)


func test_replay_records_and_verifies() -> void:
	var frames := F.random_frames(TICKS, 3, 5)
	var cfg := _config()
	var sim := Sim.new(cfg)
	var replay := Replay.create(cfg)
	for t in TICKS:
		sim.step(frames[t])
		replay.record(frames[t], sim.checksum(), true)
	assert_eq(replay.tick_count(), TICKS)
	assert_eq(replay.verify(), -1, "replay reproduces every checksum")
	replay.frames[600 * 3 + 2] = SimInput.make(SimInput.DODGE, 100, 0)
	assert_true(replay.verify() >= 600, "an edited input is detected as a desync")


func test_replay_survives_save_and_load() -> void:
	var frames := F.random_frames(200, 3, 11)
	var cfg := _config()
	var sim := Sim.new(cfg)
	var replay := Replay.create(cfg)
	for t in 200:
		sim.step(frames[t])
		replay.record(frames[t], sim.checksum(), true)
	var path := "user://test_replay.res"
	assert_eq(ResourceSaver.save(replay, path), OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Replay
	assert_not_null(loaded)
	assert_eq(loaded.verify(), -1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_replay_input_source_drives_a_new_sim() -> void:
	var frames := F.random_frames(300, 3, 3)
	var cfg := _config()
	var sim := Sim.new(cfg)
	var replay := Replay.create(cfg)
	for t in 300:
		sim.step(frames[t])
		replay.record(frames[t])
	var replayed := Sim.new(cfg)
	var sources: Array[InputSource] = []
	for slot in 3:
		sources.append(ReplayInputSource.new(replay, slot))
	for _t in 300:
		var inputs := PackedInt32Array()
		for slot in 3:
			inputs.append(sources[slot].next_frame(replayed, slot))
		replayed.step(inputs)
	assert_eq(replayed.checksum(), sim.checksum())
