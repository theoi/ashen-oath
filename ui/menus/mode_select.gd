extends MenuScreen
## Mode select: Story, Versus, Controls, Settings, and Quit outside the web build.

var _entries: VBoxContainer
var _description: Label


func _ready() -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 70.0
	column.offset_right = 620.0
	column.offset_top = 70.0
	column.offset_bottom = -60.0
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	column.add_child(make_label("ASHEN OATH", &"HeaderLabel"))
	var gap := Control.new()
	gap.custom_minimum_size.y = 40.0
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)

	_entries = VBoxContainer.new()
	_entries.add_theme_constant_override("separation", 4)
	column.add_child(_entries)
	_add_entry("Story", "Act 1: The Bell Wakes. Fight through the Reckoning as Sir Aldric Vane.",
			func() -> void: GameFlow.open_screen(&"story"))
	_add_entry("Versus", "Face the CPU. Pick your fighter, your opponent and the arena. Best of three.",
			func() -> void: GameFlow.open_screen(&"versus"), &"versus")
	_add_entry("Controls", "Default bindings for gamepad, keyboard and mouse, and keyboard only.",
			func() -> void: GameFlow.open_screen(&"controls"))
	_add_entry("Settings", "Volume, default difficulty and fighter unlocks.",
			func() -> void: GameFlow.open_screen(&"settings"))
	if GameFlow.can_quit():
		_add_entry("Quit", "Leave Vael to its bell.", GameFlow.quit_game)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(filler)
	_description = make_label("", &"SubtleLabel")
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_description)


func default_focus() -> Control:
	return _entries.get_child(0) as Control


func _add_entry(text: String, description: String, on_press: Callable, requires_screen: StringName = &"") -> void:
	var button := make_button(text, on_press, &"MenuEntryButton")
	button.name = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if not requires_screen.is_empty() and not GameFlow.SCREENS.has(requires_screen):
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
	button.focus_entered.connect(func() -> void: _description.text = description)
	_entries.add_child(button)
