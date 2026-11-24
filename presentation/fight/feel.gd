class_name Feel
extends RefCounted
## Presentation feel values (design-lost-ark §1.13): read from the FeelTuning autoload when
## it has the setting, else the defaults below. Read them every frame so live tuning applies
## at once.

const DEFAULTS := {
	&"shake_scale": 1.0,
	&"rumble_scale": 1.0,
	&"flash_intensity": 1.0,
	&"damage_numbers": true,
	&"slow_motion": 0.4,
	&"camera_pitch_deg": 48.0,
	&"camera_distance": 14.0,
	&"camera_distance_max": 20.0,
	&"camera_fov_deg": 35.0,
	&"camera_follow": 14.0,
	&"camera_lead_mouse": 0.5,
	&"camera_lead_pad": 0.0,
}


## FeelTuning constant naming each field (FeelTuning.value(KEY) / FeelTuning.flag(KEY)).
const KEYS := {
	&"shake_scale": "SHAKE_SCALE",
	&"rumble_scale": "RUMBLE_SCALE",
	&"flash_intensity": "FLASH_INTENSITY",
	&"damage_numbers": "DAMAGE_NUMBERS",
	&"slow_motion": "SLOW_MOTION",
	&"camera_pitch_deg": "CAMERA_PITCH",
	&"camera_distance": "CAMERA_DISTANCE",
	&"camera_distance_max": "CAMERA_DISTANCE_MAX",
	&"camera_fov_deg": "CAMERA_FOV",
	&"camera_follow": "CAMERA_FOLLOW",
	&"camera_lead_mouse": "CAMERA_LEAD_MOUSE",
	&"camera_lead_pad": "CAMERA_LEAD_PAD",
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
	return DEFAULTS[field]


static func shake_scale() -> float:
	return float(value(&"shake_scale"))


static func rumble_scale() -> float:
	return float(value(&"rumble_scale"))


static func flash_intensity() -> float:
	return float(value(&"flash_intensity"))


static func damage_numbers() -> bool:
	return bool(value(&"damage_numbers"))


static func slow_motion() -> float:
	return float(value(&"slow_motion"))


static func camera_pitch() -> float:
	return deg_to_rad(float(value(&"camera_pitch_deg")))


static func camera_distance() -> float:
	return float(value(&"camera_distance"))


## Farthest the camera pulls back to keep the fight framed.
static func camera_distance_max() -> float:
	return float(value(&"camera_distance_max"))


static func camera_fov() -> float:
	return float(value(&"camera_fov_deg"))


## Spring stiffness of the camera follow (rad/s; critically damped).
static func camera_follow() -> float:
	return float(value(&"camera_follow"))


## Aim lead in metres for the control scheme in use: toward the cursor on keyboard + mouse,
## none on gamepad and keyboard-only so the player stays centred.
static func camera_lead() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var device := tree.root.get_node_or_null(^"ActiveDevice") if tree != null and tree.root != null else null
	if device != null and int(device.get(&"scheme")) != 0:
		return float(value(&"camera_lead_pad"))
	return float(value(&"camera_lead_mouse"))
