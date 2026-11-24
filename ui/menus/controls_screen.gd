extends MenuScreen
## Controls screen: the default bindings for each control scheme, read from DefaultBindings.

const B := preload("res://ui/input/default_bindings.gd")

## [row label, actions]. Direction groups are summarized ("Left stick", "W A S D", "Arrow keys").
## Ability slots are inserted after ABILITY_ROWS_AFTER from the bindings table.
const ABILITY_ROWS_AFTER := "Grab / grab tech"
const ROWS: Array[Array] = [
	["Move", [B.MOVE_FORWARD, B.MOVE_LEFT, B.MOVE_BACK, B.MOVE_RIGHT]],
	["Camera", [B.CAMERA_UP, B.CAMERA_LEFT, B.CAMERA_DOWN, B.CAMERA_RIGHT]],
	["Light attack", [B.LIGHT]],
	["Heavy attack (hold to charge)", [B.HEAVY]],
	["Jump", [B.JUMP]],
	["Dodge / tech", [B.DODGE]],
	["Guard (hold) / Parry (tap)", [B.GUARD]],
	["Grab / grab tech", [B.GRAB]],
	["Super / Soul Burst (in hitstun)", [B.SUPER]],
	["Lock-on / switch target", [B.LOCK_ON]],
	["Pause", [B.PAUSE]],
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


static func _rows() -> Array[Array]:
	var rows: Array[Array] = []
	for row in ROWS:
		rows.append(row)
		if row[0] == ABILITY_ROWS_AFTER:
			for action in B.ability_actions():
				rows.append([B.find(action).label, [action]])
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
			if text.begins_with("D-pad"):
				text = "D-pad"
			if not text in names:
				names.append(text)
	return " / ".join(names)


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
	return (" " if actions.size() > 1 else " / ").join(names)
