extends MenuScreen
## Move list for one fighter (GameFlow.move_list_fighter), generated from its data by
## MoveList. Inputs are drawn for the device the player last used and switch live.

const NAME_WIDTH := 250.0
const CONTEXT_WIDTH := 120.0
const INPUT_WIDTH := 210.0

var _first_row: Control
var _device: Label
var _scroll: ScrollContainer


func _ready() -> void:
	var id := GameFlow.move_list_fighter
	var data := MatchSetup.fighter_data(id)
	var page := make_page("Move list  ·  %s" % Roster.fighter_name(id))
	_device = make_label("", &"SubtleLabel")
	page.add_child(_device)
	ActiveDevice.changed.connect(_show_device)
	_show_device()

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	page.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	_scroll.add_child(list)

	var section := ""
	for entry in MoveList.build(data, load(MatchSetup.RULES) as CombatRules):
		if entry.section != section:
			section = entry.section
			var header := make_label(section, &"SubheaderLabel")
			header.add_theme_color_override("font_color", Palette.EMBER)
			list.add_child(header)
		list.add_child(_row(entry))

	var back := make_button("Back", go_back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(back)


func default_focus() -> Control:
	return _first_row


func _show_device() -> void:
	var scheme := ActiveDevice.scheme_name()
	_device.text = "Showing %s controls. Use any other device to switch." % (scheme.left(1).to_lower() + scheme.substr(1))


func _row(entry: MoveList.Entry) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"RowPanel"
	panel.focus_mode = Control.FOCUS_ALL
	panel.mouse_entered.connect(panel.grab_focus)
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(Palette.EMBER.r, Palette.EMBER.g, Palette.EMBER.b, 0.14)
	lit.border_color = Palette.EMBER
	lit.border_width_left = 3
	lit.content_margin_left = 12.0
	lit.content_margin_right = 12.0
	lit.content_margin_top = 4.0
	lit.content_margin_bottom = 4.0
	panel.focus_entered.connect(func() -> void: panel.add_theme_stylebox_override("panel", lit))
	panel.focus_exited.connect(func() -> void: panel.remove_theme_stylebox_override("panel"))
	if _first_row == null:
		_first_row = panel

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var name := make_label(entry.name, &"StrongLabel")
	name.custom_minimum_size.x = NAME_WIDTH
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name)
	var context := make_label(entry.context, &"SubtleLabel")
	context.custom_minimum_size.x = CONTEXT_WIDTH
	context.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(context)
	var inputs := HBoxContainer.new()
	inputs.custom_minimum_size.x = INPUT_WIDTH
	inputs.add_theme_constant_override("separation", 6)
	for action in entry.inputs:
		inputs.add_child(InputPrompt.new(action, 30.0))
	row.add_child(inputs)
	var detail := make_label(entry.detail, &"BodyLabel")
	detail.add_theme_font_size_override("font_size", 19)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(detail)
	return panel
