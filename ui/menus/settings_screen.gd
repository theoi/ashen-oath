extends MenuScreen
## Settings: bus volumes, default CPU difficulty and the unlock-all-fighters toggle.
## Changes apply at once and are saved shortly after the last change, and on leaving.

const SAVE_DELAY := 0.6
const VOLUME_ROWS: Array[Array] = [
	["Master volume", &"Master"],
	["Music volume", &"Music"],
	["Effects volume", &"SFX"],
	["Interface volume", &"UI"],
]

var _first: Control
var _save_timer: Timer
var _difficulty: OptionCycler
var _unlock: OptionCycler


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(Settings.save_settings)
	add_child(_save_timer)

	var page := make_page("Settings")
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size.x = 760.0
	page.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)

	for entry in VOLUME_ROWS:
		var slider := _volume_slider(entry[1])
		rows.add_child(_row(entry[0], slider))
		if _first == null:
			_first = slider

	rows.add_child(HSeparator.new())
	_difficulty = OptionCycler.new()
	_difficulty.custom_minimum_size.x = 300.0
	_difficulty.set_options(MatchConfig.DIFFICULTY_NAMES, Settings.default_difficulty)
	_difficulty.selection_changed.connect(func(index: int) -> void:
		Settings.set_default_difficulty(index as MatchConfig.Difficulty)
		_queue_save())
	rows.add_child(_row("Default difficulty", _difficulty))

	_unlock = OptionCycler.new()
	_unlock.custom_minimum_size.x = 300.0
	_unlock.set_options(["Off", "On"], 1 if Settings.unlock_all_fighters else 0)
	_unlock.selection_changed.connect(func(index: int) -> void:
		Settings.set_unlock_all_fighters(index == 1)
		_queue_save())
	rows.add_child(_row("Unlock all fighters (versus)", _unlock))

	var back := make_button("Back", go_back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(back)


func default_focus() -> Control:
	return _first


func go_back() -> void:
	_flush_save()
	super.go_back()


func _exit_tree() -> void:
	_flush_save()


func _flush_save() -> void:
	if _save_timer != null and not _save_timer.is_stopped():
		_save_timer.stop()
		Settings.save_settings()


func _queue_save() -> void:
	_save_timer.start()


func _volume_slider(bus: StringName) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.volume(bus)
	slider.custom_minimum_size = Vector2(300.0, 28.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.mouse_entered.connect(slider.grab_focus)
	slider.value_changed.connect(func(value: float) -> void:
		Settings.set_volume(bus, value)
		if bus != &"Music":
			Sound.play(&"ui_cycle")
		_queue_save())
	return slider


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var label := make_label(label_text, &"BodyLabel")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if control is HSlider:
		var value := make_label("", &"StrongLabel")
		value.custom_minimum_size.x = 64.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var slider := control as HSlider
		var show := func(v: float) -> void: value.text = "%d%%" % roundi(v * 100.0)
		show.call(slider.value)
		slider.value_changed.connect(show)
		row.add_child(control)
		row.add_child(value)
	else:
		row.add_child(control)
	return row
