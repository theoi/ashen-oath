extends Node
## Autoload `ActiveDevice`: which control scheme the player last used, so prompts show the
## right buttons. Gamepad input switches to GAMEPAD (Xbox or PlayStation glyphs from the pad's
## name); mouse use and keys only the keyboard + mouse scheme binds switch to KEYBOARD_MOUSE;
## keys only the keyboard-only scheme binds (J, K, L, arrows...) switch to KEYBOARD_ONLY.
## Keys both keyboard schemes share (WASD, Space, Esc) keep the last keyboard scheme.

signal changed

enum Scheme { KEYBOARD_MOUSE, KEYBOARD_ONLY, GAMEPAD }
enum PadFamily { XBOX, PLAYSTATION }

const SCHEME_NAMES: PackedStringArray = ["Keyboard + mouse", "Keyboard only", "Gamepad"]
const STICK_THRESHOLD := 0.5
const MOUSE_MOTION_THRESHOLD := 8.0
const PLAYSTATION_NAMES: PackedStringArray = ["ps3", "ps4", "ps5", "dualshock", "dualsense", "sony", "playstation"]

var scheme := Scheme.KEYBOARD_MOUSE
var pad_family := PadFamily.XBOX

var _last_keyboard := Scheme.KEYBOARD_MOUSE
var _mouse_only_keys: Array[Key] = []
var _keyboard_only_keys: Array[Key] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mouse_keys: Array[Key] = []
	var solo_keys: Array[Key] = []
	for binding in DefaultBindings.gameplay():
		for event in binding.keyboard_mouse:
			if event is InputEventKey:
				mouse_keys.append((event as InputEventKey).physical_keycode)
		for event in binding.keyboard_only:
			if event is InputEventKey:
				solo_keys.append((event as InputEventKey).physical_keycode)
	for code in mouse_keys:
		if not code in solo_keys:
			_mouse_only_keys.append(code)
	for code in solo_keys:
		if not code in mouse_keys:
			_keyboard_only_keys.append(code)
	# Captures and dev runs can pick the prompts: -- --device=gamepad|playstation|keyboard
	for arg in OS.get_cmdline_user_args():
		match arg:
			"--device=gamepad":
				set_scheme(Scheme.GAMEPAD, PadFamily.XBOX)
			"--device=playstation":
				set_scheme(Scheme.GAMEPAD, PadFamily.PLAYSTATION)
			"--device=keyboard":
				set_scheme(Scheme.KEYBOARD_ONLY)


func _exit_tree() -> void:
	# Static caches would otherwise hold textures and input events past resource teardown at quit.
	InputGlyphs.clear_cache()
	DefaultBindings.clear_cache()


func scheme_name() -> String:
	if scheme == Scheme.GAMEPAD:
		return "Gamepad (%s)" % ("PlayStation" if pad_family == PadFamily.PLAYSTATION else "Xbox")
	return SCHEME_NAMES[scheme]


func set_scheme(value: Scheme, family: PadFamily = pad_family) -> void:
	if value != Scheme.GAMEPAD:
		_last_keyboard = value
	if value == scheme and family == pad_family:
		return
	scheme = value
	pad_family = family
	changed.emit()


func _input(event: InputEvent) -> void:
	note(event)


## Updates the scheme from one input event.
func note(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if event.is_pressed():
			set_scheme(Scheme.GAMEPAD, _family_of(event.device))
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= STICK_THRESHOLD:
			set_scheme(Scheme.GAMEPAD, _family_of(event.device))
	elif event is InputEventMouseButton:
		if event.is_pressed():
			set_scheme(Scheme.KEYBOARD_MOUSE)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= MOUSE_MOTION_THRESHOLD:
			set_scheme(Scheme.KEYBOARD_MOUSE)
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var code := (event as InputEventKey).physical_keycode
		if code in _keyboard_only_keys:
			set_scheme(Scheme.KEYBOARD_ONLY)
		elif code in _mouse_only_keys:
			set_scheme(Scheme.KEYBOARD_MOUSE)
		elif scheme == Scheme.GAMEPAD:
			set_scheme(_last_keyboard)


func _family_of(device: int) -> PadFamily:
	var name := Input.get_joy_name(device).to_lower()
	for marker in PLAYSTATION_NAMES:
		if name.contains(marker):
			return PadFamily.PLAYSTATION
	return PadFamily.XBOX
