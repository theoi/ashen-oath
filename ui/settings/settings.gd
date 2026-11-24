extends Node
## Autoload `Settings`: player preferences, persisted to user://settings.cfg.
##
## Volumes are linear 0..1 per audio bus and are applied to the AudioServer on change.
## Load and save never log errors: a missing or unreadable file means defaults.

signal changed

const DEFAULT_PATH := "user://settings.cfg"
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"UI"]
const DEFAULT_VOLUMES: Dictionary[StringName, float] = {&"Master": 0.8, &"Music": 0.7, &"SFX": 0.9, &"UI": 0.7}

## Where settings are read and written. Tests point this elsewhere.
var path := DEFAULT_PATH
var default_difficulty := MatchConfig.Difficulty.NORMAL
## Versus: every fighter selectable regardless of story progress.
var unlock_all_fighters := false

var _volumes: Dictionary[StringName, float] = DEFAULT_VOLUMES.duplicate()


func _ready() -> void:
	load_settings()


func volume(bus: StringName) -> float:
	return _volumes.get(bus, 1.0)


func set_volume(bus: StringName, value: float) -> void:
	if not bus in BUSES:
		return
	_volumes[bus] = clampf(value, 0.0, 1.0)
	apply_audio()
	changed.emit()


func set_default_difficulty(value: MatchConfig.Difficulty) -> void:
	default_difficulty = value
	changed.emit()


func set_unlock_all_fighters(value: bool) -> void:
	unlock_all_fighters = value
	changed.emit()


func reset_to_defaults() -> void:
	_volumes = DEFAULT_VOLUMES.duplicate()
	default_difficulty = MatchConfig.Difficulty.NORMAL
	unlock_all_fighters = false
	apply_audio()
	changed.emit()


func load_settings() -> void:
	reset_to_defaults()
	if not FileAccess.file_exists(path):
		return
	var config := ConfigFile.new()
	if config.parse(FileAccess.get_file_as_string(path)) != OK:
		return
	for bus in BUSES:
		var value: Variant = config.get_value("audio", String(bus).to_lower(), _volumes[bus])
		if value is float or value is int:
			_volumes[bus] = clampf(float(value), 0.0, 1.0)
	var difficulty: Variant = config.get_value("gameplay", "default_difficulty", default_difficulty)
	if difficulty is int and difficulty >= 0 and difficulty < MatchConfig.Difficulty.size():
		default_difficulty = difficulty as MatchConfig.Difficulty
	var unlock: Variant = config.get_value("gameplay", "unlock_all_fighters", false)
	if unlock is bool:
		unlock_all_fighters = unlock
	apply_audio()
	changed.emit()


func save_settings() -> Error:
	var config := ConfigFile.new()
	for bus in BUSES:
		config.set_value("audio", String(bus).to_lower(), _volumes[bus])
	config.set_value("gameplay", "default_difficulty", int(default_difficulty))
	config.set_value("gameplay", "unlock_all_fighters", unlock_all_fighters)
	return config.save(path)


func apply_audio() -> void:
	for bus in BUSES:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var value := _volumes[bus]
		AudioServer.set_bus_mute(index, value <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))
