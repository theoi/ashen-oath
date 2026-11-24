class_name StoryResultsScreen
extends MenuScreen
## Story results card after a won fight: the score, unlocks, the save, the difficulty for
## what comes next, and Continue.

var director: StoryDirector

var _continue: Button
var _difficulty: OptionCycler


func _ready() -> void:
	var run := director.run
	var fight := run.current_fight()
	var column := _column()
	var title := make_label("Victory", &"TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	column.add_child(title)
	var summary := make_label(_summary(run, fight), &"SubheaderLabel")
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(summary)
	for id in run.new_unlocks:
		var unlock := make_label("%s can now be chosen in Versus." % Roster.fighter_name(id), &"StrongLabel")
		unlock.name = "Unlock_%s" % id
		unlock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unlock.add_theme_color_override("font_color", Palette.SOUL)
		column.add_child(unlock)
	if not run.chapter_only:
		var saved := make_label("Progress saved.", &"SubtleLabel")
		saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(saved)

	if _fights_ahead(run):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		column.add_child(row)
		row.add_child(make_label("Difficulty", &"SubtleLabel"))
		_difficulty = OptionCycler.new()
		_difficulty.name = "Difficulty"
		_difficulty.set_options(MatchConfig.DIFFICULTY_NAMES, run.difficulty)
		_difficulty.custom_minimum_size.x = 300.0
		_difficulty.selection_changed.connect(func(i: int) -> void: run.set_difficulty(i as MatchConfig.Difficulty))
		row.add_child(_difficulty)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	_continue = make_button("Continue", director.continue_after_results)
	_continue.name = "Continue"
	_continue.custom_minimum_size.x = 220.0
	buttons.add_child(_continue)
	var quit := make_button("Quit to menu", director.quit)
	quit.name = "Quit"
	buttons.add_child(quit)
	if _difficulty != null:
		_difficulty.focus_neighbor_bottom = _difficulty.get_path_to(_continue)
		_continue.focus_neighbor_top = _continue.get_path_to(_difficulty)
		quit.focus_neighbor_top = quit.get_path_to(_difficulty)


func default_focus() -> Control:
	return _continue


func can_go_back() -> bool:
	return false


func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	return column


static func _summary(run: StoryRun, fight: StoryFight) -> String:
	if fight == null:
		return ""
	var text := "Fight %d of %d  ·  %s" % [run.data.fight_number(fight), run.data.fights().size(), fight.opponent_name]
	var result := run.last_result
	if result != null and fight.rounds_to_win > 1 and result.round_wins.size() >= 2:
		text += "   %d – %d" % [result.round_wins[0], result.round_wins[1]]
	return text


## Whether another fight follows in this run (the difficulty can change before it).
static func _fights_ahead(run: StoryRun) -> bool:
	if run.chapter_only:
		return false
	for i in range(run.index + 1, run.data.steps.size()):
		if run.data.steps[i] is StoryFight:
			return true
	return false
