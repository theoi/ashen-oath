extends MenuScreen
## Versus select: your fighter, the CPU opponent, the arena and the difficulty. Best of 3.
## Locked fighters are listed but cannot be confirmed.

var _fighter: OptionCycler
var _opponent: OptionCycler
var _arena: OptionCycler
var _difficulty: OptionCycler
var _fight: Button
var _cards: Array[VBoxContainer] = []
var _arena_blurb: Label
var _notice: Label
var _ids: Array[StringName] = Roster.fighter_ids()


func _ready() -> void:
	var page := make_page("Versus")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 470.0
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)

	var names := PackedStringArray()
	for id in _ids:
		names.append(Roster.fighter_name(id))
	_fighter = _cycler(rows, "Your fighter", names, 0)
	_opponent = _cycler(rows, "Opponent (CPU)", names, mini(1, names.size() - 1))
	var arena_names := PackedStringArray()
	for entry in Roster.ARENAS:
		arena_names.append(entry["name"])
	_arena = _cycler(rows, "Arena", arena_names, 0)
	_arena_blurb = make_label("", &"SubtleLabel")
	_arena_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_arena_blurb.custom_minimum_size.y = 50.0
	rows.add_child(_arena_blurb)
	_difficulty = _cycler(rows, "Difficulty", MatchConfig.DIFFICULTY_NAMES, Settings.default_difficulty)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	rows.add_child(buttons)
	_fight = make_button("Fight", _on_fight)
	_fight.name = "Fight"
	_fight.custom_minimum_size.x = 200.0
	buttons.add_child(_fight)
	var moves := make_button("Move list", func() -> void: GameFlow.open_move_list(_ids[_fighter.selected]))
	moves.name = "MoveList"
	buttons.add_child(moves)
	var back := make_button("Back", go_back)
	buttons.add_child(back)
	# Back sits nearer the selectors' center than Fight, so geometric focus would skip Fight.
	_difficulty.focus_neighbor_bottom = _difficulty.get_path_to(_fight)
	_fight.focus_neighbor_top = _fight.get_path_to(_difficulty)
	back.focus_neighbor_top = back.get_path_to(_difficulty)
	moves.focus_neighbor_top = moves.get_path_to(_difficulty)
	_notice = make_label("", &"SubtleLabel")
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	rows.add_child(_notice)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cards)
	_cards.append(_card(cards))
	var versus := make_label("vs", &"HeaderLabel")
	versus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cards.add_child(versus)
	_cards.append(_card(cards))

	for cycler: OptionCycler in [_fighter, _opponent, _arena]:
		cycler.selection_changed.connect(func(_i: int) -> void: _refresh())
	Profile.changed.connect(_refresh)
	ActiveDevice.changed.connect(_refresh)
	Settings.changed.connect(_refresh)


func default_focus() -> Control:
	return _fighter


func on_shown() -> void:
	_refresh()


## The match the current selection describes.
func build_config() -> MatchConfig:
	var config := MatchConfig.versus(_ids[_fighter.selected], _ids[_opponent.selected],
			Roster.ARENAS[_arena.selected]["id"], _difficulty.selected as MatchConfig.Difficulty)
	return config


func select(fighter: StringName, opponent: StringName, arena: StringName) -> void:
	_fighter.select(_ids.find(fighter))
	_opponent.select(_ids.find(opponent))
	for i in Roster.ARENAS.size():
		if Roster.ARENAS[i]["id"] == arena:
			_arena.select(i)


func _on_fight() -> void:
	if _fighter.is_selected_locked() or _opponent.is_selected_locked():
		Sound.play(&"ui_denied")
		_notice.text = "That fighter is still bound. Win them in Story mode, or turn on \"Unlock all fighters\" in Settings."
		return
	GameFlow.start_match(build_config())


func _refresh() -> void:
	for i in _ids.size():
		var locked := not Profile.is_fighter_unlocked(_ids[i])
		_fighter.set_locked(i, locked)
		_opponent.set_locked(i, locked)
	_arena_blurb.text = Roster.ARENAS[_arena.selected]["blurb"]
	_fill_card(_cards[0], _ids[_fighter.selected], _fighter.is_selected_locked())
	_fill_card(_cards[1], _ids[_opponent.selected], _opponent.is_selected_locked())
	if not (_fighter.is_selected_locked() or _opponent.is_selected_locked()):
		_notice.text = ""


func _cycler(parent: Container, label_text: String, options: PackedStringArray, index: int) -> OptionCycler:
	parent.add_child(make_label(label_text, &"SubtleLabel"))
	var cycler := OptionCycler.new()
	cycler.name = label_text.get_slice(" ", 0)
	cycler.set_options(options, index)
	cycler.custom_minimum_size.x = 400.0
	parent.add_child(cycler)
	return cycler


func _card(parent: Container) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 290.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	return column


## The button for `action` on the device in use, as short text ("Q", "A", "R3").
static func _key(action: StringName) -> String:
	return InputGlyphs.text(action, ActiveDevice.scheme, ActiveDevice.pad_family, true)


func _fill_card(card: VBoxContainer, id: StringName, locked: bool) -> void:
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()
	var info := Roster.fighter(id)
	var sigil := ColorRect.new()
	sigil.custom_minimum_size = Vector2(0.0, 6.0)
	sigil.color = Palette.LOCKED if locked else info["color"]
	card.add_child(sigil)
	var title := make_label(info["name"], &"SubheaderLabel")
	card.add_child(title)
	card.add_child(make_label(info["epithet"], &"SubtleLabel"))
	if locked:
		title.add_theme_color_override("font_color", Palette.LOCKED.lightened(0.3))
		var note := make_label("Locked", &"StrongLabel")
		note.add_theme_color_override("font_color", Palette.EMBER_DIM)
		card.add_child(note)
		var how := make_label("Unlocked through Story mode.", &"SubtleLabel")
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(how)
		return
	var style := make_label(info["style"], &"BodyLabel")
	style.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(style)
	card.add_child(HSeparator.new())
	var abilities := Roster.ability_names(id)
	for i in abilities.size():
		card.add_child(make_label("%s   %s" % [_key(DefaultBindings.ability_action(i)), abilities[i]], &"BodyLabel"))
	var skill_kit := MatchSetup.fighter_data(id).dash != null
	var super_label := make_label("%s   %s" % [_key(DefaultBindings.AWAKEN) if skill_kit else "Super", info["super"]], &"StrongLabel")
	super_label.add_theme_color_override("font_color", Palette.SOUL)
	card.add_child(super_label)
	var trait_label := make_label(info["trait"], &"SubtleLabel")
	trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(trait_label)
