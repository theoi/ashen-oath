class_name TuningPanel
extends PanelContainer
## The hidden feel-tuning panel (FeelTuning owns and shows it): a slider per setting, the
## values as copyable text, and a match restart for the sim settings.

const WIDTH := 400.0
const FONT := 15

var _sliders: Dictionary[StringName, Range] = {}
var _toggles: Dictionary[StringName, CheckButton] = {}
var _shown: Dictionary[StringName, Label] = {}
var _pending: Label
var _text: TextEdit
var _copied: Label
var _restart: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -WIDTH - 16.0
	offset_right = -16.0
	offset_top = 16.0
	offset_bottom = -16.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.035, 0.04, 0.92)
	style.border_color = Palette.EMBER
	style.set_border_width_all(1)
	style.set_content_margin_all(14.0)
	add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	scroll.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("Feel tuning", &"SubheaderLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Close", FeelTuning.close_panel))
	column.add_child(_label("Ctrl+Shift+F toggles this panel.", &"SubtleLabel"))

	column.add_child(_section("Applied live"))
	for setting in FeelTuning.settings():
		if not setting.sim:
			column.add_child(_row(setting))
	column.add_child(_section("Next match (changes the sim)"))
	for setting in FeelTuning.settings():
		if setting.sim:
			column.add_child(_row(setting))
	_pending = _label("", &"SubtleLabel")
	_pending.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	_pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_pending)

	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	column.add_child(buttons)
	buttons.add_child(_button("Copy values", _copy))
	_restart = _button("Restart match", _restart_match)
	buttons.add_child(_restart)
	buttons.add_child(_button("Defaults", func() -> void:
		FeelTuning.reset_to_defaults()
		FeelTuning.save_values()))
	_copied = _label("", &"SubtleLabel")
	column.add_child(_copied)

	_text = TextEdit.new()
	_text.editable = false
	_text.custom_minimum_size.y = 150.0
	_text.add_theme_font_size_override("font_size", 13)
	column.add_child(_text)

	FeelTuning.changed.connect(_refresh)
	visibility_changed.connect(_refresh)
	_refresh()


## The values text shown in the panel (what Copy puts on the clipboard).
func values_text() -> String:
	return _text.text


func slider(key: StringName) -> Range:
	return _sliders.get(key)


func _row(setting: FeelTuning.Setting) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name := _label(setting.label, &"BodyLabel")
	name.custom_minimum_size.x = 128.0
	row.add_child(name)
	if setting.is_toggle():
		var toggle := CheckButton.new()
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle.toggled.connect(func(on: bool) -> void: FeelTuning.set_value(setting.key, 1.0 if on else 0.0))
		_toggles[setting.key] = toggle
		row.add_child(toggle)
	else:
		var slider := HSlider.new()
		slider.min_value = setting.min_value
		slider.max_value = setting.max_value
		slider.step = setting.step
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.x = 110.0
		slider.value_changed.connect(func(v: float) -> void: FeelTuning.set_value(setting.key, v))
		_sliders[setting.key] = slider
		row.add_child(slider)
	var shown := _label("", &"BodyLabel")
	shown.custom_minimum_size.x = 58.0
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shown[setting.key] = shown
	row.add_child(shown)
	return row


func _refresh() -> void:
	for setting in FeelTuning.settings():
		var v := FeelTuning.value(setting.key)
		if _sliders.has(setting.key):
			_sliders[setting.key].set_value_no_signal(v)
		if _toggles.has(setting.key):
			_toggles[setting.key].set_pressed_no_signal(v >= 0.5)
		var shown := _shown[setting.key]
		shown.text = setting.format(v)
		shown.add_theme_color_override("font_color",
				Palette.ASH_TEXT if is_equal_approx(v, setting.default) else Palette.EMBER_BRIGHT)
	var pending := FeelTuning.pending_restart()
	_pending.text = "" if pending.is_empty() else "Restart the match to apply: %s." % ", ".join(pending)
	_restart.disabled = not _in_match()
	_text.text = FeelTuning.as_text()


func _process(_delta: float) -> void:
	if visible and _restart.disabled == _in_match():
		_refresh()


func _in_match() -> bool:
	return GameFlow.current_match != null and is_inside_tree() and get_tree().current_scene is MatchScreen


func _copy() -> void:
	DisplayServer.clipboard_set(FeelTuning.as_text())
	_copied.text = "Copied. If pasting fails, select the text below."


func _restart_match() -> void:
	FeelTuning.close_panel()
	GameFlow.rematch()


func _section(text: String) -> Label:
	var label := _label(text, &"StrongLabel")
	label.add_theme_color_override("font_color", Palette.EMBER)
	return label


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if variation != &"SubheaderLabel":
		label.add_theme_font_size_override("font_size", FONT)
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", FONT)
	button.pressed.connect(action)
	return button
