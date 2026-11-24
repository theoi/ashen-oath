class_name Feel
extends RefCounted
## Presentation feel values (design-lost-ark §1.13): read from the FeelTuning autoload when
## it exists, else the defaults below. Read them every frame so live tuning applies at once.

const DEFAULTS := {
	&"shake_scale": 1.0,
	&"rumble_scale": 1.0,
	&"damage_numbers": true,
	&"slow_motion": 0.4,
	&"camera_pitch_deg": 52.0,
	&"camera_distance": 15.0,
	&"camera_fov_deg": 40.0,
	&"camera_smoothing_s": 0.2,
	&"camera_lead_m": 1.0,
}


## FeelTuning constant naming each field (FeelTuning.value(KEY) / FeelTuning.flag(KEY)).
const KEYS := {
	&"shake_scale": "SHAKE_SCALE",
	&"rumble_scale": "RUMBLE_SCALE",
	&"damage_numbers": "DAMAGE_NUMBERS",
	&"slow_motion": "SLOW_MOTION",
	&"camera_pitch_deg": "CAMERA_PITCH",
	&"camera_distance": "CAMERA_DISTANCE",
	&"camera_fov_deg": "CAMERA_FOV",
	&"camera_smoothing_s": "CAMERA_SMOOTHING",
	&"camera_lead_m": "CAMERA_LEAD",
}


static func value(field: StringName) -> Variant:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return DEFAULTS[field]
	var tuning := tree.root.get_node_or_null(^"FeelTuning")
	if tuning == null:
		return DEFAULTS[field]
	var script := tuning.get_script() as Script
	var constants := script.get_script_constant_map() if script != null else {}
	var key_name: String = KEYS[field]
	if constants.has(key_name):
		var key: Variant = constants[key_name]
		if field == &"damage_numbers" and tuning.has_method(&"flag"):
			return tuning.call(&"flag", key)
		if tuning.has_method(&"value"):
			return tuning.call(&"value", key)
	if field in tuning:
		return tuning.get(field)
	return DEFAULTS[field]


static func shake_scale() -> float:
	return float(value(&"shake_scale"))


static func rumble_scale() -> float:
	return float(value(&"rumble_scale"))


static func damage_numbers() -> bool:
	return bool(value(&"damage_numbers"))


static func slow_motion() -> float:
	return float(value(&"slow_motion"))


static func camera_pitch() -> float:
	return deg_to_rad(float(value(&"camera_pitch_deg")))


static func camera_distance() -> float:
	return float(value(&"camera_distance"))


static func camera_fov() -> float:
	return float(value(&"camera_fov_deg"))


static func camera_smoothing() -> float:
	return float(value(&"camera_smoothing_s"))


static func camera_lead() -> float:
	return float(value(&"camera_lead_m"))
