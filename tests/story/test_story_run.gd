extends TestCase
## A scripted story run through StoryDirector, with navigation recorded instead of changing
## scenes and fight results injected through the match's on_finished callback: all five
## fights and scenes, auto-save and resume, unlocks, retries and lower difficulty.

const SAVE_PATH := "user://test_story_run.cfg"
const PROFILE_PATH := "user://test_story_run_profile.cfg"

var story: StoryData
var director: StoryDirector
## What the director did, in order: "scene:<id>", "fight:<id>", "results:<id>",
## "hollowed:<id>", "menu:<last screen>".
var trail: Array[String] = []
var matches: Array[MatchConfig] = []
var menus: Array[Array] = []


func before_each() -> void:
	Profile.path = PROFILE_PATH
	Profile.load_profile()
	StorySave.default_path = SAVE_PATH
	_remove_files()
	story = StoryDirector.load_story()


func after_each() -> void:
	_remove_files()
	StorySave.default_path = StorySave.DEFAULT_PATH
	Profile.path = Profile.DEFAULT_PATH
	Profile.load_profile()
	GameFlow.story_director = null
	# The recording lambdas capture this test, which holds the director: break the cycle.
	if director != null:
		director.show_player = Callable()
		director.start_match = Callable()
		director.to_menu = Callable()
		director.after = Callable()
	director = null
	matches.clear()


func test_full_act_runs_every_scene_and_fight_then_opens_chapter_select() -> void:
	_begin(StoryRun.new_story(story, StorySave.load_from(), MatchConfig.Difficulty.HARD))
	var unlocked_after: Dictionary = {}
	for guard in 100:
		if not menus.is_empty():
			break
		var last := trail.back() as String
		if last.begins_with("scene:"):
			director.scene_finished()
		elif last.begins_with("fight:"):
			_finish_match(true)
			unlocked_after[last] = [Profile.is_fighter_unlocked(&"morrigan"), Profile.is_fighter_unlocked(&"gorrath")]
		elif last.begins_with("results:"):
			director.continue_after_results()
	assert_eq(trail, [
		"scene:prologue", "fight:fight_squire", "results:fight_squire",
		"scene:the_dead_stir", "fight:fight_two_hollowed", "results:fight_two_hollowed",
		"scene:the_grave_witch", "fight:fight_morrigan", "results:fight_morrigan",
		"scene:the_road_below", "scene:the_chainbound", "fight:fight_gorrath", "results:fight_gorrath",
		"scene:what_the_fire_left", "fight:fight_oath_shade", "results:fight_oath_shade",
		"scene:epilogue", "menu:story_chapters",
	] as Array[String])
	assert_eq(unlocked_after["fight:fight_squire"], [false, false])
	assert_eq(unlocked_after["fight:fight_morrigan"], [true, false], "Morrigan unlocks after fight 3")
	assert_eq(unlocked_after["fight:fight_gorrath"], [true, true], "Gorrath unlocks after fight 4")
	assert_true(StorySave.load_from().completed, "completion is saved")

	assert_eq(matches.size(), 5)
	for config in matches:
		assert_eq(config.mode, MatchConfig.Mode.STORY)
		assert_eq(config.fighters[0], &"aldric")
		assert_eq(config.menu_stack, [&"mode_select", &"story"] as Array[StringName])
		assert_true(config.on_finished.is_valid() and config.on_started.is_valid())
	assert_eq(matches[0].difficulty, MatchConfig.Difficulty.EASY, "fight 1 AI is capped at Easy")
	assert_eq(matches[0].ai_cap, MatchConfig.Difficulty.EASY)
	assert_eq(matches[4].ai_profiles, {1: &"oath_shade"} as Dictionary[int, StringName], "the Shade plays its own aggressive profile")
	assert_eq(matches[0].rounds_to_win, 1)
	assert_eq(matches[0].round_seconds, -1, "no timer while learning")
	assert_eq(matches[1].fighters, [&"aldric", &"hollowed", &"hollowed"] as Array[StringName])
	assert_eq(matches[1].teams, [0, 1, 1] as Array[int], "fight 2 is a 1v2")
	assert_eq(matches[1].difficulty, MatchConfig.Difficulty.HARD)
	assert_eq(matches[2].arena, &"ashen_chapel_night")
	assert_eq(matches[2].rounds_to_win, 2, "best of 3")
	assert_eq(matches[3].arena, &"drowned_crypt")
	assert_eq(matches[4].fighters[1], &"oath_shade")
	assert_eq(matches[4].starting_soul, [0, 50] as Array[int], "the Shade starts with 50 Soul")
	assert_eq(matches[4].arena, &"drowned_crypt_depths")


func test_progress_saves_after_each_won_fight_and_resumes_mid_act() -> void:
	_begin(StoryRun.new_story(story, StorySave.load_from(), MatchConfig.Difficulty.NORMAL))
	director.scene_finished()
	assert_eq(StorySave.load_from().next_step, 0, "a scene alone does not move the save")
	_finish_match(true)
	assert_eq(StorySave.load_from().next_step, story.step_index(&"the_dead_stir"), "saved after fight 1")
	director.continue_after_results()
	director.scene_finished()
	_finish_match(true)
	director.continue_after_results()
	director.scene_finished()
	director.run.set_difficulty(MatchConfig.Difficulty.NIGHTMARE)
	_finish_match(true)
	director.quit()
	assert_eq(trail.back(), "menu:story")

	var save := StorySave.load_from()
	assert_true(save.can_continue(story.steps.size()))
	assert_false(save.completed)
	assert_eq(save.next_step, story.step_index(&"the_road_below"), "resumes after the Morrigan fight")
	assert_eq(save.difficulty, MatchConfig.Difficulty.NIGHTMARE, "difficulty changes are saved")

	trail.clear()
	matches.clear()
	_begin(StoryRun.resume(story, save))
	assert_eq(trail, ["scene:the_road_below"] as Array[String])
	director.scene_finished()
	director.scene_finished()
	assert_eq(trail.back(), "fight:fight_gorrath")
	assert_eq(matches[0].difficulty, MatchConfig.Difficulty.NIGHTMARE)


func test_two_losses_offer_retry_on_lower_difficulty() -> void:
	var save := StorySave.load_from()
	save.started = true
	save.next_step = story.step_index(&"fight_morrigan")
	save.difficulty = MatchConfig.Difficulty.HARD
	save.write()
	_begin(StoryRun.resume(story, StorySave.load_from()))
	assert_eq(trail.back(), "fight:fight_morrigan")

	_finish_match(false)
	assert_eq(trail.back(), "hollowed:fight_morrigan")
	assert_false(director.run.can_lower_difficulty(), "not after one loss")
	director.retry()
	assert_eq(trail.back(), "fight:fight_morrigan", "retry goes straight back to the fight")
	assert_eq(matches.back().difficulty, MatchConfig.Difficulty.HARD)

	_finish_match(false)
	assert_true(director.run.can_lower_difficulty(), "offered after two losses")
	director.retry_on_lower_difficulty()
	assert_eq(trail.back(), "fight:fight_morrigan")
	assert_eq(matches.back().difficulty, MatchConfig.Difficulty.NORMAL)
	assert_eq(StorySave.load_from().difficulty, MatchConfig.Difficulty.NORMAL)
	assert_eq(StorySave.load_from().next_step, story.step_index(&"fight_morrigan"), "losses do not move the save")

	_finish_match(true)
	assert_eq(trail.back(), "results:fight_morrigan")
	assert_eq(director.run.losses, 0)
	assert_eq(director.run.new_unlocks, [&"morrigan"] as Array[StringName])


func test_draw_counts_as_a_loss_and_fight_one_never_goes_below_easy() -> void:
	_begin(StoryRun.new_story(story, StorySave.load_from(), MatchConfig.Difficulty.NIGHTMARE))
	director.scene_finished()
	_finish_match(false, -1)
	assert_eq(trail.back(), "hollowed:fight_squire")
	director.retry()
	_finish_match(false)
	assert_eq(director.run.losses, 2)
	assert_false(director.run.can_lower_difficulty(), "fight 1 already plays at Easy")


func test_chapter_replay_plays_one_step_and_leaves_the_save_alone() -> void:
	var save := StorySave.load_from()
	save.started = true
	save.completed = true
	save.next_step = story.steps.size()
	save.write()
	_begin(StoryRun.chapter(story, StorySave.load_from(), story.step_index(&"fight_gorrath"), MatchConfig.Difficulty.EASY))
	assert_eq(trail, ["fight:fight_gorrath"] as Array[String])
	assert_eq(matches[0].difficulty, MatchConfig.Difficulty.EASY)
	_finish_match(true)
	director.continue_after_results()
	assert_eq(trail.back(), "menu:story_chapters")
	var after := StorySave.load_from()
	assert_eq(after.next_step, story.steps.size())
	assert_true(after.completed)


func test_missing_or_corrupt_save_starts_fresh() -> void:
	var save := StorySave.load_from()
	assert_false(save.started)
	assert_false(save.can_continue(story.steps.size()))
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("[story]\nnext_step = \"twelve\"\ncompleted = 3\ndifficulty = 99\n")
	file.close()
	save = StorySave.load_from()
	assert_eq(save.next_step, 0)
	assert_false(save.completed)


# --- Helpers ------------------------------------------------------------------------------

func _begin(run: StoryRun) -> void:
	director = StoryDirector.new(run)
	director.show_player = func() -> void:
		var tag: String = ["scene", "results", "hollowed"][director.view]
		trail.append("%s:%s" % [tag, director.run.step().id])
	director.start_match = func(config: MatchConfig) -> void:
		matches.append(config)
		trail.append("fight:%s" % director.run.step().id)
	director.to_menu = func(stack: Array[StringName]) -> void:
		menus.append(stack)
		trail.append("menu:%s" % stack.back())
	director.after = func(_seconds: float, callback: Callable) -> void: callback.call()
	StoryDirector.begin(director)


## Ends the current fight through its on_finished callback, as the match screen does.
func _finish_match(won: bool, winner: int = -2) -> void:
	var config := matches.back() as MatchConfig
	var result := MatchResult.new()
	result.config = config
	result.winner_team = (0 if won else 1) if winner == -2 else winner
	result.round_wins.assign([config.rounds_to_win, 0] if won else [0, config.rounds_to_win])
	config.on_finished.call(result)


func _remove_files() -> void:
	for path: String in [SAVE_PATH, PROFILE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.load_profile()
