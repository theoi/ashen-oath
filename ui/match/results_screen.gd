extends MenuScreen
## Versus results: who won, the round score, and what next.

var _rematch: Button


func _ready() -> void:
	var result := GameFlow.last_result if GameFlow.last_result != null else MatchResult.new()
	var config := result.config if result.config != null else GameFlow.current_match
	var won := result.player_won()

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	var title := make_label("Victory" if won else "Defeat", &"TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if won else Palette.ASH_TEXT.lightened(0.2))
	column.add_child(title)
	var line := make_label(_summary(result, config), &"SubheaderLabel")
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(line)
	if not won:
		var flavor := make_label("The bell tolls on. Rise and fight again.", &"SubtleLabel")
		flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(flavor)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	_rematch = make_button("Rematch", GameFlow.rematch)
	_rematch.name = "Rematch"
	buttons.add_child(_rematch)
	buttons.add_child(make_button("Change fighters", GameFlow.leave_match))
	buttons.add_child(make_button("Main menu", func() -> void: GameFlow.return_to_menu([&"mode_select"])))


func default_focus() -> Control:
	return _rematch


func can_go_back() -> bool:
	return false


func _summary(result: MatchResult, config: MatchConfig) -> String:
	if config == null or result.winner_team < 0:
		return "A draw. Nobody walks away."
	var winners := PackedStringArray()
	for slot in config.slot_count():
		if config.teams[slot] == result.winner_team:
			winners.append(Roster.fighter_name(config.fighters[slot]))
	var score := PackedStringArray()
	for wins in result.round_wins:
		score.append(str(wins))
	return "%s %s  %s" % [" and ".join(winners), "wins" if winners.size() == 1 else "win", " – ".join(score)]

