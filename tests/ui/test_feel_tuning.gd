extends TestCase
## The feel-tuning values and panel (design-lost-ark §1.13).

const PATH := "user://test_feel_tuning.cfg"


func before_each() -> void:
	FeelTuning.path = PATH
	FeelTuning.reset_to_defaults()


func after_each() -> void:
	FeelTuning.close_panel()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	FeelTuning.path = FeelTuning.DEFAULT_PATH
	FeelTuning.load_values()


func test_defaults_follow_the_design_table() -> void:
	var expected := {
		FeelTuning.HITSTOP_SCALE: 1.0, FeelTuning.SHAKE_SCALE: 1.0, FeelTuning.FLASH_INTENSITY: 1.0,
		FeelTuning.SKILL_SPEED: 100.0, FeelTuning.DASH_DISTANCE: 4.5, FeelTuning.DASH_CHARGES: 2.0,
		FeelTuning.DASH_RECHARGE: 5.0, FeelTuning.CAMERA_PITCH: 48.0, FeelTuning.CAMERA_DISTANCE: 14.0,
		FeelTuning.CAMERA_DISTANCE_MAX: 20.0, FeelTuning.CAMERA_FOV: 35.0, FeelTuning.CAMERA_FOLLOW: 14.0,
		FeelTuning.AIM_LEAD_MOUSE: 0.5, FeelTuning.AIM_LEAD_PAD: 0.0, FeelTuning.SLOW_MOTION: 0.4,
	}
	for key: StringName in expected:
		assert_almost_eq(FeelTuning.value(key), expected[key], 0.0001, String(key))
	assert_true(FeelTuning.flag(FeelTuning.DAMAGE_NUMBERS))
	assert_almost_eq(FeelTuning.setting(FeelTuning.HITSTOP_SCALE).max_value, 3.0, 0.0001, "hitstop scales 0-3×")


func test_values_clamp_snap_persist_and_signal() -> void:
	var seen := [0]
	var count := func() -> void: seen[0] += 1
	FeelTuning.changed.connect(count)
	FeelTuning.set_value(FeelTuning.CAMERA_PITCH, 80.0)
	FeelTuning.set_value(FeelTuning.SHAKE_SCALE, 0.512)
	FeelTuning.changed.disconnect(count)
	assert_eq(seen[0], 2)
	assert_almost_eq(FeelTuning.value(FeelTuning.CAMERA_PITCH), 65.0, 0.0001, "clamped to the range")
	assert_almost_eq(FeelTuning.value(FeelTuning.SHAKE_SCALE), 0.5, 0.0001, "snapped to the step")
	FeelTuning.reset_to_defaults()
	FeelTuning.load_values()
	assert_almost_eq(FeelTuning.value(FeelTuning.CAMERA_PITCH), 65.0, 0.0001, "saved on change")


func test_sim_values_apply_only_through_the_config_at_match_start() -> void:
	FeelTuning.set_value(FeelTuning.SKILL_SPEED, 120.0)
	var config := SimConfig.new()
	FeelTuning.apply_to(config)
	assert_true(FeelTuning.pending_restart().is_empty(), "the match started with these values")
	assert_eq(config.move_speed_percent, 120)
	assert_eq(config.hitstop_percent, 100)
	assert_eq(config.dash_charges, -1, "defaults leave the fighter's own dash data")
	assert_almost_eq(config.dash_distance, -1.0, 0.0001)
	FeelTuning.set_value(FeelTuning.HITSTOP_SCALE, 2.5)
	FeelTuning.set_value(FeelTuning.DASH_DISTANCE, 6.0)
	FeelTuning.apply_to(config)
	assert_eq(config.hitstop_percent, 250)
	FeelTuning.set_value(FeelTuning.DASH_RECHARGE, 4.0)
	FeelTuning.apply_to(config)
	if &"dash_recharge_frames" in config:
		assert_eq(config.get(&"dash_recharge_frames"), 240, "seconds to frames")
	assert_almost_eq(config.dash_distance, 6.0, 0.0001)
	FeelTuning.set_value(FeelTuning.DASH_CHARGES, 3.0)
	assert_eq(FeelTuning.pending_restart(), PackedStringArray(["Dash charges"]))
	FeelTuning.set_value(FeelTuning.SHAKE_SCALE, 1.5)
	assert_eq(FeelTuning.pending_restart().size(), 1, "live values never need a restart")


func test_copy_text_lists_every_value_and_marks_changes() -> void:
	FeelTuning.set_value(FeelTuning.CAMERA_FOV, 45.0)
	var text := FeelTuning.as_text()
	for setting in FeelTuning.settings():
		assert_true(text.contains(String(setting.key) + " = "), String(setting.key))
	assert_true(text.contains("camera_fov = 45  # default 35"), text)
	assert_true(text.contains("damage_numbers = true"))


func test_panel_opens_with_ctrl_shift_f_and_sliders_set_values() -> void:
	var press := InputEventKey.new()
	press.physical_keycode = KEY_F
	press.ctrl_pressed = true
	press.shift_pressed = true
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await wait_frames(1)
	assert_true(FeelTuning.is_panel_open())
	var panel: TuningPanel = FeelTuning._panel
	panel.slider(FeelTuning.CAMERA_DISTANCE).value = 18.0
	assert_almost_eq(FeelTuning.value(FeelTuning.CAMERA_DISTANCE), 18.0, 0.0001)
	assert_true(panel.values_text().contains("camera_distance = 18"))
	FeelTuning.set_value(FeelTuning.CAMERA_DISTANCE, 12.0)
	assert_almost_eq(panel.slider(FeelTuning.CAMERA_DISTANCE).value, 12.0, 0.0001, "the panel follows outside changes")
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await wait_frames(1)
	assert_false(FeelTuning.is_panel_open())
