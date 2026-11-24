extends TestCase
## Menu navigation with keyboard / gamepad actions only, as a player without a mouse would.

const MENU_APP := preload("res://ui/app/menu_app.tscn")
const TEST_SETTINGS := "user://test_menu_flow_settings.cfg"

var app: MenuApp


func before_each() -> void:
	Settings.path = TEST_SETTINGS
	Settings.reset_to_defaults()
	app = add_child_autofree(MENU_APP.instantiate())
	await wait_frames(1)


func after_each() -> void:
	if is_instance_valid(app):
		app.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	Settings.path = Settings.DEFAULT_PATH
	Settings.load_settings()


func test_title_continues_to_mode_select_with_focus_on_story() -> void:
	assert_eq(app.screen_ids(), [&"title"] as Array[StringName])
	await _press(&"ui_accept")
	assert_eq(app.screen_ids(), [&"title", &"mode_select"] as Array[StringName])
	assert_eq(_focused_name(), "Story")


func test_cancel_from_mode_select_returns_to_title_and_title_stays() -> void:
	await _press(&"ui_accept")
	await _press(&"ui_cancel")
	assert_eq(app.screen_ids(), [&"title"] as Array[StringName])
	await _press(&"ui_cancel")
	assert_eq(app.screen_ids(), [&"title", &"mode_select"] as Array[StringName], "any button on the title continues")


func test_open_controls_and_back_restores_focus() -> void:
	await _press(&"ui_accept")
	for i in 5:
		if _focused_name() == "Controls":
			break
		await _press(&"ui_down")
	assert_eq(_focused_name(), "Controls")
	await _press(&"ui_accept")
	assert_eq(app.current_screen().screen_id, &"controls")
	assert_true(_focus_in_current_screen(), "controls screen has focus")
	await _press(&"ui_cancel")
	assert_eq(app.current_screen().screen_id, &"mode_select")
	assert_eq(_focused_name(), "Controls", "focus returns to the entry that opened the screen")


func test_every_screen_takes_focus_and_cancel_goes_back() -> void:
	await _press(&"ui_accept")
	for id: StringName in GameFlow.SCREENS:
		if id == &"title" or id == &"mode_select":
			continue
		GameFlow.open_screen(id)
		await wait_frames(1)
		assert_eq(app.current_screen().screen_id, id)
		assert_true(_focus_in_current_screen(), "%s has a focused control for gamepad use" % id)
		await _press(&"ui_cancel")
		assert_eq(app.current_screen().screen_id, &"mode_select", "cancel leaves %s" % id)


func test_lost_focus_is_recovered_by_a_direction_press() -> void:
	await _press(&"ui_accept")
	app.get_viewport().gui_release_focus()
	await _press(&"ui_down")
	assert_true(_focus_in_current_screen())


func test_settings_difficulty_changes_with_left_right_and_saves_on_back() -> void:
	await _press(&"ui_accept")
	GameFlow.open_screen(&"settings")
	await wait_frames(1)
	for i in 8:
		if app.get_viewport().gui_get_focus_owner() is OptionCycler:
			break
		await _press(&"ui_down")
	assert_true(app.get_viewport().gui_get_focus_owner() is OptionCycler, "reached the difficulty selector")
	assert_eq(Settings.default_difficulty, MatchConfig.Difficulty.NORMAL)
	await _press(&"ui_right")
	assert_eq(Settings.default_difficulty, MatchConfig.Difficulty.HARD)
	await _press(&"ui_left")
	await _press(&"ui_left")
	assert_eq(Settings.default_difficulty, MatchConfig.Difficulty.EASY)
	await _press(&"ui_cancel")
	assert_true(FileAccess.file_exists(TEST_SETTINGS), "leaving settings saves them")
	Settings.reset_to_defaults()
	Settings.load_settings()
	assert_eq(Settings.default_difficulty, MatchConfig.Difficulty.EASY)


func test_volume_slider_moves_with_right_press() -> void:
	await _press(&"ui_accept")
	GameFlow.open_screen(&"settings")
	await wait_frames(1)
	assert_true(app.get_viewport().gui_get_focus_owner() is HSlider, "the first volume slider has focus")
	var before := Settings.volume(&"Master")
	await _press(&"ui_left")
	assert_almost_eq(Settings.volume(&"Master"), before - 0.05, 0.001)


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await wait_frames(1)


func _focused_name() -> String:
	var owner := app.get_viewport().gui_get_focus_owner()
	return "" if owner == null else String(owner.name)


func _focus_in_current_screen() -> bool:
	var owner := app.get_viewport().gui_get_focus_owner()
	return owner != null and app.current_screen().is_ancestor_of(owner)
