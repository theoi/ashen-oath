extends TestCase
## Sim cost budget (design §8): one tick for 3-4 fighters well under 1 ms, so an 8-frame
## rollback fits in a frame later. Measured headless on random brawls with the test fighter.
## Prints the numbers; asserts generous ceilings so slow CI machines don't flake.

const F := preload("res://tests/sim/sim_fixtures.gd")
const TICKS := 3000


func test_tick_cost_for_3_and_4_fighters() -> void:
	for count: int in [3, 4]:
		var stats := measure(count, TICKS, 21)
		print("    sim bench %d fighters: mean %.3f ms/tick, p99 %.3f ms, max %.3f ms, snapshot+restore %.3f ms, checksum %.3f ms, %d hits" % [
				count, stats["mean"], stats["p99"], stats["max"], stats["snapshot"], stats["checksum"], stats["hits"]])
		assert_true(stats["mean"] < 1.0, "%d fighters: mean tick %.3f ms over budget" % [count, stats["mean"]])
		# Loose: CI runners and this shared machine have scheduling spikes.
		assert_true(stats["p99"] < 5.0, "%d fighters: p99 tick %.3f ms" % [count, stats["p99"]])


## Runs `ticks` random-input ticks (the first 30 as warm-up) and returns timing stats in ms.
static func measure(count: int, ticks: int, seed_value: int) -> Dictionary:
	var cfg := F.config(count, F.test_fighter())
	cfg.round_seconds = 99
	for slot in cfg.slots:
		slot.start_soul = 100
	var sim := Sim.new(cfg)
	var bots: Array[DebugBot] = []
	for slot in count:
		bots.append(DebugBot.new(seed_value + slot))
	var inputs := PackedInt32Array()
	inputs.resize(count)
	var costs := PackedFloat64Array()
	var hits := 0
	for t in ticks:
		for slot in count:
			inputs[slot] = bots[slot].next_frame(sim, slot)
		var start := Time.get_ticks_usec()
		var events := sim.step(inputs)
		if t < 30:
			continue
		costs.append((Time.get_ticks_usec() - start) / 1000.0)
		for e in events:
			if e.type == SimEvent.Type.HIT:
				hits += 1
	var snap_start := Time.get_ticks_usec()
	for _i in 100:
		var snap := sim.snapshot()
		sim.restore(snap)
	var snap_cost := (Time.get_ticks_usec() - snap_start) / 100000.0
	var sum_start := Time.get_ticks_usec()
	for _i in 100:
		sim.checksum()
	var sum_cost := (Time.get_ticks_usec() - sum_start) / 100000.0
	var total := 0.0
	for c in costs:
		total += c
	var sorted := costs.duplicate()
	sorted.sort()
	return {
		"mean": total / costs.size(),
		"p99": sorted[int(costs.size() * 0.99)],
		"max": sorted[costs.size() - 1],
		"snapshot": snap_cost,
		"checksum": sum_cost,
		"hits": hits,
	}
