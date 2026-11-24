extends TestCase
## A versus match end to end on the real sim: HUD wiring, pause, and the end of the match.

const MATCH_SCENE := preload("res://ui/match/match_screen.tscn")

var screen: MatchScreen
var _finished: Array[MatchResult] = []


func before_each() -> void:
	Engine.time_scale = 1.0


func after_each() -> void:
	host.get_tree().paused = false
	if is_instance_valid(screen):
		screen.free()
	GameFlow.current_match = null
	if GameFlow.match_finished.is_connected(_on_finished):
		GameFlow.match_finished.disconnect(_on_finished)


func test_one_vs_two_hud_follows_the_sim() -> void:
	var config := MatchConfig.versus(&"aldric", &"morrigan", &"ashen_chapel", MatchConfig.Difficulty.NORMAL)
	config.fighters = [&"aldric", &"morrigan", &"gorrath"]
	config.teams = [0, 1, 1]
	config.starting_soul = [0, 0, 50]
	await _open(config)
	var announced := _step_until_fight()
	assert_has(announced, "Round 1")
	assert_has(announced, "Fight")
	await wait_frames(1)

	var hud := screen.hud
	for slot in 3:
		assert_not_null(hud.plate_for(slot), "plate for slot %d" % slot)
	assert_almost_eq(hud.plate_for(2).soul_shown(), 0.5, 0.001, "starting Soul reaches the HUD")
	assert_true(hud.ability_bar().visible, "the player's ability bar is shown")
	var sim := screen.runner.sim
	assert_eq(sim.fighter(0).hp, sim.fighter(0).max_hp)
	assert_almost_eq(hud.plate_for(0).health_shown(), 1.0, 0.001)


func test_pause_stops_the_sim_and_resume_continues() -> void:
	await _open(MatchConfig.versus(&"aldric", &"morrigan", &"ashen_chapel", MatchConfig.Difficulty.NORMAL))
	await wait_physics_frames(3)
	screen.pause()
	await wait_frames(1)
	assert_true(host.get_tree().paused)
	var tick := screen.runner.sim.state.tick
	await wait_physics_frames(4)
	assert_eq(screen.runner.sim.state.tick, tick, "no ticks while paused")
	var focus := host.get_viewport().gui_get_focus_owner()
	assert_not_null(focus, "pause menu has focus for gamepad use")
	assert_eq(String(focus.name) if focus != null else "", "Resume")

	_press(&"ui_cancel")
	await wait_frames(1)
	assert_false(screen.is_paused(), "back on the pause menu resumes")
	await wait_physics_frames(3)
	assert_true(screen.runner.sim.state.tick > tick, "ticks resume")


func test_match_end_reports_the_result_and_shows_results() -> void:
	var config := MatchConfig.versus(&"aldric", &"morrigan", &"ashen_chapel", MatchConfig.Difficulty.NORMAL)
	config.rounds_to_win = 1
	config.round_seconds = 1
	GameFlow.match_finished.connect(_on_finished)
	await _open(config)
	_step_until_fight()
	screen.runner.sim.fighter(1).hp -= 100
	screen.runner.paused = true
	for i in 2000:
		if screen.is_finished():
			break
		screen.runner.step_once()
	assert_true(screen.is_finished(), "the match ended")
	assert_eq(_finished.size(), 1, "GameFlow.match_finished fired once")
	if _finished.size() == 1:
		assert_eq(_finished[0].winner_team, 0, "more HP at time-up wins")
		assert_true(_finished[0].player_won())
	screen._show_results()
	await wait_frames(1)
	var focus := host.get_viewport().gui_get_focus_owner()
	assert_eq(String(focus.name) if focus != null else "", "Rematch")


func _open(config: MatchConfig) -> void:
	GameFlow.current_match = config
	screen = MATCH_SCENE.instantiate()
	host.add_child(screen)
	await wait_frames(1)


## Steps the sim by hand through the round intro; returns the announcements made.
func _step_until_fight() -> PackedStringArray:
	screen.runner.paused = true
	for i in 600:
		screen.runner.step_once()
		if screen.runner.sim.state.phase == SimState.Phase.FIGHT:
			break
	screen.runner.paused = false
	return screen.hud.announced


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _on_finished(result: MatchResult) -> void:
	_finished.append(result)
