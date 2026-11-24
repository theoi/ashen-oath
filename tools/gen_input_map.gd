extends SceneTree
## Writes DefaultBindings into the [input] section of project.godot.
##
##   godot --headless --path . -s "$PWD/tools/gen_input_map.gd"
##
## Rerun after editing ui/input/default_bindings.gd; tests/ui/test_input_map.gd fails until you do.
## Only the [input] section is replaced: ProjectSettings.save() would also drop settings that
## equal their defaults (such as the explicit 60 Hz physics tick), so it is not used here.

const PROJECT_FILE := "res://project.godot"
const SCRATCH_FILE := "user://gen_input_map.godot"


func _init() -> void:
	var bindings: GDScript = load("res://ui/input/default_bindings.gd")
	for binding: RefCounted in bindings.gameplay():
		var setting := "input/%s" % binding.action
		var events: Array = []
		events.append_array(binding.all_events())
		ProjectSettings.set_setting(setting, {"deadzone": binding.deadzone, "events": events})
	var additions: Dictionary = bindings.ui_additions()
	for action: StringName in additions:
		var setting := "input/%s" % action
		var current: Dictionary = ProjectSettings.get_setting(setting)
		var events: Array = current["events"].duplicate()
		for event: InputEvent in additions[action]:
			if not events.any(func(e: InputEvent) -> bool: return bindings.same_event(e, event)):
				events.append(event)
		ProjectSettings.set_setting(setting, {"deadzone": current["deadzone"], "events": events})

	var error := ProjectSettings.save_custom(SCRATCH_FILE)
	if error != OK:
		printerr("could not write %s: %s" % [SCRATCH_FILE, error_string(error)])
		quit(1)
		return
	var input_section := _section(FileAccess.get_file_as_string(SCRATCH_FILE), "input")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_FILE))
	var project := FileAccess.get_file_as_string(PROJECT_FILE)
	var old_section := _section(project, "input")
	if old_section.is_empty():
		project = project.replace("\n[physics]\n", "\n%s\n[physics]\n" % input_section)
	else:
		project = project.replace(old_section, input_section)
	if not project.contains(input_section):
		printerr("could not place the [input] section in project.godot")
		quit(1)
		return
	var file := FileAccess.open(PROJECT_FILE, FileAccess.WRITE)
	file.store_string(project)
	file.close()
	print("project.godot input map written")
	quit(0)


## The text of `[name]` up to (not including) the next section header.
func _section(text: String, name: String) -> String:
	var start := text.find("\n[%s]\n" % name)
	if start < 0:
		return ""
	start += 1
	var end := text.find("\n[", start + name.length() + 2)
	return text.substr(start, (end + 1 if end >= 0 else text.length()) - start)
