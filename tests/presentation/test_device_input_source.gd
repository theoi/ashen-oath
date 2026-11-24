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
	assert_eq(SimInput.aim_z(frame), -SimInput.AIM_MAX, "camera-up is world forward (-Z without a camera)")


func test_no_input_means_no_aim() -> void:
	var sim := F.fighting_sim(F.config(2))
	assert_false(SimInput.has_aim(DeviceInputSource.new().next_frame(sim, 0)))
