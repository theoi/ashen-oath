extends TestCase
## The project's InputMap must match DefaultBindings and the default controls in design §7.

const B := preload("res://ui/input/default_bindings.gd")


func test_input_map_matches_the_bindings_table() -> void:
	for binding in B.gameplay():
		if not InputMap.has_action(binding.action):
			fail("missing action %s; rerun tools/gen_input_map.gd" % binding.action)
			continue
		var actual := InputMap.action_get_events(binding.action)
		var expected := binding.all_events()
		assert_eq(actual.size(), expected.size(), "%s event count" % binding.action)
		for event in expected:
			assert_true(_contains(actual, event), "%s lacks %s" % [binding.action, B.describe(event)])
		assert_almost_eq(InputMap.action_get_deadzone(binding.action), binding.deadzone, 0.0001, "%s deadzone" % binding.action)


func test_design_default_bindings() -> void:
	# Design §7, written out independently of the table: [action, gamepad, keyboard+mouse, keyboard only].
	var rows: Array[Array] = [
		[B.LIGHT, B.button(JOY_BUTTON_X), B.mouse(MOUSE_BUTTON_LEFT), B.key(KEY_J)],
		[B.HEAVY, B.button(JOY_BUTTON_Y), B.mouse(MOUSE_BUTTON_RIGHT), B.key(KEY_K)],
		[B.JUMP, B.button(JOY_BUTTON_A), B.key(KEY_SPACE), B.key(KEY_SPACE)],
		[B.DODGE, B.button(JOY_BUTTON_B), B.key(KEY_SHIFT), B.key(KEY_L)],
		[B.GUARD, B.button(JOY_BUTTON_RIGHT_SHOULDER), B.key(KEY_Q), B.key(KEY_SEMICOLON)],
		[B.GRAB, B.button(JOY_BUTTON_LEFT_SHOULDER), B.key(KEY_E), B.key(KEY_H)],
		[B.ABILITY_1, null, B.key(KEY_1), B.key(KEY_U)],
		[B.ABILITY_2, null, B.key(KEY_2), B.key(KEY_I)],
		[B.ABILITY_3, null, B.key(KEY_3), B.key(KEY_O)],
		[B.SUPER, B.axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), B.key(KEY_R), B.key(KEY_P)],
		[B.LOCK_ON, B.button(JOY_BUTTON_RIGHT_STICK), B.mouse(MOUSE_BUTTON_MIDDLE), B.key(KEY_TAB)],
		[B.PAUSE, B.button(JOY_BUTTON_START), B.key(KEY_ESCAPE), B.key(KEY_ESCAPE)],
		[B.MOVE_FORWARD, B.axis(JOY_AXIS_LEFT_Y, -1.0), B.key(KEY_W), B.key(KEY_W)],
		[B.MOVE_LEFT, B.axis(JOY_AXIS_LEFT_X, -1.0), B.key(KEY_A), B.key(KEY_A)],
		[B.MOVE_BACK, B.axis(JOY_AXIS_LEFT_Y, 1.0), B.key(KEY_S), B.key(KEY_S)],
		[B.MOVE_RIGHT, B.axis(JOY_AXIS_LEFT_X, 1.0), B.key(KEY_D), B.key(KEY_D)],
		[B.CAMERA_LEFT, B.axis(JOY_AXIS_RIGHT_X, -1.0), null, B.key(KEY_LEFT)],
		[B.CAMERA_UP, B.axis(JOY_AXIS_RIGHT_Y, -1.0), null, B.key(KEY_UP)],
		[B.ABILITY_MODIFIER, B.axis(JOY_AXIS_TRIGGER_LEFT, 1.0), null, null],
	]
	for row in rows:
		var action: StringName = row[0]
		var events := InputMap.action_get_events(action)
		for i in range(1, 4):
			if row[i] != null:
				assert_true(_contains(events, row[i]), "%s lacks %s" % [action, B.describe(row[i])])
	assert_eq(B.ability_actions(), [B.ABILITY_1, B.ABILITY_2, B.ABILITY_3] as Array[StringName])
	assert_eq(B.gamepad_hint(B.ABILITY_1), "LT + X  /  L2 + Square")
	assert_eq(B.gamepad_hint(B.ABILITY_2), "LT + Y  /  L2 + Triangle")
	assert_eq(B.gamepad_hint(B.ABILITY_3), "LT + B  /  L2 + Circle")
	assert_eq(B.gamepad_hint(B.LIGHT), "", "plain pad buttons need no hint")


func test_no_event_triggers_two_gameplay_actions() -> void:
	var owners: Array[Array] = []
	for binding in B.gameplay():
		for event in InputMap.action_get_events(binding.action):
			for owner in owners:
				if owner[0] != binding.action and B.same_event(owner[1], event):
					fail("%s is bound to both %s and %s" % [B.describe(event), owner[0], binding.action])
			owners.append([binding.action, event])


func test_menus_accept_gamepad_and_keep_keyboard() -> void:
	assert_true(_contains(InputMap.action_get_events(&"ui_accept"), B.button(JOY_BUTTON_A)))
	assert_true(_contains(InputMap.action_get_events(&"ui_cancel"), B.button(JOY_BUTTON_B)))
	assert_true(InputMap.action_get_events(&"ui_cancel").any(func(e: InputEvent) -> bool:
		return e is InputEventKey and (e as InputEventKey).keycode == KEY_ESCAPE), "Esc still cancels")
	assert_true(InputMap.action_get_events(&"ui_accept").any(func(e: InputEvent) -> bool:
		return e is InputEventKey and (e as InputEventKey).keycode == KEY_ENTER), "Enter still accepts")
	assert_true(_contains(InputMap.action_get_events(&"ui_down"), B.button(JOY_BUTTON_DPAD_DOWN)))


func test_pressing_a_bound_key_triggers_its_action() -> void:
	var press := B.key(KEY_SEMICOLON)
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	assert_true(Input.is_action_pressed(B.GUARD))
	var release := B.key(KEY_SEMICOLON)
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	assert_false(Input.is_action_pressed(B.GUARD))


func _contains(events: Array[InputEvent], event: InputEvent) -> bool:
	return events.any(func(e: InputEvent) -> bool: return B.same_event(e, event))
