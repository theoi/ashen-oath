extends TestCase
## Settings persistence: what is saved comes back, and bad files fall back to defaults quietly.

const PATH := "user://test_settings.cfg"


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


func test_corrupt_or_out_of_range_values_are_ignored_or_clamped() -> void:
	_write("[audio]\nmaster=7.5\nmusic=\"loud\"\n[gameplay]\ndefault_difficulty=99\nunlock_all_fighters=\"yes\"\n")
	Settings.load_settings()
	assert_almost_eq(Settings.volume(&"Master"), 1.0, 0.0001, "clamped")
	assert_almost_eq(Settings.volume(&"Music"), Settings.DEFAULT_VOLUMES[&"Music"], 0.0001, "wrong type ignored")
	assert_eq(Settings.default_difficulty, MatchConfig.Difficulty.NORMAL)
	assert_false(Settings.unlock_all_fighters)

	_write("this is { not a config file")
	Settings.load_settings()
	assert_almost_eq(Settings.volume(&"Master"), Settings.DEFAULT_VOLUMES[&"Master"], 0.0001)


func _write(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
