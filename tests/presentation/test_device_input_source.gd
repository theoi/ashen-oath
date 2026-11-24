extends TestCase
## DeviceInputSource: buttons and aim capture without a real mouse.

const F := preload("res://tests/sim/sim_fixtures.gd")


func after_each() -> void:
	for action: StringName in [DefaultBindings.MOVE_RIGHT, DefaultBindings.CAMERA_UP, DefaultBindings.LIGHT]:
		Input.action_release(action)


func test_movement_direction_is_the_aim_without_mouse_or_right_stick() -> void:
	var sim := F.fighting_sim(F.config(2))
	var source := DeviceInputSource.new()
	Input.action_press(DefaultBindings.MOVE_RIGHT)
	Input.action_press(DefaultBindings.LIGHT)
	var frame := source.next_frame(sim, 0)
	assert_eq(SimInput.buttons_of(frame), SimInput.BASIC)
	assert_eq(SimInput.stick_x(frame), 127)
	assert_false(SimInput.aim_is_point(frame))
	assert_eq(SimInput.aim_x(frame), SimInput.AIM_MAX, "aims along the movement")
	assert_eq(SimInput.aim_z(frame), 0)


func test_right_stick_aim_wins_over_movement() -> void:
	var sim := F.fighting_sim(F.config(2))
	var source := DeviceInputSource.new()
	Input.action_press(DefaultBindings.MOVE_RIGHT)
	Input.action_press(DefaultBindings.CAMERA_UP)
	var frame := source.next_frame(sim, 0)
	assert_eq(SimInput.aim_x(frame), 0)
	assert_eq(SimInput.aim_z(frame), -SimInput.AIM_MAX, "aim-up is world forward (-Z without a camera)")


func test_no_input_means_no_aim() -> void:
	var sim := F.fighting_sim(F.config(2))
	assert_false(SimInput.has_aim(DeviceInputSource.new().next_frame(sim, 0)))

func test_skill_kit_buttons_map_to_sim_bits() -> void:
	var pairs: Array[Array] = [
		[DefaultBindings.BASIC, SimInput.BASIC], [DefaultBindings.DASH, SimInput.DASH],
		[DefaultBindings.AWAKEN, SimInput.AWAKEN], [DefaultBindings.LOCK_ON, SimInput.LOCK],
		[DefaultBindings.TARGET_NEXT, SimInput.TARGET_NEXT],
	]
	for i in SimInput.SKILLS.size():
		pairs.append([DefaultBindings.ability_action(i), SimInput.SKILLS[i]])
	for pair in pairs:
		Input.action_press(pair[0])
		assert_eq(DeviceInputSource.buttons(), pair[1], String(pair[0]))
		Input.action_release(pair[0])


func test_a_skill_key_sets_only_its_slot() -> void:
	var press := DefaultBindings.key(KEY_F)
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	assert_eq(DeviceInputSource.buttons(), SimInput.SKILL_4, "F is skill 4 (design §2)")
	var release := DefaultBindings.key(KEY_F)
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	assert_eq(DeviceInputSource.buttons(), 0)
