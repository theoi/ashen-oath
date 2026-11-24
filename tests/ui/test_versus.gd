extends TestCase
## Versus select and fighter unlocks: locked fighters cannot be picked until story mode (or
## the "unlock all" setting) frees them, and unlocks persist.

const VERSUS := preload("res://ui/versus/versus_select.tscn")
const PROFILE_PATH := "user://test_profile.cfg"
const SETTINGS_PATH := "user://test_versus_settings.cfg"

var versus: MenuScreen


func before_each() -> void:
	Profile.path = PROFILE_PATH
	Profile.load_profile()
	Settings.path = SETTINGS_PATH
	Settings.load_settings()
	GameFlow.current_match = null


func after_each() -> void:
	if is_instance_valid(versus):
		versus.free()
	for path: String in [PROFILE_PATH, SETTINGS_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.path = Profile.DEFAULT_PATH
	Profile.load_profile()
	Settings.path = Settings.DEFAULT_PATH
	Settings.load_settings()


func test_only_aldric_starts_unlocked() -> void:
	assert_true(Profile.is_fighter_unlocked(&"aldric"))
	assert_false(Profile.is_fighter_unlocked(&"morrigan"))
	assert_false(Profile.is_fighter_unlocked(&"gorrath"))


func test_unlocks_persist() -> void:
	assert_true(Profile.unlock_fighter(&"morrigan"))
	assert_false(Profile.unlock_fighter(&"morrigan"), "second unlock is a no-op")
	Profile.reset()
	Profile.load_profile()
	assert_true(Profile.is_fighter_unlocked(&"morrigan"))
	assert_false(Profile.is_fighter_unlocked(&"gorrath"))


func test_unlock_all_setting_frees_everyone() -> void:
	Settings.set_unlock_all_fighters(true)
	for id in Roster.fighter_ids():
		assert_true(Profile.is_fighter_unlocked(id), "%s unlocked" % id)


func test_locked_opponent_cannot_be_confirmed() -> void:
	await _open()
	versus.select(&"aldric", &"morrigan", &"drowned_crypt")
	versus._on_fight()
	assert_null(GameFlow.current_match, "no match started with a locked fighter")
	assert_ne(versus._notice.text, "", "the screen says why")


func test_selection_builds_the_match_config() -> void:
	Settings.set_default_difficulty(MatchConfig.Difficulty.HARD)
	Profile.unlock_fighter(&"gorrath")
	await _open()
	versus.select(&"gorrath", &"aldric", &"drowned_crypt_depths")
	var config: MatchConfig = versus.build_config()
	assert_eq(config.fighters, [&"gorrath", &"aldric"] as Array[StringName])
	assert_eq(config.teams, [0, 1] as Array[int])
	assert_eq(config.arena, &"drowned_crypt_depths")
	assert_eq(config.difficulty, MatchConfig.Difficulty.HARD, "defaults to the settings difficulty")
	assert_eq(config.rounds_to_win, 2, "best of 3")
	assert_eq(config.menu_stack, [&"mode_select", &"versus"] as Array[StringName])


func test_unlocking_while_open_updates_the_screen() -> void:
	await _open()
	versus.select(&"aldric", &"morrigan", &"ashen_chapel")
	assert_true(versus._opponent.is_selected_locked())
	Profile.unlock_fighter(&"morrigan")
	assert_false(versus._opponent.is_selected_locked())


func _open() -> void:
	versus = VERSUS.instantiate()
	host.add_child(versus)
	await wait_frames(1)
