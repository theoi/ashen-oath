class_name StoryHollowedScreen
extends MenuScreen
## "You Hollowed": the story loss screen. Retry the fight at once, retry on a lower
## difficulty (after two losses), or quit to the menu.

var director: StoryDirector

var _retry: Button


func _ready() -> void:
	var run := director.run
	var fight := run.current_fight()
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	var title := make_label("You Hollowed", &"TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Palette.ASH_TEXT.lightened(0.15))
	column.add_child(title)
	var flavor := make_label("The fire gutters. The bell tolls on. Rise, and fight again.", &"SubheaderLabel")
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(flavor)
	if fight != null:
		var times := "once" if run.losses == 1 else "%d times" % run.losses
		var info := make_label("Fallen %s to %s  ·  %s" % [times, fight.opponent_name,
				MatchConfig.difficulty_name(run.fight_difficulty(fight))], &"SubtleLabel")
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(info)

	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(buttons)
	_retry = _entry(buttons, "Retry", "Retry", director.retry)
	if run.can_lower_difficulty():
		var lower := MatchConfig.difficulty_name(maxi(0, int(run.fight_difficulty(fight)) - 1) as MatchConfig.Difficulty)
		_entry(buttons, "RetryLower", "Retry on lower difficulty (%s)" % lower, director.retry_on_lower_difficulty)
	_entry(buttons, "Quit", "Quit to menu", director.quit)


func default_focus() -> Control:
	return _retry


func can_go_back() -> bool:
	return false


func _entry(parent: Container, id: String, text: String, on_press: Callable) -> Button:
	var button := make_button(text, on_press, &"MenuEntryButton")
	button.name = id
	button.custom_minimum_size.x = 440.0
	parent.add_child(button)
	return button
