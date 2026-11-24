extends MenuScreen
## Controls screen: the default bindings for each control scheme, read from DefaultBindings.

const B := preload("res://ui/input/default_bindings.gd")

## Direction groups, summarized in one row each ("Left stick", "W A S D", "Arrow keys").
const GROUPS: Array[Array] = [
	["Move", [B.MOVE_FORWARD, B.MOVE_LEFT, B.MOVE_BACK, B.MOVE_RIGHT]],
	["Aim", [B.AIM_UP, B.AIM_LEFT, B.AIM_DOWN, B.AIM_RIGHT]],
]
const COLUMNS: PackedStringArray = ["", "Gamepad (Xbox / PS)", "Keyboard + mouse", "Keyboard only"]

var _back: Button


func _ready() -> void:
	var page := make_page("Controls")
	var panel := PanelContainer.new()
	page.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 3)
	panel.add_child(grid)

	for header in COLUMNS:
		grid.add_child(make_label(header, &"StrongLabel"))
	var bindings := {}
	for binding in B.gameplay():
		bindings[binding.action] = binding
	for row in _rows():
		var actions: Array = row[1]
		grid.add_child(make_label(row[0], &"BodyLabel"))
		grid.add_child(_cell(_gamepad_text(actions, bindings)))
		grid.add_child(_cell(_keyboard_text(actions, bindings, true)))
		grid.add_child(_cell(_keyboard_text(actions, bindings, false)))

	page.add_child(make_label("Menus: A / Enter to choose, B / Esc to go back.", &"SubtleLabel"))
	_back = make_button("Back", go_back)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(_back)


## [row label, actions]: the direction groups, then every other action in table order.
static func _rows() -> Array[Array]:
	var rows: Array[Array] = GROUPS.duplicate()
	var grouped: Array = []
	for group in GROUPS:
		grouped.append_array(group[1])
	for binding in B.gameplay():
		if not binding.action in grouped:
			rows.append([binding.label, [binding.action]])
	return rows


func default_focus() -> Control:
	return _back


func _cell(text: String) -> Label:
	var label := make_label(text, &"BodyLabel")
	label.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	return label


func _gamepad_text(actions: Array, bindings: Dictionary) -> String:
	var hint := B.gamepad_hint(actions[0])
	if not hint.is_empty():
		return hint
	var names: PackedStringArray = []
	for action: StringName in actions:
		for event: InputEvent in bindings[action].gamepad:
			var text := B.describe(event)
			if not text in names:
				names.append(text)
	return " / ".join(names) if not names.is_empty() else "—"


func _keyboard_text(actions: Array, bindings: Dictionary, with_mouse: bool) -> String:
	if with_mouse:
		var hint := B.keyboard_mouse_hint(actions[0])
		if not hint.is_empty():
			return hint
	var names: PackedStringArray = []
	for action: StringName in actions:
		var events: Array[InputEvent] = bindings[action].keyboard_mouse if with_mouse else bindings[action].keyboard_only
		for event in events:
			var text := B.describe(event)
			if not text in names:
				names.append(text)
	if names == PackedStringArray(["Up", "Left", "Down", "Right"]):
		return "Arrow keys"
	if names.is_empty():
		return "—"
	return (" " if actions.size() > 1 else " / ").join(names)
