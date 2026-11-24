extends TestCase
## Golden replay: a recorded bot brawl must reproduce every per-tick checksum. A failure
## means outcomes changed (intended: regenerate with tools/gen_golden_replay.gd and say so;
## unintended: a determinism or logic regression).


func test_golden_replay_reproduces_every_tick() -> void:
	var replay := load("res://tests/sim/golden/bot_brawl.res") as Replay
	assert_not_null(replay)
	assert_eq(replay.tick_count(), 1800)
	assert_eq(replay.checksums.size(), 1800)
	var mismatch := replay.verify()
	assert_eq(mismatch, -1, "first differing tick: %d" % mismatch)
