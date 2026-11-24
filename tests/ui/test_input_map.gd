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
	# design-lost-ark §2, written out independently of the table:
	# [action, gamepad, keyboard+mouse, keyboard only].
	var rows: Array[Array] = [
		[B.BASIC, B.button(JOY_BUTTON_X), B.mouse(MOUSE_BUTTON_LEFT), B.key(KEY_J)],
		[B.DASH, B.button(JOY_BUTTON_B), B.key(KEY_SPACE), B.key(KEY_SPACE)],
		[B.SKILL_1, B.button(JOY_BUTTON_A), B.key(KEY_Q), B.key(KEY_Q)],
		[B.SKILL_2, B.button(JOY_BUTTON_Y), B.key(KEY_E), B.key(KEY_E)],
		[B.SKILL_3, B.button(JOY_BUTTON_RIGHT_SHOULDER), B.key(KEY_R), B.key(KEY_R)],
		[B.SKILL_4, B.button(JOY_BUTTON_LEFT_SHOULDER), B.key(KEY_F), B.key(KEY_F)],
		[B.SKILL_5, B.axis(JOY_AXIS_TRIGGER_RIGHT, 1.0), B.key(KEY_Z), B.key(KEY_Z)],
		[B.SKILL_5, null, B.mouse(MOUSE_BUTTON_RIGHT), null],
		[B.SKILL_6, B.axis(JOY_AXIS_TRIGGER_LEFT, 1.0), B.key(KEY_X), B.key(KEY_X)],
		[B.SKILL_6, null, B.mouse(MOUSE_BUTTON_XBUTTON1), null],
		[B.AWAKEN, B.button(JOY_BUTTON_RIGHT_STICK), B.key(KEY_V), B.key(KEY_V)],
		[B.AWAKEN, B.button(JOY_BUTTON_DPAD_UP), null, null],
		[B.LOCK_ON, B.button(JOY_BUTTON_DPAD_DOWN), B.key(KEY_TAB), B.key(KEY_TAB)],
		[B.TARGET_NEXT, B.button(JOY_BUTTON_DPAD_RIGHT), null, null],
		[B.PAUSE, B.button(JOY_BUTTON_START), B.key(KEY_ESCAPE), B.key(KEY_ESCAPE)],
		[B.MOVE_FORWARD, B.axis(JOY_AXIS_LEFT_Y, -1.0), B.key(KEY_W), B.key(KEY_W)],
		[B.MOVE_LEFT, B.axis(JOY_AXIS_LEFT_X, -1.0), B.key(KEY_A), B.key(KEY_A)],
		[B.MOVE_BACK, B.axis(JOY_AXIS_LEFT_Y, 1.0), B.key(KEY_S), B.key(KEY_S)],
		[B.MOVE_RIGHT, B.axis(JOY_AXIS_LEFT_X, 1.0), B.key(KEY_D), B.key(KEY_D)],
		[B.AIM_LEFT, B.axis(JOY_AXIS_RIGHT_X, -1.0), null, B.key(KEY_LEFT)],
		[B.AIM_UP, B.axis(JOY_AXIS_RIGHT_Y, -1.0), null, B.key(KEY_UP)],
	]
	for row in rows:
		var action: StringName = row[0]
		var events := InputMap.action_get_events(action)
		for i in range(1, 4):
			if row[i] != null:
				assert_true(_contains(events, row[i]), "%s lacks %s" % [action, B.describe(row[i])])
	assert_eq(B.ability_actions(), [B.SKILL_1, B.SKILL_2, B.SKILL_3, B.SKILL_4, B.SKILL_5, B.SKILL_6] as Array[StringName])
	for removed: StringName in [&"attack_heavy", &"jump", &"guard", &"grab", &"ability_modifier"]:
		assert_false(InputMap.has_action(removed), "%s has no player binding in the skill kit" % removed)


func test_no_chords_by_default() -> void:
	for binding in B.gameplay():
		assert_true(binding.gamepad_chord.is_empty(), "%s is a single button" % binding.action)
		assert_eq(B.gamepad_hint(binding.action), "")


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
	var press := B.key(KEY_Z)
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	assert_true(Input.is_action_pressed(B.SKILL_5))
	var release := B.key(KEY_Z)
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	assert_false(Input.is_action_pressed(B.SKILL_5))


func _contains(events: Array[InputEvent], event: InputEvent) -> bool:
	return events.any(func(e: InputEvent) -> bool: return B.same_event(e, event))
