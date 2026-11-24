extends Node
## Autoload `Settings`: player preferences, persisted to user://settings.cfg.
##
## Volumes are linear 0..1 per audio bus and are applied to the AudioServer on change.
## Brightness scales the tonemap exposure of every WorldEnvironment in the tree (arenas, story
## stages, menu backdrops), on top of the exposure each scene was authored with.
## Load and save never log errors: a missing or unreadable file means defaults.

signal changed

const DEFAULT_PATH := "user://settings.cfg"
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"UI"]
const DEFAULT_VOLUMES: Dictionary[StringName, float] = {&"Master": 0.8, &"Music": 0.7, &"SFX": 0.9, &"UI": 0.7}
const BRIGHTNESS_MIN := 0.6
const BRIGHTNESS_MAX := 1.6
const BRIGHTNESS_DEFAULT := 1.0
## Environment metas: the exposure the scene set, and the scaled value last written over it.
const BASE_EXPOSURE_META := &"authored_exposure"
const APPLIED_EXPOSURE_META := &"applied_exposure"

## Where settings are read and written. Tests point this elsewhere.
var path := DEFAULT_PATH
var default_difficulty := MatchConfig.Difficulty.NORMAL
## Versus: every fighter selectable regardless of story progress.
var unlock_all_fighters := false
## Multiplier on scene exposure, BRIGHTNESS_MIN..BRIGHTNESS_MAX.
var brightness := BRIGHTNESS_DEFAULT

var _volumes: Dictionary[StringName, float] = DEFAULT_VOLUMES.duplicate()


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	load_settings()
	# Captures can preview a brightness without saving it (-- --brightness=1.4).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--brightness="):
			set_brightness(float(arg.trim_prefix("--brightness=")))


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


func set_brightness(value: float) -> void:
	brightness = clampf(value, BRIGHTNESS_MIN, BRIGHTNESS_MAX)
	apply_brightness()
	changed.emit()


func reset_to_defaults() -> void:
	_volumes = DEFAULT_VOLUMES.duplicate()
	default_difficulty = MatchConfig.Difficulty.NORMAL
	unlock_all_fighters = false
	brightness = BRIGHTNESS_DEFAULT
	apply_audio()
	apply_brightness()
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
	var bright: Variant = config.get_value("video", "brightness", brightness)
	if bright is float or bright is int:
		brightness = clampf(float(bright), BRIGHTNESS_MIN, BRIGHTNESS_MAX)
	apply_audio()
	apply_brightness()
	changed.emit()


func save_settings() -> Error:
	var config := ConfigFile.new()
	for bus in BUSES:
		config.set_value("audio", String(bus).to_lower(), _volumes[bus])
	config.set_value("gameplay", "default_difficulty", int(default_difficulty))
	config.set_value("gameplay", "unlock_all_fighters", unlock_all_fighters)
	config.set_value("video", "brightness", brightness)
	return config.save(path)


func apply_audio() -> void:
	for bus in BUSES:
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var value := _volumes[bus]
		AudioServer.set_bus_mute(index, value <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))


func apply_brightness() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		apply_brightness_to(node as WorldEnvironment)


## Scales `world_env`'s exposure by the brightness setting. The scene's own exposure is
## remembered so repeated calls never compound; if the scene changed the exposure since the
## last call (live tuning), that new value becomes the base.
func apply_brightness_to(world_env: WorldEnvironment) -> void:
	var env := world_env.environment
	if env == null:
		return
	var applied: float = env.get_meta(APPLIED_EXPOSURE_META, NAN)
	if not env.has_meta(BASE_EXPOSURE_META) or not is_equal_approx(env.tonemap_exposure, applied):
		env.set_meta(BASE_EXPOSURE_META, env.tonemap_exposure)
	env.tonemap_exposure = float(env.get_meta(BASE_EXPOSURE_META)) * brightness
	env.set_meta(APPLIED_EXPOSURE_META, env.tonemap_exposure)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		# Deferred: scenes may assign the environment after adding the node.
		_apply_later.call_deferred(node.get_instance_id())


func _apply_later(id: int) -> void:
	var node := instance_from_id(id)
	if node is WorldEnvironment and (node as WorldEnvironment).is_inside_tree():
		apply_brightness_to(node as WorldEnvironment)
