extends TestCase
## Loads every script, scene and resource in the project so parse errors and broken
## references fail CI even when no other test touches them.

const SKIP_DIRS: PackedStringArray = ["res://.godot", "res://build", "res://tools"]
const EXTENSIONS: PackedStringArray = ["gd", "tscn", "tres"]


func test_every_script_scene_and_resource_loads() -> void:
	var paths := _collect("res://")
	assert_true(paths.size() > 0, "found no project files")
	for path in paths:
		if load(path) == null:
			fail("could not load %s" % path)


func _collect(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file in DirAccess.get_files_at(dir_path):
		if file.get_extension() in EXTENSIONS:
			found.append(dir_path.path_join(file))
	for dir in DirAccess.get_directories_at(dir_path):
		var child := dir_path.path_join(dir)
		if not child in SKIP_DIRS and not dir.begins_with("."):
			found.append_array(_collect(child))
	return found
