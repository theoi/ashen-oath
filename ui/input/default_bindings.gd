class_name DefaultBindings
extends RefCounted
## Default control bindings (design-lost-ark §2, no chords): gamepad, keyboard + mouse, and
## keyboard only.
##
## This table is the source of truth. tools/gen_input_map.gd writes it into the [input]
## section of project.godot, the controls screen shows it, and a test checks that the
## project's InputMap matches it. All three schemes are active at the same time.
##
## Not in the InputMap, so input capture handles them itself:
## - Mouse aim: the cursor ray-cast onto the floor (DeviceInputSource).
## - Gamepad chords (Binding.gamepad_chord; none by default); use held_ability_chord() and
##   is_chord_consumed() rather than the actions alone.
##
## Skill slots are the actions ability_1, ability_2, ... in the table; prompts, the HUD and
## the move list read them through ability_actions(), so adding a slot is a table change.
## Action ids predate the skill kit and are kept so content and other code stay valid: the
## basic attack is attack_light, the dash is dodge, the awakening is super, aim is camera_*.

const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
## Right stick (gamepad) or arrow keys (keyboard only); the mouse cursor aims otherwise.
const AIM_LEFT := &"camera_left"
const AIM_RIGHT := &"camera_right"
const AIM_UP := &"camera_up"
const AIM_DOWN := &"camera_down"
const BASIC := &"attack_light"
const DASH := &"dodge"
const SKILL_1 := &"ability_1"
const SKILL_2 := &"ability_2"
const SKILL_3 := &"ability_3"
const SKILL_4 := &"ability_4"
const SKILL_5 := &"ability_5"
const SKILL_6 := &"ability_6"
const AWAKEN := &"super"
const LOCK_ON := &"lock_on"
const TARGET_NEXT := &"target_next"
const PAUSE := &"pause"

## Older names for the same actions (fight prompts and the debug view use them).
const LIGHT := BASIC
const DODGE := DASH
const SUPER := AWAKEN
const ABILITY_1 := SKILL_1
const ABILITY_2 := SKILL_2
const ABILITY_3 := SKILL_3
const CAMERA_LEFT := AIM_LEFT
const CAMERA_RIGHT := AIM_RIGHT
const CAMERA_UP := AIM_UP
const CAMERA_DOWN := AIM_DOWN

const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.3
const BUTTON_DEADZONE := 0.5

static var _table: Array[Binding] = []
static var _abilities: Array[StringName] = []


## One action and its default events per control scheme.
class Binding:
	var action: StringName
	## Shown on the controls screen.
	var label: String
	var deadzone: float
	var gamepad: Array[InputEvent] = []
	var keyboard_mouse: Array[InputEvent] = []
	var keyboard_only: Array[InputEvent] = []
	## Gamepad events held together (modifier first). Not written to the InputMap, since the
	## button alone belongs to another action; capture checks them with held_ability_chord().
	var gamepad_chord: Array[InputEvent] = []

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

	func pad_chord(events: Array[InputEvent]) -> Binding:
		gamepad_chord = events
		return self

	## Every event across schemes, without duplicates (WASD is shared by both keyboard schemes).
	func all_events() -> Array[InputEvent]:
		var result: Array[InputEvent] = []
		for event in gamepad + keyboard_mouse + keyboard_only:
			if not result.any(func(e: InputEvent) -> bool: return DefaultBindings.same_event(e, event)):
				result.append(event)
		return result


## Gameplay actions in display order. Skill slots follow the slot convention of §2: 1 gap
## closer, 2 launcher, 3 ranged, 4 defensive, 5 hold / big damage, 6 longest cooldown.
static func gameplay() -> Array[Binding]:
	return [
		Binding.new(MOVE_LEFT, "Move left", STICK_DEADZONE).pad([axis(JOY_AXIS_LEFT_X, -1.0)]).kbm([key(KEY_A)]).kb([key(KEY_A)]),
		Binding.new(MOVE_RIGHT, "Move right", STICK_DEADZONE).pad([axis(JOY_AXIS_LEFT_X, 1.0)]).kbm([key(KEY_D)]).kb([key(KEY_D)]),
		Binding.new(MOVE_FORWARD, "Move forward", STICK_DEADZONE).pad([axis(JOY_AXIS_LEFT_Y, -1.0)]).kbm([key(KEY_W)]).kb([key(KEY_W)]),
		Binding.new(MOVE_BACK, "Move back", STICK_DEADZONE).pad([axis(JOY_AXIS_LEFT_Y, 1.0)]).kbm([key(KEY_S)]).kb([key(KEY_S)]),
		Binding.new(AIM_LEFT, "Aim left", STICK_DEADZONE).pad([axis(JOY_AXIS_RIGHT_X, -1.0)]).kb([key(KEY_LEFT)]),
		Binding.new(AIM_RIGHT, "Aim right", STICK_DEADZONE).pad([axis(JOY_AXIS_RIGHT_X, 1.0)]).kb([key(KEY_RIGHT)]),
		Binding.new(AIM_UP, "Aim up", STICK_DEADZONE).pad([axis(JOY_AXIS_RIGHT_Y, -1.0)]).kb([key(KEY_UP)]),
		Binding.new(AIM_DOWN, "Aim down", STICK_DEADZONE).pad([axis(JOY_AXIS_RIGHT_Y, 1.0)]).kb([key(KEY_DOWN)]),
		Binding.new(BASIC, "Basic attack (hold to repeat)").pad([button(JOY_BUTTON_X)]).kbm([mouse(MOUSE_BUTTON_LEFT)]).kb([key(KEY_J)]),
		Binding.new(DASH, "Dash (Soul Burst in hitstun, quick rise when down)").pad([button(JOY_BUTTON_B)]).kbm([key(KEY_SPACE)]).kb([key(KEY_SPACE)]),
		Binding.new(SKILL_1, "Skill 1").pad([button(JOY_BUTTON_A)]).kbm([key(KEY_Q)]).kb([key(KEY_Q)]),
		Binding.new(SKILL_2, "Skill 2").pad([button(JOY_BUTTON_Y)]).kbm([key(KEY_E)]).kb([key(KEY_E)]),
		Binding.new(SKILL_3, "Skill 3").pad([button(JOY_BUTTON_RIGHT_SHOULDER)]).kbm([key(KEY_R)]).kb([key(KEY_R)]),
		Binding.new(SKILL_4, "Skill 4").pad([button(JOY_BUTTON_LEFT_SHOULDER)]).kbm([key(KEY_F)]).kb([key(KEY_F)]),
		Binding.new(SKILL_5, "Skill 5", TRIGGER_DEADZONE).pad([axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]).kbm([key(KEY_Z), mouse(MOUSE_BUTTON_RIGHT)]).kb([key(KEY_Z)]),
		Binding.new(SKILL_6, "Skill 6", TRIGGER_DEADZONE).pad([axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]).kbm([key(KEY_X), mouse(MOUSE_BUTTON_XBUTTON1)]).kb([key(KEY_X)]),
		Binding.new(AWAKEN, "Awakening").pad([button(JOY_BUTTON_RIGHT_STICK), button(JOY_BUTTON_DPAD_UP)]).kbm([key(KEY_V)]).kb([key(KEY_V)]),
		Binding.new(LOCK_ON, "Lock-on / next target").pad([button(JOY_BUTTON_DPAD_DOWN)]).kbm([key(KEY_TAB)]).kb([key(KEY_TAB)]),
		Binding.new(TARGET_NEXT, "Next target (stay locked)").pad([button(JOY_BUTTON_DPAD_RIGHT)]),
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


static func clear_cache() -> void:
	_table.clear()
	_abilities.clear()


## The binding for `action`, or null.
static func find(action: StringName) -> Binding:
	if _table.is_empty():
		_table = gameplay()
	for binding in _table:
		if binding.action == action:
			return binding
	return null


## Action for ability slot `slot` (0-based): ability_1, ability_2, ...
static func ability_action(slot: int) -> StringName:
	return StringName("ability_%d" % (slot + 1))


## The bound ability slot actions in slot order.
static func ability_actions() -> Array[StringName]:
	if _abilities.is_empty():
		while find(ability_action(_abilities.size())) != null:
			_abilities.append(ability_action(_abilities.size()))
	return _abilities


## Ability slot (1-based) whose gamepad chord is held, or 0. Keyboard ability keys are plain actions.
static func held_ability_chord() -> int:
	var actions := ability_actions()
	for i in actions.size():
		var chord := find(actions[i]).gamepad_chord
		if not chord.is_empty() and chord.all(_pad_event_held):
			return i + 1
	return 0


## True when `action` is only held because its pad button is part of a held chord, so
## capture should not also report the action underneath (light under LT + X).
static func is_chord_consumed(action: StringName) -> bool:
	var binding := find(action)
	if binding == null or binding.gamepad.is_empty():
		return false
	for chord_action in ability_actions():
		var chord := find(chord_action).gamepad_chord
		if chord.is_empty() or not chord.all(_pad_event_held):
			continue
		for event in binding.gamepad:
			if chord.any(func(e: InputEvent) -> bool: return same_event(e, event)):
				return true
	return false


## Gamepad text for actions bound as a chord, e.g. "LT + X  /  L2 + Square"; "" otherwise.
static func gamepad_hint(action: StringName) -> String:
	var binding := find(action)
	if binding == null or binding.gamepad_chord.is_empty():
		return ""
	var xbox := PackedStringArray()
	var playstation := PackedStringArray()
	for event in binding.gamepad_chord:
		# describe() names pad inputs "Xbox / PlayStation".
		var names := describe(event).split(" / ")
		xbox.append(names[0])
		playstation.append(names[names.size() - 1])
	return "%s  /  %s" % [" + ".join(xbox), " + ".join(playstation)]


## Keyboard + mouse text for actions that are not plain events.
static func keyboard_mouse_hint(action: StringName) -> String:
	if action in [AIM_LEFT, AIM_RIGHT, AIM_UP, AIM_DOWN]:
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
		return _KEY_NAMES.get(_key_code(event), OS.get_keycode_string(_key_code(event)))
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "Left mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle mouse"
			MOUSE_BUTTON_XBUTTON1:
				return "Mouse 4"
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


const _KEY_NAMES: Dictionary[Key, String] = {KEY_SEMICOLON: ";", KEY_ESCAPE: "Esc"}

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


static func _pad_event_held(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return _any_joypad_button((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		for device in Input.get_connected_joypads():
			if Input.get_joy_axis(device, motion.axis) * signf(motion.axis_value) >= TRIGGER_DEADZONE:
				return true
	return false


static func _any_joypad_button(index: JoyButton) -> bool:
	for device in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, index):
			return true
	return false
