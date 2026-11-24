extends Node
## Autoload `Profile`: player progress that unlocks content, persisted to user://profile.cfg.
##
## Story mode calls unlock_fighter() as fights are won. Versus asks is_fighter_unlocked(),
## which also honors the "unlock all fighters" setting.

signal changed

const DEFAULT_PATH := "user://profile.cfg"
const STARTING_FIGHTERS: Array[StringName] = [&"aldric"]

## Where the profile is read and written. Tests point this elsewhere.
var path := DEFAULT_PATH

var _unlocked: Array[StringName] = []


func _ready() -> void:
	load_profile()


func is_fighter_unlocked(id: StringName) -> bool:
	return Settings.unlock_all_fighters or id in STARTING_FIGHTERS or id in _unlocked


## Unlocks `id` and saves. Returns true if it was newly unlocked.
func unlock_fighter(id: StringName) -> bool:
	if id in _unlocked or id in STARTING_FIGHTERS:
		return false
	_unlocked.append(id)
	save_profile()
	changed.emit()
	return true


func unlocked_fighters() -> Array[StringName]:
	return _unlocked.duplicate()


func reset() -> void:
	_unlocked.clear()
	changed.emit()


func load_profile() -> void:
	_unlocked.clear()
	if FileAccess.file_exists(path):
		var config := ConfigFile.new()
		if config.parse(FileAccess.get_file_as_string(path)) == OK:
			var saved: Variant = config.get_value("unlocks", "fighters", PackedStringArray())
			if saved is PackedStringArray or saved is Array:
				for id: Variant in saved:
					if id is String or id is StringName:
						_unlocked.append(StringName(id))
	changed.emit()


func save_profile() -> Error:
	var config := ConfigFile.new()
	var ids := PackedStringArray()
	for id in _unlocked:
		ids.append(String(id))
	config.set_value("unlocks", "fighters", ids)
	return config.save(path)
