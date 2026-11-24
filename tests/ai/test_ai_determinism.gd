extends TestCase
## CPU matches are deterministic: the same config gives the same inputs and states, and the
## recorded replay reproduces the match tick for tick.

const A := preload("res://tests/ai/ai_fixtures.gd")
const LEVELS: Array[int] = [AiDifficulty.Level.HARD, AiDifficulty.Level.NORMAL]


func test_same_config_plays_the_same_match() -> void:
	var a := A.bout(A.config([0, 1], 11, 30), LEVELS)
	var b := A.bout(A.config([0, 1], 11, 30), LEVELS)
	assert_true(a.ticks > 600, "the match ran (%d ticks)" % a.ticks)
	assert_eq(a.replay.frames, b.replay.frames, "identical input frames")
	assert_eq(a.final_checksum, b.final_checksum)


func test_seed_changes_the_cpu_decisions() -> void:
	var a := A.bout(A.config([0, 1], 11, 30), LEVELS)
	var b := A.bout(A.config([0, 1], 12, 30), LEVELS)
	assert_ne(a.replay.frames, b.replay.frames)


func test_replay_of_a_cpu_match_reproduces_every_checksum() -> void:
	var cfg := A.config([0, 1, 1], 5, 30)
	var bout := AiBout.new(cfg, A.sources(cfg, [AiDifficulty.Level.NIGHTMARE, AiDifficulty.Level.NORMAL,
			AiDifficulty.Level.EASY]))
	bout.record_checksums = true
	bout.run()
	assert_eq(bout.replay.tick_count(), bout.ticks)
	assert_eq(bout.replay.verify(), -1, "replay matches the live match on every tick")
