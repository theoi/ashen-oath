extends TestCase
## Settings persistence: what is saved comes back, and bad files fall back to defaults quietly.

const PATH := "user://test_settings.cfg"
const SCREEN := preload("res://ui/menus/settings_screen.tscn")


func before_each() -> void:
	Settings.path = PATH
	Settings.reset_to_defaults()


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	Settings.path = Settings.DEFAULT_PATH
	Settings.load_settings()


func test_saved_settings_load_back() -> void:
	Settings.set_volume(&"Master", 0.35)
	Settings.set_volume(&"Music", 0.0)
	Settings.set_volume(&"SFX", 1.0)
	Settings.set_volume(&"UI", 0.5)
	Settings.set_default_difficulty(MatchConfig.Difficulty.NIGHTMARE)
	Settings.set_unlock_all_fighters(true)
	Settings.set_brightness(1.35)
	assert_eq(Settings.save_settings(), OK)

	Settings.reset_to_defaults()
	assert_almost_eq(Settings.volume(&"Master"), 0.8, 0.0001, "defaults restored before loading")
	Settings.load_settings()
	assert_almost_eq(Settings.volume(&"Master"), 0.35, 0.0001)
	assert_almost_eq(Settings.volume(&"Music"), 0.0, 0.0001)
	assert_almost_eq(Settings.volume(&"SFX"), 1.0, 0.0001)
	assert_almost_eq(Settings.volume(&"UI"), 0.5, 0.0001)
	assert_eq(Settings.default_difficulty, MatchConfig.Difficulty.NIGHTMARE)
	assert_true(Settings.unlock_all_fighters)
	assert_almost_eq(Settings.brightness, 1.35, 0.0001)


func test_volumes_reach_the_audio_buses() -> void:
	for bus: StringName in Settings.BUSES:
		assert_true(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
	Settings.set_volume(&"SFX", 0.5)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")), linear_to_db(0.5), 0.01)
	Settings.set_volume(&"Music", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "zero volume mutes")


func test_missing_file_gives_defaults() -> void:
	Settings.set_volume(&"Master", 0.1)
	Settings.load_settings()
	assert_almost_eq(Settings.volume(&"Master"), Settings.DEFAULT_VOLUMES[&"Master"], 0.0001)
	assert_eq(Settings.default_difficulty, MatchConfig.Difficulty.NORMAL)
	assert_almost_eq(Settings.brightness, 1.0, 0.0001)


func test_corrupt_or_out_of_range_values_are_ignored_or_clamped() -> void:
	_write("[audio]\nmaster=7.5\nmusic=\"loud\"\n[gameplay]\ndefault_difficulty=99\nunlock_all_fighters=\"yes\"\n[video]\nbrightness=9.0\n")
	Settings.load_settings()
	assert_almost_eq(Settings.brightness, Settings.BRIGHTNESS_MAX, 0.0001, "brightness clamped")
	assert_almost_eq(Settings.volume(&"Master"), 1.0, 0.0001, "clamped")
	assert_almost_eq(Settings.volume(&"Music"), Settings.DEFAULT_VOLUMES[&"Music"], 0.0001, "wrong type ignored")
	assert_eq(Settings.default_difficulty, MatchConfig.Difficulty.NORMAL)
	assert_false(Settings.unlock_all_fighters)

	_write("this is { not a config file")
	Settings.load_settings()
	assert_almost_eq(Settings.volume(&"Master"), Settings.DEFAULT_VOLUMES[&"Master"], 0.0001)


func test_brightness_scales_scene_exposure_without_compounding() -> void:
	var world_env := WorldEnvironment.new()
	world_env.environment = Environment.new()
	world_env.environment.tonemap_exposure = 1.2
	add_child_autofree(world_env)
	await wait_frames(1)
	assert_almost_eq(world_env.environment.tonemap_exposure, 1.2, 0.0001, "default brightness leaves it")

	Settings.set_brightness(1.5)
	assert_almost_eq(world_env.environment.tonemap_exposure, 1.8, 0.0001)
	Settings.set_brightness(0.6)
	Settings.set_brightness(0.6)
	assert_almost_eq(world_env.environment.tonemap_exposure, 0.72, 0.0001, "scales the scene's value, not the last result")
	Settings.set_brightness(9.0)
	assert_almost_eq(Settings.brightness, Settings.BRIGHTNESS_MAX, 0.0001)

	world_env.environment.tonemap_exposure = 0.5
	Settings.set_brightness(2.0)
	assert_almost_eq(world_env.environment.tonemap_exposure, 0.5 * Settings.BRIGHTNESS_MAX, 0.0001, "a scene's own change becomes the base")


func test_brightness_reaches_environments_added_later() -> void:
	Settings.set_brightness(0.8)
	var world_env := WorldEnvironment.new()
	add_child_autofree(world_env)
	world_env.environment = Environment.new()
	world_env.environment.tonemap_exposure = 1.1
	await wait_frames(1)
	assert_almost_eq(world_env.environment.tonemap_exposure, 0.88, 0.0001)


func test_settings_screen_brightness_slider_and_reference() -> void:
	Settings.set_brightness(1.2)
	var screen: MenuScreen = add_child_autofree(SCREEN.instantiate())
	await wait_frames(1)
	var sliders := screen.find_children("*", "HSlider", true, false)
	var brightness: HSlider
	for node: Node in sliders:
		if is_equal_approx((node as HSlider).max_value, Settings.BRIGHTNESS_MAX):
			brightness = node
	assert_not_null(brightness, "a slider spans the brightness range")
	assert_almost_eq(brightness.value, 1.2, 0.0001, "starts at the saved value")
	brightness.value = 0.7
	assert_almost_eq(Settings.brightness, 0.7, 0.0001)
	assert_eq(screen.find_children("*", "BrightnessReference", true, false).size(), 1, "calibration sword shown")


func _write(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
