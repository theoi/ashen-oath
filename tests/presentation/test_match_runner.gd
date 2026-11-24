extends TestCase
## MatchRunner steps the sim on physics ticks and records a replay that reproduces it.

const F := preload("res://tests/sim/sim_fixtures.gd")


func test_runner_steps_on_physics_ticks_and_records() -> void:
	var runner := MatchRunner.new()
	add_child_autofree(runner)
	var cfg := F.config(2)
	var walk := ScriptedInputSource.new(PackedInt32Array([SimInput.make(0, 127, 0)]), true)
	var sources: Array[InputSource] = [walk, null]
	runner.start(cfg, sources)
	runner.record_checksums = true
	var seen: Array[int] = []
	runner.stepped.connect(func(_events: Array[SimEvent]) -> void: seen.append(runner.sim.state.tick))
	await wait_physics_frames(5)
	assert_true(seen.size() >= 4, "stepped %d times" % seen.size())
	assert_eq(runner.replay.tick_count(), runner.sim.state.tick)
	assert_eq(runner.replay.verify(), -1)
	assert_true(runner.fighter_position(0).is_finite())
