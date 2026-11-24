class_name InputGlyphs
extends RefCounted
## Button glyphs (Kenney Input Prompts, CC0) and plain-text labels for an action in a scheme.
##
## parts() returns what to draw, in order: Texture2D glyphs and short Strings ("+", "/").
## Besides the gameplay actions, two grouped actions exist for prompts: MOVE and CAMERA.

const MOVE := &"move"
const CAMERA := &"camera"

const _DIR := "res://assets/kenney-input-prompts/"
const _XBOX: Dictionary[JoyButton, String] = {
	JOY_BUTTON_A: "xbox/xbox_button_a", JOY_BUTTON_B: "xbox/xbox_button_b",
	JOY_BUTTON_X: "xbox/xbox_button_x", JOY_BUTTON_Y: "xbox/xbox_button_y",
	JOY_BUTTON_LEFT_SHOULDER: "xbox/xbox_lb", JOY_BUTTON_RIGHT_SHOULDER: "xbox/xbox_rb",
	JOY_BUTTON_RIGHT_STICK: "xbox/xbox_rs", JOY_BUTTON_START: "xbox/xbox_button_menu",
}
const _PLAYSTATION: Dictionary[JoyButton, String] = {
	JOY_BUTTON_A: "playstation/playstation_button_cross", JOY_BUTTON_B: "playstation/playstation_button_circle",
	JOY_BUTTON_X: "playstation/playstation_button_square", JOY_BUTTON_Y: "playstation/playstation_button_triangle",
	JOY_BUTTON_LEFT_SHOULDER: "playstation/playstation_trigger_l1", JOY_BUTTON_RIGHT_SHOULDER: "playstation/playstation_trigger_r1",
	JOY_BUTTON_RIGHT_STICK: "playstation/playstation_button_r3", JOY_BUTTON_START: "playstation/playstation5_button_options",
}
const _PS_TEXT: Dictionary[JoyButton, String] = {
	JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Options",
}
const _XBOX_TEXT: Dictionary[JoyButton, String] = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_START: "Menu",
}
const _KEY_FILES: Dictionary[Key, String] = {
	KEY_SPACE: "space", KEY_SHIFT: "shift", KEY_TAB: "tab", KEY_ESCAPE: "escape", KEY_SEMICOLON: "semicolon",
}
const _MOUSE_FILES: Dictionary[MouseButton, String] = {
	MOUSE_BUTTON_LEFT: "mouse_left", MOUSE_BUTTON_RIGHT: "mouse_right", MOUSE_BUTTON_MIDDLE: "mouse_scroll",
}

static var _cache: Dictionary[String, Texture2D] = {}


## What to draw for `action` in `scheme`: Texture2D glyphs and joiner strings.
static func parts(action: StringName, scheme: int, family: int) -> Array:
	var result: Array = []
	for token: Variant in _tokens(action, scheme, family):
		if token is String and (token == "+" or token == "/"):
			result.append(token)
			continue
		var texture: Texture2D = _texture(token[0]) if token is Array else null
		result.append(texture if texture != null else (token[1] if token is Array else token))
	return result


## Plain text for `action` in `scheme`, e.g. "LT + X", "J", "Left mouse / Tab".
static func text(action: StringName, scheme: int, family: int) -> String:
	var words := PackedStringArray()
	for token: Variant in _tokens(action, scheme, family):
		words.append(token if token is String else token[1])
	return " ".join(words)


## [glyph file, text] pairs and joiners.
static func _tokens(action: StringName, scheme: int, family: int) -> Array:
	var pad := scheme == ActiveDevice.Scheme.GAMEPAD
	var ps := family == ActiveDevice.PadFamily.PLAYSTATION
	if action == MOVE:
		if pad:
			return [[(_PS_STICK_L if ps else _XBOX_STICK_L), "Left stick"]]
		return [_key(KEY_W), _key(KEY_A), _key(KEY_S), _key(KEY_D)]
	if action == CAMERA:
		if pad:
			return [[(_PS_STICK_R if ps else _XBOX_STICK_R), "Right stick"]]
		if scheme == ActiveDevice.Scheme.KEYBOARD_MOUSE:
			return [["keyboard/mouse_move", "Mouse"]]
		return [["keyboard/keyboard_arrows_all", "Arrow keys"]]
	var binding := _binding(action)
	if binding == null:
		return [String(action).capitalize()]
	if pad:
		if not binding.gamepad_chord.is_empty():
			return _chord(binding.gamepad_chord, ps)
		return _join(binding.gamepad, ps)
	return _join(binding.keyboard_mouse if scheme == ActiveDevice.Scheme.KEYBOARD_MOUSE else binding.keyboard_only, ps)


const _XBOX_STICK_L := "xbox/xbox_stick_l"
const _XBOX_STICK_R := "xbox/xbox_stick_r"
const _PS_STICK_L := "playstation/playstation_stick_l"
const _PS_STICK_R := "playstation/playstation_stick_r"


static func _join(events: Array[InputEvent], ps: bool) -> Array:
	var result: Array = []
	for event in events:
		var token: Variant = _event_token(event, ps)
		if token == null:
			continue
		if not result.is_empty():
			result.append("/")
		result.append(token)
	return result


static func _chord(events: Array[InputEvent], ps: bool) -> Array:
	var result: Array = []
	for event in events:
		var token: Variant = _event_token(event, ps)
		if token == null:
			continue
		if not result.is_empty():
			result.append("+")
		result.append(token)
	return result


static func _event_token(event: InputEvent, ps: bool) -> Variant:
	if event is InputEventKey:
		return _key((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		var index := (event as InputEventMouseButton).button_index
		return ["keyboard/" + _MOUSE_FILES.get(index, "mouse"), DefaultBindings.describe(event)]
	if event is InputEventJoypadButton:
		var index := (event as InputEventJoypadButton).button_index
		if index >= JOY_BUTTON_DPAD_UP and index <= JOY_BUTTON_DPAD_RIGHT:
			return null
		return _pad_button(index, ps)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis == JOY_AXIS_TRIGGER_LEFT or motion.axis == JOY_AXIS_TRIGGER_RIGHT:
			return _trigger(motion.axis, ps)
		var left := motion.axis == JOY_AXIS_LEFT_X or motion.axis == JOY_AXIS_LEFT_Y
		if ps:
			return [_PS_STICK_L if left else _PS_STICK_R, "Left stick" if left else "Right stick"]
		return [_XBOX_STICK_L if left else _XBOX_STICK_R, "Left stick" if left else "Right stick"]
	return null


static func _key(code: Key) -> Array:
	var name: String = _KEY_FILES.get(code, OS.get_keycode_string(code).to_lower())
	return ["keyboard/keyboard_" + name, DefaultBindings.describe(DefaultBindings.key(code))]


static func _pad_button(index: JoyButton, ps: bool) -> Array:
	if ps:
		return [_PLAYSTATION.get(index, ""), _PS_TEXT.get(index, "Button")]
	return [_XBOX.get(index, ""), _XBOX_TEXT.get(index, "Button")]


static func _trigger(axis: JoyAxis, ps: bool) -> Array:
	var left := axis == JOY_AXIS_TRIGGER_LEFT
	if ps:
		return ["playstation/playstation_trigger_" + ("l2" if left else "r2"), "L2" if left else "R2"]
	return ["xbox/xbox_" + ("lt" if left else "rt"), "LT" if left else "RT"]


static func _binding(action: StringName) -> DefaultBindings.Binding:
	return DefaultBindings.find(action)


static func clear_cache() -> void:
	_cache.clear()


static func _texture(file: String) -> Texture2D:
	if file.is_empty():
		return null
	if not _cache.has(file):
		var path := _DIR + file + ".png"
		_cache[file] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[file]
