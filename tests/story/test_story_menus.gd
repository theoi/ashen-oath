extends TestCase
## Story entry and chapter select in the menus: Begin / Continue / Start over, chapter
## select only once the act is complete, and focus for gamepad play.

const MENU_APP := preload("res://ui/app/menu_app.tscn")
const SAVE_PATH := "user://test_story_menus.cfg"

var app: MenuApp
var story: StoryData


func before_each() -> void:
	StorySave.default_path = SAVE_PATH
	story = StoryDirector.load_story()


func after_each() -> void:
	if is_instance_valid(app):
		app.free()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	StorySave.default_path = StorySave.DEFAULT_PATH


func test_fresh_profile_offers_begin_and_locks_chapter_select() -> void:
	await _open([&"mode_select", &"story"])
	var screen := app.current_screen()
	assert_null(screen.find_child("Continue", true, false))
	var begin := screen.find_child("New", true, false) as Button
	assert_eq(begin.text, "Begin")
	assert_eq(_focused_name(), "New")
	var chapters := screen.find_child("Chapters", true, false) as Button
	assert_true(chapters.disabled, "chapter select waits for completion")


func test_saved_progress_offers_continue_first() -> void:
	_write_save(story.step_index(&"fight_gorrath"), false, MatchConfig.Difficulty.HARD)
	await _open([&"mode_select", &"story"])
	var screen := app.current_screen()
	var continue_button := screen.find_child("Continue", true, false) as Button
	assert_not_null(continue_button)
	assert_true(continue_button.text.contains("IV · Gorrath"), "says where the story continues")
	assert_eq(_focused_name(), "Continue")
	assert_eq((screen.find_child("New", true, false) as Button).text, "Start over")
	assert_eq(screen.call("selected_difficulty"), MatchConfig.Difficulty.HARD, "the saved difficulty is preselected")


func test_completed_act_opens_chapter_select_with_every_step() -> void:
	_write_save(story.steps.size(), true, MatchConfig.Difficulty.NORMAL)
	await _open([&"mode_select", &"story"])
	var chapters := app.current_screen().find_child("Chapters", true, false) as Button
	assert_false(chapters.disabled)
	await _press_on(chapters)
	assert_eq(app.current_screen().screen_id, &"story_chapters")
	assert_eq(app.current_screen().call("chapter_count"), story.steps.size())
	assert_eq(_focused_name(), "prologue")
	await _press(&"ui_cancel")
	assert_eq(app.current_screen().screen_id, &"story")


func _write_save(next_step: int, completed: bool, difficulty: MatchConfig.Difficulty) -> void:
	var save := StorySave.load_from()
	save.started = true
	save.next_step = next_step
	save.completed = completed
	save.difficulty = difficulty
	save.write()


func _open(stack: Array[StringName]) -> void:
	GameFlow._pending_menu = stack
	app = add_child_autofree(MENU_APP.instantiate())
	await wait_frames(1)


func _press_on(button: Button) -> void:
	button.grab_focus()
	await _press(&"ui_accept")


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
