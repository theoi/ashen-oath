extends TestCase
## The story player with keyboard / gamepad actions: typewriter lines, advancing, title
## cards, portraits, hold-to-skip, and the results and "You Hollowed" screens.

const PLAYER := preload("res://ui/story/story_player.tscn")
const SAVE_PATH := "user://test_story_player.cfg"
const PROFILE_PATH := "user://test_story_player_profile.cfg"

var story: StoryData
var director: StoryDirector
var player: StoryPlayer
var started: Array[StringName] = []
var menus: Array[StringName] = []


func before_each() -> void:
	StorySave.default_path = SAVE_PATH
	Profile.path = PROFILE_PATH
	Profile.load_profile()
	story = StoryDirector.load_story()


func after_each() -> void:
	if is_instance_valid(player):
		player.free()
	for path: String in [SAVE_PATH, PROFILE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	StorySave.default_path = StorySave.DEFAULT_PATH
	Profile.path = Profile.DEFAULT_PATH
	Profile.load_profile()
	GameFlow.story_director = null
	if director != null:
		director.show_player = Callable()
		director.start_match = Callable()
		director.to_menu = Callable()
		director.after = Callable()
	director = null
	Input.action_release(&"ui_cancel")


func test_lines_type_out_and_advance_with_accept() -> void:
	await _open_scene(&"the_grave_witch")
	var scene := player.scene
	assert_eq(player.line_index, 0)
	assert_true(player.dialogue.visible)
	assert_eq(player.dialogue.text(), scene.lines[0].text)
	assert_eq(player.dialogue.speaker(), "", "narration has no name")
	assert_true(player.dialogue.is_typing(), "the line types out")
	await _press(&"ui_accept")
	assert_false(player.dialogue.is_typing(), "the first press finishes the line")
	assert_eq(player.line_index, 0)
	await _press(&"attack_light")
	assert_eq(player.line_index, 1, "Light advances too")
	assert_eq(player.dialogue.speaker(), "Morrigan")
	await wait_frames(2)
	var portrait := player.get_children().filter(func(n: Node) -> bool: return n is StoryPortrait)
	assert_eq(portrait.size(), 1, "a portrait is rendered for the speaker")
	assert_eq((portrait[0] as StoryPortrait).fighter, &"morrigan")

	for i in 40:
		if player.is_finished():
			break
		await _press(&"ui_accept")
	assert_true(player.is_finished(), "the last line ends the scene")
	assert_eq(started, [&"fight_morrigan"] as Array[StringName], "then the next fight starts")


func test_title_cards_and_actors_follow_the_lines() -> void:
	await _open_scene(&"prologue")
	assert_true(player.card.visible, "the prologue opens on a title card")
	assert_eq(player.card.title(), "Vael")
	assert_false(player.dialogue.visible)
	# Lying Aldric until line 5, then standing Aldric.
	assert_true(player.stage.actors[0].visible)
	assert_false(player.stage.actors[1].visible)
	for i in 5:
		player.advance()
		player.advance()
	assert_eq(player.line_index, 5)
	assert_false(player.card.visible)
	assert_true(player.dialogue.visible)
	assert_false(player.stage.actors[0].visible)
	assert_true(player.stage.actors[1].visible)
	assert_eq(player.stage.camera.position, (player.scene.shots[2] as StoryShot).position, "the line switches shots")


func test_holding_back_skips_the_scene() -> void:
	await _open_scene(&"the_chainbound")
	Input.action_press(&"ui_cancel")
	player._process(0.4)
	assert_false(player.is_finished(), "a short hold does not skip")
	player._process(0.7)
	assert_true(player.is_finished(), "holding for a second skips")
	Input.action_release(&"ui_cancel")
	assert_eq(started, [&"fight_gorrath"] as Array[StringName])


func test_results_card_shows_unlocks_and_continues() -> void:
	_make_director(StoryRun.resume(story, _save_at(&"fight_morrigan")))
	var result := MatchResult.new()
	result.config = director.match_config()
	result.winner_team = 0
	result.round_wins.assign([2, 1])
	director.run.record(result)
	director.view = StoryDirector.View.RESULTS
	await _open_player()
	assert_true(player.panel is StoryResultsScreen)
	assert_not_null(player.panel.find_child("Unlock_morrigan", true, false), "the unlock is announced")
	assert_eq(_focused_name(), "Continue")
	await _press(&"ui_accept")
	assert_eq(menus, [] as Array[StringName])
	assert_eq(director.run.step().id, &"the_road_below", "Continue moves on to the next scene")


func test_loss_screen_offers_lower_difficulty_only_after_two_losses() -> void:
	_make_director(StoryRun.resume(story, _save_at(&"fight_gorrath")))
	director.run.losses = 1
	director.view = StoryDirector.View.HOLLOWED
	await _open_player()
	assert_true(player.panel is StoryHollowedScreen)
	assert_eq(_focused_name(), "Retry")
	assert_null(player.panel.find_child("RetryLower", true, false))
	assert_not_null(player.panel.find_child("Quit", true, false))
	player.free()

	director.run.losses = 2
	await _open_player()
	var lower := player.panel.find_child("RetryLower", true, false) as Button
	assert_not_null(lower, "offered after two losses")
	if lower != null:
		lower.grab_focus()
		await _press(&"ui_accept")
		assert_eq(started, [&"fight_gorrath"] as Array[StringName])
		assert_eq(director.run.difficulty, MatchConfig.Difficulty.EASY)


# --- Helpers ------------------------------------------------------------------------------

func _save_at(step_id: StringName) -> StorySave:
	var save := StorySave.load_from()
	save.started = true
	save.next_step = story.step_index(step_id)
	save.difficulty = MatchConfig.Difficulty.NORMAL
	save.write()
	return save


func _make_director(run: StoryRun) -> void:
	director = StoryDirector.new(run)
	director.show_player = func() -> void: pass
	director.start_match = func(_config: MatchConfig) -> void: started.append(director.run.step().id)
	director.to_menu = func(stack: Array[StringName]) -> void: menus.append(stack.back())
	director.after = func(_seconds: float, callback: Callable) -> void: callback.call()
	StoryDirector.set_current(director)


func _open_scene(step_id: StringName) -> void:
	_make_director(StoryRun.resume(story, _save_at(step_id)))
	director.view = StoryDirector.View.SCENE
	await _open_player()


func _open_player() -> void:
	player = PLAYER.instantiate()
	host.add_child(player)
	await wait_frames(1)


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await wait_frames(1)


func _focused_name() -> String:
	var owner := host.get_viewport().gui_get_focus_owner()
	return "" if owner == null else String(owner.name)
