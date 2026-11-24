extends TestCase
## Guards project settings that other systems rely on.


func test_simulation_tick_is_60_hz() -> void:
	assert_eq(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"), 60)


func test_uses_compatibility_renderer() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")


func test_web_export_is_single_threaded() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK, "export_presets.cfg must load")
	var web_section := ""
	for section in presets.get_sections():
		if presets.get_value(section, "platform", "") == "Web":
			web_section = section
	assert_ne(web_section, "", "a Web export preset must exist")
	var options := web_section + ".options"
	assert_eq(presets.get_value(options, "variant/thread_support", true), false,
			"threads need SharedArrayBuffer, which GitHub Pages cannot enable")
	assert_eq(presets.get_value(options, "variant/extensions_support", true), false)
