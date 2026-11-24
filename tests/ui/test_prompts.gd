extends TestCase
## Button prompts follow the device the player last used.

const B := preload("res://ui/input/default_bindings.gd")

var _scheme_before: int
var _family_before: int


func before_each() -> void:
	_scheme_before = ActiveDevice.scheme
	_family_before = ActiveDevice.pad_family
	ActiveDevice.set_scheme(ActiveDevice.Scheme.KEYBOARD_MOUSE, ActiveDevice.PadFamily.XBOX)


func after_each() -> void:
	ActiveDevice.set_scheme(_scheme_before as ActiveDevice.Scheme, _family_before as ActiveDevice.PadFamily)


func test_input_events_switch_the_scheme() -> void:
	ActiveDevice.note(_pad_button(JOY_BUTTON_A))
	assert_eq(ActiveDevice.scheme, ActiveDevice.Scheme.GAMEPAD, "a pad button")
	ActiveDevice.note(_key(KEY_W))
	assert_eq(ActiveDevice.scheme, ActiveDevice.Scheme.KEYBOARD_MOUSE, "a shared key returns to the last keyboard scheme")
	ActiveDevice.note(_key(KEY_J))
	assert_eq(ActiveDevice.scheme, ActiveDevice.Scheme.KEYBOARD_ONLY, "J is only bound in keyboard-only")
	ActiveDevice.note(_key(KEY_SPACE))
	assert_eq(ActiveDevice.scheme, ActiveDevice.Scheme.KEYBOARD_ONLY, "shared keys keep the scheme")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ActiveDevice.note(click)
	assert_eq(ActiveDevice.scheme, ActiveDevice.Scheme.KEYBOARD_MOUSE, "a mouse click")
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.1
	ActiveDevice.note(drift)
	assert_eq(ActiveDevice.scheme, ActiveDevice.Scheme.KEYBOARD_MOUSE, "stick drift does not switch")


func test_prompts_update_when_the_device_changes() -> void:
	var prompt: InputPrompt = add_child_autofree(InputPrompt.new(B.ABILITY_1))
	await wait_frames(1)
	assert_eq(prompt.describe(), "1")
	assert_true(prompt.get_child(0) is TextureRect, "drawn as a glyph")
	ActiveDevice.set_scheme(ActiveDevice.Scheme.GAMEPAD, ActiveDevice.PadFamily.XBOX)
	assert_eq(prompt.describe(), "LT + X")
	assert_eq(prompt.get_child_count(), 3, "trigger glyph, plus, button glyph")
	ActiveDevice.set_scheme(ActiveDevice.Scheme.GAMEPAD, ActiveDevice.PadFamily.PLAYSTATION)
	assert_eq(prompt.describe(), "L2 + Square")
	ActiveDevice.set_scheme(ActiveDevice.Scheme.KEYBOARD_ONLY)
	assert_eq(prompt.describe(), "U")


func test_hud_ability_bar_prompts_follow_the_device() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	await wait_frames(1)
	hud.apply(_state(["Oathfire Lunge", "Brand Rise", "Bulwark Charge"]))
	var texts := func() -> PackedStringArray:
		var out := PackedStringArray()
		for prompt in hud.ability_bar().prompts():
			out.append(prompt.describe())
		return out
	assert_eq(texts.call(), PackedStringArray(["1", "2", "3", "R"]))
	ActiveDevice.set_scheme(ActiveDevice.Scheme.GAMEPAD, ActiveDevice.PadFamily.XBOX)
	assert_eq(texts.call(), PackedStringArray(["LT + X", "LT + Y", "LT + B", "RT"]))
	ActiveDevice.set_scheme(ActiveDevice.Scheme.KEYBOARD_ONLY)
	assert_eq(texts.call(), PackedStringArray(["U", "I", "O", "P"]))


func test_ability_bar_follows_the_fighters_slot_count() -> void:
	var hud: Hud = add_child_autofree(Hud.new())
	await wait_frames(1)
	hud.apply(_state(["A", "B", "C", "D", "E", "F"]))
	var bar := hud.ability_bar()
	assert_eq(bar.slot_count(), 6)
	assert_eq(bar.prompts().size(), 7, "six slots and the super")
	assert_eq(bar.prompts()[3].action, B.ability_action(3), "slot 4 asks for ability_4")
	hud.apply(_state(["A", "B"]))
	assert_eq(bar.slot_count(), 2, "slots are rebuilt when the fighter changes")
	assert_eq(bar.prompts().size(), 3)


func test_every_bound_action_has_glyphs_in_every_scheme() -> void:
	var actions: Array[StringName] = [InputGlyphs.MOVE, InputGlyphs.CAMERA]
	for binding in B.gameplay():
		if binding.action != B.ABILITY_MODIFIER and not String(binding.action).begins_with("move_") and not String(binding.action).begins_with("camera_"):
			actions.append(binding.action)
	for scheme in 3:
		for family in 2:
			for action in actions:
				var parts := InputGlyphs.parts(action, scheme, family)
				assert_false(parts.is_empty(), "%s has a prompt in scheme %d" % [action, scheme])
				for part: Variant in parts:
					if part is String and part != "+" and part != "/":
						fail("%s in scheme %d/%d falls back to text '%s' (missing glyph)" % [action, scheme, family, part])


func _state(ability_names: PackedStringArray) -> HudState:
	var state := HudState.new()
	for slot in 2:
		var fighter := HudState.Fighter.new()
		fighter.slot = slot
		fighter.name = "Fighter %d" % slot
		fighter.team = slot
		fighter.is_player = slot == 0
		fighter.ability_names = ability_names
		state.fighters.append(fighter)
	return state


func _pad_button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event
