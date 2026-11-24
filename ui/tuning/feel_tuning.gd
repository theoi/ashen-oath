extends Node
## Autoload `FeelTuning`: the hidden feel-tuning values from design-lost-ark §1.13.
##
## Live values (camera, shake, rumble, slow motion, damage numbers) are read by presentation
## every frame or on `changed`. Sim values (hitstop, skill speed, dash) only reach a match
## through apply_to(SimConfig) at match start, so a running match stays deterministic and
## its replay records them. Values persist in user://feel_tuning.cfg.
##
## The panel opens with Ctrl+Shift+F, `-- --tune` on the command line, or ?tune=1 on web.

signal changed
## The panel was opened or closed.
signal panel_toggled(open: bool)

const DEFAULT_PATH := "user://feel_tuning.cfg"

const SHAKE_SCALE := &"shake_scale"
const FLASH_INTENSITY := &"flash_intensity"
const RUMBLE_SCALE := &"rumble_scale"
const DAMAGE_NUMBERS := &"damage_numbers"
const SLOW_MOTION := &"slow_motion"
const CAMERA_PITCH := &"camera_pitch"
## Distance at rest, and the farthest the camera pulls back to keep everyone framed.
const CAMERA_DISTANCE := &"camera_distance"
const CAMERA_DISTANCE_MAX := &"camera_distance_max"
## Vertical field of view, degrees.
const CAMERA_FOV := &"camera_fov"
## Follow spring angular frequency ω (rad/s); higher follows tighter.
const CAMERA_FOLLOW := &"camera_follow"
## How far the camera leads toward the aim point, per aiming device.
const AIM_LEAD_MOUSE := &"aim_lead_mouse"
const AIM_LEAD_PAD := &"aim_lead_pad"
const HITSTOP_SCALE := &"hitstop_scale"
const SKILL_SPEED := &"skill_speed"
const DASH_DISTANCE := &"dash_distance"
const DASH_CHARGES := &"dash_charges"
const DASH_RECHARGE := &"dash_recharge"


class Setting:
	var key: StringName
	var label: String
	var default: float
	var min_value: float
	var max_value: float
	var step: float
	var unit: String
	## True: changes reach the sim, so they apply at the next match start.
	var sim: bool
	## SimConfig property it sets, and the factor from this value to that property.
	var sim_property: StringName
	var sim_factor: float

	func _init(p_key: StringName, p_label: String, p_default: float, p_min: float, p_max: float, p_step: float,
			p_unit: String = "", p_sim_property: StringName = &"", p_sim_factor: float = 1.0) -> void:
		key = p_key
		label = p_label
		default = p_default
		min_value = p_min
		max_value = p_max
		step = p_step
		unit = p_unit
		sim_property = p_sim_property
		sim_factor = p_sim_factor
		sim = not p_sim_property.is_empty()

	func is_toggle() -> bool:
		return min_value == 0.0 and max_value == 1.0 and step == 1.0

	func format(value: float) -> String:
		if is_toggle():
			return "on" if value >= 0.5 else "off"
		var digits := 0 if step >= 1.0 else (1 if step >= 0.1 else 2)
		return String.num(value, digits) + unit


## Display order. Defaults are the design-lost-ark §1.13 table (v4).
static func settings() -> Array[Setting]:
	return [
		Setting.new(SHAKE_SCALE, "Shake scale", 1.0, 0.0, 2.0, 0.05, "×"),
		Setting.new(FLASH_INTENSITY, "Flash intensity", 1.0, 0.0, 2.0, 0.05, "×"),
		Setting.new(CAMERA_PITCH, "Camera pitch", 48.0, 35.0, 65.0, 1.0, "°"),
		Setting.new(CAMERA_DISTANCE, "Camera distance", 14.0, 8.0, 24.0, 0.5, " m"),
		Setting.new(CAMERA_DISTANCE_MAX, "Max distance", 20.0, 10.0, 30.0, 0.5, " m"),
		Setting.new(CAMERA_FOV, "Field of view", 35.0, 20.0, 60.0, 1.0, "°"),
		Setting.new(CAMERA_FOLLOW, "Follow speed (ω)", 14.0, 2.0, 30.0, 0.5, " rad/s"),
		Setting.new(AIM_LEAD_MOUSE, "Aim lead (mouse)", 0.5, 0.0, 3.0, 0.1, " m"),
		Setting.new(AIM_LEAD_PAD, "Aim lead (gamepad)", 0.0, 0.0, 3.0, 0.1, " m"),
		Setting.new(SLOW_MOTION, "Slow motion", 0.4, 0.1, 1.0, 0.05, "×"),
		Setting.new(RUMBLE_SCALE, "Rumble scale", 1.0, 0.0, 2.0, 0.05, "×"),
		Setting.new(DAMAGE_NUMBERS, "Damage numbers", 1.0, 0.0, 1.0, 1.0),
		Setting.new(HITSTOP_SCALE, "Hitstop scale", 1.0, 0.0, 3.0, 0.05, "×", &"hitstop_percent", 100.0),
		Setting.new(SKILL_SPEED, "Skill speed", 100.0, 50.0, 150.0, 5.0, "%", &"move_speed_percent"),
		Setting.new(DASH_DISTANCE, "Dash distance", 4.5, 2.0, 8.0, 0.25, " m", &"dash_distance"),
		Setting.new(DASH_CHARGES, "Dash charges", 2.0, 1.0, 4.0, 1.0, "", &"dash_charges"),
		Setting.new(DASH_RECHARGE, "Dash recharge", 5.0, 1.0, 10.0, 0.25, " s", &"dash_recharge_frames", 60.0),
	]


## Where values are read and written. Tests point this elsewhere.
var path := DEFAULT_PATH

var _settings: Dictionary[StringName, Setting] = {}
var _values: Dictionary[StringName, float] = {}
## Sim values the running match started with (empty before the first match).
var _applied: Dictionary[StringName, float] = {}
var _layer: CanvasLayer
var _panel: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for setting in settings():
		_settings[setting.key] = setting
	load_values()
	if "--tune" in OS.get_cmdline_user_args() or _url_flag():
		open_panel.call_deferred()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F \
			and key.ctrl_pressed and key.shift_pressed:
		toggle_panel()
		get_viewport().set_input_as_handled()


func value(key: StringName) -> float:
	return _values.get(key, 0.0)


func flag(key: StringName) -> bool:
	return value(key) >= 0.5


func setting(key: StringName) -> Setting:
	return _settings.get(key)


func set_value(key: StringName, new_value: float) -> void:
	var s: Setting = _settings.get(key)
	if s == null:
		return
	var snapped := clampf(snappedf(new_value, s.step), s.min_value, s.max_value)
	if is_equal_approx(snapped, _values[key]):
		return
	_values[key] = snapped
	save_values()
	changed.emit()


func reset_to_defaults() -> void:
	for key in _settings:
		_values[key] = _settings[key].default
	changed.emit()


## Writes the sim values into `config` (call once per match, before Sim.new). Values at
## their default are left alone, so a fighter's own dash data still applies.
func apply_to(config: SimConfig) -> void:
	_applied.clear()
	for key in _settings:
		var s := _settings[key]
		if not s.sim:
			continue
		_applied[key] = _values[key]
		# Overrides the sim does not support yet are skipped (still listed for restart).
		if is_equal_approx(_values[key], s.default) or not s.sim_property in config:
			continue
		var current: Variant = config.get(s.sim_property)
		var scaled := _values[key] * s.sim_factor
		config.set(s.sim_property, roundi(scaled) if current is int else scaled)


## Sim settings changed since the running match started (they apply on restart).
func pending_restart() -> PackedStringArray:
	var out := PackedStringArray()
	for key in _applied:
		if not is_equal_approx(_applied[key], _values[key]):
			out.append(_settings[key].label)
	return out


## Every value as text to paste back to the team, e.g. "camera_pitch = 52".
func as_text() -> String:
	var lines := PackedStringArray(["# Ashen Oath feel tuning (%s)" % BuildInfo.label()])
	for setting in settings():
		var v := _values[setting.key]
		var shown := _num(v) if not setting.is_toggle() else ("true" if v >= 0.5 else "false")
		var note := "" if is_equal_approx(v, setting.default) else "  # default %s" % _num(setting.default)
		lines.append("%s = %s%s" % [setting.key, shown, note])
	return "\n".join(lines)


func load_values() -> void:
	for key in _settings:
		_values[key] = _settings[key].default
	if FileAccess.file_exists(path):
		var config := ConfigFile.new()
		if config.parse(FileAccess.get_file_as_string(path)) == OK:
			for key in _settings:
				var stored: Variant = config.get_value("tuning", String(key), _values[key])
				if stored is float or stored is int:
					var s := _settings[key]
					_values[key] = clampf(float(stored), s.min_value, s.max_value)
	changed.emit()


func save_values() -> Error:
	var config := ConfigFile.new()
	for key in _settings:
		config.set_value("tuning", String(key), _values[key])
	return config.save(path)


func is_panel_open() -> bool:
	return _panel != null and _panel.visible


func open_panel() -> void:
	if _panel == null:
		_layer = CanvasLayer.new()
		_layer.layer = 100
		add_child(_layer)
		_panel = TuningPanel.new()
		_layer.add_child(_panel)
	_panel.visible = true
	panel_toggled.emit(true)


func close_panel() -> void:
	if _panel != null and _panel.visible:
		_panel.visible = false
		panel_toggled.emit(false)


func toggle_panel() -> void:
	if is_panel_open():
		close_panel()
	else:
		open_panel()


func _url_flag() -> bool:
	if not OS.has_feature("web"):
		return false
	var search: Variant = JavaScriptBridge.eval("window.location.search", true)
	return search is String and (search as String).contains("tune=1")


static func _num(v: float) -> String:
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else String.num(v, 3)
