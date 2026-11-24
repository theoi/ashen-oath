extends TestCase
## Difficulty ordering: over a fixed set of seeded AI-vs-AI matches (sides swapped every other
## match), each level beats the one below it in a clear majority. Longer runs: tools/ai_soak.sh.

const A := preload("res://tests/ai/ai_fixtures.gd")
const MATCHES := 8
const NEEDED := 6


func _wins(strong: int, weak: int) -> int:
	var wins := 0
	for m in MATCHES:
		var cfg := A.config([0, 1], 300 + m, 45)
		var levels: Array[int] = [strong, weak]
		if m % 2 == 1:
			levels = [weak, strong]
		var bout := A.bout(cfg, levels)
		var strong_team := 0 if m % 2 == 0 else 1
		if bout.winner_team == strong_team:
			wins += 1
	return wins


func test_nightmare_beats_easy() -> void:
	var wins := _wins(AiDifficulty.Level.NIGHTMARE, AiDifficulty.Level.EASY)
	assert_true(wins >= NEEDED, "nightmare won %d of %d" % [wins, MATCHES])


func test_nightmare_beats_hard() -> void:
	var wins := _wins(AiDifficulty.Level.NIGHTMARE, AiDifficulty.Level.HARD)
	assert_true(wins >= NEEDED, "nightmare won %d of %d" % [wins, MATCHES])


func test_hard_beats_normal() -> void:
	var wins := _wins(AiDifficulty.Level.HARD, AiDifficulty.Level.NORMAL)
	assert_true(wins >= NEEDED, "hard won %d of %d" % [wins, MATCHES])


func test_normal_beats_easy() -> void:
	var wins := _wins(AiDifficulty.Level.NORMAL, AiDifficulty.Level.EASY)
	assert_true(wins >= NEEDED, "normal won %d of %d" % [wins, MATCHES])
