extends TestCase
## Versus through the real match screen with a CPU Aldric (skill kit): against an idle human
## slot, and in attract mode against a CPU on an old kit. The runner records 64-bit frames,
## so the CPU's aim reaches the sim.

const MATCH_SCENE := preload("res://ui/match/match_screen.tscn")

var screen: MatchScreen


func after_each() -> void:
	if is_instance_valid(screen):
		screen.free()
	GameFlow.current_match = null


func test_cpu_aldric_beats_an_idle_player() -> void:
	var config := MatchConfig.versus(&"morrigan", &"aldric", &"ashen_chapel", MatchConfig.Difficulty.NORMAL)
	config.rounds_to_win = 1
	await _play(config)
	assert_true(screen.is_finished(), "the match ended")
	assert_eq(screen.runner.sim.state.winner_team, 1, "the CPU Aldric wins")
	assert_true(_aimed_frames(1) > 0, "the CPU's frames carry an aim")


func test_attract_cpu_aldric_against_an_old_kit() -> void:
	var config := MatchConfig.versus(&"aldric", &"gorrath", &"drowned_crypt", MatchConfig.Difficulty.HARD)
	config.rounds_to_win = 1
	config.attract = true
	await _play(config)
	assert_true(screen.is_finished(), "the match ended")
	assert_eq(screen.runner.replay.verify(), -1, "the recorded replay reproduces the match")


func _play(config: MatchConfig) -> void:
	GameFlow.current_match = config
	screen = MATCH_SCENE.instantiate()
	host.add_child(screen)
	await wait_frames(1)
	screen.runner.paused = true
	for i in 12000:
		if screen.is_finished():
			break
		screen.runner.step_once()


func _aimed_frames(slot: int) -> int:
	var replay := screen.runner.replay
	var count := 0
	for i in replay.tick_count():
		if SimInput.has_aim(replay.frame(i, slot)):
			count += 1
	return count
