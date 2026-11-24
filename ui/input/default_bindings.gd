class_name DefaultBindings
extends RefCounted
## Default control bindings from design §7: gamepad, keyboard + mouse, and keyboard only.
##
## This table is the source of truth. tools/gen_input_map.gd writes it into the [input]
## section of project.godot, the controls screen shows it, and a test checks that the
## project's InputMap matches it. All three schemes are active at the same time.
##
## Not in the InputMap, so input capture handles them itself:
## - Mouse camera: read InputEventMouseMotion while the mouse is captured.
## - Right-stick flick to switch target: watch camera_* axis strength.
## - Gamepad abilities are chords (ability_modifier + light / heavy / dodge); use
##   held_ability_slot() and is_chord_consumed() rather than the ability_* actions alone.

const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const CAMERA_LEFT := &"camera_left"
const CAMERA_RIGHT := &"camera_right"
const CAMERA_UP := &"camera_up"
const CAMERA_DOWN := &"camera_down"
const LIGHT := &"attack_light"
const HEAVY := &"attack_heavy"
const JUMP := &"jump"
const DODGE := &"dodge"
const GUARD := &"guard"
const GRAB := &"grab"
const ABILITY_1 := &"ability_1"
const ABILITY_2 := &"ability_2"
const ABILITY_3 := &"ability_3"
## Held on a gamepad (LT / L2) to turn light / heavy / dodge into abilities 1 / 2 / 3.
const ABILITY_MODIFIER := &"ability_modifier"
const SUPER := &"super"
const LOCK_ON := &"lock_on"
const PAUSE := &"pause"

const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.3
const BUTTON_DEADZONE := 0.5

## Gamepad face buttons that become ability 1 / 2 / 3 while ABILITY_MODIFIER is held.
const ABILITY_CHORD_BUTTONS: Array[JoyButton] = [JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_B]
## The actions those face buttons trigger on their own.
const ABILITY_CHORD_BASE_ACTIONS: Array[StringName] = [LIGHT, HEAVY, DODGE]


## One action and its default events per control scheme.
class Binding:
	var action: StringName
	## Shown on the controls screen.
	var label: String
	var deadzone: float
	var gamepad: Array[InputEvent] = []
	var keyboard_mouse: Array[InputEvent] = []
	var keyboard_only: Array[InputEvent] = []

	func _init(p_action: StringName, p_label: String, p_deadzone: float = BUTTON_DEADZONE) -> void:
		action = p_action
		label = p_label
		deadzone = p_deadzone

	func pad(events: Array[InputEvent]) -> Binding:
		gamepad = events
		return self

	func kbm(events: Array[InputEvent]) -> Binding:
		keyboard_mouse = events
		return self

	func kb(events: Array[InputEvent]) -> Binding:
		keyboard_only = events
		return self

	## Every event across schemes, without duplicates (WASD is shared by both keyboard schemes).
	func all_events() -> Array[InputEvent]:
		var result: Array[InputEvent] = []
		for event in gamepad + keyboard_mouse + keyboard_only:
			if not result.any(func(e: InputEvent) -> bool: return DefaultBindings.same_event(e, event)):
				result.append(event)
		return result


## Gameplay actions in display order.
static func gameplay() -> Array[Binding]:
	return [
		Binding.new(MOVE_LEFT, "Move left", STICK_DEADZONE).pad([axis(JOY_AXIS_LEFT_X, -1.0), button(JOY_BUTTON_DPAD_LEFT)]).kbm([key(KEY_A)]).kb([key(KEY_A)]),
		Binding.new(MOVE_RIGHT, "Move right", STICK_DEADZONE).pad([axis(JOY_AXIS_LEFT_X, 1.0), button(JOY_BUTTON_DPAD_RIGHT)]).kbm([key(KEY_D)]).kb([key(KEY_D)]),
		Binding.new(MOVE_FORWARD, "Move forward", STICK_DEADZONE).pad([axis(JOY_AXIS_LEFT_Y, -1.0), button(JOY_BUTTON_DPAD_UP)]).kbm([key(KEY_W)]).kb([key(KEY_W)]),
		Binding.new(MOVE_BACK, "Move back", STICK_DEADZONE).pad([axis(JOY_AXIS_LEFT_Y, 1.0), button(JOY_BUTTON_DPAD_DOWN)]).kbm([key(KEY_S)]).kb([key(KEY_S)]),
		Binding.new(CAMERA_LEFT, "Camera left", STICK_DEADZONE).pad([axis(JOY_AXIS_RIGHT_X, -1.0)]).kb([key(KEY_LEFT)]),
		Binding.new(CAMERA_RIGHT, "Camera right", STICK_DEADZONE).pad([axis(JOY_AXIS_RIGHT_X, 1.0)]).kb([key(KEY_RIGHT)]),
		Binding.new(CAMERA_UP, "Camera up", STICK_DEADZONE).pad([axis(JOY_AXIS_RIGHT_Y, -1.0)]).kb([key(KEY_UP)]),
		Binding.new(CAMERA_DOWN, "Camera down", STICK_DEADZONE).pad([axis(JOY_AXIS_RIGHT_Y, 1.0)]).kb([key(KEY_DOWN)]),
		Binding.new(LIGHT, "Light attack").pad([button(JOY_BUTTON_X)]).kbm([mouse(MOUSE_BUTTON_LEFT)]).kb([key(KEY_J)]),
		Binding.new(HEAVY, "Heavy attack (hold to charge)").pad([button(JOY_BUTTON_Y)]).kbm([mouse(MOUSE_BUTTON_RIGHT)]).kb([key(KEY_K)]),
		Binding.new(JUMP, "Jump").pad([button(JOY_BUTTON_A)]).kbm([key(KEY_SPACE)]).kb([key(KEY_SPACE)]),
		Binding.new(DODGE, "Dodge / tech / air tech").pad([button(JOY_BUTTON_B)]).kbm([key(KEY_SHIFT)]).kb([key(KEY_L)]),
		Binding.new(GUARD, "Guard (hold) / Parry (tap)").pad([button(JOY_BUTTON_RIGHT_SHOULDER)]).kbm([key(KEY_Q)]).kb([key(KEY_SEMICOLON)]),
		Binding.new(GRAB, "Grab / grab tech").pad([button(JOY_BUTTON_LEFT_SHOULDER)]).kbm([key(KEY_E)]).kb([key(KEY_H)]),
		Binding.new(ABILITY_1, "Ability 1").kbm([key(KEY_1)]).kb([key(KEY_U)]),
		Binding.new(ABILITY_2, "Ability 2").kbm([key(KEY_2)]).kb([key(KEY_I)]),
		Binding.new(ABILITY_3, "Ability 3").kbm([key(KEY_3)]).kb([key(KEY_O)]),
		Binding.new(ABILITY_MODIFIER, "Ability modifier", TRIGGER_DEADZONE).pad([axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]),
		Binding.new(SUPER, "Super (Soul Burst in hitstun)", TRIGGER_DEADZONE).pad([axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]).kbm([key(KEY_R)]).kb([key(KEY_P)]),
		Binding.new(LOCK_ON, "Lock-on / switch target").pad([button(JOY_BUTTON_RIGHT_STICK)]).kbm([mouse(MOUSE_BUTTON_MIDDLE), key(KEY_TAB)]).kb([key(KEY_TAB)]),
		Binding.new(PAUSE, "Pause").pad([button(JOY_BUTTON_START)]).kbm([key(KEY_ESCAPE)]).kb([key(KEY_ESCAPE)]),
	]


## Gamepad events added to Godot's built-in ui_* actions so menus work with a pad.
## Their keyboard defaults (and d-pad / left stick for directions) stay in place.
static func ui_additions() -> Dictionary[StringName, Array]:
	return {
		&"ui_accept": [button(JOY_BUTTON_A)],
		&"ui_cancel": [button(JOY_BUTTON_B)],
		&"ui_focus_next": [button(JOY_BUTTON_RIGHT_SHOULDER)],
		&"ui_focus_prev": [button(JOY_BUTTON_LEFT_SHOULDER)],
	}


## Ability slot (1-3) whose gamepad chord is held, or 0. Keyboard ability keys are plain actions.
static func held_ability_chord() -> int:
	if not Input.is_action_pressed(ABILITY_MODIFIER):
		return 0
	for i in ABILITY_CHORD_BUTTONS.size():
		if _any_joypad_button(ABILITY_CHORD_BUTTONS[i]):
			return i + 1
	return 0


## True when `action` is only held because its pad button is part of an ability chord,
## so capture should not also report the light / heavy / dodge underneath.
static func is_chord_consumed(action: StringName) -> bool:
	var index := ABILITY_CHORD_BASE_ACTIONS.find(action)
	if index < 0 or not Input.is_action_pressed(ABILITY_MODIFIER):
		return false
	return _any_joypad_button(ABILITY_CHORD_BUTTONS[index])


## Gamepad text for actions that have no direct pad event.
static func gamepad_hint(action: StringName) -> String:
	match action:
		ABILITY_1:
			return "LT + X  /  L2 + Square"
		ABILITY_2:
			return "LT + Y  /  L2 + Triangle"
		ABILITY_3:
			return "LT + B  /  L2 + Circle"
	return ""


## Keyboard + mouse text for actions that are not plain events.
static func keyboard_mouse_hint(action: StringName) -> String:
	if action in [CAMERA_LEFT, CAMERA_RIGHT, CAMERA_UP, CAMERA_DOWN]:
		return "Mouse"
	return ""


static func key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


static func mouse(index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	return event


static func button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.device = -1
	return event


static func axis(index: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = index
	event.axis_value = direction
	event.device = -1
	return event


## Compares the identity of two binding events (device-agnostic), not their pressed state.
static func same_event(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return _key_code(a) == _key_code(b)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false


## Short display name for one event, e.g. "Left mouse", "Shift", "RB / R1".
static func describe(event: InputEvent) -> String:
	if event is InputEventKey:
		return OS.get_keycode_string(_key_code(event))
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "Left mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle mouse"
		return "Mouse %d" % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return _JOY_BUTTON_NAMES.get((event as InputEventJoypadButton).button_index, "Button")
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		match motion.axis:
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
				return "Left stick"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
				return "Right stick"
			JOY_AXIS_TRIGGER_LEFT:
				return "LT / L2"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT / R2"
	return event.as_text()


const _JOY_BUTTON_NAMES: Dictionary[JoyButton, String] = {
	JOY_BUTTON_A: "A / Cross",
	JOY_BUTTON_B: "B / Circle",
	JOY_BUTTON_X: "X / Square",
	JOY_BUTTON_Y: "Y / Triangle",
	JOY_BUTTON_LEFT_SHOULDER: "LB / L1",
	JOY_BUTTON_RIGHT_SHOULDER: "RB / R1",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Start / Options",
	JOY_BUTTON_BACK: "Back / Share",
	JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}


static func _key_code(event: InputEventKey) -> Key:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode


static func _any_joypad_button(index: JoyButton) -> bool:
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, index):
			return true
	return false
