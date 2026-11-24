extends MenuScreen
## Story mode entry (GameFlow screen "story"): continue from the save, begin or start over,
## chapter select once the act is complete, and the difficulty.

var story: StoryData
var save: StorySave

var _entries: VBoxContainer
var _difficulty: OptionCycler
var _notice: Label
var _confirm_restart := false


func _ready() -> void:
	story = StoryDirector.load_story()
	save = StorySave.load_from()
	var page := make_page("%s · %s" % [story.title, story.subtitle])
	var blurb := make_label(story.blurb, &"BodyLabel")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 620.0
	blurb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(blurb)

	_entries = VBoxContainer.new()
	_entries.add_theme_constant_override("separation", 4)
	page.add_child(_entries)
	var can_continue := save.can_continue(story.steps.size())
	if can_continue:
		var next := story.step(save.next_step)
		_entry("Continue", "Continue  ·  %s" % next.title, _on_continue)
	_entry("New", "Start over" if can_continue or save.completed else "Begin", _on_new)
	var chapters := _entry("Chapters", "Chapter select", func() -> void: GameFlow.open_screen(&"story_chapters"))
	if not save.completed:
		chapters.disabled = true
		chapters.focus_mode = Control.FOCUS_NONE
		chapters.text = "Chapter select  ·  opens when Act 1 is complete"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	page.add_child(row)
	var label := make_label("Difficulty", &"SubtleLabel")
	label.custom_minimum_size.x = 120.0
	row.add_child(label)
	_difficulty = OptionCycler.new()
	_difficulty.name = "Difficulty"
	_difficulty.set_options(MatchConfig.DIFFICULTY_NAMES, save.difficulty)
	_difficulty.custom_minimum_size.x = 340.0
	row.add_child(_difficulty)

	var back := make_button("Back", go_back)
	back.name = "Back"
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(back)
	_notice = make_label("", &"SubtleLabel")
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	page.add_child(_notice)


func default_focus() -> Control:
	for child in _entries.get_children():
		var button := child as Button
		if button != null and not button.disabled:
			return button
	return _difficulty


func selected_difficulty() -> MatchConfig.Difficulty:
	return _difficulty.selected as MatchConfig.Difficulty


func _on_continue() -> void:
	var run := StoryRun.resume(story, save)
	run.set_difficulty(selected_difficulty())
	StoryDirector.begin(StoryDirector.new(run))


func _on_new() -> void:
	if save.can_continue(story.steps.size()) and not _confirm_restart:
		_confirm_restart = true
		Sound.play(&"ui_denied")
		_notice.text = "Starting over replaces your saved progress. Choose it again to begin anew."
		return
	StoryDirector.begin(StoryDirector.new(StoryRun.new_story(story, save, selected_difficulty())))


func _entry(id: String, text: String, on_press: Callable) -> Button:
	var button := make_button(text, on_press, &"MenuEntryButton")
	button.name = id
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.x = 560.0
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_entries.add_child(button)
	return button
