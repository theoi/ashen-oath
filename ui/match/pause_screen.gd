extends MenuScreen
## Pause menu inside a match: resume, controls, settings, or leave.

var _resume: Button


func _ready() -> void:
	var page := make_page("Paused")
	var config := GameFlow.current_match
	if config != null:
		var names := PackedStringArray()
		for id in config.fighters:
			names.append(Roster.fighter_name(id))
		var line := "%s  ·  %s  ·  %s" % [" vs ".join(names), Roster.arena(config.arena)["name"],
				MatchConfig.difficulty_name(config.difficulty)]
		page.add_child(make_label(line, &"SubtleLabel"))
	var entries := VBoxContainer.new()
	entries.add_theme_constant_override("separation", 4)
	page.add_child(entries)
	_resume = _entry(entries, "Resume", go_back)
	_entry(entries, "Controls", func() -> void: GameFlow.open_screen(&"controls"))
	_entry(entries, "Settings", func() -> void: GameFlow.open_screen(&"settings"))
	_entry(entries, "Quit to menu", GameFlow.leave_match)


func default_focus() -> Control:
	return _resume


func _entry(parent: Container, text: String, on_press: Callable) -> Button:
	var button := make_button(text, on_press, &"MenuEntryButton")
	button.name = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.x = 420.0
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(button)
	return button

